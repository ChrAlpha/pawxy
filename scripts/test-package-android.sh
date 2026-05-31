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
cat > "$tmp/pawxyctl" <<'CTL'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/pawxyctl.args"
if [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; then
  printf '%s\n' '{"running":true,"native_running":true,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false}'
fi
CTL
chmod 755 "$tmp/pawxyctl"

PAWXY_APK_SOURCE="$tmp/app-debug.apk" \
  PAWXY_CTL_SOURCE="$tmp/pawxyctl" \
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

mkdir -p "$tmp/bin" "$tmp/log-bundled" "$tmp/install-bundled" "$tmp/tmp"
cat > "$tmp/bin/curl" <<'CURL'
#!/bin/sh
printf '%s\n' "curl" > "$PAWXY_TEST_LOG/network-attempted"
exit 37
CURL
chmod 755 "$tmp/bin/curl"
cat > "$tmp/bin/wget" <<'WGET'
#!/bin/sh
printf '%s\n' "wget" > "$PAWXY_TEST_LOG/network-attempted"
exit 37
WGET
chmod 755 "$tmp/bin/wget"
cat > "$tmp/bin/pm" <<'PM'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/pm.args"
case "${1:-}" in
  check-permission)
    printf '%s\n' "granted"
    ;;
  path)
    if [ -f "$PAWXY_TEST_LOG/pm-installed" ]; then
      printf '%s\n' "package:/data/app/dev.pawxy/base.apk"
    fi
    ;;
  install)
    : > "$PAWXY_TEST_LOG/pm-installed"
    ;;
esac
PM
chmod 755 "$tmp/bin/pm"
cat > "$tmp/bin/id" <<'ID'
#!/bin/sh
[ "${1:-}" = "-u" ] || exit 1
printf '%s\n' "2000"
ID
chmod 755 "$tmp/bin/id"

PATH="$tmp/bin:$PATH" \
  PAWXY_INSTALL_DIR="$tmp/install-bundled" \
  PAWXY_TEST_LOG="$tmp/log-bundled" \
  TMPDIR="$tmp/tmp" \
  sh < "$tmp/dist/install-android.sh" >/dev/null

[ ! -f "$tmp/log-bundled/network-attempted" ] \
  || fail "bundled release installer must not require curl or wget in the rish shell"
grep -F -- "install -r" "$tmp/log-bundled/pm.args" >/dev/null \
  || fail "bundled release installer must install the embedded APK"
grep -Fx -- "start" "$tmp/log-bundled/pawxyctl.args" >/dev/null \
  || fail "bundled release installer must start through embedded pawxyctl"

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
