#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/pawxyctl

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "scripts/pawxyctl must exist"
sh -n "$SCRIPT"

tmp=${TMPDIR:-/tmp}/pawxyctl-test.$$
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/log"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cat > "$tmp/bin/od" <<'OD'
#!/bin/sh
printf '%s\n' ' 12 34 56 78 90 ab cd ef 12 34 56 78 90 ab cd ef 12 34 56 78 90 ab cd ef 12 34 56 78 90 ab cd ef'
OD
chmod 755 "$tmp/bin/od"

cat > "$tmp/bin/content" <<'CONTENT'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/content.args"
if [ "${PAWXY_TEST_CONTENT_FAIL:-0}" = "1" ]; then
  printf '%s\n' "SecurityException: Permission Denial" >&2
  exit 13
fi
if [ "${PAWXY_TEST_CONTENT_EMPTY:-0}" = "1" ]; then
  exit 0
fi
if [ "${PAWXY_TEST_STATUS_UNAUTHORIZED:-0}" = "1" ]; then
  printf '%s\n' 'Row: 0 json={"ok":false,"error":"unauthorized"}'
  exit 0
fi
if [ "${PAWXY_TEST_STATUS_UNAUTHORIZED_ONCE:-0}" = "1" ] && [ ! -f "$PAWXY_TEST_LOG/status-authorized" ]; then
  : > "$PAWXY_TEST_LOG/status-authorized"
  printf '%s\n' 'Row: 0 json={"ok":false,"error":"unauthorized"}'
  exit 0
fi
if [ -n "${PAWXY_TEST_STATUS_JSON:-}" ]; then
  printf '%s\n' "Row: 0 json=$PAWXY_TEST_STATUS_JSON"
  exit 0
fi
if [ -f "$PAWXY_TEST_LOG/status-state.json" ]; then
  printf 'Row: 0 json=%s\n' "$(cat "$PAWXY_TEST_LOG/status-state.json")"
  exit 0
fi
printf '%s\n' 'Row: 0 json={ "running" : true, "native_running" : true, "listen" : "127.0.0.1:3218", "native_listen" : "127.0.0.1:3218", "configured_listen" : "127.0.0.1:3218", "lan" : false, "native_lan" : false, "configured_lan" : false, "auth_enabled" : true, "native_auth_enabled" : true, "configured_auth_enabled" : true, "native_started_at_unix_ms" : 1000, "active_connections" : 2, "total_connections" : 7, "bytes_in" : 11, "bytes_out" : 13, "wake_lock_enabled" : true, "network_available" : true, "network_transport" : "wifi", "network_generation" : 3, "last_error" : null }'
CONTENT
chmod 755 "$tmp/bin/content"

cat > "$tmp/bin/am" <<'AM'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/am.args"
if [ "${PAWXY_TEST_AM_FAIL:-0}" = "1" ]; then
  case "$*" in
    *"dev.pawxy.action.RESET_TOKEN"*) ;;
    *)
      printf '%s\n' "am failed" >&2
      exit 37
      ;;
  esac
fi
if [ "${PAWXY_TEST_FGS_BACKGROUND_FAIL:-0}" = "1" ]; then
  case "$*" in
    start-foreground-service*)
      printf '%s\n' "Error: app is in background uid null" >&2
      exit 37
      ;;
  esac
