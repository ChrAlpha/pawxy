#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

ADB=${ADB:-adb}
APK=${PAWXY_APK:-android/app/build/outputs/apk/debug/app-debug.apk}
CTL=${PAWXY_CTL:-scripts/pawxyctl}
DEVICE_CTL=${PAWXY_DEVICE_CTL:-/data/local/tmp/pawxyctl}
DEVICE_HOME=${PAWXY_DEVICE_HOME:-/data/local/tmp/pawxy}
ADB_TIMEOUT_SECONDS=${PAWXY_ADB_TIMEOUT_SECONDS:-120}
DEVICE_SHELL_TIMEOUT_SECONDS=${PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS:-30}
STARTUP_RETRIES=${PAWXY_STARTUP_RETRIES:-20}
STARTUP_SLEEP_SECONDS=${PAWXY_STARTUP_SLEEP_SECONDS:-1}
SELECTED_SERIAL=${ANDROID_SERIAL:-}
START_SENT=0

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1 || [ -x "$1" ]
}

require_positive_int() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a positive integer" ;;
  esac
  [ "$value" -gt 0 ] 2>/dev/null || fail "$name must be greater than zero"
}

require_non_negative_int() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a non-negative integer" ;;
  esac
}

json_bool_field() {
  json=$1
  field=$2
  printf '%s\n' "$json" | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | sed -n '1p'
}

json_string_field() {
  json=$1
  field=$2
  printf '%s\n' "$json" | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p'
}

adb_cmd() {
  if [ -n "$SELECTED_SERIAL" ]; then
    timeout "$ADB_TIMEOUT_SECONDS" "$ADB" -s "$SELECTED_SERIAL" "$@"
  else
    timeout "$ADB_TIMEOUT_SECONDS" "$ADB" "$@"
  fi
}

device_sh() {
  if [ -n "$SELECTED_SERIAL" ]; then
    timeout "$DEVICE_SHELL_TIMEOUT_SECONDS" "$ADB" -s "$SELECTED_SERIAL" shell "$@"
  else
    timeout "$DEVICE_SHELL_TIMEOUT_SECONDS" "$ADB" shell "$@"
  fi
}

list_adb_device_serials() {
  timeout "$ADB_TIMEOUT_SECONDS" "$ADB" devices | awk '$2 == "device" { print $1 }'
}

select_device() {
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    SELECTED_SERIAL=$ANDROID_SERIAL
    state=$(adb_cmd get-state 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }' || true)
    [ "$state" = "device" ] || fail "ANDROID_SERIAL=$ANDROID_SERIAL is not in device state: ${state:-unknown}"
    return 0
  fi

  devices=$(list_adb_device_serials)
  count=$(printf '%s\n' "$devices" | awk 'NF { count += 1 } END { print count + 0 }')
  [ "$count" = "1" ] || fail "expected exactly one adb device or ANDROID_SERIAL, found $count"
  SELECTED_SERIAL=$(printf '%s\n' "$devices" | awk 'NF { print; exit }')
}

verify_android_shell_permissions() {
  uid=$(device_sh id -u 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }')
  case "$uid" in
    0|2000)
      ;;
    *)
      fail "installer must run as Android shell or root; got uid ${uid:-unknown}. Check adb shell or Shizuku/rish setup."
      ;;
  esac

  if [ "$uid" = "2000" ]; then
    dump_permission=$(device_sh pm check-permission android.permission.DUMP com.android.shell 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }')
    case "$dump_permission" in
      granted*)
        ;;
      *)
        fail "com.android.shell lacks android.permission.DUMP: ${dump_permission:-unknown}. Check adb shell or Shizuku/rish setup."
        ;;
    esac
  fi
}

verify_package_installed() {
  package_path=$(device_sh pm path dev.pawxy 2>/dev/null | tr -d '\r' | awk '/^package:/ { print; exit }')
  [ -n "$package_path" ] \
    || fail "Pawxy package dev.pawxy was not visible after adb install; pm path returned empty"
}

status_json() {
  device_sh "PAWXY_HOME=$DEVICE_HOME $DEVICE_CTL status --json" | tr -d '\r'
}

stop_started_service() {
  [ "$START_SENT" = "1" ] || return 0
  device_sh "PAWXY_HOME=$DEVICE_HOME $DEVICE_CTL stop" >/dev/null 2>&1 || true
}

wait_for_running_status() {
  attempt=0
  status_json_text=
  status_error=
  while [ "$attempt" -le "$STARTUP_RETRIES" ]; do
    status_json_text=$(status_json 2>/dev/null || true)
    if [ "$(json_bool_field "$status_json_text" running)" = "true" ] \
      && [ "$(json_bool_field "$status_json_text" native_running)" = "true" ] \
      && [ "$(json_bool_field "$status_json_text" auth_enabled)" = "false" ] \
      && [ "$(json_bool_field "$status_json_text" native_auth_enabled)" = "false" ] \
      && [ "$(json_bool_field "$status_json_text" configured_auth_enabled)" = "false" ]; then
      return 0
    fi
    current_error=$(json_string_field "$status_json_text" error)
    if [ -z "$current_error" ] || [ "$current_error" = "null" ]; then
      current_error=$(json_string_field "$status_json_text" last_error)
    fi
    if [ -n "$current_error" ] && [ "$current_error" != "null" ]; then
      status_error=$current_error
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$STARTUP_RETRIES" ] || break
    sleep "$STARTUP_SLEEP_SECONDS"
  done
  if [ -n "$status_error" ]; then
    stop_started_service
    fail "Pawxy did not report running=true/native_running=true after adb install; status error=$status_error: ${status_json_text:-empty status}"
  fi
  stop_started_service
  fail "Pawxy did not report running=true/native_running=true after adb install: ${status_json_text:-empty status}"
}

has_cmd "$ADB" || fail "adb not found: $ADB"
has_cmd timeout || fail "host timeout is required for bounded adb install"
require_positive_int PAWXY_ADB_TIMEOUT_SECONDS "$ADB_TIMEOUT_SECONDS"
require_positive_int PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS "$DEVICE_SHELL_TIMEOUT_SECONDS"
require_non_negative_int PAWXY_STARTUP_RETRIES "$STARTUP_RETRIES"
require_non_negative_int PAWXY_STARTUP_SLEEP_SECONDS "$STARTUP_SLEEP_SECONDS"
[ -f "$APK" ] || {
  printf '%s\n' "APK not found at $APK. Run scripts/build-android.sh first." >&2
  exit 1
}
[ -f "$CTL" ] || {
  printf '%s\n' "pawxyctl not found at $CTL." >&2
  exit 1
}

select_device
verify_android_shell_permissions
adb_cmd install -r "$APK"
verify_package_installed
device_sh pm grant dev.pawxy android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb_cmd push "$CTL" "$DEVICE_CTL"
device_sh chmod 755 "$DEVICE_CTL"
START_SENT=1
device_sh "PAWXY_HOME=$DEVICE_HOME $DEVICE_CTL start" >/dev/null \
  || {
    stop_started_service
    fail "failed to start Pawxy through pushed pawxyctl"
  }
wait_for_running_status

cat <<'USAGE'
Installed and started Pawxy.

Examples:
  adb shell PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl start
  adb shell PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl status --json
  adb shell PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl share on

Shizuku/rish examples:
  rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl start'
  rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl status --json'
  rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl share on'
  RISH_APPLICATION_ID=com.termux sh /sdcard/Android/data/moe.shizuku.privileged.api/files/rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl status --json'

Direct intent example:
  adb shell am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token "$(adb shell cat /data/local/tmp/pawxy/token 2>/dev/null)"
USAGE
