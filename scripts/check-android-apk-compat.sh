#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APK=${PAWXY_APK:-$ROOT/android/app/build/outputs/apk/debug/app-debug.apk}
SDK_ROOT=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}
AAPT2=${PAWXY_AAPT2:-}
ZIPALIGN=${PAWXY_ZIPALIGN:-}
LLVM_OBJDUMP=${PAWXY_LLVM_OBJDUMP:-}
TMP=

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

note() {
  printf '%s\n' "pawxy apk compat: $*"
}

find_tool() {
  var_name=$1
  candidate=$2
  pattern=$3
  if [ -n "$candidate" ]; then
    [ -x "$candidate" ] || fail "$var_name is not executable: $candidate"
    printf '%s\n' "$candidate"
    return 0
  fi
  found=$(find "$SDK_ROOT" -path "$pattern" -type f 2>/dev/null | sort | tail -n 1)
  [ -n "$found" ] || fail "could not find $var_name under $SDK_ROOT"
  [ -x "$found" ] || fail "$var_name is not executable: $found"
  printf '%s\n' "$found"
}

cleanup() {
  [ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

[ -f "$APK" ] || fail "APK not found: $APK"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"
command -v awk >/dev/null 2>&1 || fail "awk is required"

AAPT2=$(find_tool PAWXY_AAPT2 "$AAPT2" '*/build-tools/*/aapt2')
ZIPALIGN=$(find_tool PAWXY_ZIPALIGN "$ZIPALIGN" '*/build-tools/*/zipalign')
LLVM_OBJDUMP=$(find_tool PAWXY_LLVM_OBJDUMP "$LLVM_OBJDUMP" '*/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-objdump')

note "verifying manifest control surface"
manifest=$("$AAPT2" dump xmltree --file AndroidManifest.xml "$APK")
badging=$("$AAPT2" dump badging "$APK")
printf '%s\n' "$badging" | grep -F "package: name='dev.pawxy'" >/dev/null \
  || fail "APK package name is not dev.pawxy"
printf '%s\n' "$badging" | grep -F "minSdkVersion:'26'" >/dev/null \
  || fail "APK minSdkVersion must remain 26 for Android foreground-service compatibility"
printf '%s\n' "$badging" | grep -F "targetSdkVersion:'35'" >/dev/null \
  || fail "APK targetSdkVersion must remain 35 for Pixel/Android 15 behavior"
printf '%s\n' "$manifest" | grep -F 'android.permission.ACCESS_NETWORK_STATE' >/dev/null \
  || fail "manifest missing ACCESS_NETWORK_STATE"
printf '%s\n' "$manifest" | grep -F 'android.permission.FOREGROUND_SERVICE_SPECIAL_USE' >/dev/null \
  || fail "manifest missing FOREGROUND_SERVICE_SPECIAL_USE"
printf '%s\n' "$manifest" | grep -F 'android.permission.POST_NOTIFICATIONS' >/dev/null \
  || fail "manifest missing POST_NOTIFICATIONS"
printf '%s\n' "$manifest" | grep -F 'dev.pawxy.ProxyService' >/dev/null \
  || fail "manifest missing ProxyService"
printf '%s\n' "$manifest" | grep -F 'dev.pawxy.StatusProvider' >/dev/null \
  || fail "manifest missing StatusProvider"
printf '%s\n' "$manifest" | grep -F 'dev.pawxy.action.RESET_TOKEN' >/dev/null \
  || fail "manifest missing RESET_TOKEN control action"
dump_count=$(printf '%s\n' "$manifest" | grep -F 'android.permission.DUMP' | wc -l | tr -d ' ')
[ "$dump_count" -ge 2 ] || fail "ProxyService and StatusProvider must both require android.permission.DUMP"
printf '%s\n' "$badging" | grep -F "PROPERTY_SPECIAL_USE_FGS_SUBTYPE" >/dev/null \
  || fail "APK missing specialUse foreground-service subtype property"
printf '%s\n' "$badging" | grep -F "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'" >/dev/null \
  || fail "APK native-code badging must include arm64-v8a, armeabi-v7a, and x86_64"

note "verifying 16 KB APK zip alignment"
"$ZIPALIGN" -c -P 16 -v 4 "$APK" >/dev/null

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pawxy-apk-compat.XXXXXX")
unzip -q "$APK" 'lib/*/libpawxy_jni.so' -d "$TMP"

for abi in arm64-v8a armeabi-v7a x86_64; do
  [ -f "$TMP/lib/$abi/libpawxy_jni.so" ] || fail "APK missing lib/$abi/libpawxy_jni.so"
done

note "verifying native ELF LOAD segment alignment"
find "$TMP/lib" -name 'libpawxy_jni.so' -type f | sort | while IFS= read -r so; do
  loads=$TMP/loads.$(basename "$(dirname "$so")")
  "$LLVM_OBJDUMP" -p "$so" | awk '/LOAD/ { print $NF }' > "$loads"
  [ -s "$loads" ] || fail "no LOAD segments found in $so"
  while IFS= read -r align; do
    case "$align" in
      2**[0-9]*)
        exponent=${align#2\*\*}
        ;;
      *)
        fail "unexpected LOAD alignment in $so: $align"
        ;;
    esac
    [ "$exponent" -ge 14 ] 2>/dev/null \
      || fail "$so LOAD segment alignment $align is below 16 KB"
  done < "$loads"
done

printf '%s\n' "pawxy apk compatibility ok"
