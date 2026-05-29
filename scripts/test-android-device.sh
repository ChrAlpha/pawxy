#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APK=${PAWXY_APK:-$ROOT/android/app/build/outputs/apk/debug/app-debug.apk}
CTL=${PAWXY_CTL:-$ROOT/scripts/pawxyctl}
ADB=${ADB:-adb}
CONTROL_MODE=${PAWXY_CONTROL_MODE:-adb}
RISH=${PAWXY_RISH:-rish}
RISH_RUNNER=${PAWXY_RISH_RUNNER:-}
RISH_APPLICATION_ID=${PAWXY_RISH_APPLICATION_ID:-}
ADB_TIMEOUT_SECONDS=${PAWXY_ADB_TIMEOUT_SECONDS:-120}
CONTROL_TIMEOUT_SECONDS=${PAWXY_CONTROL_TIMEOUT_SECONDS:-20}
DEVICE_SHELL_TIMEOUT_SECONDS=${PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS:-30}
HOST_PROXY_PORT=${PAWXY_HOST_PROXY_PORT:-3218}
HOST_TARGET_PORT=${PAWXY_HOST_TARGET_PORT:-32180}
HOLD_SECONDS=${PAWXY_HOLD_SECONDS:-3}
HOLD_INTERVAL_SECONDS=${PAWXY_HOLD_INTERVAL_SECONDS:-30}
BULK_KIB=${PAWXY_BULK_KIB:-1024}
MIN_BULK_KIB_PER_SECOND=${PAWXY_MIN_BULK_KIB_PER_SECOND:-1}
CURL_CONNECT_TIMEOUT_SECONDS=${PAWXY_CURL_CONNECT_TIMEOUT_SECONDS:-5}
CURL_MAX_TIME_SECONDS=${PAWXY_CURL_MAX_TIME_SECONDS:-30}
IDLE_DRAIN_RETRIES=${PAWXY_IDLE_DRAIN_RETRIES:-5}
IDLE_DRAIN_SLEEP_SECONDS=${PAWXY_IDLE_DRAIN_SLEEP_SECONDS:-1}
RUN_IDLE_EFFICIENCY=${PAWXY_RUN_IDLE_EFFICIENCY:-1}
IDLE_EFFICIENCY_SECONDS=${PAWXY_IDLE_EFFICIENCY_SECONDS:-5}
MAX_IDLE_CPU_TICKS=${PAWXY_MAX_IDLE_CPU_TICKS:-100}
MAX_IDLE_RSS_KIB=${PAWXY_MAX_IDLE_RSS_KIB:-262144}
MAX_IDLE_FD_SIZE=${PAWXY_MAX_IDLE_FD_SIZE:-1024}
MAX_HOLD_RSS_KIB=${PAWXY_MAX_HOLD_RSS_KIB:-$MAX_IDLE_RSS_KIB}
MAX_HOLD_FD_SIZE=${PAWXY_MAX_HOLD_FD_SIZE:-$MAX_IDLE_FD_SIZE}
RUN_BULK=${PAWXY_RUN_BULK:-1}
RUN_PARALLEL_BURST=${PAWXY_RUN_PARALLEL_BURST:-0}
PARALLEL_BURST_CONNECTIONS=${PAWXY_PARALLEL_BURST_CONNECTIONS:-8}
RUN_SHARE=${PAWXY_RUN_SHARE:-1}
RUN_WAKE=${PAWXY_RUN_WAKE:-1}
RUN_WAKE_HOLD=${PAWXY_RUN_WAKE_HOLD:-0}
RUN_SCREEN_OFF=${PAWXY_RUN_SCREEN_OFF:-0}
KEEP_SCREEN_OFF_DURING_HOLD=${PAWXY_KEEP_SCREEN_OFF_DURING_HOLD:-0}
RUN_DUPLICATE_START=${PAWXY_RUN_DUPLICATE_START:-1}
RUN_RESTART=${PAWXY_RUN_RESTART:-1}
RUN_PROCESS_RESTART=${PAWXY_RUN_PROCESS_RESTART:-1}
PROCESS_RESTART_RETRIES=${PAWXY_PROCESS_RESTART_RETRIES:-20}
PROCESS_RESTART_SLEEP_SECONDS=${PAWXY_PROCESS_RESTART_SLEEP_SECONDS:-1}
STARTUP_RETRIES=${PAWXY_STARTUP_RETRIES:-20}
STARTUP_SLEEP_SECONDS=${PAWXY_STARTUP_SLEEP_SECONDS:-1}
TARGET_SERVER_RETRIES=${PAWXY_TARGET_SERVER_RETRIES:-20}
TARGET_SERVER_SLEEP_SECONDS=${PAWXY_TARGET_SERVER_SLEEP_SECONDS:-1}
RUN_TOKEN_REPAIR=${PAWXY_RUN_TOKEN_REPAIR:-1}
RUN_STOP_START=${PAWXY_RUN_STOP_START:-1}
RUN_BAD_TOKEN=${PAWXY_RUN_BAD_TOKEN:-1}
RUN_UNKNOWN_ACTION=${PAWXY_RUN_UNKNOWN_ACTION:-1}
RUN_UNSAFE_LAN=${PAWXY_RUN_UNSAFE_LAN:-1}
RUN_INVALID_CONFIG=${PAWXY_RUN_INVALID_CONFIG:-1}
RUN_RISH_PROBE=${PAWXY_RUN_RISH_PROBE:-1}
RUN_CONTROL_PREFLIGHT=${PAWXY_RUN_CONTROL_PREFLIGHT:-1}
RUN_DEVICE_ORIGIN=${PAWXY_RUN_DEVICE_ORIGIN:-1}
DEVICE_ORIGIN_TIMEOUT_SECONDS=${PAWXY_DEVICE_ORIGIN_TIMEOUT_SECONDS:-15}
RUN_NOTIFICATION_DENIAL=${PAWXY_RUN_NOTIFICATION_DENIAL:-0}
RUN_NETWORK_TOGGLE=${PAWXY_RUN_NETWORK_TOGGLE:-0}
NETWORK_TOGGLE_MODE=${PAWXY_NETWORK_TOGGLE_MODE:-wifi}
NETWORK_TOGGLE_SLEEP_SECONDS=${PAWXY_NETWORK_TOGGLE_SLEEP_SECONDS:-3}
RUN_DOZE=${PAWXY_RUN_DOZE:-0}
RUN_APP_STANDBY=${PAWXY_RUN_APP_STANDBY:-0}
RUN_STANDBY_BUCKET=${PAWXY_RUN_STANDBY_BUCKET:-0}
RUN_BACKGROUND_RESTRICTION=${PAWXY_RUN_BACKGROUND_RESTRICTION:-0}
RUN_BATTERY_SAVER=${PAWXY_RUN_BATTERY_SAVER:-0}
COLLECT_DIAGNOSTICS=${PAWXY_COLLECT_DIAGNOSTICS:-1}
ARTIFACT_DIR=${PAWXY_ARTIFACT_DIR:-}
DEVICE_HOME=/data/local/tmp/pawxy
DEVICE_CTL=/data/local/tmp/pawxyctl
PKG=dev.pawxy
SERVICE=dev.pawxy/.ProxyService
DEVICE_READY=0
CONTROL_READY=0
SERVICE_STOP_NEEDED=0
CLEANUP_DONE=0
POWER_MODE_CHANGED=0
NETWORK_TOGGLE_CHANGED=0
NETWORK_TOGGLE_ACTIVE_MODE=
WAKE_HOLD_ENABLED=0
SCREEN_OFF_CHANGED=0
NOTIFICATION_DENIAL_CHANGED=0
ARTIFACT_READY=0

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

note() {
  printf '%s\n' "pawxy device smoke: $*"
}

artifact_label_slug() {
  printf '%s\n' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' '-' \
    | sed 's/^-//; s/-$//; s/^$/artifact/'
}

artifact_write() {
  [ "$ARTIFACT_READY" = "1" ] || return 0
  artifact_file=$1
  shift
  printf '%s\n' "$@" > "$ARTIFACT_DIR/$artifact_file"
}

artifact_append_status() {
  [ "$ARTIFACT_READY" = "1" ] || return 0
  artifact_status_label=$1
  artifact_status_json=$2
  printf '%s\t%s\n' "$artifact_status_label" "$artifact_status_json" >> "$ARTIFACT_DIR/status-samples.tsv"
}

init_artifacts() {
  [ -n "$ARTIFACT_DIR" ] || return 0
  mkdir -p "$ARTIFACT_DIR/diagnostics" || fail "cannot create PAWXY_ARTIFACT_DIR: $ARTIFACT_DIR"
  ARTIFACT_READY=1
  note "artifact dir: $ARTIFACT_DIR"
  artifact_write run-info.txt \
    "control_mode=$CONTROL_MODE" \
    "android_serial=${ANDROID_SERIAL:-}" \
    "apk=$APK" \
    "ctl=$CTL" \
    "host_proxy_port=$HOST_PROXY_PORT" \
    "host_target_port=$HOST_TARGET_PORT" \
    "hold_seconds=$HOLD_SECONDS" \
    "hold_interval_seconds=$HOLD_INTERVAL_SECONDS"
  artifact_write status-samples.tsv "label	status_json"
  artifact_write hold-samples.tsv "elapsed_s	pid	cpu_ticks	rss_kib	fd_size	active_connections	total_connections	bytes_in	bytes_out	network_available	network_transport	network_generation"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

adb_base() {
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    timeout "$ADB_TIMEOUT_SECONDS" "$ADB" -s "$ANDROID_SERIAL" "$@"
  else
    timeout "$ADB_TIMEOUT_SECONDS" "$ADB" "$@"
  fi
}

device_sh() {
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    timeout "$DEVICE_SHELL_TIMEOUT_SECONDS" "$ADB" -s "$ANDROID_SERIAL" shell "$@"
  else
    timeout "$DEVICE_SHELL_TIMEOUT_SECONDS" "$ADB" shell "$@"
  fi
}

device_sh_control() {
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    timeout "$CONTROL_TIMEOUT_SECONDS" "$ADB" -s "$ANDROID_SERIAL" shell "$@"
  else
    timeout "$CONTROL_TIMEOUT_SECONDS" "$ADB" shell "$@"
  fi
}

device_sh_timeout() {
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    timeout "$DEVICE_ORIGIN_TIMEOUT_SECONDS" "$ADB" -s "$ANDROID_SERIAL" shell "$@"
  else
    timeout "$DEVICE_ORIGIN_TIMEOUT_SECONDS" "$ADB" shell "$@"
  fi
}

shell_word() {
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:-]*|'')
      quoted=$(printf '%s\n' "$1" | sed "s/'/'\\\\''/g")
      printf "'%s'" "$quoted"
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

rish_command_prefix() {
  if [ -n "$RISH_RUNNER" ]; then
    rish_command="$(shell_word "$RISH_RUNNER") $(shell_word "$RISH")"
  else
    rish_command=$(shell_word "$RISH")
  fi
  if [ -n "$RISH_APPLICATION_ID" ]; then
    rish_command="RISH_APPLICATION_ID=$(shell_word "$RISH_APPLICATION_ID") $rish_command"
  fi
  printf '%s\n' "$rish_command"
}

rish_shell() {
  command_text=$1
  rish_command=$(rish_command_prefix)
  device_sh_control "$rish_command -c $(shell_word "$command_text")"
}

rish_shell_timeout() {
  command_text=$1
  rish_command=$(rish_command_prefix)
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    timeout "$DEVICE_ORIGIN_TIMEOUT_SECONDS" "$ADB" -s "$ANDROID_SERIAL" shell "$rish_command -c $(shell_word "$command_text")"
  else
    timeout "$DEVICE_ORIGIN_TIMEOUT_SECONDS" "$ADB" shell "$rish_command -c $(shell_word "$command_text")"
  fi
}

