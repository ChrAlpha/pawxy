#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/install-apk-adb.sh

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "scripts/install-apk-adb.sh must exist"
sh -n "$SCRIPT"

tmp=${TMPDIR:-/tmp}/pawxy-install-apk-adb-test.$$
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/log" "$tmp/log-auto-serial" "$tmp/log-no-device" "$tmp/log-multiple-devices" "$tmp/log-bad-serial" "$tmp/log-bad-uid" "$tmp/log-dump-denied" "$tmp/log-package-missing" "$tmp/log-status-failure" "$tmp/log-start-failure" "$tmp/log-status-last-error" "$tmp/log-invalid-timeout" "$tmp/files"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

printf '%s\n' "fake apk" > "$tmp/files/app-debug.apk"
printf '%s\n' "#!/bin/sh" > "$tmp/files/pawxyctl"
chmod 755 "$tmp/files/pawxyctl"

cat > "$tmp/bin/timeout" <<'TIMEOUT'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/timeout.log"
shift
exec "$@"
TIMEOUT
chmod 755 "$tmp/bin/timeout"

cat > "$tmp/bin/adb" <<'ADB'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/adb.log"
if [ "${1:-}" = "-s" ]; then
  shift 2
fi
cmd=${1:-}
[ "$#" -gt 0 ] && shift || true
case "$cmd" in
  devices)
    printf '%s\n\n' "List of devices attached"
    case "${PAWXY_TEST_DEVICE_COUNT:-1}" in
      0)
        ;;
      2)
        printf '%s\t%s\n' "FAKEPIXEL" "device"
        printf '%s\t%s\n' "FAKETABLET" "device"
        ;;
      *)
        printf '%s\t%s\n' "FAKEPIXEL" "device"
        ;;
    esac
    ;;
  get-state)
    if [ "${PAWXY_TEST_BAD_SERIAL:-0}" = "1" ]; then
      printf '%s\n' "unknown"
      exit 1
    fi
    printf '%s\n' "device"
    ;;
  install|push)
    exit 0
    ;;
  shell)
    line=$*
    case "$line" in
      "id -u")
        printf '%s\n' "${PAWXY_TEST_SHELL_UID:-2000}"
        ;;
      "pm check-permission android.permission.DUMP com.android.shell")
        printf '%s\n' "${PAWXY_TEST_DUMP_PERMISSION:-granted}"
        ;;
      "pm path dev.pawxy")
        if [ "${PAWXY_TEST_PM_PATH_MISSING:-0}" != "1" ]; then
          printf '%s\n' "package:/data/app/dev.pawxy/base.apk"
        fi
        ;;
      *"pawxyctl start"*)
        if [ "${PAWXY_TEST_START_FAIL:-0}" = "1" ]; then
          exit 42
        fi
        printf '%s\n' "started"
        ;;
      *"pawxyctl status --json"*)
        printf '%s\n' "${PAWXY_TEST_STATUS_JSON:-{\"running\":true,\"native_running\":true,\"auth_enabled\":false,\"native_auth_enabled\":false,\"configured_auth_enabled\":false}}"
        ;;
    esac
    ;;
esac
ADB
chmod 755 "$tmp/bin/adb"

PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  ANDROID_SERIAL=FAKEPIXEL \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" >"$tmp/log/script.out"

grep -F -- "120 $tmp/bin/adb -s FAKEPIXEL install -r $tmp/files/app-debug.apk" "$tmp/log/timeout.log" >/dev/null \
  || fail "install-apk-adb must bound adb install with timeout and selected serial"
grep -F -- "120 $tmp/bin/adb -s FAKEPIXEL get-state" "$tmp/log/timeout.log" >/dev/null \
  || fail "install-apk-adb must validate explicit ANDROID_SERIAL before installing"
grep -F -- "30 $tmp/bin/adb -s FAKEPIXEL shell id -u" "$tmp/log/timeout.log" >/dev/null \
  || fail "install-apk-adb must preflight shell identity under timeout"
grep -F -- "pm check-permission android.permission.DUMP com.android.shell" "$tmp/log/adb.log" >/dev/null \
  || fail "install-apk-adb must verify shell DUMP permission"
