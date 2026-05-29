#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

SKIP_RUST=${PAWXY_SKIP_RUST_GATES:-0}
SKIP_ANDROID_BUILD=${PAWXY_SKIP_ANDROID_BUILD:-0}
SKIP_RUNTIME=${PAWXY_SKIP_RUNTIME:-0}
APK=${PAWXY_APK:-android/app/build/outputs/apk/debug/app-debug.apk}

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

note() {
  printf '%s\n' "pawxy public readiness: $*"
}

run() {
  note "$*"
  "$@"
}

validate_flag() {
  name=$1
  value=$2
  case "$value" in
    0|1) ;;
    *) fail "$name must be 0 or 1" ;;
  esac
}

validate_flag PAWXY_SKIP_RUST_GATES "$SKIP_RUST"
validate_flag PAWXY_SKIP_ANDROID_BUILD "$SKIP_ANDROID_BUILD"
validate_flag PAWXY_SKIP_RUNTIME "$SKIP_RUNTIME"

note "syntax gates"
run sh -n \
  scripts/pawxyctl \
  scripts/test-pawxyctl.sh \
  scripts/package-android.sh \
  scripts/test-package-android.sh \
  scripts/install-apk-adb.sh \
  scripts/test-install-apk-adb.sh \
  scripts/install-android.sh \
  scripts/test-install-android.sh \
  scripts/test-android-device.sh \
  scripts/test-android-device-mock.sh \
  scripts/test-android-vm.sh \
  scripts/test-android-vm-mock.sh \
  scripts/check-best-practices.sh \
  scripts/build-android.sh \
  scripts/check-android-apk-compat.sh \
  scripts/test-public-readiness.sh

if [ "$SKIP_RUST" = "0" ]; then
  run cargo fmt --all -- --check
  run cargo clippy --workspace --all-targets -- -D warnings
  run cargo test --workspace
else
  note "skipping Rust gates because PAWXY_SKIP_RUST_GATES=1"
fi

run scripts/test-pawxyctl.sh
run scripts/test-package-android.sh
run scripts/test-install-apk-adb.sh
run scripts/test-install-android.sh
run scripts/test-android-device-mock.sh
run scripts/test-android-vm-mock.sh
run scripts/check-best-practices.sh

if [ "$SKIP_ANDROID_BUILD" = "0" ]; then
  run scripts/build-android.sh
else
  note "skipping Android build because PAWXY_SKIP_ANDROID_BUILD=1"
fi
run scripts/check-android-apk-compat.sh "$APK"
package_tmp=${TMPDIR:-/tmp}/pawxy-readiness-package.$$
rm -rf "$package_tmp"
trap 'rm -rf "$package_tmp"' EXIT HUP INT TERM
run env PAWXY_APK_SOURCE="$APK" PAWXY_DIST_DIR="$package_tmp" scripts/package-android.sh
run git diff --check

if [ "$SKIP_RUNTIME" = "0" ]; then
  note "runtime gate: existing Pixel/GSI/VM, PAWXY_AVD, or PAWXY_GSI_SYSTEM_IMG"
  run scripts/test-android-vm.sh
else
  note "skipping real Android runtime because PAWXY_SKIP_RUNTIME=1"
fi

printf '%s\n' "pawxy public readiness ok"