device_origin_shell() {
  case "$CONTROL_MODE" in
    rish)
      if [ "$CONTROL_READY" = "1" ]; then
        rish_shell_timeout "$1"
      else
        device_sh_timeout "$1"
      fi
      ;;
    adb)
      device_sh_timeout "$1"
      ;;
    *)
      fail "unsupported PAWXY_CONTROL_MODE=$CONTROL_MODE"
      ;;
  esac
}

control() {
  case "$CONTROL_MODE" in
    adb)
      device_sh_control "PAWXY_HOME=/data/local/tmp/pawxy $DEVICE_CTL $*"
      ;;
    rish)
      rish_shell "PAWXY_HOME=/data/local/tmp/pawxy $DEVICE_CTL $*"
      ;;
    *)
      fail "unsupported PAWXY_CONTROL_MODE=$CONTROL_MODE"
      ;;
  esac
}

control_shell() {
  case "$CONTROL_MODE" in
    adb)
      device_sh_control "$1"
      ;;
    rish)
      rish_shell "$1"
      ;;
    *)
      fail "unsupported PAWXY_CONTROL_MODE=$CONTROL_MODE"
      ;;
  esac
}

observability_shell() {
  if [ "$CONTROL_READY" = "1" ]; then
    control_shell "$1"
  else
    device_sh "$1"
  fi
}

status_json() {
  control status --json
}

status_json_or_empty() {
  control status --json 2>/dev/null || true
}

control_shell_uid() {
  case "$CONTROL_MODE" in
    adb)
      device_sh_control "id -u"
      ;;
    rish)
      rish_shell "id -u"
      ;;
    *)
      fail "unsupported PAWXY_CONTROL_MODE=$CONTROL_MODE"
      ;;
  esac
}

require_json_field() {
  json=$1
  field=$2
  expected=$3
  case "$expected" in
    true|false)
      value=$(json_bool_field "$json" "$field")
      [ "$value" = "$expected" ] \
        || fail "expected status field $field=$expected, got: $json"
      ;;
    *)
      printf '%s\n' "$json" | grep -F "\"$field\":$expected" >/dev/null \
        || fail "expected status field $field=$expected, got: $json"
      ;;
  esac
}

require_proxy_running() {
  json=$1
  require_json_field "$json" running true
  require_json_field "$json" native_running true
}

require_proxy_stopped() {
  json=$1
  require_json_field "$json" running false
  require_json_field "$json" native_running false
}

require_auth_state() {
  json=$1
  expected=$2
  require_json_field "$json" auth_enabled "$expected"
  require_json_field "$json" native_auth_enabled "$expected"
  require_json_field "$json" configured_auth_enabled "$expected"
}

require_json_key() {
  json=$1
  field=$2
  json_has_key "$json" "$field" \
    || fail "expected status field $field to be present, got: $json"
}

require_json_string_equals() {
  json=$1
  field=$2
  expected=$3
  value=$(json_string_field "$json" "$field")
  [ "$value" = "$expected" ] \
    || fail "expected status field $field=$expected, got ${value:-missing} in: $json"
}

require_stable_listen() {
  listen_json=$1
  listen_expected=$2
  listen_label=$3
  listen_value=$(json_string_field "$listen_json" listen)
  [ "$listen_value" = "$listen_expected" ] \
    || fail "$listen_label changed the proxy listen endpoint: expected $listen_expected, got ${listen_value:-missing} in: $listen_json"
  listen_native_value=$(json_string_field "$listen_json" native_listen)
  [ "$listen_native_value" = "$listen_expected" ] \
    || fail "$listen_label changed the native proxy listen endpoint: expected $listen_expected, got ${listen_native_value:-missing} in: $listen_json"
  listen_configured_value=$(json_string_field "$listen_json" configured_listen)
  [ "$listen_configured_value" = "$listen_expected" ] \
    || fail "$listen_label changed the persisted proxy listen endpoint: expected $listen_expected, got ${listen_configured_value:-missing} in: $listen_json"
}

require_stable_started_at() {
  started_json=$1
  started_expected=$2
  started_label=$3
  started_value=$(json_number_field "$started_json" started_at_unix_ms)
  [ "$started_value" = "$started_expected" ] \
    || fail "$started_label restarted the native proxy: started_at_unix_ms $started_expected -> ${started_value:-missing} in: $started_json"
  started_native_value=$(json_number_field "$started_json" native_started_at_unix_ms)
  [ "$started_native_value" = "$started_expected" ] \
    || fail "$started_label restarted the native proxy: native_started_at_unix_ms $started_expected -> ${started_native_value:-missing} in: $started_json"
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

json_number_field() {
  json=$1
  field=$2
  printf '%s\n' "$json" | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | sed -n '1p'
}

json_has_key() {
  json=$1
  field=$2
  printf '%s\n' "$json" | sed -n 's/.*"'"$field"'"[[:space:]]*:.*/present/p' | sed -n '1p' | grep -Fx present >/dev/null
}

status_error_detail() {
  json=$1
  error=$(json_string_field "$json" error)
  if [ -z "$error" ] || [ "$error" = "null" ]; then
    error=$(json_string_field "$json" last_error)
  fi
  if [ -n "$error" ] && [ "$error" != "null" ]; then
    printf '%s\n' "$error"
  fi
}

require_json_number_at_least() {
  number_json=$1
  number_field=$2
  number_expected=$3
  number_value=$(json_number_field "$number_json" "$number_field")
  [ -n "$number_value" ] || fail "expected numeric status field $number_field, got: $number_json"
  [ "$number_value" -ge "$number_expected" ] 2>/dev/null \
    || fail "expected status field $number_field >= $number_expected, got $number_value in: $number_json"
}

require_json_number_greater_than() {
  number_json=$1
  number_field=$2
  number_previous=$3
  number_value=$(json_number_field "$number_json" "$number_field")
  [ -n "$number_value" ] || fail "expected numeric status field $number_field, got: $number_json"
  [ "$number_value" -gt "$number_previous" ] 2>/dev/null \
    || fail "expected status field $number_field > $number_previous, got $number_value in: $number_json"
}

require_json_number_at_most() {
  number_json=$1
  number_field=$2
  number_expected=$3
  number_value=$(json_number_field "$number_json" "$number_field")
  [ -n "$number_value" ] || fail "expected numeric status field $number_field, got: $number_json"
  [ "$number_value" -le "$number_expected" ] 2>/dev/null \
    || fail "expected status field $number_field <= $number_expected, got $number_value in: $number_json"
}

require_json_bool_present() {
  bool_json=$1
  bool_field=$2
  bool_value=$(json_bool_field "$bool_json" "$bool_field")
  case "$bool_value" in
    true|false) ;;
    *) fail "expected boolean status field $bool_field, got: $bool_json" ;;
  esac
}

require_status_observability() {
  status_json_text=$1
  status_label=$2
  require_json_bool_present "$status_json_text" network_available
  status_network_transport=$(json_string_field "$status_json_text" network_transport)
  [ -n "$status_network_transport" ] \
    || fail "$status_label status did not include network_transport: $status_json_text"
  require_json_number_at_least "$status_json_text" network_generation 0
  require_json_number_at_least "$status_json_text" active_connections 0
  require_json_number_at_least "$status_json_text" total_connections 0
  require_json_number_at_least "$status_json_text" bytes_in 0
  require_json_number_at_least "$status_json_text" bytes_out 0
}

log_hold_sample() {
  hold_json=$1
  hold_elapsed=$2
  hold_pid=$3
  require_process_resource_caps "persistence hold sample" "$hold_pid" "$MAX_HOLD_RSS_KIB" "$MAX_HOLD_FD_SIZE"
  hold_active=$(json_number_field "$hold_json" active_connections)
  hold_total=$(json_number_field "$hold_json" total_connections)
  hold_bytes_in=$(json_number_field "$hold_json" bytes_in)
  hold_bytes_out=$(json_number_field "$hold_json" bytes_out)
  hold_network_available=$(json_bool_field "$hold_json" network_available)
  hold_network_transport=$(json_string_field "$hold_json" network_transport)
  hold_network_generation=$(json_number_field "$hold_json" network_generation)
  note "hold sample: elapsed=${hold_elapsed}s pid=$hold_pid cpu_ticks=$PROCESS_SAMPLE_CPU_TICKS rss_kib=$PROCESS_SAMPLE_RSS_KIB fd_size=$PROCESS_SAMPLE_FD_SIZE active=${hold_active:-unknown} total=${hold_total:-unknown} bytes_in=${hold_bytes_in:-unknown} bytes_out=${hold_bytes_out:-unknown} network=${hold_network_available:-unknown}/${hold_network_transport:-unknown} generation=${hold_network_generation:-unknown}"
  if [ "$ARTIFACT_READY" = "1" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$hold_elapsed" \
      "$hold_pid" \
      "$PROCESS_SAMPLE_CPU_TICKS" \
      "$PROCESS_SAMPLE_RSS_KIB" \
      "$PROCESS_SAMPLE_FD_SIZE" \
      "${hold_active:-unknown}" \
      "${hold_total:-unknown}" \
      "${hold_bytes_in:-unknown}" \
      "${hold_bytes_out:-unknown}" \
      "${hold_network_available:-unknown}" \
      "${hold_network_transport:-unknown}" \
      "${hold_network_generation:-unknown}" >> "$ARTIFACT_DIR/hold-samples.tsv"
    artifact_append_status "hold elapsed=${hold_elapsed}s" "$hold_json"
  fi
}

wait_for_idle_connections() {
  attempt=0
  while [ "$attempt" -le "$IDLE_DRAIN_RETRIES" ]; do
    json=$(status_json)
    require_status_observability "$json" "idle drain"
    active=$(json_number_field "$json" active_connections)
    [ -n "$active" ] || fail "expected numeric status field active_connections, got: $json"
    if [ "$active" -eq 0 ] 2>/dev/null; then
      return 0
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$IDLE_DRAIN_RETRIES" ] || break
    sleep "$IDLE_DRAIN_SLEEP_SECONDS"
  done
  require_json_number_at_most "$(status_json)" active_connections 0
}

process_pid() {
  pid=$(observability_shell "pidof $PKG 2>/dev/null" | tr -d '\r' | awk '/^[0-9 ]+$/ { print $1; exit }')
  if [ -n "$pid" ]; then
    printf '%s\n' "$pid"
    return 0
  fi
  observability_shell "ps -A -o PID,NAME 2>/dev/null" | tr -d '\r' | awk '$2 == "'"$PKG"'" { print $1; exit }'
}

process_cpu_ticks() {
  pid=$1
  observability_shell "cat /proc/$pid/stat" | tr -d '\r' | awk 'NF >= 15 { print $14 + $15; exit }'
}

process_rss_kib() {
  pid=$1
  observability_shell "sed -n 's/^VmRSS:[[:space:]]*//p' /proc/$pid/status" | tr -d '\r' | awk '/^[0-9]+[[:space:]]+kB$/ { print $1; exit }'
}

process_fd_size() {
  pid=$1
  observability_shell "sed -n 's/^FDSize:[[:space:]]*//p' /proc/$pid/status" | tr -d '\r' | awk '/^[0-9]+$/ { print $1; exit }'
}

require_process_resource_caps() {
  resource_label=$1
  resource_pid=$2
  resource_max_rss_kib=$3
  resource_max_fd_size=$4
  PROCESS_SAMPLE_CPU_TICKS=$(process_cpu_ticks "$resource_pid")
  PROCESS_SAMPLE_RSS_KIB=$(process_rss_kib "$resource_pid")
  PROCESS_SAMPLE_FD_SIZE=$(process_fd_size "$resource_pid")
  require_numeric_value "Pawxy process CPU ticks during $resource_label" "$PROCESS_SAMPLE_CPU_TICKS"
  require_numeric_value "Pawxy process RSS during $resource_label" "$PROCESS_SAMPLE_RSS_KIB"
  require_numeric_value "Pawxy process FDSize during $resource_label" "$PROCESS_SAMPLE_FD_SIZE"
  [ "$PROCESS_SAMPLE_RSS_KIB" -le "$resource_max_rss_kib" ] 2>/dev/null \
    || fail "Pawxy RSS during $resource_label exceeds PAWXY_MAX_HOLD_RSS_KIB=$resource_max_rss_kib KiB: $PROCESS_SAMPLE_RSS_KIB KiB"
  [ "$PROCESS_SAMPLE_FD_SIZE" -le "$resource_max_fd_size" ] 2>/dev/null \
    || fail "Pawxy FDSize during $resource_label exceeds PAWXY_MAX_HOLD_FD_SIZE=$resource_max_fd_size: $PROCESS_SAMPLE_FD_SIZE"
}

require_numeric_value() {
  numeric_label=$1
  numeric_value=$2
  case "$numeric_value" in
    ''|*[!0-9]*) fail "$numeric_label is not numeric: ${numeric_value:-empty}" ;;
  esac
}

