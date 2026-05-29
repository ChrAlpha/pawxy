#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/package-android.sh

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "scripts/package-android.sh must exist"
sh -n "$SCRIPT"

tmp=${TMPDIR:-/tmp}/pawxy-package-android-test.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

printf '%s\n' "fake apk" > "$tmp/app-debug.apk"

PAWXY_APK_SOURCE="$tmp/app-debug.apk" \
  PAWXY_DIST_DIR="$tmp/dist" \
  PAWXY_PACKAGE_VERSION='v0.1.0 test/tag' \
  sh "$SCRIPT" >"$tmp/package.out"

[ -f "$tmp/dist/pawxy-v0.1.0-test-tag-debug.apk" ] \
  || fail "package script must sanitize the version into the APK asset name"
[ -x "$tmp/dist/pawxyctl" ] \
  || fail "package script must copy executable pawxyctl"
[ -x "$tmp/dist/install-android.sh" ] \
  || fail "package script must copy executable install-android.sh"
[ -f "$tmp/dist/SHA256SUMS" ] \
  || fail "package script must write SHA256SUMS"

(
  cd "$tmp/dist"
  sha256sum -c SHA256SUMS >/dev/null
)
grep -F -- "pawxy-v0.1.0-test-tag-debug.apk" "$tmp/dist/SHA256SUMS" >/dev/null \
  || fail "SHA256SUMS must cover the packaged APK"
grep -F -- "pawxyctl" "$tmp/dist/SHA256SUMS" >/dev/null \
  || fail "SHA256SUMS must cover pawxyctl"
! grep -F -- "install-android.sh" "$tmp/dist/SHA256SUMS" >/dev/null \
  || fail "SHA256SUMS must not checksum install-android.sh itself"

for unsafe_dist in '' / . .. "$ROOT" /tmp "$tmp/output"; do
  if PAWXY_APK_SOURCE="$tmp/app-debug.apk" \
    PAWXY_DIST_DIR="$unsafe_dist" \
    sh "$SCRIPT" >"$tmp/unsafe.out" 2>"$tmp/unsafe.err"; then
    fail "package script must reject unsafe PAWXY_DIST_DIR=${unsafe_dist:-empty}"
  fi
  grep -F -- "refusing" "$tmp/unsafe.err" >/dev/null \
    || fail "unsafe PAWXY_DIST_DIR rejection must explain the refusal"
done

PAWXY_APK_SOURCE="$tmp/app-debug.apk" \
  PAWXY_DIST_DIR="$tmp/pawxy-release-assets" \
  sh "$SCRIPT" >"$tmp/absolute-package.out"
[ -f "$tmp/pawxy-release-assets/SHA256SUMS" ] \
  || fail "package script must allow explicit pawxy-named output directories"

printf '%s\n' "package-android test ok"