grep -F -- "pm path dev.pawxy" "$tmp/log/adb.log" >/dev/null \
  || fail "install-apk-adb must verify package visibility after adb install"
grep -F -- "120 $tmp/bin/adb -s FAKEPIXEL push $tmp/files/pawxyctl /data/local/tmp/pawxyctl" "$tmp/log/timeout.log" >/dev/null \
  || fail "install-apk-adb must bound pawxyctl push with timeout and selected serial"
grep -F -- "30 $tmp/bin/adb -s FAKEPIXEL shell chmod 755 /data/local/tmp/pawxyctl" "$tmp/log/timeout.log" >/dev/null \
  || fail "install-apk-adb must bound remote chmod with timeout and selected serial"
grep -F -- "30 $tmp/bin/adb -s FAKEPIXEL shell PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl start" "$tmp/log/timeout.log" >/dev/null \
  || fail "install-apk-adb must start Pawxy through pushed pawxyctl under timeout"
grep -F -- "30 $tmp/bin/adb -s FAKEPIXEL shell PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl status --json" "$tmp/log/timeout.log" >/dev/null \
  || fail "install-apk-adb must verify Pawxy status through pushed pawxyctl under timeout"
grep -F -- "Installed and started Pawxy." "$tmp/log/script.out" >/dev/null \
  || fail "install-apk-adb must report that Pawxy was started"
grep -F -- "rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl start'" "$tmp/log/script.out" >/dev/null \
  || fail "install-apk-adb must print Shizuku/rish control examples"
grep -F -- "RISH_APPLICATION_ID=com.termux sh /sdcard/Android/data/moe.shizuku.privileged.api/files/rish -c" "$tmp/log/script.out" >/dev/null \
  || fail "install-apk-adb must print a terminal-exported Shizuku rish example"

PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-auto-serial" \
  sh "$SCRIPT" >"$tmp/log-auto-serial/script.out"

grep -F -- "120 $tmp/bin/adb devices" "$tmp/log-auto-serial/timeout.log" >/dev/null \
  || fail "install-apk-adb must discover a single connected adb device when ANDROID_SERIAL is unset"
grep -F -- "120 $tmp/bin/adb -s FAKEPIXEL install -r $tmp/files/app-debug.apk" "$tmp/log-auto-serial/timeout.log" >/dev/null \
  || fail "install-apk-adb must install to the selected single adb device"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-no-device" \
  PAWXY_TEST_DEVICE_COUNT=0 \
  sh "$SCRIPT" >"$tmp/log-no-device/script.out" 2>"$tmp/log-no-device/script.err"; then
  fail "install-apk-adb must fail clearly when no adb device is connected"
fi
grep -F -- "expected exactly one adb device or ANDROID_SERIAL, found 0" "$tmp/log-no-device/script.err" >/dev/null \
  || fail "install-apk-adb no-device failure must explain the adb device count"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-multiple-devices" \
  PAWXY_TEST_DEVICE_COUNT=2 \
  sh "$SCRIPT" >"$tmp/log-multiple-devices/script.out" 2>"$tmp/log-multiple-devices/script.err"; then
  fail "install-apk-adb must fail clearly when multiple adb devices are connected"
fi
grep -F -- "expected exactly one adb device or ANDROID_SERIAL, found 2" "$tmp/log-multiple-devices/script.err" >/dev/null \
  || fail "install-apk-adb multiple-device failure must explain the adb device count"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  ANDROID_SERIAL=BADPIXEL \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-bad-serial" \
  PAWXY_TEST_BAD_SERIAL=1 \
  sh "$SCRIPT" >"$tmp/log-bad-serial/script.out" 2>"$tmp/log-bad-serial/script.err"; then
  fail "install-apk-adb must fail clearly when ANDROID_SERIAL is not connected"
fi
grep -F -- "ANDROID_SERIAL=BADPIXEL is not in device state" "$tmp/log-bad-serial/script.err" >/dev/null \
  || fail "install-apk-adb bad-serial failure must explain the selected serial state"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-bad-uid" \
  PAWXY_TEST_SHELL_UID=10000 \
  sh "$SCRIPT" >"$tmp/log-bad-uid/script.out" 2>"$tmp/log-bad-uid/script.err"; then
  fail "install-apk-adb must reject app-like shell uids before installing"