require_same_process_pid() {
  pid_context=$1
  expected_pid=$2
  actual_pid=$(process_pid)
  require_numeric_value "Pawxy process pid during $pid_context" "$actual_pid"
  [ "$actual_pid" = "$expected_pid" ] \
    || fail "Pawxy process restarted during $pid_context: $expected_pid -> $actual_pid"
}

require_non_negative_int_setting() {
  setting_name=$1
  setting_value=$2
  case "$setting_value" in
    ''|*[!0-9]*) fail "$setting_name must be a non-negative integer" ;;
  esac
}

require_positive_int_setting() {
  positive_name=$1
  positive_value=$2
  require_non_negative_int_setting "$positive_name" "$positive_value"
  [ "$positive_value" -gt 0 ] 2>/dev/null || fail "$positive_name must be greater than zero"
}

require_tcp_port_setting() {
  port_name=$1
  port_value=$2
  require_positive_int_setting "$port_name" "$port_value"
  [ "$port_value" -le 65535 ] 2>/dev/null || fail "$port_name must be <= 65535"
}

require_flag_setting() {
  flag_name=$1
  flag_value=$2
  case "$flag_value" in
    0|1) ;;
    *) fail "$flag_name must be 0 or 1" ;;
  esac
}

validate_config() {
  case "$CONTROL_MODE" in
    adb|rish) ;;
    *) fail "unsupported PAWXY_CONTROL_MODE=$CONTROL_MODE" ;;
  esac

  require_positive_int_setting PAWXY_ADB_TIMEOUT_SECONDS "$ADB_TIMEOUT_SECONDS"
  require_positive_int_setting PAWXY_CONTROL_TIMEOUT_SECONDS "$CONTROL_TIMEOUT_SECONDS"
  require_positive_int_setting PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS "$DEVICE_SHELL_TIMEOUT_SECONDS"
  require_tcp_port_setting PAWXY_HOST_PROXY_PORT "$HOST_PROXY_PORT"
  require_tcp_port_setting PAWXY_HOST_TARGET_PORT "$HOST_TARGET_PORT"
  [ "$HOST_PROXY_PORT" != "$HOST_TARGET_PORT" ] \
    || fail "PAWXY_HOST_PROXY_PORT and PAWXY_HOST_TARGET_PORT must be different"
  require_non_negative_int_setting PAWXY_HOLD_SECONDS "$HOLD_SECONDS"
  require_non_negative_int_setting PAWXY_HOLD_INTERVAL_SECONDS "$HOLD_INTERVAL_SECONDS"
  require_positive_int_setting PAWXY_BULK_KIB "$BULK_KIB"
  require_positive_int_setting PAWXY_PARALLEL_BURST_CONNECTIONS "$PARALLEL_BURST_CONNECTIONS"
  require_non_negative_int_setting PAWXY_MIN_BULK_KIB_PER_SECOND "$MIN_BULK_KIB_PER_SECOND"
  require_positive_int_setting PAWXY_CURL_CONNECT_TIMEOUT_SECONDS "$CURL_CONNECT_TIMEOUT_SECONDS"
  require_positive_int_setting PAWXY_CURL_MAX_TIME_SECONDS "$CURL_MAX_TIME_SECONDS"
  require_non_negative_int_setting PAWXY_IDLE_DRAIN_RETRIES "$IDLE_DRAIN_RETRIES"
  require_non_negative_int_setting PAWXY_IDLE_DRAIN_SLEEP_SECONDS "$IDLE_DRAIN_SLEEP_SECONDS"
  require_non_negative_int_setting PAWXY_IDLE_EFFICIENCY_SECONDS "$IDLE_EFFICIENCY_SECONDS"
  require_non_negative_int_setting PAWXY_MAX_IDLE_CPU_TICKS "$MAX_IDLE_CPU_TICKS"
  require_non_negative_int_setting PAWXY_MAX_IDLE_RSS_KIB "$MAX_IDLE_RSS_KIB"
  require_non_negative_int_setting PAWXY_MAX_IDLE_FD_SIZE "$MAX_IDLE_FD_SIZE"
  require_non_negative_int_setting PAWXY_MAX_HOLD_RSS_KIB "$MAX_HOLD_RSS_KIB"
  require_non_negative_int_setting PAWXY_MAX_HOLD_FD_SIZE "$MAX_HOLD_FD_SIZE"
  require_non_negative_int_setting PAWXY_PROCESS_RESTART_RETRIES "$PROCESS_RESTART_RETRIES"
  require_non_negative_int_setting PAWXY_PROCESS_RESTART_SLEEP_SECONDS "$PROCESS_RESTART_SLEEP_SECONDS"
  require_non_negative_int_setting PAWXY_STARTUP_RETRIES "$STARTUP_RETRIES"
  require_non_negative_int_setting PAWXY_STARTUP_SLEEP_SECONDS "$STARTUP_SLEEP_SECONDS"
  require_non_negative_int_setting PAWXY_TARGET_SERVER_RETRIES "$TARGET_SERVER_RETRIES"
  require_non_negative_int_setting PAWXY_TARGET_SERVER_SLEEP_SECONDS "$TARGET_SERVER_SLEEP_SECONDS"
  require_positive_int_setting PAWXY_DEVICE_ORIGIN_TIMEOUT_SECONDS "$DEVICE_ORIGIN_TIMEOUT_SECONDS"
  require_non_negative_int_setting PAWXY_NETWORK_TOGGLE_SLEEP_SECONDS "$NETWORK_TOGGLE_SLEEP_SECONDS"

  require_flag_setting PAWXY_RUN_IDLE_EFFICIENCY "$RUN_IDLE_EFFICIENCY"
  require_flag_setting PAWXY_RUN_BULK "$RUN_BULK"
  require_flag_setting PAWXY_RUN_PARALLEL_BURST "$RUN_PARALLEL_BURST"
  require_flag_setting PAWXY_RUN_SHARE "$RUN_SHARE"
  require_flag_setting PAWXY_RUN_WAKE "$RUN_WAKE"
  require_flag_setting PAWXY_RUN_WAKE_HOLD "$RUN_WAKE_HOLD"
  require_flag_setting PAWXY_RUN_SCREEN_OFF "$RUN_SCREEN_OFF"
  require_flag_setting PAWXY_KEEP_SCREEN_OFF_DURING_HOLD "$KEEP_SCREEN_OFF_DURING_HOLD"
  require_flag_setting PAWXY_RUN_DUPLICATE_START "$RUN_DUPLICATE_START"
  require_flag_setting PAWXY_RUN_RESTART "$RUN_RESTART"
  require_flag_setting PAWXY_RUN_PROCESS_RESTART "$RUN_PROCESS_RESTART"
  require_flag_setting PAWXY_RUN_TOKEN_REPAIR "$RUN_TOKEN_REPAIR"
  require_flag_setting PAWXY_RUN_STOP_START "$RUN_STOP_START"
  require_flag_setting PAWXY_RUN_BAD_TOKEN "$RUN_BAD_TOKEN"
  require_flag_setting PAWXY_RUN_UNKNOWN_ACTION "$RUN_UNKNOWN_ACTION"
  require_flag_setting PAWXY_RUN_UNSAFE_LAN "$RUN_UNSAFE_LAN"
  require_flag_setting PAWXY_RUN_INVALID_CONFIG "$RUN_INVALID_CONFIG"
  require_flag_setting PAWXY_RUN_RISH_PROBE "$RUN_RISH_PROBE"
  require_flag_setting PAWXY_RUN_CONTROL_PREFLIGHT "$RUN_CONTROL_PREFLIGHT"
  require_flag_setting PAWXY_RUN_DEVICE_ORIGIN "$RUN_DEVICE_ORIGIN"
  require_flag_setting PAWXY_RUN_NOTIFICATION_DENIAL "$RUN_NOTIFICATION_DENIAL"
  require_flag_setting PAWXY_RUN_NETWORK_TOGGLE "$RUN_NETWORK_TOGGLE"
  require_flag_setting PAWXY_RUN_DOZE "$RUN_DOZE"
  require_flag_setting PAWXY_RUN_APP_STANDBY "$RUN_APP_STANDBY"
  require_flag_setting PAWXY_RUN_STANDBY_BUCKET "$RUN_STANDBY_BUCKET"
  require_flag_setting PAWXY_RUN_BACKGROUND_RESTRICTION "$RUN_BACKGROUND_RESTRICTION"
  require_flag_setting PAWXY_RUN_BATTERY_SAVER "$RUN_BATTERY_SAVER"
  require_flag_setting PAWXY_COLLECT_DIAGNOSTICS "$COLLECT_DIAGNOSTICS"

  if [ "$KEEP_SCREEN_OFF_DURING_HOLD" = "1" ] && [ "$RUN_SCREEN_OFF" != "1" ]; then
    fail "PAWXY_KEEP_SCREEN_OFF_DURING_HOLD requires PAWXY_RUN_SCREEN_OFF=1"
  fi

  validate_network_toggle_modes
}

validate_network_toggle_modes() {
  case "$NETWORK_TOGGLE_MODE" in
    ''|*,,*|*,|,*)
      fail "PAWXY_NETWORK_TOGGLE_MODE must be wifi, airplane, or a comma-separated list of those modes"
      ;;
  esac
  old_ifs=$IFS
  IFS=,
  set -- $NETWORK_TOGGLE_MODE
  IFS=$old_ifs
  for mode do
    case "$mode" in
      wifi|airplane) ;;
      *) fail "PAWXY_NETWORK_TOGGLE_MODE must be wifi, airplane, or a comma-separated list of those modes" ;;
    esac
  done
}

require_wake_hold_enabled() {
  [ "$WAKE_HOLD_ENABLED" = "1" ] || return 0
  json=$1
  require_json_field "$json" wake_lock_enabled true
}

