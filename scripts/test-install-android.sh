#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/install-android.sh

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "scripts/install-android.sh must exist"
sh -n "$SCRIPT"

tmp=${TMPDIR:-/tmp}/pawxy-install-test.$$
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/bin-local" "$tmp/log" "$tmp/log-api" "$tmp/log-local" "$tmp/log-delayed-start" "$tmp/log-status-failure" "$tmp/log-native-status-failure" "$tmp/log-start-failure" "$tmp/log-status-error" "$tmp/log-last-error" "$tmp/log-bad-shell-uid" "$tmp/log-dump-denied" "$tmp/log-package-missing" "$tmp/release" "$tmp/install" "$tmp/install-api" "$tmp/install-local" "$tmp/install-delayed-start" "$tmp/install-status-failure" "$tmp/install-native-status-failure" "$tmp/install-start-failure" "$tmp/install-status-error" "$tmp/install-last-error" "$tmp/install-bad-shell-uid" "$tmp/install-dump-denied" "$tmp/install-package-missing" "$tmp/tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

printf 'fake apk\n' > "$tmp/release/pawxy-0.1.0-debug.apk"
cat > "$tmp/release/pawxyctl" <<'CTL'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/pawxyctl.args"
if [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; then
  if [ "${PAWXY_TEST_DELAY_STATUS_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    count_file=$PAWXY_TEST_LOG/status-count
    count=0
    [ -f "$count_file" ] && count=$(cat "$count_file")
    count=$((count + 1))
    printf '%s\n' "$count" > "$count_file"
    if [ "$count" -le "$PAWXY_TEST_DELAY_STATUS_COUNT" ]; then
      printf '%s\n' '{"running":false,"native_running":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"error":"starting"}'
      exit 0
    fi
  fi
  printf '%s\n' "${PAWXY_TEST_STATUS_JSON:-{ \"running\" : true, \"native_running\" : true, \"auth_enabled\" : false, \"native_auth_enabled\" : false, \"configured_auth_enabled\" : false }}"
elif [ "${1:-}" = "start" ] && [ "${PAWXY_TEST_START_FAIL:-0}" = "1" ]; then
  exit 42
fi
CTL
chmod 755 "$tmp/release/pawxyctl"
(
  cd "$tmp/release"
  sha256sum pawxy-0.1.0-debug.apk pawxyctl > SHA256SUMS
)
cat > "$tmp/release.json" <<JSON
{
  "assets": [
    {
      "url": "https://api.github.com/repos/ChrAlpha/pawxy/releases/assets/100",
      "name": "SHA256SUMS"
    },
    {
      "url": "https://api.github.com/repos/ChrAlpha/pawxy/releases/assets/101",
      "name": "pawxy-0.1.0-debug.apk"
    },
    {
      "url": "https://api.github.com/repos/ChrAlpha/pawxy/releases/assets/102",
      "name": "pawxyctl"
    }
  ]
}
JSON

cat > "$tmp/bin/curl" <<'CURL'
#!/bin/sh
out=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out=$2
      shift 2
      ;;
    -H)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done
[ -n "$out" ] || exit 2
case "$url" in
  */releases/latest|*/releases/tags/*)
    cp "$PAWXY_TEST_RELEASE_JSON" "$out"
    ;;
  */releases/assets/100)
    cp "$PAWXY_TEST_RELEASE/SHA256SUMS" "$out"
    ;;
  */releases/assets/101)
    cp "$PAWXY_TEST_RELEASE/pawxy-0.1.0-debug.apk" "$out"
    ;;
  */releases/assets/102)
    cp "$PAWXY_TEST_RELEASE/pawxyctl" "$out"
    ;;
  *)
    asset=${url##*/}
    cp "$PAWXY_TEST_RELEASE/$asset" "$out"
    ;;
esac
CURL
chmod 755 "$tmp/bin/curl"

cat > "$tmp/bin/pm" <<'PM'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/pm.args"
if [ "${1:-}" = "check-permission" ]; then
  printf '%s\n' "${PAWXY_TEST_DUMP_PERMISSION:-granted}"
elif [ "${1:-}" = "path" ] && [ "${2:-}" = "dev.pawxy" ]; then
  if [ "${PAWXY_TEST_PM_PATH_MISSING:-0}" != "1" ]; then
    printf '%s\n' "package:/data/app/dev.pawxy/base.apk"
  fi
fi
PM
chmod 755 "$tmp/bin/pm"

cat > "$tmp/bin/id" <<'ID'
#!/bin/sh
[ "${1:-}" = "-u" ] || exit 1
printf '%s\n' "${PAWXY_TEST_SHELL_UID:-2000}"
ID
chmod 755 "$tmp/bin/id"

PATH="$tmp/bin:$PATH" \
PAWXY_VERSION=0.1.0 \
PAWXY_INSTALL_DIR="$tmp/install" \
PAWXY_TEST_RELEASE="$tmp/release" \
	PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
	PAWXY_TEST_LOG="$tmp/log" \
	TMPDIR="$tmp/tmp" \
	  sh "$SCRIPT" >"$tmp/log/script.out"

grep -F -- "install -r" "$tmp/log/pm.args" >/dev/null \
  || fail "installer must call pm install -r"
grep -F -- "path dev.pawxy" "$tmp/log/pm.args" >/dev/null \
  || fail "installer must verify package visibility after install"
grep -F -- "grant dev.pawxy android.permission.POST_NOTIFICATIONS" "$tmp/log/pm.args" >/dev/null \
  || fail "installer must grant notification permission when shell can grant it"
grep -F -- "check-permission android.permission.DUMP com.android.shell" "$tmp/log/pm.args" >/dev/null \
  || fail "installer must verify shell DUMP permission before starting Pawxy"
grep -Fx -- "start" "$tmp/log/pawxyctl.args" >/dev/null \
  || fail "installer must start pawxy through installed pawxyctl"
grep -Fx -- "status --json" "$tmp/log/pawxyctl.args" >/dev/null \
  || fail "installer must verify Pawxy is running after start"
[ -x "$tmp/install/pawxyctl" ] || fail "installer must install executable pawxyctl"
grep -F -- "PAWXY_HOME=$tmp/install/pawxy $tmp/install/pawxyctl status" "$tmp/log/script.out" >/dev/null \
  || fail "installer output must show stable PAWXY_HOME control commands for Shizuku/rish"

PATH="$tmp/bin:$PATH" \
PAWXY_VERSION=0.1.0 \
PAWXY_GITHUB_TOKEN=fake-token \
PAWXY_INSTALL_DIR="$tmp/install-api" \
PAWXY_TEST_RELEASE="$tmp/release" \
PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
PAWXY_TEST_LOG="$tmp/log-api" \
TMPDIR="$tmp/tmp" \
  sh "$SCRIPT" >/dev/null

grep -F -- "install -r" "$tmp/log-api/pm.args" >/dev/null \
  || fail "private-token installer must call pm install -r"
grep -F -- "grant dev.pawxy android.permission.POST_NOTIFICATIONS" "$tmp/log-api/pm.args" >/dev/null \
  || fail "private-token installer must grant notification permission when shell can grant it"
grep -Fx -- "start" "$tmp/log-api/pawxyctl.args" >/dev/null \
  || fail "private-token installer must start pawxy through installed pawxyctl"
grep -Fx -- "status --json" "$tmp/log-api/pawxyctl.args" >/dev/null \
  || fail "private-token installer must verify Pawxy is running after start"
[ -x "$tmp/install-api/pawxyctl" ] || fail "private-token installer must install executable pawxyctl"

cat > "$tmp/bin-local/curl" <<'CURL'
#!/bin/sh
printf '%s\n' "curl" > "$PAWXY_TEST_LOG/network-attempted"
exit 37
CURL
chmod 755 "$tmp/bin-local/curl"

cat > "$tmp/bin-local/wget" <<'WGET'
#!/bin/sh
printf '%s\n' "wget" > "$PAWXY_TEST_LOG/network-attempted"
exit 37
WGET
chmod 755 "$tmp/bin-local/wget"

cat > "$tmp/bin-local/pm" <<'PM'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/pm.args"
if [ "${1:-}" = "check-permission" ]; then
  printf '%s\n' "${PAWXY_TEST_DUMP_PERMISSION:-granted}"
elif [ "${1:-}" = "path" ] && [ "${2:-}" = "dev.pawxy" ]; then
  if [ "${PAWXY_TEST_PM_PATH_MISSING:-0}" != "1" ]; then
    printf '%s\n' "package:/data/app/dev.pawxy/base.apk"
  fi
fi
PM
chmod 755 "$tmp/bin-local/pm"
ln -s "$tmp/bin/id" "$tmp/bin-local/id"

if ! PATH="$tmp/bin-local:$PATH" \
  PAWXY_ASSET_DIR="$tmp/release" \
  PAWXY_INSTALL_DIR="$tmp/install-local" \
  PAWXY_TEST_LOG="$tmp/log-local" \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >/dev/null; then
  fail "local asset installer must not require curl or wget"
fi

[ ! -f "$tmp/log-local/network-attempted" ] \
  || fail "local asset installer must not call curl or wget"
grep -F -- "install -r" "$tmp/log-local/pm.args" >/dev/null \
  || fail "local asset installer must call pm install -r"
grep -F -- "path dev.pawxy" "$tmp/log-local/pm.args" >/dev/null \
  || fail "local asset installer must verify package visibility after install"
grep -F -- "grant dev.pawxy android.permission.POST_NOTIFICATIONS" "$tmp/log-local/pm.args" >/dev/null \
  || fail "local asset installer must grant notification permission when shell can grant it"
grep -F -- "check-permission android.permission.DUMP com.android.shell" "$tmp/log-local/pm.args" >/dev/null \
  || fail "local asset installer must verify shell DUMP permission before starting Pawxy"
grep -Fx -- "start" "$tmp/log-local/pawxyctl.args" >/dev/null \
  || fail "local asset installer must start pawxy through installed pawxyctl"
grep -Fx -- "status --json" "$tmp/log-local/pawxyctl.args" >/dev/null \
  || fail "local asset installer must verify Pawxy is running after start"
[ -x "$tmp/install-local/pawxyctl" ] || fail "local asset installer must install executable pawxyctl"

PATH="$tmp/bin:$PATH" \
PAWXY_VERSION=0.1.0 \
PAWXY_INSTALL_DIR="$tmp/install-delayed-start" \
PAWXY_TEST_RELEASE="$tmp/release" \
PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
PAWXY_TEST_LOG="$tmp/log-delayed-start" \
PAWXY_TEST_DELAY_STATUS_COUNT=2 \
PAWXY_STARTUP_SLEEP_SECONDS=0 \
TMPDIR="$tmp/tmp" \
  sh "$SCRIPT" >/dev/null

status_checks=$(grep -cFx -- "status --json" "$tmp/log-delayed-start/pawxyctl.args")
[ "$status_checks" -ge 3 ] \
  || fail "installer must retry status checks while Pawxy is still starting"
[ -x "$tmp/install-delayed-start/pawxyctl" ] || fail "delayed-start installer must install executable pawxyctl"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-status-failure" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-status-failure" \
  PAWXY_TEST_STATUS_JSON='{"running":false,"error":"not-started"}' \
  PAWXY_STARTUP_RETRIES=2 \
  PAWXY_STARTUP_SLEEP_SECONDS=0 \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-status-failure/script.out" 2>"$tmp/log-status-failure/script.err"; then
  fail "installer must fail when Pawxy does not report running after start"
fi
grep -F -- "did not report running=true" "$tmp/log-status-failure/script.err" >/dev/null \
  || fail "installer status failure must explain that Pawxy did not report running=true"
grep -Fx -- "stop" "$tmp/log-status-failure/pawxyctl.args" >/dev/null \
  || fail "installer status failure must stop Pawxy after failed startup verification"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-native-status-failure" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-native-status-failure" \
  PAWXY_TEST_STATUS_JSON='{"running":true,"native_running":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false}' \
  PAWXY_STARTUP_RETRIES=2 \
  PAWXY_STARTUP_SLEEP_SECONDS=0 \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-native-status-failure/script.out" 2>"$tmp/log-native-status-failure/script.err"; then
  fail "installer must fail when wrapper status reports running but native proxy is not running"
fi
grep -F -- "did not report running=true/native_running=true" "$tmp/log-native-status-failure/script.err" >/dev/null \
  || fail "installer native status failure must explain that Pawxy did not report native_running=true"
grep -Fx -- "stop" "$tmp/log-native-status-failure/pawxyctl.args" >/dev/null \
  || fail "installer native status failure must stop Pawxy after failed startup verification"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-start-failure" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-start-failure" \
  PAWXY_TEST_START_FAIL=1 \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-start-failure/script.out" 2>"$tmp/log-start-failure/script.err"; then
  fail "installer must fail when installed pawxyctl start fails"
fi
grep -F -- "failed to start Pawxy through installed pawxyctl" "$tmp/log-start-failure/script.err" >/dev/null \
  || fail "installer start failure must explain that pawxyctl start failed"
grep -Fx -- "stop" "$tmp/log-start-failure/pawxyctl.args" >/dev/null \
  || fail "installer start failure must stop Pawxy after partial startup"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-status-error" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-status-error" \
  PAWXY_TEST_STATUS_JSON='{"ok":false,"error":"unauthorized"}' \
  PAWXY_STARTUP_RETRIES=2 \
  PAWXY_STARTUP_SLEEP_SECONDS=0 \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-status-error/script.out" 2>"$tmp/log-status-error/script.err"; then
  fail "installer must fail when Pawxy status reports an error instead of running"
fi
grep -F -- "status error=unauthorized" "$tmp/log-status-error/script.err" >/dev/null \
  || fail "installer status-error failure must surface the status error field"
grep -F -- '{"ok":false,"error":"unauthorized"}' "$tmp/log-status-error/script.err" >/dev/null \
  || fail "installer status-error failure must preserve the raw status JSON"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-last-error" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-last-error" \
  PAWXY_TEST_STATUS_JSON='{"running":false,"native_running":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"last_error":"bind preflight failed"}' \
  PAWXY_STARTUP_RETRIES=2 \
  PAWXY_STARTUP_SLEEP_SECONDS=0 \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-last-error/script.out" 2>"$tmp/log-last-error/script.err"; then
  fail "installer must fail when Pawxy status reports native last_error instead of running"
fi
grep -F -- "status error=bind preflight failed" "$tmp/log-last-error/script.err" >/dev/null \
  || fail "installer last-error failure must surface the native last_error field"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-bad-shell-uid" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-bad-shell-uid" \
  PAWXY_TEST_SHELL_UID=10000 \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-bad-shell-uid/script.out" 2>"$tmp/log-bad-shell-uid/script.err"; then
  fail "installer must reject non-shell app-like uids before installing Pawxy"
fi
grep -F -- "installer must run as Android shell or root" "$tmp/log-bad-shell-uid/script.err" >/dev/null \
  || fail "bad shell uid installer failure must explain the rejected uid"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-dump-denied" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-dump-denied" \
  PAWXY_TEST_DUMP_PERMISSION=denied \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-dump-denied/script.out" 2>"$tmp/log-dump-denied/script.err"; then
  fail "installer must reject shell environments without DUMP permission before starting Pawxy"
fi
grep -F -- "com.android.shell lacks android.permission.DUMP" "$tmp/log-dump-denied/script.err" >/dev/null \
  || fail "DUMP denied installer failure must explain the missing shell DUMP permission"

if PATH="$tmp/bin:$PATH" \
  PAWXY_VERSION=0.1.0 \
  PAWXY_INSTALL_DIR="$tmp/install-package-missing" \
  PAWXY_TEST_RELEASE="$tmp/release" \
  PAWXY_TEST_RELEASE_JSON="$tmp/release.json" \
  PAWXY_TEST_LOG="$tmp/log-package-missing" \
  PAWXY_TEST_PM_PATH_MISSING=1 \
  TMPDIR="$tmp/tmp" \
    sh "$SCRIPT" >"$tmp/log-package-missing/script.out" 2>"$tmp/log-package-missing/script.err"; then
  fail "installer must fail when the package is not visible after install"
fi
grep -F -- "Pawxy package dev.pawxy was not visible after install" "$tmp/log-package-missing/script.err" >/dev/null \
  || fail "package visibility installer failure must explain pm path did not find dev.pawxy"

printf '%s\n' "install-android test ok"