fi
state=$PAWXY_TEST_LOG/status-state.json
case "$*" in
  *"dev.pawxy.action.START"*)
    case "$*" in
      *"--ez auth_enabled true"*)
        printf '%s\n' '{"running":true,"native_running":true,"listen":"0.0.0.0:3218","native_listen":"0.0.0.0:3218","configured_listen":"0.0.0.0:3218","lan":true,"native_lan":true,"configured_lan":true,"auth_enabled":true,"native_auth_enabled":true,"configured_auth_enabled":true,"native_started_at_unix_ms":1000,"active_connections":0,"total_connections":7,"bytes_in":11,"bytes_out":13,"wake_lock_enabled":false,"network_available":true,"network_transport":"wifi","network_generation":3,"last_error":null}' > "$state"
        ;;
      *)
        printf '%s\n' '{"running":true,"native_running":true,"listen":"127.0.0.1:3218","native_listen":"127.0.0.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"native_started_at_unix_ms":1000,"active_connections":0,"total_connections":7,"bytes_in":11,"bytes_out":13,"wake_lock_enabled":false,"network_available":true,"network_transport":"wifi","network_generation":3,"last_error":null}' > "$state"
        ;;
    esac
    ;;
  *"dev.pawxy.action.RESTART"*)
    printf '%s\n' '{"running":true,"native_running":true,"listen":"127.0.0.1:3218","native_listen":"127.0.0.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"native_started_at_unix_ms":1000,"active_connections":0,"total_connections":7,"bytes_in":11,"bytes_out":13,"wake_lock_enabled":false,"network_available":true,"network_transport":"wifi","network_generation":3,"last_error":null}' > "$state"
    ;;
  *"dev.pawxy.action.STOP"*)
    printf '%s\n' '{"running":false,"native_running":false,"listen":"127.0.0.1:3218","native_listen":"127.0.0.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"native_started_at_unix_ms":1000,"active_connections":0,"total_connections":7,"bytes_in":11,"bytes_out":13,"wake_lock_enabled":false,"network_available":true,"network_transport":"wifi","network_generation":3,"last_error":null}' > "$state"
    ;;
  *"dev.pawxy.action.WAKE_ON"*)
    printf '%s\n' '{"running":true,"native_running":true,"listen":"127.0.0.1:3218","native_listen":"127.0.0.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"native_started_at_unix_ms":1000,"active_connections":0,"total_connections":7,"bytes_in":11,"bytes_out":13,"wake_lock_enabled":true,"network_available":true,"network_transport":"wifi","network_generation":3,"last_error":null}' > "$state"
    ;;
  *"dev.pawxy.action.WAKE_OFF"*)
    printf '%s\n' '{"running":true,"native_running":true,"listen":"127.0.0.1:3218","native_listen":"127.0.0.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"native_started_at_unix_ms":1000,"active_connections":0,"total_connections":7,"bytes_in":11,"bytes_out":13,"wake_lock_enabled":false,"network_available":true,"network_transport":"wifi","network_generation":3,"last_error":null}' > "$state"
    ;;
esac
if [ "${PAWXY_TEST_NATIVE_RUNNING_FALSE:-0}" = "1" ] && [ -f "$state" ]; then
  sed 's/"native_running":true/"native_running":false/g' "$state" > "$state.tmp"
  mv "$state.tmp" "$state"
fi
AM
chmod 755 "$tmp/bin/am"

cat > "$tmp/bin/pm" <<'PM'
#!/bin/sh
case "${1:-}" in
  path)
    printf '%s\n' 'package:/data/app/dev.pawxy/base.apk'
    ;;
  check-permission)
    case "${2:-}" in
      android.permission.DUMP)
        printf '%s\n' "${PAWXY_TEST_DUMP_PERMISSION:-granted}"
        ;;
      *)
        printf '%s\n' 'granted'
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
PM
chmod 755 "$tmp/bin/pm"

expected_token=1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
expected_lan_password=1234567890abcdef1234567890abcdef

PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" status >"$tmp/log/status.out"

grep -Fx -- "pawxy: running" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must parse spaced JSON running=true"
grep -Fx -- "auth: on" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must parse spaced JSON auth_enabled=true"
grep -Fx -- "native: running=true listen=127.0.0.1:3218 lan=false auth=true started-at=1000" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must surface native runtime state"
grep -Fx -- "configured: listen=127.0.0.1:3218 lan=false auth=true" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must surface persisted configured state"
grep -Fx -- "active: 2" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must parse spaced JSON active_connections"
grep -Fx -- "bytes: 11/13" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must parse spaced JSON byte counters"
grep -Fx -- "wake-lock: on" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must parse spaced JSON wake_lock_enabled=true"
grep -Fx -- "network: true/wifi gen=3" "$tmp/log/status.out" >/dev/null \
  || fail "pawxyctl status must parse spaced JSON network fields"

PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_STATUS_JSON='{"ok":false,"error":"unauthorized"}' \
  sh "$SCRIPT" status >"$tmp/log/status-error.out"

grep -Fx -- "pawxy: unknown" "$tmp/log/status-error.out" >/dev/null \
  || fail "pawxyctl status must not report stopped when status JSON contains an error without running"
grep -Fx -- "last-error: unauthorized" "$tmp/log/status-error.out" >/dev/null \
  || fail "pawxyctl status must surface status JSON error messages"

: > "$tmp/log/am.args"
rm -f "$tmp/log/status-authorized"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_STATUS_UNAUTHORIZED_ONCE=1 \
  sh "$SCRIPT" status >"$tmp/log/status-healed.out"

grep -Fx -- "pawxy: running" "$tmp/log/status-healed.out" >/dev/null \
  || fail "pawxyctl status must retry after synchronizing an unauthorized control token"
grep -F -- "dev.pawxy.action.RESET_TOKEN" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl status must synchronize the control token when the provider reports unauthorized"

PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_CONTENT_EMPTY=1 \
  sh "$SCRIPT" status >"$tmp/log/status-unavailable.out"

grep -Fx -- "pawxy: unknown" "$tmp/log/status-unavailable.out" >/dev/null \
  || fail "pawxyctl status must not report stopped when provider status is unavailable"
grep -Fx -- "last-error: status unavailable" "$tmp/log/status-unavailable.out" >/dev/null \
  || fail "pawxyctl status must surface provider status unavailable errors"

PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_CONTENT_FAIL=1 \
  sh "$SCRIPT" status >"$tmp/log/status-content-fail.out"

grep -Fx -- "pawxy: unknown" "$tmp/log/status-content-fail.out" >/dev/null \
  || fail "pawxyctl status must not report stopped when content query fails"
grep -Fx -- "last-error: content query failed" "$tmp/log/status-content-fail.out" >/dev/null \
  || fail "pawxyctl status must distinguish content query failures from empty provider output"

: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" doctor >"$tmp/log/doctor.out"

grep -Fx -- "wake lock according to status: enabled" "$tmp/log/doctor.out" >/dev/null \
  || fail "pawxyctl doctor must parse spaced JSON wake_lock_enabled=true"
grep -Fx -- "network according to status: true/wifi gen=3" "$tmp/log/doctor.out" >/dev/null \
  || fail "pawxyctl doctor must parse spaced JSON network fields"
grep -Fx -- "  native: running=true listen=127.0.0.1:3218 lan=false auth=true started-at=1000" "$tmp/log/doctor.out" >/dev/null \
  || fail "pawxyctl doctor must surface native runtime state"
grep -Fx -- "  configured: listen=127.0.0.1:3218 lan=false auth=true" "$tmp/log/doctor.out" >/dev/null \
  || fail "pawxyctl doctor must surface persisted configured state"
grep -Fx -- "shell DUMP permission: granted" "$tmp/log/doctor.out" >/dev/null \
  || fail "pawxyctl doctor must report whether com.android.shell has DUMP permission"
doctor_status_queries=$(wc -l < "$tmp/log/content.args" | tr -d ' ')
[ "$doctor_status_queries" = "1" ] \
  || fail "pawxyctl doctor must query status once to keep Shizuku/rish diagnostics efficient"

PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_CONTENT_FAIL=1 \
  sh "$SCRIPT" doctor >"$tmp/log/doctor-content-fail.out"

grep -Fx -- "  pawxy: unknown" "$tmp/log/doctor-content-fail.out" >/dev/null \
  || fail "pawxyctl doctor must not report stopped when content query fails"
grep -Fx -- "  last-error: content query failed" "$tmp/log/doctor-content-fail.out" >/dev/null \
  || fail "pawxyctl doctor must surface content query failures"

PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_DUMP_PERMISSION=denied \
  sh "$SCRIPT" doctor >"$tmp/log/doctor-dump-denied.out"

grep -Fx -- "shell DUMP permission: denied" "$tmp/log/doctor-dump-denied.out" >/dev/null \
  || fail "pawxyctl doctor must make missing shell DUMP permission visible"

printf '%s\n' "bad/token value" > "$tmp/home/token"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" status --json >"$tmp/log/status-json.out"

grep -Fx -- "$expected_token" "$tmp/home/token" >/dev/null \
  || fail "pawxyctl must repair invalid persisted control tokens"
grep -F -- "$expected_token" "$tmp/log/content.args" >/dev/null \
  || fail "pawxyctl status must query with the repaired control token"
! grep -F -- "bad/token value" "$tmp/log/content.args" >/dev/null \
  || fail "pawxyctl status must not query with an invalid persisted control token"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" reset-token >"$tmp/log/reset-token.out"

grep -F -- "dev.pawxy.action.RESET_TOKEN" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl reset-token must send the reset-token service action"
grep -F -- "startservice -n dev.pawxy/.ProxyService -a dev.pawxy.action.RESET_TOKEN" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl reset-token must avoid foreground-service startup for token-only recovery"
! grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.RESET_TOKEN" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl reset-token must not use foreground-service startup for token-only recovery"
grep -F -- "--es token $expected_token" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl reset-token must send the repaired control token"
grep -F -- "$expected_token" "$tmp/log/content.args" >/dev/null \
  || fail "pawxyctl reset-token must verify the status provider with the repaired control token"
grep -F -- "control token reset" "$tmp/log/reset-token.out" >/dev/null \
  || fail "pawxyctl reset-token must report the reset token path"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_STATUS_JSON='{"ok":false,"error":"unauthorized"}' \
  PAWXY_STARTUP_RETRIES=0 \
  sh "$SCRIPT" reset-token >"$tmp/log/reset-token-status-fail.out" 2>"$tmp/log/reset-token-status-fail.err"; then
  fail "pawxyctl reset-token must fail when provider authorization is still unavailable"
fi
grep -F -- "did not expose status field running after reset-token" "$tmp/log/reset-token-status-fail.err" >/dev/null \
  || fail "pawxyctl reset-token status failure must explain the missing running field"
grep -F -- "control token reset did not restore status authorization" "$tmp/log/reset-token-status-fail.err" >/dev/null \
  || fail "pawxyctl reset-token status failure must explain that authorization was not restored"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_STATUS_UNAUTHORIZED=1 \
  PAWXY_STARTUP_RETRIES=0 \
  sh "$SCRIPT" start >"$tmp/log/start-token-sync-fail.out" 2>"$tmp/log/start-token-sync-fail.err"; then
  fail "pawxyctl start must fail before START when token synchronization is still unauthorized"
fi
grep -F -- "dev.pawxy.action.RESET_TOKEN" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl start token-sync failure must try to reset the control token"
if grep -F -- "dev.pawxy.action.START" "$tmp/log/am.args" >/dev/null; then
  fail "pawxyctl start must not send START before token synchronization is verified"
fi
grep -F -- "control token was not accepted after token-sync" "$tmp/log/start-token-sync-fail.err" >/dev/null \
  || fail "pawxyctl start token-sync failure must explain that provider authorization was not restored"
grep -F -- "failed to start proxy" "$tmp/log/start-token-sync-fail.err" >/dev/null \
  || fail "pawxyctl start token-sync failure must explain the failed proxy start"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" start >/dev/null

reset_line=$(grep -n -- "dev.pawxy.action.RESET_TOKEN" "$tmp/log/am.args" | sed -n '1s/:.*//p')
start_line=$(grep -n -- "dev.pawxy.action.START" "$tmp/log/am.args" | sed -n '1s/:.*//p')
[ -n "$reset_line" ] && [ -n "$start_line" ] && [ "$reset_line" -lt "$start_line" ] \
  || fail "pawxyctl start must synchronize the control token before starting"
grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl start must use foreground-service startup"
grep -F -- '"running":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl start must wait for running=true status"
grep -F -- '"native_running":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl start must wait for native_running=true status"
grep -F -- '"auth_enabled":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl start must wait for auth_enabled=false status"
grep -F -- '"native_auth_enabled":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl start must wait for native_auth_enabled=false status"
grep -F -- '"configured_auth_enabled":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl start must wait for configured_auth_enabled=false status"
start_status_queries=$(grep -c -- "content://dev.pawxy.status/status" "$tmp/log/content.args")
[ "$start_status_queries" = "2" ] \
  || fail "pawxyctl start must verify token sync and startup fields with bounded status queries"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
rm -f "$tmp/log/status-state.json"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_FGS_BACKGROUND_FAIL=1 \
  sh "$SCRIPT" start >/dev/null

grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl start must try direct foreground-service startup before the activity bridge"
grep -F -- "start -n dev.pawxy/.ControlActivity -a dev.pawxy.action.START" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl start must fall back to the control activity when direct foreground-service startup is background-blocked"
grep -F -- '"running":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl start activity fallback must wait for running=true status"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_STATUS_JSON='{"running":false,"error":"bind failed"}' \
  PAWXY_STARTUP_RETRIES=0 \
  sh "$SCRIPT" start >"$tmp/log/start-status-fail.out" 2>"$tmp/log/start-status-fail.err"; then
  fail "pawxyctl start must fail when status never reports running=true"
fi
grep -F -- "did not report running=true/native_running=true/auth_enabled=false/native_auth_enabled=false/configured_auth_enabled=false after start" "$tmp/log/start-status-fail.err" >/dev/null \
  || fail "pawxyctl start status failure must explain the missing running=true status"
grep -F -- "status error=bind failed" "$tmp/log/start-status-fail.err" >/dev/null \
  || fail "pawxyctl start status failure must surface status errors"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_NATIVE_RUNNING_FALSE=1 \
  PAWXY_STARTUP_RETRIES=0 \
  sh "$SCRIPT" start >"$tmp/log/start-native-status-fail.out" 2>"$tmp/log/start-native-status-fail.err"; then
  fail "pawxyctl start must fail when wrapper status reports running=true but native_running=false"
fi
grep -F -- "did not report running=true/native_running=true/auth_enabled=false/native_auth_enabled=false/configured_auth_enabled=false after start" "$tmp/log/start-native-status-fail.err" >/dev/null \
  || fail "pawxyctl start native status failure must explain the missing native_running=true status"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" stop >/dev/null

reset_line=$(grep -n -- "dev.pawxy.action.RESET_TOKEN" "$tmp/log/am.args" | sed -n '1s/:.*//p')
stop_line=$(grep -n -- "dev.pawxy.action.STOP" "$tmp/log/am.args" | sed -n '1s/:.*//p')
[ -n "$reset_line" ] && [ -n "$stop_line" ] && [ "$reset_line" -lt "$stop_line" ] \
  || fail "pawxyctl stop must synchronize the control token before stopping"
grep -F -- "startservice -n dev.pawxy/.ProxyService -a dev.pawxy.action.STOP" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl stop must use normal service start for short control"
! grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.STOP" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl stop must not use foreground-service startup for short control"
grep -F -- '"running":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl stop must wait for running=false status"
grep -F -- '"native_running":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl stop must wait for native_running=false status"
stop_status_queries=$(grep -c -- "content://dev.pawxy.status/status" "$tmp/log/content.args")
[ "$stop_status_queries" = "2" ] \
  || fail "pawxyctl stop must verify token sync and stopped fields with bounded status queries"

printf '%s\n' "LAN_PASSWORD=a" > "$tmp/home/config.env"
: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" share on >"$tmp/log/share.out"

grep -Fx -- "LAN_PASSWORD=$expected_lan_password" "$tmp/home/config.env" >/dev/null \
  || fail "pawxyctl share on must repair weak persisted LAN passwords"