probe_idle_efficiency() {
  label=$1
  [ "$RUN_IDLE_EFFICIENCY" = "1" ] || return 0
  case "$IDLE_EFFICIENCY_SECONDS" in
    ''|*[!0-9]*) fail "PAWXY_IDLE_EFFICIENCY_SECONDS must be a non-negative integer" ;;
  esac
  case "$MAX_IDLE_CPU_TICKS" in
    ''|*[!0-9]*) fail "PAWXY_MAX_IDLE_CPU_TICKS must be a non-negative integer" ;;
  esac
  case "$MAX_IDLE_RSS_KIB" in
    ''|*[!0-9]*) fail "PAWXY_MAX_IDLE_RSS_KIB must be a non-negative integer" ;;
  esac
  case "$MAX_IDLE_FD_SIZE" in
    ''|*[!0-9]*) fail "PAWXY_MAX_IDLE_FD_SIZE must be a non-negative integer" ;;
  esac

  note "sampling idle efficiency: $label"
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "$label idle efficiency"
  require_json_number_at_most "$json" active_connections 0
  require_wake_hold_enabled "$json"

  pid_before=$(process_pid)
  require_numeric_value "Pawxy process pid" "$pid_before"
  ticks_before=$(process_cpu_ticks "$pid_before")
  rss_before=$(process_rss_kib "$pid_before")
  fd_size_before=$(process_fd_size "$pid_before")
  require_numeric_value "Pawxy process CPU ticks before idle sample" "$ticks_before"
  require_numeric_value "Pawxy process RSS before idle sample" "$rss_before"
  require_numeric_value "Pawxy process FDSize before idle sample" "$fd_size_before"
  [ "$rss_before" -le "$MAX_IDLE_RSS_KIB" ] 2>/dev/null \
    || fail "Pawxy RSS before idle sample exceeds PAWXY_MAX_IDLE_RSS_KIB=$MAX_IDLE_RSS_KIB KiB: $rss_before KiB"
  [ "$fd_size_before" -le "$MAX_IDLE_FD_SIZE" ] 2>/dev/null \
    || fail "Pawxy FDSize before idle sample exceeds PAWXY_MAX_IDLE_FD_SIZE=$MAX_IDLE_FD_SIZE: $fd_size_before"

  if [ "$IDLE_EFFICIENCY_SECONDS" -gt 0 ] 2>/dev/null; then
    sleep "$IDLE_EFFICIENCY_SECONDS"
  fi

  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "$label idle efficiency"
  require_json_number_at_most "$json" active_connections 0
  require_wake_hold_enabled "$json"
  pid_after=$(process_pid)
  require_numeric_value "Pawxy process pid after idle sample" "$pid_after"
  [ "$pid_after" = "$pid_before" ] \
    || fail "Pawxy process restarted during idle efficiency sample: $pid_before -> $pid_after"
  ticks_after=$(process_cpu_ticks "$pid_after")
  rss_after=$(process_rss_kib "$pid_after")
  fd_size_after=$(process_fd_size "$pid_after")
  require_numeric_value "Pawxy process CPU ticks after idle sample" "$ticks_after"
  require_numeric_value "Pawxy process RSS after idle sample" "$rss_after"
  require_numeric_value "Pawxy process FDSize after idle sample" "$fd_size_after"

  tick_delta=$((ticks_after - ticks_before))
  [ "$tick_delta" -ge 0 ] 2>/dev/null \
    || fail "Pawxy process CPU ticks moved backward during idle sample: $ticks_before -> $ticks_after"
  [ "$tick_delta" -le "$MAX_IDLE_CPU_TICKS" ] 2>/dev/null \
    || fail "Pawxy idle CPU growth exceeds PAWXY_MAX_IDLE_CPU_TICKS=$MAX_IDLE_CPU_TICKS ticks: $tick_delta ticks over ${IDLE_EFFICIENCY_SECONDS}s"
  [ "$rss_after" -le "$MAX_IDLE_RSS_KIB" ] 2>/dev/null \
    || fail "Pawxy RSS after idle sample exceeds PAWXY_MAX_IDLE_RSS_KIB=$MAX_IDLE_RSS_KIB KiB: $rss_after KiB"
  [ "$fd_size_after" -le "$MAX_IDLE_FD_SIZE" ] 2>/dev/null \
    || fail "Pawxy FDSize after idle sample exceeds PAWXY_MAX_IDLE_FD_SIZE=$MAX_IDLE_FD_SIZE: $fd_size_after"
  note "idle efficiency: $label pid=$pid_after cpu_ticks_delta=$tick_delta rss_kib=$rss_after fd_size=$fd_size_after"
}

wait_for_running_status() {
  label=$1
  retries=$2
  sleep_seconds=$3
  case "$retries" in
    ''|*[!0-9]*) fail "$label retries must be a non-negative integer" ;;
  esac
  case "$sleep_seconds" in
    ''|*[!0-9]*) fail "$label sleep seconds must be a non-negative integer" ;;
  esac
  attempt=0
  while [ "$attempt" -le "$retries" ]; do
    json=$(status_json_or_empty)
    if [ "$(json_bool_field "$json" running)" = "true" ] && [ "$(json_bool_field "$json" native_running)" = "true" ]; then
      printf '%s\n' "$json"
      return 0
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$retries" ] || break
    sleep "$sleep_seconds"
  done
  status_error=$(status_error_detail "${json:-}")
  if [ -n "$status_error" ]; then
    fail "$label did not report running=true/native_running=true within $retries attempts; status error=$status_error; last status: ${json:-empty}"
  fi
  fail "$label did not report running=true/native_running=true within $retries attempts; last status: ${json:-empty}"
}

wait_for_stopped_status() {
  label=$1
  retries=$2
  sleep_seconds=$3
  case "$retries" in
    ''|*[!0-9]*) fail "$label retries must be a non-negative integer" ;;
  esac
  case "$sleep_seconds" in
    ''|*[!0-9]*) fail "$label sleep seconds must be a non-negative integer" ;;
  esac
  attempt=0
  while [ "$attempt" -le "$retries" ]; do
    json=$(status_json_or_empty)
    if [ "$(json_bool_field "$json" running)" = "false" ] && [ "$(json_bool_field "$json" native_running)" = "false" ]; then
      printf '%s\n' "$json"
      return 0
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$retries" ] || break
    sleep "$sleep_seconds"
  done
  status_error=$(status_error_detail "${json:-}")
  if [ -n "$status_error" ]; then
    fail "$label did not report running=false/native_running=false within $retries attempts; status error=$status_error; last status: ${json:-empty}"
  fi
  fail "$label did not report running=false/native_running=false within $retries attempts; last status: ${json:-empty}"
}

wait_for_target_server() {
  url=$1
  retries=$2
  sleep_seconds=$3
  attempt=0
  while [ "$attempt" -le "$retries" ]; do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$retries" ] || break
    sleep "$sleep_seconds"
  done
  fail "host target server did not become ready at $url within $retries attempts"
}

probe_process_restart() {
  [ "$RUN_PROCESS_RESTART" = "1" ] || return 0
  case "$PROCESS_RESTART_RETRIES" in
    ''|*[!0-9]*) fail "PAWXY_PROCESS_RESTART_RETRIES must be a non-negative integer" ;;
  esac
  case "$PROCESS_RESTART_SLEEP_SECONDS" in
    ''|*[!0-9]*) fail "PAWXY_PROCESS_RESTART_SLEEP_SECONDS must be a non-negative integer" ;;
  esac

  note "testing sticky restart after app process crash"
  pid_before=$(process_pid)
  require_numeric_value "Pawxy process pid before process restart" "$pid_before"
  control_shell "am crash $PKG" >/dev/null 2>&1 || fail "am crash $PKG failed through $CONTROL_MODE; disable with PAWXY_RUN_PROCESS_RESTART=0 if this device blocks crash injection"
  note "waiting for proxy to recover after process restart"
  json=$(wait_for_running_status "process restart" "$PROCESS_RESTART_RETRIES" "$PROCESS_RESTART_SLEEP_SECONDS")
  require_proxy_running "$json"
  pid_after=$(process_pid)
  require_numeric_value "Pawxy process pid after process restart" "$pid_after"
  [ "$pid_after" != "$pid_before" ] \
    || fail "Pawxy process pid did not change after crash injection: $pid_before"
  note "process restart: pid $pid_before -> $pid_after"
}

probe_token_repair() {
  [ "$RUN_TOKEN_REPAIR" = "1" ] || return 0
  note "testing control token repair"
  current_token=$(control_shell "sed -n 1p $DEVICE_HOME/token" | tr -d '\r')
  [ -n "$current_token" ] || fail "control token missing from $DEVICE_HOME/token before repair test"
  repair_token=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  if [ "$current_token" = "$repair_token" ]; then
    repair_token=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
  fi
  control_shell "printf '%s\n' $repair_token > $DEVICE_HOME/token"
  mismatch_json=$(status_json_or_empty)
  if [ "$(json_bool_field "$mismatch_json" running)" = "true" ]; then
    control_shell "printf '%s\n' $current_token > $DEVICE_HOME/token" >/dev/null 2>&1 || true
    fail "control token mismatch unexpectedly still returned running=true; restored token file"
  fi
  if ! control reset-token >/dev/null; then
    control_shell "printf '%s\n' $current_token > $DEVICE_HOME/token" >/dev/null 2>&1 || true
    fail "control token reset failed; restored token file"
  fi
  json=$(wait_for_running_status "token repair" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_running "$json"
}

probe_duplicate_start() {
  target_url=$1
  note "verifying duplicate start keeps the running proxy in place"
  pid_before=$(process_pid)
  require_numeric_value "Pawxy process pid before duplicate start" "$pid_before"
  before_json=$(status_json)
  before_started_at=$(json_number_field "$before_json" started_at_unix_ms)
  before_listen=$(json_string_field "$before_json" listen)
  [ -n "$before_started_at" ] \
    || fail "expected numeric status field started_at_unix_ms before duplicate start, got: $before_json"
  [ -n "$before_listen" ] \
    || fail "expected status field listen before duplicate start, got: $before_json"
  control start >/dev/null
  after_json=$(wait_for_running_status "duplicate start" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_running "$after_json"
  require_auth_state "$after_json" false
  after_started_at=$(json_number_field "$after_json" started_at_unix_ms)
  [ -n "$after_started_at" ] \
    || fail "expected numeric status field started_at_unix_ms after duplicate start, got: $after_json"
  [ "$after_started_at" = "$before_started_at" ] \
    || fail "duplicate start restarted the native proxy: started_at_unix_ms $before_started_at -> $after_started_at"
  require_stable_listen "$after_json" "$before_listen" "duplicate start"
  require_same_process_pid "duplicate start" "$pid_before"
  probe_local_proxy_traffic "$target_url"
}

fetch_through_http_proxy() {
  url=$1
  curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" -x "http://127.0.0.1:$HOST_PROXY_PORT" "$url"
}

fetch_through_connect_proxy() {
  url=$1
  curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" --proxytunnel -x "http://127.0.0.1:$HOST_PROXY_PORT" "$url"
}

fetch_through_socks_proxy() {
  url=$1
  curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" --socks5-hostname "127.0.0.1:$HOST_PROXY_PORT" "$url"
}

fetch_through_auth_proxy() {
  url=$1
  password=$2
  curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" -x "http://pawxy:$password@127.0.0.1:$HOST_PROXY_PORT" "$url"
}

fetch_through_auth_socks_proxy() {
  url=$1
  password=$2
  curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" --socks5-hostname "127.0.0.1:$HOST_PROXY_PORT" --proxy-user "pawxy:$password" "$url"
}

require_lan_password_shape() {
  password=$1
  case "$password" in
    ????????????????????????????????)
      case "$password" in
        *[!0123456789abcdefABCDEF]*) fail "LAN password must be 32 hex characters" ;;
      esac
      ;;
    *) fail "LAN password must be 32 hex characters" ;;
  esac
}

lan_basic_auth_token() {
  password=$1
  printf '%s' "pawxy:$password" | base64 | tr -d '\n'
}

device_proxy_nc_cmd() {
  printf '%s\n' 'if [ -x /system/bin/toybox ]; then /system/bin/toybox nc 127.0.0.1 3218; elif command -v nc >/dev/null 2>&1; then nc 127.0.0.1 3218; else exit 127; fi'
}

probe_unauthenticated_lan_proxy_rejected() {
  target_url=$1
  if fetch_through_http_proxy "$target_url" >/dev/null 2>&1; then
    fail "unauthenticated LAN HTTP proxy traffic unexpectedly succeeded"
  fi
  if fetch_through_socks_proxy "$target_url" >/dev/null 2>&1; then
    fail "unauthenticated LAN SOCKS5 proxy traffic unexpectedly succeeded"
  fi
  wait_for_idle_connections
}

