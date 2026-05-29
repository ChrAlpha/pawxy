#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

APK_SOURCE=${PAWXY_APK_SOURCE:-android/app/build/outputs/apk/debug/app-debug.apk}
DIST_DIR=${PAWXY_DIST_DIR-dist}
VERSION=${PAWXY_PACKAGE_VERSION:-${GITHUB_REF_NAME:-manual}}

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

[ -f "$APK_SOURCE" ] || fail "APK not found: $APK_SOURCE"
[ -f scripts/pawxyctl ] || fail "scripts/pawxyctl not found"
[ -f scripts/install-android.sh ] || fail "scripts/install-android.sh not found"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

case "$DIST_DIR" in
  ''|/|.|..)
    fail "refusing unsafe PAWXY_DIST_DIR: ${DIST_DIR:-empty}"
    ;;
esac
case "$DIST_DIR" in
  "$ROOT"|"$ROOT/"|"$ROOT/."|"$ROOT/..")
    fail "refusing to package into repository root: $DIST_DIR"
    ;;
esac
dist_base=${DIST_DIR##*/}
case "$dist_base" in
  dist|*pawxy*)
    ;;
  *)
    fail "refusing output directory without a pawxy/dist name: $DIST_DIR"
    ;;
esac
case "$dist_base" in
  ''|/|.|..)
    fail "refusing unsafe PAWXY_DIST_DIR basename: ${dist_base:-empty}"
    ;;
esac

safe_version=$(printf '%s' "$VERSION" | tr -c 'A-Za-z0-9._-' '-')
[ -n "$safe_version" ] || safe_version=manual
apk_name=pawxy-${safe_version}-debug.apk

rm -rf -- "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp "$APK_SOURCE" "$DIST_DIR/$apk_name"
cp scripts/pawxyctl "$DIST_DIR/pawxyctl"
cp scripts/install-android.sh "$DIST_DIR/install-android.sh"
chmod 755 "$DIST_DIR/pawxyctl"
chmod 755 "$DIST_DIR/install-android.sh"

(
  cd "$DIST_DIR"
  sha256sum "$apk_name" pawxyctl > SHA256SUMS
  sha256sum -c SHA256SUMS >/dev/null
)

printf '%s\n' "pawxy android package ready: $DIST_DIR"