grep -F -- "--es password $expected_lan_password" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl share on must send the repaired LAN password"
grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl share on must use foreground-service startup"
! grep -F -- "--es password a" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl share on must not reuse weak persisted LAN passwords"
grep -F -- '"auth_enabled":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl share on must wait for auth_enabled=true status"
grep -F -- '"native_auth_enabled":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl share on must wait for native_auth_enabled=true status"
grep -F -- '"configured_auth_enabled":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl share on must wait for configured_auth_enabled=true status"
share_on_status_queries=$(grep -c -- "content://dev.pawxy.status/status" "$tmp/log/content.args")
[ "$share_on_status_queries" = "2" ] \
  || fail "pawxyctl share on must verify token sync and startup fields with bounded status queries"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" share off >/dev/null

grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl share off must use foreground-service startup"
grep -F -- '"auth_enabled":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl share off must wait for auth_enabled=false status"
grep -F -- '"native_auth_enabled":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl share off must wait for native_auth_enabled=false status"
grep -F -- '"configured_auth_enabled":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl share off must wait for configured_auth_enabled=false status"
share_off_status_queries=$(grep -c -- "content://dev.pawxy.status/status" "$tmp/log/content.args")
[ "$share_off_status_queries" = "2" ] \
  || fail "pawxyctl share off must verify token sync and startup fields with bounded status queries"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" wake on >/dev/null

grep -F -- "startservice -n dev.pawxy/.ProxyService -a dev.pawxy.action.WAKE_ON" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl wake on must use normal service start for short control"
! grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.WAKE_ON" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl wake on must not use foreground-service startup for short control"
grep -F -- '"wake_lock_enabled":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl wake on must wait for wake_lock_enabled=true status"
grep -F -- '"running":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl wake on must preserve running=true status"
grep -F -- '"native_running":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl wake on must preserve native_running=true status"
wake_on_status_queries=$(grep -c -- "content://dev.pawxy.status/status" "$tmp/log/content.args")
[ "$wake_on_status_queries" = "2" ] \
  || fail "pawxyctl wake on must verify token sync, wake, and running fields with bounded status queries"

: > "$tmp/log/am.args"
: > "$tmp/log/content.args"
PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  sh "$SCRIPT" wake off >/dev/null

grep -F -- "startservice -n dev.pawxy/.ProxyService -a dev.pawxy.action.WAKE_OFF" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl wake off must use normal service start for short control"
! grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.WAKE_OFF" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl wake off must not use foreground-service startup for short control"
grep -F -- '"wake_lock_enabled":false' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl wake off must wait for wake_lock_enabled=false status"
grep -F -- '"running":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl wake off must preserve running=true status"
grep -F -- '"native_running":true' "$tmp/log/status-state.json" >/dev/null \
  || fail "pawxyctl wake off must preserve native_running=true status"
wake_off_status_queries=$(grep -c -- "content://dev.pawxy.status/status" "$tmp/log/content.args")
[ "$wake_off_status_queries" = "2" ] \
  || fail "pawxyctl wake off must verify token sync, wake, and running fields with bounded status queries"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_NATIVE_RUNNING_FALSE=1 \
  PAWXY_STARTUP_RETRIES=0 \
  sh "$SCRIPT" wake on >"$tmp/log/wake-native-status-fail.out" 2>"$tmp/log/wake-native-status-fail.err"; then
  fail "pawxyctl wake on must fail when wake status reports native_running=false"
fi
grep -F -- "did not report running=true/native_running=true/wake_lock_enabled=true after wake on" "$tmp/log/wake-native-status-fail.err" >/dev/null \
  || fail "pawxyctl wake on native status failure must explain the missing native_running=true status"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_AM_FAIL=1 \
  sh "$SCRIPT" share on >"$tmp/log/share-fail.out" 2>"$tmp/log/share-fail.err"; then
  fail "pawxyctl share on must fail when am start-foreground-service fails"