probe_unauthenticated_device_origin_lan_proxy_rejected() {
  [ "$RUN_DEVICE_ORIGIN" = "1" ] || return 0
  target_url=$1
  nc_cmd=$(device_proxy_nc_cmd)
  if device_origin_shell "printf 'GET $target_url HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null; then
    fail "unauthenticated device-origin LAN HTTP proxy traffic unexpectedly succeeded"
  fi
  if device_origin_shell "printf 'CONNECT 127.0.0.1:$HOST_TARGET_PORT HTTP/1.1\r\nHost: 127.0.0.1:$HOST_TARGET_PORT\r\n\r\nGET /pawxy-smoke.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null; then
    fail "unauthenticated device-origin LAN HTTP CONNECT proxy traffic unexpectedly succeeded"
  fi
  port_hi=$(printf '\\%03o' $((HOST_TARGET_PORT / 256)))
  port_lo=$(printf '\\%03o' $((HOST_TARGET_PORT % 256)))
  if device_origin_shell "printf '\005\001\000\005\001\000\003\011127.0.0.1${port_hi}${port_lo}GET /pawxy-smoke.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null; then
    fail "unauthenticated device-origin LAN SOCKS5 proxy traffic unexpectedly succeeded"
  fi
  wait_for_idle_connections
}

probe_host_proxy_traffic() {
  target_url=$1
  fetch_through_http_proxy "$target_url" | grep -Fx "pawxy-smoke-ok" >/dev/null \
    || fail "HTTP proxy traffic did not reach loopback target"
  fetch_through_connect_proxy "$target_url" | grep -Fx "pawxy-smoke-ok" >/dev/null \
    || fail "HTTP CONNECT proxy traffic did not reach loopback target"
  fetch_through_socks_proxy "$target_url" | grep -Fx "pawxy-smoke-ok" >/dev/null \
    || fail "SOCKS5 proxy traffic did not reach loopback target"
}

probe_device_origin_proxy_traffic() {
  [ "$RUN_DEVICE_ORIGIN" = "1" ] || return 0
  target_url=$1
  nc_cmd=$(device_proxy_nc_cmd)
  device_origin_shell "printf 'GET $target_url HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null \
    || fail "device-origin HTTP proxy traffic did not reach loopback target; Android shell needs /system/bin/toybox nc or nc"
  device_origin_shell "printf 'CONNECT 127.0.0.1:$HOST_TARGET_PORT HTTP/1.1\r\nHost: 127.0.0.1:$HOST_TARGET_PORT\r\n\r\nGET /pawxy-smoke.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null \
    || fail "device-origin HTTP CONNECT proxy traffic did not reach loopback target; Android shell needs /system/bin/toybox nc or nc"
  port_hi=$(printf '\\%03o' $((HOST_TARGET_PORT / 256)))
  port_lo=$(printf '\\%03o' $((HOST_TARGET_PORT % 256)))
  device_origin_shell "printf '\005\001\000\005\001\000\003\011127.0.0.1${port_hi}${port_lo}GET /pawxy-smoke.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null \
    || fail "device-origin SOCKS5 proxy traffic did not reach loopback target; Android shell needs /system/bin/toybox nc or nc"
}

probe_device_origin_authenticated_proxy_traffic() {
  [ "$RUN_DEVICE_ORIGIN" = "1" ] || return 0
  target_url=$1
  password=$2
  require_lan_password_shape "$password"
  nc_cmd=$(device_proxy_nc_cmd)
  basic_auth=$(lan_basic_auth_token "$password")
  device_origin_shell "printf 'GET $target_url HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Basic $basic_auth\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null \
    || fail "authenticated device-origin LAN HTTP proxy traffic failed; Android shell needs /system/bin/toybox nc or nc"
  device_origin_shell "printf 'CONNECT 127.0.0.1:$HOST_TARGET_PORT HTTP/1.1\r\nHost: 127.0.0.1:$HOST_TARGET_PORT\r\nProxy-Authorization: Basic $basic_auth\r\n\r\nGET /pawxy-smoke.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null \
    || fail "authenticated device-origin LAN HTTP CONNECT proxy traffic failed; Android shell needs /system/bin/toybox nc or nc"
  port_hi=$(printf '\\%03o' $((HOST_TARGET_PORT / 256)))
  port_lo=$(printf '\\%03o' $((HOST_TARGET_PORT % 256)))
  device_origin_shell "printf '\005\001\002\001\005pawxy\040$password\005\001\000\003\011127.0.0.1${port_hi}${port_lo}GET /pawxy-smoke.txt HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' | $nc_cmd" 2>/dev/null | grep -F "pawxy-smoke-ok" >/dev/null \
    || fail "authenticated device-origin LAN SOCKS5 proxy traffic failed; Android shell needs /system/bin/toybox nc or nc"
}

probe_local_proxy_traffic() {
  target_url=$1
  probe_host_proxy_traffic "$target_url"
  probe_device_origin_proxy_traffic "$target_url"
  wait_for_idle_connections
}

verify_file_size() {
  file=$1
  expected=$2
  got=$(wc -c < "$file" | tr -d ' ')
  [ "$got" = "$expected" ] || fail "expected $expected bytes from bulk transfer, got $got"
}

probe_one_bulk_transfer() {
  label=$1
  proxy_arg=$2
  bulk_url=$3
  output_file=$4
  expected_bytes=$5
  speed_bps=$(curl -fsS --connect-timeout "$CURL_CONNECT_TIMEOUT_SECONDS" --max-time "$CURL_MAX_TIME_SECONDS" $proxy_arg -w '%{speed_download}' -o "$output_file" "$bulk_url")
  verify_file_size "$output_file" "$expected_bytes"
  speed_bps=${speed_bps%.*}
  case "$speed_bps" in
    ''|*[!0-9]*) fail "curl did not report numeric speed_download for $label bulk transfer: ${speed_bps:-empty}" ;;
  esac
  kib_per_second=$((speed_bps / 1024))
  note "bulk throughput: $label ${kib_per_second} KiB/s"
  [ "$kib_per_second" -ge "$MIN_BULK_KIB_PER_SECOND" ] 2>/dev/null \
    || fail "$label bulk throughput below PAWXY_MIN_BULK_KIB_PER_SECOND=$MIN_BULK_KIB_PER_SECOND KiB/s: $kib_per_second KiB/s"
}

probe_bulk_proxy_transfer() {
  bulk_url=$1
  expected_bytes=$2
  output_dir=$3
  http_out=$output_dir/pawxy-bulk-http.bin
  socks_out=$output_dir/pawxy-bulk-socks.bin

  probe_one_bulk_transfer "HTTP" "-x http://127.0.0.1:$HOST_PROXY_PORT" "$bulk_url" "$http_out" "$expected_bytes"
  probe_one_bulk_transfer "SOCKS5" "--socks5-hostname 127.0.0.1:$HOST_PROXY_PORT" "$bulk_url" "$socks_out" "$expected_bytes"
  wait_for_idle_connections
}

probe_parallel_proxy_burst() {
  [ "$RUN_PARALLEL_BURST" = "1" ] || return 0
  target_url=$1
  output_dir=$2

  note "probing parallel proxy burst with $PARALLEL_BURST_CONNECTIONS connections"
  burst_stable_pid=$(process_pid)
  require_numeric_value "Pawxy process pid before parallel proxy burst" "$burst_stable_pid"
  before_json=$(status_json)
  before_total_connections=$(json_number_field "$before_json" total_connections)
  before_bytes_in=$(json_number_field "$before_json" bytes_in)
  before_bytes_out=$(json_number_field "$before_json" bytes_out)
  before_started_at=$(json_number_field "$before_json" started_at_unix_ms)
  require_proxy_running "$before_json"
  require_status_observability "$before_json" "parallel proxy burst before"
  [ -n "$before_total_connections" ] || fail "expected numeric status field total_connections before parallel proxy burst, got: $before_json"
  [ -n "$before_bytes_in" ] || fail "expected numeric status field bytes_in before parallel proxy burst, got: $before_json"
  [ -n "$before_bytes_out" ] || fail "expected numeric status field bytes_out before parallel proxy burst, got: $before_json"
  [ -n "$before_started_at" ] || fail "expected numeric status field started_at_unix_ms before parallel proxy burst, got: $before_json"

  burst_dir=$output_dir/pawxy-parallel-burst
  rm -rf "$burst_dir"
  mkdir -p "$burst_dir"
  : > "$burst_dir/pids"
  i=1
  while [ "$i" -le "$PARALLEL_BURST_CONNECTIONS" ]; do
    out=$burst_dir/$i.out
    err=$burst_dir/$i.err
    case $((i % 3)) in
      1)
        (fetch_through_http_proxy "$target_url" > "$out") 2>"$err" &
        ;;
      2)
        (fetch_through_connect_proxy "$target_url" > "$out") 2>"$err" &
        ;;
      0)
        (fetch_through_socks_proxy "$target_url" > "$out") 2>"$err" &
        ;;
    esac
    printf '%s %s\n' "$!" "$i" >> "$burst_dir/pids"
    i=$((i + 1))
  done

  failed=0
  while read -r pid index; do
    wait "$pid" || failed=1
  done < "$burst_dir/pids"
  [ "$failed" = "0" ] || fail "parallel proxy burst failed; inspect $burst_dir/*.err"

  i=1
  while [ "$i" -le "$PARALLEL_BURST_CONNECTIONS" ]; do
    grep -Fx "pawxy-smoke-ok" "$burst_dir/$i.out" >/dev/null \
      || fail "parallel proxy burst response $i did not match expected body"
    i=$((i + 1))
  done

  wait_for_idle_connections
  after_json=$(status_json)
  require_proxy_running "$after_json"
  require_status_observability "$after_json" "parallel proxy burst after"
  require_wake_hold_enabled "$after_json"
  require_stable_started_at "$after_json" "$before_started_at" "parallel proxy burst"
  require_same_process_pid "parallel proxy burst" "$burst_stable_pid"
  require_json_number_greater_than "$after_json" total_connections "$before_total_connections"
  require_json_number_greater_than "$after_json" bytes_in "$before_bytes_in"
  require_json_number_greater_than "$after_json" bytes_out "$before_bytes_out"
  note "parallel proxy burst: $PARALLEL_BURST_CONNECTIONS connections completed"
}

probe_power_mode_proxy_traffic() {
  label=$1
  target_url=$2
  bulk_url=$3
  expected_bytes=$4
  output_dir=$5
  stable_pid=$(process_pid)
  require_numeric_value "Pawxy process pid before $label" "$stable_pid"
  before_json=$(status_json)
  before_total_connections=$(json_number_field "$before_json" total_connections)
  before_bytes_in=$(json_number_field "$before_json" bytes_in)
  before_bytes_out=$(json_number_field "$before_json" bytes_out)
  before_started_at=$(json_number_field "$before_json" started_at_unix_ms)
  require_status_observability "$before_json" "$label before"
  [ -n "$before_total_connections" ] || fail "expected numeric status field total_connections before $label, got: $before_json"
  [ -n "$before_bytes_in" ] || fail "expected numeric status field bytes_in before $label, got: $before_json"
  [ -n "$before_bytes_out" ] || fail "expected numeric status field bytes_out before $label, got: $before_json"
  [ -n "$before_started_at" ] || fail "expected numeric status field started_at_unix_ms before $label, got: $before_json"
  probe_local_proxy_traffic "$target_url"
  require_same_process_pid "$label" "$stable_pid"
  if [ "$RUN_BULK" = "1" ]; then
    probe_bulk_proxy_transfer "$bulk_url" "$expected_bytes" "$output_dir"
    require_same_process_pid "$label" "$stable_pid"
  fi
  after_json=$(status_json)
  require_proxy_running "$after_json"
  require_status_observability "$after_json" "$label after"
  require_wake_hold_enabled "$after_json"
  require_stable_started_at "$after_json" "$before_started_at" "$label"
  require_json_number_greater_than "$after_json" total_connections "$before_total_connections"
  require_json_number_greater_than "$after_json" bytes_in "$before_bytes_in"
  require_json_number_greater_than "$after_json" bytes_out "$before_bytes_out"
  probe_idle_efficiency "$label"
}

