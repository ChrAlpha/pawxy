#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

APK_SOURCE=${PAWXY_APK_SOURCE:-android/app/build/outputs/apk/debug/app-debug.apk}
CTL_SOURCE=${PAWXY_CTL_SOURCE:-scripts/pawxyctl}
DIST_DIR=${PAWXY_DIST_DIR-dist}
VERSION=${PAWXY_PACKAGE_VERSION:-${GITHUB_REF_NAME:-manual}}
SUMS=SHA256SUMS

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

[ -f "$APK_SOURCE" ] || fail "APK not found: $APK_SOURCE"
[ -f "$CTL_SOURCE" ] || fail "pawxyctl not found: $CTL_SOURCE"
[ -f scripts/install-android.sh ] || fail "scripts/install-android.sh not found"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
command -v base64 >/dev/null 2>&1 || fail "base64 is required"
command -v awk >/dev/null 2>&1 || fail "awk is required"

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
cp "$CTL_SOURCE" "$DIST_DIR/pawxyctl"
chmod 755 "$DIST_DIR/pawxyctl"

(
  cd "$DIST_DIR"
  sha256sum "$apk_name" pawxyctl > SHA256SUMS
  sha256sum -c SHA256SUMS >/dev/null
)

embedded_function=$DIST_DIR/embedded-assets.sh
{
  printf '%s\n' 'embedded_asset() {'
  printf '%s\n' '  asset=$1'
  printf '%s\n' '  out=$2'
  printf '%s\n' '  case "$asset" in'
  for asset in "$SUMS" "$apk_name" pawxyctl; do
    marker=$(printf '%s' "$asset" | tr -c 'A-Za-z0-9_' '_')
    printf "    '%s')\n" "$asset"
    printf '%s\n' '      base64_decode > "$out" <<'"PAWXY_ASSET_$marker"
    base64 "$DIST_DIR/$asset"
    printf '%s\n' "PAWXY_ASSET_$marker"
    printf '%s\n' '      ;;'
  done
  printf '%s\n' '    *)'
  printf '%s\n' '      return 1'
  printf '%s\n' '      ;;'
  printf '%s\n' '  esac'
  printf '%s\n' '}'
} > "$embedded_function"

awk -v embedded="$embedded_function" '
  $0 == "# PAWXY_EMBEDDED_ASSETS_BEGIN" {
    print
    while ((getline line < embedded) > 0) print line
    in_block = 1
    next
  }
  $0 == "# PAWXY_EMBEDDED_ASSETS_END" {
    in_block = 0
    print
    next
  }
  !in_block { print }
' scripts/install-android.sh > "$DIST_DIR/install-android.sh"
rm -f "$embedded_function"
chmod 755 "$DIST_DIR/install-android.sh"

printf '%s\n' "pawxy android package ready: $DIST_DIR"