fi
! grep -F -- "LAN sharing enabled" "$tmp/log/share-fail.out" >/dev/null \
  || fail "pawxyctl share on must not print success after am failure"
grep -F -- "am failed" "$tmp/log/share-fail.err" >/dev/null \
  || fail "pawxyctl share on must preserve am failure output"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_AM_FAIL=1 \
  sh "$SCRIPT" share off >"$tmp/log/share-off-fail.out" 2>"$tmp/log/share-off-fail.err"; then
  fail "pawxyctl share off must fail when am start-foreground-service fails"
fi
grep -F -- "am failed" "$tmp/log/share-off-fail.err" >/dev/null \
  || fail "pawxyctl share off must preserve am failure output"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_AM_FAIL=1 \
  sh "$SCRIPT" start >"$tmp/log/start-fail.out" 2>"$tmp/log/start-fail.err"; then
  fail "pawxyctl start must fail when am start-foreground-service fails"
fi
grep -F -- "am failed" "$tmp/log/start-fail.err" >/dev/null \
  || fail "pawxyctl start must preserve am failure output"
grep -F -- "pawxyctl: failed to start proxy" "$tmp/log/start-fail.err" >/dev/null \
  || fail "pawxyctl start must explain the failed proxy start"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_AM_FAIL=1 \
  sh "$SCRIPT" stop >"$tmp/log/stop-fail.out" 2>"$tmp/log/stop-fail.err"; then
  fail "pawxyctl stop must fail when am service start fails"
fi
grep -F -- "am failed" "$tmp/log/stop-fail.err" >/dev/null \
  || fail "pawxyctl stop must preserve am failure output"
grep -F -- "pawxyctl: failed to stop proxy" "$tmp/log/stop-fail.err" >/dev/null \
  || fail "pawxyctl stop must explain the failed proxy stop"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_AM_FAIL=1 \
  sh "$SCRIPT" restart >"$tmp/log/restart-fail.out" 2>"$tmp/log/restart-fail.err"; then
  fail "pawxyctl restart must fail when am start-foreground-service fails"
fi
grep -F -- "am failed" "$tmp/log/restart-fail.err" >/dev/null \
  || fail "pawxyctl restart must preserve am failure output"
grep -F -- "start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.RESTART" "$tmp/log/am.args" >/dev/null \
  || fail "pawxyctl restart must use foreground-service startup"
grep -F -- "pawxyctl: failed to restart proxy" "$tmp/log/restart-fail.err" >/dev/null \
  || fail "pawxyctl restart must explain the failed proxy restart"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_AM_FAIL=1 \
  sh "$SCRIPT" wake on >"$tmp/log/wake-on-fail.out" 2>"$tmp/log/wake-on-fail.err"; then
  fail "pawxyctl wake on must fail when am service start fails"
fi
grep -F -- "am failed" "$tmp/log/wake-on-fail.err" >/dev/null \
  || fail "pawxyctl wake on must preserve am failure output"
grep -F -- "pawxyctl: failed to enable wake lock" "$tmp/log/wake-on-fail.err" >/dev/null \
  || fail "pawxyctl wake on must explain the failed wake-lock enable"

if PATH="$tmp/bin:$PATH" \
  PAWXY_HOME="$tmp/home" \
  PAWXY_TEST_LOG="$tmp/log" \
  PAWXY_TEST_AM_FAIL=1 \
  sh "$SCRIPT" wake off >"$tmp/log/wake-off-fail.out" 2>"$tmp/log/wake-off-fail.err"; then
  fail "pawxyctl wake off must fail when am service start fails"
fi
grep -F -- "am failed" "$tmp/log/wake-off-fail.err" >/dev/null \
  || fail "pawxyctl wake off must preserve am failure output"
grep -F -- "pawxyctl: failed to disable wake lock" "$tmp/log/wake-off-fail.err" >/dev/null \
  || fail "pawxyctl wake off must explain the failed wake-lock disable"

printf '%s\n' "pawxyctl test ok"