verify_control_preflight() {
  [ "$RUN_CONTROL_PREFLIGHT" = "1" ] || return 0
  note "verifying $CONTROL_MODE control identity and status channel"

  uid=$(control_shell_uid | tr -d '\r' | awk '/^[0-9]+$/ { print; exit }')
  [ -n "$uid" ] || fail "control shell uid unavailable through $CONTROL_MODE"
  case "$uid" in
    0|2000)
      ;;
    *)
      fail "control shell uid $uid is not root or adb shell; Shizuku/rish must expose shell-level privileges for Pawxy"
      ;;
  esac

  if [ "$uid" = "2000" ]; then
    dump_permission=$(control_shell "pm check-permission android.permission.DUMP com.android.shell" | tr -d '\r' | awk 'NF { print; exit }')
    [ "$dump_permission" = "granted" ] \
      || fail "com.android.shell lacks android.permission.DUMP: ${dump_permission:-unknown}"
  fi

  json=$(status_json)
  if json_has_key "$json" running; then
    return 0
  fi
  status_error=$(json_string_field "$json" error)
  if [ "$status_error" = "unauthorized" ]; then
    note "status channel reachable before control token provisioning"
    return 0
  fi
  fail "status channel unavailable through $CONTROL_MODE; expected running field or pre-start unauthorized error, got: $json"
}

verify_package_installed() {
  package_path=$(device_sh "pm path $PKG" 2>/dev/null | tr -d '\r' | awk '/^package:/ { print; exit }')
  [ -n "$package_path" ] \
    || fail "Pawxy package $PKG was not visible after install; pm path returned empty"
}

restore_power_command() {
  if [ "$CONTROL_READY" = "1" ]; then
    control_shell "$1" >/dev/null 2>&1 && return 0
  fi
  device_sh "$1" >/dev/null 2>&1 || true
}

power_shell() {
  if [ "$CONTROL_READY" = "1" ]; then
    control_shell "$1"
  else
    device_sh "$1"
  fi
}

network_shell() {
  power_shell "$1"
}

notification_shell() {
  power_shell "$1"
}

run_network_command() {
  primary=$1
  fallback=$2
  if network_shell "$primary" >/dev/null 2>&1; then
    return 0
  fi
  [ -n "$fallback" ] || return 1
  network_shell "$fallback" >/dev/null
}

set_network_toggled_down() {
  mode=$1
  case "$mode" in
    wifi)
      run_network_command "cmd wifi set-wifi-enabled disabled" "svc wifi disable"
      ;;
    airplane)
      run_network_command "cmd connectivity airplane-mode enable" "settings put global airplane_mode_on 1; am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true"
      ;;
    *)
      fail "PAWXY_NETWORK_TOGGLE_MODE must be wifi, airplane, or a comma-separated list of those modes"
      ;;
  esac
}

set_network_toggled_up() {
  mode=$1
  case "$mode" in
    wifi)
      run_network_command "cmd wifi set-wifi-enabled enabled" "svc wifi enable"
      ;;
    airplane)
      run_network_command "cmd connectivity airplane-mode disable" "settings put global airplane_mode_on 0; am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false"
      ;;
    *)
      fail "PAWXY_NETWORK_TOGGLE_MODE must be wifi, airplane, or a comma-separated list of those modes"
      ;;
  esac
}

diagnostic_shell() {
  if [ "$CONTROL_READY" = "1" ]; then
    control_shell "$1"
  else
    device_sh "$1"
  fi
}

restore_screen_state() {
  [ "$DEVICE_READY" = "1" ] || return 0
  [ "$SCREEN_OFF_CHANGED" = "1" ] || return 0
  power_shell "input keyevent KEYCODE_WAKEUP" >/dev/null 2>&1 || true
  SCREEN_OFF_CHANGED=0
}

restore_network_state() {
  [ "$DEVICE_READY" = "1" ] || return 0
  [ "$NETWORK_TOGGLE_CHANGED" = "1" ] || return 0
  [ -n "$NETWORK_TOGGLE_ACTIVE_MODE" ] || return 0
  set_network_toggled_up "$NETWORK_TOGGLE_ACTIVE_MODE" >/dev/null 2>&1 || true
  NETWORK_TOGGLE_CHANGED=0
  NETWORK_TOGGLE_ACTIVE_MODE=
}

set_notification_denied() {
  notification_shell "cmd appops set $PKG POST_NOTIFICATION ignore" >/dev/null 2>&1 \
    || notification_shell "appops set $PKG POST_NOTIFICATION ignore" >/dev/null 2>&1 \
    || notification_shell "pm revoke $PKG android.permission.POST_NOTIFICATIONS" >/dev/null 2>&1
}

restore_notification_permission() {
  [ "$DEVICE_READY" = "1" ] || return 0
  [ "$NOTIFICATION_DENIAL_CHANGED" = "1" ] || return 0
  notification_shell "cmd appops set $PKG POST_NOTIFICATION allow" >/dev/null 2>&1 || true
  notification_shell "appops set $PKG POST_NOTIFICATION allow" >/dev/null 2>&1 || true
  notification_shell "pm grant $PKG android.permission.POST_NOTIFICATIONS" >/dev/null 2>&1 || true
  NOTIFICATION_DENIAL_CHANGED=0
}

probe_screen_off() {
  [ "$RUN_SCREEN_OFF" = "1" ] || return 0
  target_url=$1
  bulk_url=$2
  expected_bytes=$3
  output_dir=$4

  note "turning screen off and verifying proxy bridge"
  screen_stable_pid=$(process_pid)
  require_numeric_value "Pawxy process pid before screen-off probe" "$screen_stable_pid"
  screen_before_json=$(status_json)
  require_proxy_running "$screen_before_json"
  require_status_observability "$screen_before_json" "screen-off before"
  screen_started_at=$(json_number_field "$screen_before_json" started_at_unix_ms)
  [ -n "$screen_started_at" ] || fail "expected numeric status field started_at_unix_ms before screen-off probe, got: $screen_before_json"

  power_shell "input keyevent KEYCODE_SLEEP" >/dev/null
  SCREEN_OFF_CHANGED=1
  probe_local_proxy_traffic "$target_url"
  if [ "$RUN_BULK" = "1" ]; then
    probe_bulk_proxy_transfer "$bulk_url" "$expected_bytes" "$output_dir"
  fi
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "screen-off after traffic"
  require_wake_hold_enabled "$json"
  require_stable_started_at "$json" "$screen_started_at" "screen-off probe"
  require_same_process_pid "screen-off probe" "$screen_stable_pid"

  if [ "$KEEP_SCREEN_OFF_DURING_HOLD" = "1" ] && [ "$HOLD_SECONDS" -gt 0 ] 2>/dev/null; then
    note "keeping screen off for persistence hold"
    return 0
  fi

  note "waking screen after screen-off proxy verification"
  restore_screen_state
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "screen-off restore"
  require_stable_started_at "$json" "$screen_started_at" "screen-off restore"
  require_same_process_pid "screen-off restore" "$screen_stable_pid"
}

restore_screen_after_screen_off_hold() {
  [ "$KEEP_SCREEN_OFF_DURING_HOLD" = "1" ] || return 0
  [ "$SCREEN_OFF_CHANGED" = "1" ] || return 0
  hold_pid_context=$1
  hold_started_at_context=$2

  note "waking screen after screen-off persistence hold"
  restore_screen_state
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "screen-off hold restore"
  require_wake_hold_enabled "$json"
  require_stable_started_at "$json" "$hold_started_at_context" "screen-off hold restore"
  require_same_process_pid "screen-off hold restore" "$hold_pid_context"
}

probe_network_toggle() {
  [ "$RUN_NETWORK_TOGGLE" = "1" ] || return 0
  target_url=$1
  bulk_url=$2
  expected_bytes=$3
  output_dir=$4

  old_ifs=$IFS
  IFS=,
  set -- $NETWORK_TOGGLE_MODE
  IFS=$old_ifs
  for mode do
    probe_one_network_toggle "$mode" "$target_url" "$bulk_url" "$expected_bytes" "$output_dir"
  done
}

probe_one_network_toggle() {
  mode=$1
  target_url=$2
  bulk_url=$3
  expected_bytes=$4
  output_dir=$5

  note "toggling $mode network state and verifying proxy bridge"
  network_stable_pid=$(process_pid)
  require_numeric_value "Pawxy process pid before network toggle" "$network_stable_pid"
  network_before_json=$(status_json)
  require_proxy_running "$network_before_json"
  require_status_observability "$network_before_json" "network toggle before"
  network_started_at=$(json_number_field "$network_before_json" started_at_unix_ms)
  [ -n "$network_started_at" ] || fail "expected numeric status field started_at_unix_ms before network toggle, got: $network_before_json"

  set_network_toggled_down "$mode" || fail "failed to disable $mode network state through $CONTROL_MODE"
  NETWORK_TOGGLE_CHANGED=1
  NETWORK_TOGGLE_ACTIVE_MODE=$mode
  if [ "$NETWORK_TOGGLE_SLEEP_SECONDS" -gt 0 ] 2>/dev/null; then
    sleep "$NETWORK_TOGGLE_SLEEP_SECONDS"
  fi
  probe_power_mode_proxy_traffic "$mode network toggled off" "$target_url" "$bulk_url" "$expected_bytes" "$output_dir"
  require_same_process_pid "$mode network toggled off" "$network_stable_pid"

  note "restoring $mode network state and verifying proxy remains stable"
  set_network_toggled_up "$mode" || fail "failed to restore $mode network state through $CONTROL_MODE"
  NETWORK_TOGGLE_CHANGED=0
  NETWORK_TOGGLE_ACTIVE_MODE=
  if [ "$NETWORK_TOGGLE_SLEEP_SECONDS" -gt 0 ] 2>/dev/null; then
    sleep "$NETWORK_TOGGLE_SLEEP_SECONDS"
  fi
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "network toggle restore"
  require_wake_hold_enabled "$json"
  require_stable_started_at "$json" "$network_started_at" "network toggle restore"
  require_same_process_pid "network toggle restore" "$network_stable_pid"
  probe_local_proxy_traffic "$target_url"
  require_same_process_pid "network toggle restore" "$network_stable_pid"
  probe_idle_efficiency "network toggle restore"
}