fi
grep -F -- "installer must run as Android shell or root" "$tmp/log-bad-uid/script.err" >/dev/null \
  || fail "install-apk-adb bad uid failure must explain the rejected shell uid"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-dump-denied" \
  PAWXY_TEST_DUMP_PERMISSION=denied \
  sh "$SCRIPT" >"$tmp/log-dump-denied/script.out" 2>"$tmp/log-dump-denied/script.err"; then
  fail "install-apk-adb must reject shells without DUMP permission before installing"
fi
grep -F -- "com.android.shell lacks android.permission.DUMP" "$tmp/log-dump-denied/script.err" >/dev/null \
  || fail "install-apk-adb DUMP failure must explain the missing shell permission"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-package-missing" \
  PAWXY_TEST_PM_PATH_MISSING=1 \
  sh "$SCRIPT" >"$tmp/log-package-missing/script.out" 2>"$tmp/log-package-missing/script.err"; then
  fail "install-apk-adb must fail when the package is not visible after adb install"
fi
grep -F -- "Pawxy package dev.pawxy was not visible after adb install" "$tmp/log-package-missing/script.err" >/dev/null \
  || fail "install-apk-adb package visibility failure must explain pm path did not find dev.pawxy"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-status-failure" \
  PAWXY_STARTUP_RETRIES=0 \
  PAWXY_TEST_STATUS_JSON='{"running":true,"native_running":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false}' \
  sh "$SCRIPT" >"$tmp/log-status-failure/script.out" 2>"$tmp/log-status-failure/script.err"; then
  fail "install-apk-adb must fail when Pawxy does not report native_running=true after install"
fi
grep -F -- "did not report running=true/native_running=true after adb install" "$tmp/log-status-failure/script.err" >/dev/null \
  || fail "install-apk-adb status failure must explain missing native_running=true"
grep -F -- "PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl stop" "$tmp/log-status-failure/adb.log" >/dev/null \
  || fail "install-apk-adb status failure must stop Pawxy after failed startup verification"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-start-failure" \
  PAWXY_TEST_START_FAIL=1 \
  sh "$SCRIPT" >"$tmp/log-start-failure/script.out" 2>"$tmp/log-start-failure/script.err"; then
  fail "install-apk-adb must fail when pushed pawxyctl start fails"
fi
grep -F -- "failed to start Pawxy through pushed pawxyctl" "$tmp/log-start-failure/script.err" >/dev/null \
  || fail "install-apk-adb start failure must explain that pawxyctl start failed"
grep -F -- "PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl stop" "$tmp/log-start-failure/adb.log" >/dev/null \
  || fail "install-apk-adb start failure must stop Pawxy after partial startup"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-status-last-error" \
  PAWXY_STARTUP_RETRIES=0 \
  PAWXY_TEST_STATUS_JSON='{"running":false,"native_running":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"last_error":"bind preflight failed"}' \
  sh "$SCRIPT" >"$tmp/log-status-last-error/script.out" 2>"$tmp/log-status-last-error/script.err"; then
  fail "install-apk-adb must surface native last_error diagnostics when Pawxy does not start"
fi
grep -F -- "status error=bind preflight failed" "$tmp/log-status-last-error/script.err" >/dev/null \
  || fail "install-apk-adb status failure must surface native last_error diagnostics"
grep -F -- "PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl stop" "$tmp/log-status-last-error/adb.log" >/dev/null \
  || fail "install-apk-adb last-error failure must stop Pawxy after failed startup verification"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_ADB_TIMEOUT_SECONDS=0 \
  PAWXY_TEST_LOG="$tmp/log-invalid-timeout" \
  sh "$SCRIPT" >"$tmp/log-invalid-timeout/script.out" 2>"$tmp/log-invalid-timeout/script.err"; then
  fail "install-apk-adb must reject invalid adb timeout settings"
fi
grep -F -- "PAWXY_ADB_TIMEOUT_SECONDS must be greater than zero" "$tmp/log-invalid-timeout/script.err" >/dev/null \
  || fail "install-apk-adb invalid timeout failure must explain the rejected setting"

printf '%s\n' "install-apk-adb test ok"