probe_notification_denial() {
  [ "$RUN_NOTIFICATION_DENIAL" = "1" ] || return 0
  target_url=$1

  note "denying notification permission and verifying foreground proxy restart"
  notification_stable_pid=$(process_pid)
  require_numeric_value "Pawxy process pid before notification denial" "$notification_stable_pid"
  notification_before_json=$(status_json)
  require_proxy_running "$notification_before_json"
  require_status_observability "$notification_before_json" "notification denial before"

  set_notification_denied || fail "failed to deny notification permission through $CONTROL_MODE"
  NOTIFICATION_DENIAL_CHANGED=1
  control restart >/dev/null \
    || fail "failed to restart proxy while notification permission was denied through $CONTROL_MODE control"
  json=$(wait_for_running_status "notification-denied restart" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_running "$json"
  require_auth_state "$json" false
  require_status_observability "$json" "notification-denied restart"
  notification_started_at=$(json_number_field "$json" started_at_unix_ms)
  [ -n "$notification_started_at" ] || fail "expected numeric status field started_at_unix_ms after notification-denied restart, got: $json"
  require_same_process_pid "notification-denied restart" "$notification_stable_pid"
  probe_local_proxy_traffic "$target_url"
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "notification-denied traffic"
  require_stable_started_at "$json" "$notification_started_at" "notification-denied traffic"
  require_same_process_pid "notification-denied traffic" "$notification_stable_pid"

  restore_notification_permission
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "notification permission restore"
  require_stable_started_at "$json" "$notification_started_at" "notification permission restore"
  require_same_process_pid "notification permission restore" "$notification_stable_pid"
}

probe_forced_power_mode() {
  enabled=$1
  power_label=$2
  force_command=$3
  restore_command=$4
  target_url=$5
  bulk_url=$6
  expected_bytes=$7
  output_dir=$8

  [ "$enabled" = "1" ] || return 0
  note "forcing $power_label and verifying proxy traffic"
  power_stable_pid=$(process_pid)
  require_numeric_value "Pawxy process pid before $power_label" "$power_stable_pid"
  power_before_json=$(status_json)
  require_proxy_running "$power_before_json"
  require_status_observability "$power_before_json" "$power_label before force"
  power_started_at=$(json_number_field "$power_before_json" started_at_unix_ms)
  [ -n "$power_started_at" ] || fail "expected numeric status field started_at_unix_ms before $power_label, got: $power_before_json"
  power_shell "dumpsys battery unplug" >/dev/null
  POWER_MODE_CHANGED=1
  power_shell "$force_command" >/dev/null
  probe_power_mode_proxy_traffic "$power_label" "$target_url" "$bulk_url" "$expected_bytes" "$output_dir"
  require_same_process_pid "$power_label" "$power_stable_pid"
  restore_power_command "$restore_command"
  restore_power_command "dumpsys battery reset"
  POWER_MODE_CHANGED=0
  note "restoring $power_label and verifying proxy remains stable"
  json=$(status_json)
  require_proxy_running "$json"
  require_status_observability "$json" "$power_label after restore"
  require_wake_hold_enabled "$json"
  require_stable_started_at "$json" "$power_started_at" "$power_label restore"
  require_same_process_pid "$power_label restore" "$power_stable_pid"
  probe_local_proxy_traffic "$target_url"
  require_same_process_pid "$power_label restore" "$power_stable_pid"
}

run_device_diag() {
  label=$1
  command=$2
  note "diagnostic: $label"
  diag_output=$(diagnostic_shell "$command" 2>&1 || true)
  printf '%s\n' "$diag_output" | sed 's/^/  /'
  if [ "$ARTIFACT_READY" = "1" ]; then
    diag_slug=$(artifact_label_slug "$label")
    printf '%s\n' "$diag_output" > "$ARTIFACT_DIR/diagnostics/$diag_slug.txt"
  fi
}

run_control_diag() {
  label=$1
  shift
  if [ "$CONTROL_READY" != "1" ]; then
    note "diagnostic skipped: $label; control channel not verified"
    return 0
  fi
  note "diagnostic: $label"
  case "$CONTROL_MODE" in
    adb)
      control_diag_output=$(device_sh_control "PAWXY_HOME=/data/local/tmp/pawxy $DEVICE_CTL $*" 2>&1 || true)
      ;;
    rish)
      control_diag_output=$(rish_shell "PAWXY_HOME=/data/local/tmp/pawxy $DEVICE_CTL $*" 2>&1 || true)
      ;;
    *)
      note "diagnostic skipped: unsupported PAWXY_CONTROL_MODE=$CONTROL_MODE"
      control_diag_output=
      ;;
  esac
  [ -z "${control_diag_output:-}" ] || printf '%s\n' "$control_diag_output" | sed 's/^/  /'
  if [ "$ARTIFACT_READY" = "1" ]; then
    control_diag_slug=$(artifact_label_slug "$label")
    printf '%s\n' "${control_diag_output:-}" > "$ARTIFACT_DIR/diagnostics/$control_diag_slug.txt"
  fi
}

collect_failure_diagnostics() {
  [ "$COLLECT_DIAGNOSTICS" = "1" ] || return 0
  [ "$DEVICE_READY" = "1" ] || return 0
  note "collecting failure diagnostics"
  run_control_diag "pawxyctl doctor via $CONTROL_MODE" doctor
  run_device_diag "Pawxy logcat" "logcat -d -s Pawxy PawxyNative | tail -n 200"
  run_device_diag "device idle" "dumpsys deviceidle | head -n 80"
  run_device_diag "power" "dumpsys power | head -n 80"
  run_device_diag "standby bucket" "am get-standby-bucket $PKG"
  run_device_diag "background restriction" "cmd appops get $PKG RUN_ANY_IN_BACKGROUND"
  run_device_diag "battery saver" "settings get global low_power"
  run_device_diag "service" "dumpsys activity services $SERVICE | head -n 120"
  run_device_diag "notification permission" "pm check-permission android.permission.POST_NOTIFICATIONS $PKG"
  run_device_diag "notification app-op" "cmd appops get $PKG POST_NOTIFICATION"
}

cleanup_power_modes() {
  [ "$DEVICE_READY" = "1" ] || return 0
  [ "$POWER_MODE_CHANGED" = "1" ] || return 0
  restore_power_command "dumpsys deviceidle unforce"
  restore_power_command "am set-inactive $PKG false"
  restore_power_command "am set-standby-bucket $PKG active"
  restore_power_command "cmd appops set $PKG RUN_ANY_IN_BACKGROUND allow"
  restore_power_command "settings put global low_power 0"
  restore_power_command "dumpsys battery reset"
  POWER_MODE_CHANGED=0
}

cleanup_device_service() {
  [ "$DEVICE_READY" = "1" ] || return 0
  [ "$CONTROL_READY" = "1" ] || return 0
  [ "$SERVICE_STOP_NEEDED" = "1" ] || return 0
  control stop >/dev/null 2>&1 || true
}

cleanup() {
  code=$?
  if [ "$CLEANUP_DONE" = "1" ]; then
    exit "$code"
  fi
  CLEANUP_DONE=1
  if [ "$code" -ne 0 ]; then
    restore_screen_state
    restore_network_state
    collect_failure_diagnostics
    cleanup_power_modes
    restore_notification_permission
    cleanup_device_service
  fi
  restore_screen_state
  restore_network_state
  cleanup_power_modes
  restore_notification_permission
  if [ "$ARTIFACT_READY" = "1" ]; then
    artifact_write summary.txt \
      "exit_code=$code" \
      "device_ready=$DEVICE_READY" \
      "control_ready=$CONTROL_READY" \
      "service_stop_needed=$SERVICE_STOP_NEEDED"
    if [ "$CONTROL_READY" = "1" ]; then
      final_status_json=$(status_json_or_empty)
      artifact_append_status "final" "$final_status_json"
      artifact_write final-status.json "$final_status_json"
    fi
  fi
  [ -n "${HTTP_PID:-}" ] && kill "$HTTP_PID" >/dev/null 2>&1 || true
  adb_base forward --remove "tcp:$HOST_PROXY_PORT" >/dev/null 2>&1 || true
  adb_base reverse --remove "tcp:$HOST_TARGET_PORT" >/dev/null 2>&1 || true
  exit "$code"
}
trap cleanup EXIT HUP INT TERM

validate_config

[ -f "$APK" ] || fail "APK not found: $APK"
[ -f "$CTL" ] || fail "pawxyctl not found: $CTL"
has_cmd curl || fail "host curl is required"
has_cmd python3 || fail "host python3 is required for the loopback target server"
has_cmd dd || fail "host dd is required for the bulk transfer fixture"
has_cmd wc || fail "host wc is required for the bulk transfer check"
has_cmd timeout || fail "host timeout is required for bounded adb probes"
if [ "$RUN_DEVICE_ORIGIN" = "1" ]; then
  has_cmd timeout || fail "host timeout is required for bounded device-origin proxy probes"
  if [ "$RUN_SHARE" = "1" ]; then
    has_cmd base64 || fail "host base64 is required for authenticated device-origin LAN proxy probes"
  fi
fi

init_artifacts

if [ -n "${ANDROID_SERIAL:-}" ]; then
  state=$(adb_base get-state 2>/dev/null || true)
  [ "$state" = "device" ] || fail "ANDROID_SERIAL=$ANDROID_SERIAL is not in device state: ${state:-unknown}"
else
  devices=$(adb_base devices | awk '$2 == "device" { count += 1 } END { print count + 0 }')
  [ "$devices" = "1" ] || fail "expected exactly one adb device or ANDROID_SERIAL, found $devices"
fi
DEVICE_READY=1

note "device identity"
device_sh 'printf "brand=%s\nmodel=%s\nsdk=%s\nbuild=%s\n" "$(getprop ro.product.brand)" "$(getprop ro.product.model)" "$(getprop ro.build.version.sdk)" "$(getprop ro.build.fingerprint)"'

if [ "$CONTROL_MODE" = "rish" ] && [ "$RUN_RISH_PROBE" = "1" ]; then
  rish_shell "true" \
    || fail "rish command failed: $RISH; set PAWXY_RISH to the generated rish path, set PAWXY_RISH_RUNNER=sh for storage-exported scripts, set PAWXY_RISH_APPLICATION_ID to the Shizuku-authorized terminal package when required, or run PAWXY_CONTROL_MODE=adb"
fi

tmp=${TMPDIR:-/tmp}/pawxy-device-smoke.$$
rm -rf "$tmp"
mkdir -p "$tmp/www"
printf '%s\n' "pawxy-smoke-ok" > "$tmp/www/pawxy-smoke.txt"
dd if=/dev/zero of="$tmp/www/pawxy-bulk.bin" bs=1024 count="$BULK_KIB" >/dev/null 2>&1
target_url="http://127.0.0.1:$HOST_TARGET_PORT/pawxy-smoke.txt"
bulk_url="http://127.0.0.1:$HOST_TARGET_PORT/pawxy-bulk.bin"
bulk_bytes=$((BULK_KIB * 1024))
python3 -m http.server "$HOST_TARGET_PORT" --bind 127.0.0.1 --directory "$tmp/www" >/dev/null 2>&1 &
HTTP_PID=$!
wait_for_target_server "$target_url" "$TARGET_SERVER_RETRIES" "$TARGET_SERVER_SLEEP_SECONDS"

note "installing APK and control helper"
adb_base install -r "$APK" >/dev/null
verify_package_installed
device_sh pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb_base push "$CTL" "$DEVICE_CTL" >/dev/null
device_sh "chmod 755 $DEVICE_CTL"
verify_control_preflight
CONTROL_READY=1

note "wiring adb forward/reverse"
adb_base forward --remove "tcp:$HOST_PROXY_PORT" >/dev/null 2>&1 || true
adb_base reverse --remove "tcp:$HOST_TARGET_PORT" >/dev/null 2>&1 || true
adb_base forward "tcp:$HOST_PROXY_PORT" "tcp:3218"
adb_base reverse "tcp:$HOST_TARGET_PORT" "tcp:$HOST_TARGET_PORT"

note "starting local proxy through $CONTROL_MODE control"
SERVICE_STOP_NEEDED=1
control start >/dev/null \
  || fail "failed to start local proxy through $CONTROL_MODE control"
json=$(wait_for_running_status "initial start" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
require_proxy_running "$json"
require_auth_state "$json" false
stable_listen=$(json_string_field "$json" listen)
[ -n "$stable_listen" ] || fail "initial start status did not include listen: $json"
native_listen=$(json_string_field "$json" native_listen)
[ "$native_listen" = "$stable_listen" ] \
  || fail "initial start status native_listen did not match listen: $json"
stable_started_at=$(json_number_field "$json" started_at_unix_ms)
[ -n "$stable_started_at" ] || fail "initial start status did not include started_at_unix_ms: $json"
native_started_at=$(json_number_field "$json" native_started_at_unix_ms)
[ "$native_started_at" = "$stable_started_at" ] \
  || fail "initial start status native_started_at_unix_ms did not match started_at_unix_ms: $json"
probe_local_proxy_traffic "$target_url"
if [ "$RUN_BULK" = "1" ]; then
  probe_bulk_proxy_transfer "$bulk_url" "$bulk_bytes" "$tmp"
fi
probe_parallel_proxy_burst "$target_url" "$tmp"
json=$(status_json)
require_status_observability "$json" "initial traffic"
require_json_number_at_least "$json" total_connections 1
require_json_number_at_least "$json" bytes_in 1
require_json_number_at_least "$json" bytes_out 1
probe_idle_efficiency "initial traffic"

if [ "$RUN_DUPLICATE_START" = "1" ]; then
  probe_duplicate_start "$target_url"
fi

if [ "$RUN_BAD_TOKEN" = "1" ]; then
  note "verifying unauthorized intent cannot stop the running proxy"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.STOP --es token bad-token" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_stable_listen "$json" "$stable_listen" "unauthorized intent"
  require_stable_started_at "$json" "$stable_started_at" "unauthorized intent"
fi

if [ "$RUN_UNKNOWN_ACTION" = "1" ]; then
  note "verifying unknown intent action cannot stop the running proxy"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.UNKNOWN" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_stable_listen "$json" "$stable_listen" "unknown action"
  require_stable_started_at "$json" "$stable_started_at" "unknown action"
fi

probe_token_repair
if [ "$RUN_TOKEN_REPAIR" = "1" ]; then
  probe_local_proxy_traffic "$target_url"
fi

if [ "$RUN_UNSAFE_LAN" = "1" ]; then
  note "verifying unsafe LAN listen cannot stop the running proxy"
  token=$(control_shell "sed -n 1p $DEVICE_HOME/token" | tr -d '\r')
  [ -n "$token" ] || fail "control token missing from $DEVICE_HOME/token"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen 0.0.0.0:3218 --ez lan true --ez auth_enabled false" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "unsafe LAN listen"
  require_stable_started_at "$json" "$stable_started_at" "unsafe LAN listen"
  probe_local_proxy_traffic "$target_url"
fi

if [ "$RUN_INVALID_CONFIG" = "1" ]; then
  note "verifying malformed direct start config cannot break the running proxy"
  token=$(control_shell "sed -n 1p $DEVICE_HOME/token" | tr -d '\r')
  [ -n "$token" ] || fail "control token missing from $DEVICE_HOME/token"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen not-a-socket --ei max_connections -1" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "malformed direct start"
  require_stable_started_at "$json" "$stable_started_at" "malformed direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --ei max_connections 0 --ei max_per_source_ip 0 --el handshake_timeout_ms 0 --el connect_timeout_ms 0 --el idle_timeout_ms 0" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "zero limit direct start"
  require_stable_started_at "$json" "$stable_started_at" "zero limit direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --ei max_connections 2147483647 --ei max_per_source_ip 2147483647 --el handshake_timeout_ms 9223372036854775807 --el connect_timeout_ms 9223372036854775807 --el idle_timeout_ms 9223372036854775807" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "oversized direct start"
  require_stable_started_at "$json" "$stable_started_at" "oversized direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --ez auth_enabled true" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "auth-required direct start"
  require_stable_started_at "$json" "$stable_started_at" "auth-required direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen 127.0.0.1:$HOST_TARGET_PORT" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "bind-conflicting direct start"
  require_stable_started_at "$json" "$stable_started_at" "bind-conflicting direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen 192.0.2.1:3218" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "nonlocal listen direct start"
  require_stable_started_at "$json" "$stable_started_at" "nonlocal listen direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen 127.0.0.2:3218" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "loopback-alias direct start"
  require_stable_started_at "$json" "$stable_started_at" "loopback-alias direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen 127.0.0.1:80" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "low-port direct start"
  require_stable_started_at "$json" "$stable_started_at" "low-port direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen [::1]:3218" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "IPv6 loopback direct start"
  require_stable_started_at "$json" "$stable_started_at" "IPv6 loopback direct start"
  probe_local_proxy_traffic "$target_url"
  control_shell "am start-foreground-service -n $SERVICE -a dev.pawxy.action.START --es token $token --es listen [::]:3218 --ez auth_enabled true --es username pawxy --es password ipv6-test" >/dev/null || true
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" service_started true
  require_auth_state "$json" false
  require_stable_listen "$json" "$stable_listen" "IPv6 wildcard direct start"
  require_stable_started_at "$json" "$stable_started_at" "IPv6 wildcard direct start"
  probe_local_proxy_traffic "$target_url"
fi

if [ "$RUN_RESTART" = "1" ]; then
  note "restarting without listener bind race"
  control restart >/dev/null
  json=$(wait_for_running_status "restart" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_running "$json"
  probe_local_proxy_traffic "$target_url"
fi

probe_process_restart
if [ "$RUN_PROCESS_RESTART" = "1" ]; then
  probe_local_proxy_traffic "$target_url"
  if [ "$RUN_BULK" = "1" ]; then
    probe_bulk_proxy_transfer "$bulk_url" "$bulk_bytes" "$tmp"
  fi
  probe_idle_efficiency "process restart"
fi

if [ "$RUN_STOP_START" = "1" ]; then
  note "stopping and immediately starting without listener release race"
  control stop >/dev/null
  json=$(wait_for_stopped_status "stop/start stop" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_stopped "$json"
  SERVICE_STOP_NEEDED=0
  SERVICE_STOP_NEEDED=1
  control start >/dev/null \
    || fail "failed to start proxy after stop/start race check through $CONTROL_MODE control"
  json=$(wait_for_running_status "stop/start" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_running "$json"
  probe_local_proxy_traffic "$target_url"
fi

probe_notification_denial "$target_url"

if [ "$RUN_WAKE" = "1" ]; then
  note "toggling wake lock"
  control wake on >/dev/null
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" wake_lock_enabled true
  control wake off >/dev/null
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" wake_lock_enabled false
fi

if [ "$RUN_SHARE" = "1" ]; then
  note "testing LAN share auth path through forwarded port"
  control share on >/dev/null
  json=$(wait_for_running_status "share on" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_running "$json"
  require_auth_state "$json" true
  probe_unauthenticated_lan_proxy_rejected "$target_url"
  probe_unauthenticated_device_origin_lan_proxy_rejected "$target_url"
  password=$(control_shell "grep ^LAN_PASSWORD= $DEVICE_HOME/config.env | sed -n 1p | cut -d= -f2-" | tr -d '\r')
  [ -n "$password" ] || fail "LAN password missing from $DEVICE_HOME/config.env"
  require_lan_password_shape "$password"
  fetch_through_auth_proxy "$target_url" "$password" | grep -Fx "pawxy-smoke-ok" >/dev/null \
    || fail "authenticated LAN proxy traffic failed"
  fetch_through_auth_socks_proxy "$target_url" "$password" | grep -Fx "pawxy-smoke-ok" >/dev/null \
    || fail "authenticated LAN SOCKS5 proxy traffic failed"
  probe_device_origin_authenticated_proxy_traffic "$target_url" "$password"
  wait_for_idle_connections
  control share off >/dev/null
  json=$(wait_for_running_status "share off" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
  require_proxy_running "$json"
  require_auth_state "$json" false
fi

if [ "$RUN_WAKE_HOLD" = "1" ]; then
  note "enabling wake lock for persistence and power-mode stress"
  control wake on >/dev/null
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" wake_lock_enabled true
  WAKE_HOLD_ENABLED=1
  probe_local_proxy_traffic "$target_url"
fi

probe_network_toggle "$target_url" "$bulk_url" "$bulk_bytes" "$tmp"

probe_screen_off "$target_url" "$bulk_url" "$bulk_bytes" "$tmp"

if [ "$HOLD_SECONDS" -gt 0 ] 2>/dev/null; then
  note "holding service for $HOLD_SECONDS seconds with traffic probes every $HOLD_INTERVAL_SECONDS seconds"
  hold_pid=$(process_pid)
  require_numeric_value "Pawxy process pid before persistence hold" "$hold_pid"
  hold_previous_json=$(status_json)
  hold_previous_total_connections=$(json_number_field "$hold_previous_json" total_connections)
  hold_previous_bytes_in=$(json_number_field "$hold_previous_json" bytes_in)
  hold_previous_bytes_out=$(json_number_field "$hold_previous_json" bytes_out)
  hold_started_at=$(json_number_field "$hold_previous_json" started_at_unix_ms)
  require_status_observability "$hold_previous_json" "persistence hold before"
  [ -n "$hold_previous_total_connections" ] || fail "expected numeric status field total_connections before hold, got: $hold_previous_json"
  [ -n "$hold_previous_bytes_in" ] || fail "expected numeric status field bytes_in before hold, got: $hold_previous_json"
  [ -n "$hold_previous_bytes_out" ] || fail "expected numeric status field bytes_out before hold, got: $hold_previous_json"
  [ -n "$hold_started_at" ] || fail "expected numeric status field started_at_unix_ms before hold, got: $hold_previous_json"
  elapsed=0
  while [ "$elapsed" -lt "$HOLD_SECONDS" ]; do
    remaining=$((HOLD_SECONDS - elapsed))
    if [ "$remaining" -lt "$HOLD_INTERVAL_SECONDS" ]; then
      step=$remaining
    else
      step=$HOLD_INTERVAL_SECONDS
    fi
    [ "$step" -gt 0 ] || step=1
    sleep "$step"
    elapsed=$((elapsed + step))
    json=$(status_json)
    require_proxy_running "$json"
    require_status_observability "$json" "persistence hold sample"
    require_wake_hold_enabled "$json"
    require_same_process_pid "persistence hold" "$hold_pid"
    require_stable_started_at "$json" "$hold_started_at" "persistence hold"
    probe_local_proxy_traffic "$target_url"
    if [ "$RUN_BULK" = "1" ]; then
      probe_bulk_proxy_transfer "$bulk_url" "$bulk_bytes" "$tmp"
    fi
    require_same_process_pid "persistence hold" "$hold_pid"
    json=$(status_json)
    require_status_observability "$json" "persistence hold sample"
    require_wake_hold_enabled "$json"
    require_stable_started_at "$json" "$hold_started_at" "persistence hold"
    require_json_number_greater_than "$json" total_connections "$hold_previous_total_connections"
    require_json_number_greater_than "$json" bytes_in "$hold_previous_bytes_in"
    require_json_number_greater_than "$json" bytes_out "$hold_previous_bytes_out"
    log_hold_sample "$json" "$elapsed" "$hold_pid"
    hold_previous_total_connections=$(json_number_field "$json" total_connections)
    hold_previous_bytes_in=$(json_number_field "$json" bytes_in)
    hold_previous_bytes_out=$(json_number_field "$json" bytes_out)
  done
  probe_idle_efficiency "persistence hold"
  restore_screen_after_screen_off_hold "$hold_pid" "$hold_started_at"
fi

probe_forced_power_mode "$RUN_DOZE" "Doze mode" "dumpsys deviceidle force-idle" "dumpsys deviceidle unforce" "$target_url" "$bulk_url" "$bulk_bytes" "$tmp"
probe_forced_power_mode "$RUN_APP_STANDBY" "App Standby" "am set-inactive $PKG true" "am set-inactive $PKG false" "$target_url" "$bulk_url" "$bulk_bytes" "$tmp"
probe_forced_power_mode "$RUN_STANDBY_BUCKET" "rare App Standby Bucket" "am set-standby-bucket $PKG rare" "am set-standby-bucket $PKG active" "$target_url" "$bulk_url" "$bulk_bytes" "$tmp"
probe_forced_power_mode "$RUN_BACKGROUND_RESTRICTION" "background restriction" "cmd appops set $PKG RUN_ANY_IN_BACKGROUND ignore" "cmd appops set $PKG RUN_ANY_IN_BACKGROUND allow" "$target_url" "$bulk_url" "$bulk_bytes" "$tmp"
probe_forced_power_mode "$RUN_BATTERY_SAVER" "battery saver" "settings put global low_power 1" "settings put global low_power 0" "$target_url" "$bulk_url" "$bulk_bytes" "$tmp"

if [ "$WAKE_HOLD_ENABLED" = "1" ]; then
  note "disabling wake lock after persistence and power-mode stress"
  control wake off >/dev/null
  json=$(status_json)
  require_proxy_running "$json"
  require_json_field "$json" wake_lock_enabled false
  WAKE_HOLD_ENABLED=0
fi

note "stopping"
control stop >/dev/null
json=$(wait_for_stopped_status "final stop" "$STARTUP_RETRIES" "$STARTUP_SLEEP_SECONDS")
require_proxy_stopped "$json"
require_json_field "$json" wake_lock_enabled false
SERVICE_STOP_NEEDED=0

if [ "$RUN_WAKE" = "1" ]; then
  note "verifying wake lock cannot be enabled while proxy is stopped"
  control wake on >/dev/null || true
  json=$(status_json)
  require_proxy_stopped "$json"
  require_json_field "$json" wake_lock_enabled false
fi

printf '%s\n' "pawxy device smoke ok"
