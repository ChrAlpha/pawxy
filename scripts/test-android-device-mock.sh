#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/test-android-device.sh

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "scripts/test-android-device.sh must exist"
sh -n "$SCRIPT"

tmp=${TMPDIR:-/tmp}/pawxy-device-smoke-test.$$
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/log-adb" "$tmp/log-rish" "$tmp/log-rish-power" "$tmp/log-custom-rish" "$tmp/log-runner-rish" "$tmp/log-rish-application-id" "$tmp/log-spaced-rish" "$tmp/log-quoted-rish" "$tmp/log-rish-probe-failure" "$tmp/log-serial" "$tmp/log-hold" "$tmp/log-artifact" "$tmp/log-hold-fd" "$tmp/log-parallel-burst" "$tmp/log-rish-parallel-burst" "$tmp/log-invalid-parallel-burst" "$tmp/log-notification-denial" "$tmp/log-rish-notification-denial" "$tmp/log-notification-denial-failure" "$tmp/log-wake-hold" "$tmp/log-screen-off" "$tmp/log-screen-off-hold" "$tmp/log-rish-screen-off" "$tmp/log-rish-screen-off-hold" "$tmp/log-invalid-screen-off-hold" "$tmp/log-network-toggle" "$tmp/log-dual-network-toggle" "$tmp/log-rish-network-toggle" "$tmp/log-rish-airplane-network-toggle" "$tmp/log-network-toggle-failure" "$tmp/log-invalid-network-mode" "$tmp/log-wake-native-drift" "$tmp/log-power" "$tmp/log-power-failure" "$tmp/log-background-restriction-failure" "$tmp/log-delayed-start" "$tmp/log-delayed-stop" "$tmp/log-start-ignored" "$tmp/log-start-fails-after-launch" "$tmp/log-target-server-failure" "$tmp/log-package-missing" "$tmp/log-bad-uid" "$tmp/log-invalid-hold" "$tmp/log-invalid-adb-timeout" "$tmp/log-invalid-control-timeout" "$tmp/log-invalid-device-shell-timeout" "$tmp/log-invalid-curl-timeout" "$tmp/log-invalid-device-origin-timeout" "$tmp/log-invalid-run-flag" "$tmp/log-port-conflict" "$tmp/log-token-repair-failure" "$tmp/log-listen-drift" "$tmp/log-native-running-drift" "$tmp/log-process-pid-stuck" "$tmp/log-native-restart-during-hold" "$tmp/log-process-restart-during-hold" "$tmp/log-active-connection-leak" "$tmp/log-idle-cpu" "$tmp/log-idle-fd" "$tmp/log-failure" "$tmp/log-rish-failure" "$tmp/log-spaced-json" "$tmp/files"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

printf '%s\n' "fake apk" > "$tmp/files/app-debug.apk"
printf '%s\n' "#!/bin/sh" > "$tmp/files/pawxyctl"
chmod 755 "$tmp/files/pawxyctl"

cat > "$tmp/bin/python3" <<'PYTHON'
#!/bin/sh
exit 0
PYTHON
chmod 755 "$tmp/bin/python3"

cat > "$tmp/bin/sleep" <<'SLEEP'
#!/bin/sh
count_file=$PAWXY_TEST_LOG/sleep-count
count=0
[ -f "$count_file" ] && count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
if [ -n "${PAWXY_TEST_RESTART_AFTER_SLEEP_COUNT:-}" ] && [ "$count" -ge "$PAWXY_TEST_RESTART_AFTER_SLEEP_COUNT" ] 2>/dev/null; then
  printf '%s\n' "4344" > "$PAWXY_TEST_LOG/pid"
fi
if [ -n "${PAWXY_TEST_NATIVE_RESTART_AFTER_SLEEP_COUNT:-}" ] && [ "$count" -ge "$PAWXY_TEST_NATIVE_RESTART_AFTER_SLEEP_COUNT" ] 2>/dev/null; then
  printf '%s\n' "2000" > "$PAWXY_TEST_LOG/started-at"
fi
exit 0
SLEEP
chmod 755 "$tmp/bin/sleep"

cat > "$tmp/bin/timeout" <<'TIMEOUT'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/timeout.log"
shift
exec "$@"
TIMEOUT
chmod 755 "$tmp/bin/timeout"

cat > "$tmp/bin/curl" <<'CURL'
#!/bin/sh
write_state() {
  running=$1
  auth_enabled=$2
  wake_lock_enabled=$3
  active_connections=$4
  total_connections=$5
  bytes_out=$6
  bytes_in=$((bytes_out / 2))
	  started_at=$(started_at_value)
	  network_available=$(network_available_value)
	  network_generation=$(network_generation_value)
	  native_running=$running
	  if [ "${PAWXY_TEST_NATIVE_RUNNING_FALSE:-0}" = "1" ] && [ "$running" = "true" ]; then
	    native_running=false
	  fi
	  if [ "${PAWXY_TEST_SPACED_JSON:-0}" = "1" ]; then
	    printf '{ "running" : %s, "native_running" : %s, "service_started" : %s, "listen" : "127.0.0.1:3218", "native_listen" : "127.0.0.1:3218", "configured_listen" : "127.0.0.1:3218", "lan" : false, "native_lan" : false, "configured_lan" : false, "auth_enabled" : %s, "native_auth_enabled" : %s, "configured_auth_enabled" : %s, "wake_lock_enabled" : %s, "active_connections" : %s, "total_connections" : %s, "bytes_in" : %s, "bytes_out" : %s, "network_available" : %s, "network_transport" : "wifi", "network_generation" : %s, "started_at_unix_ms" : %s, "native_started_at_unix_ms" : %s }\n' "$running" "$native_running" "$running" "$auth_enabled" "$auth_enabled" "$auth_enabled" "$wake_lock_enabled" "$active_connections" "$total_connections" "$bytes_in" "$bytes_out" "$network_available" "$network_generation" "$started_at" "$started_at"
	  else
	    printf '{"running":%s,"native_running":%s,"service_started":%s,"listen":"127.0.0.1:3218","native_listen":"127.0.0.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":%s,"native_auth_enabled":%s,"configured_auth_enabled":%s,"wake_lock_enabled":%s,"active_connections":%s,"total_connections":%s,"bytes_in":%s,"bytes_out":%s,"network_available":%s,"network_transport":"wifi","network_generation":%s,"started_at_unix_ms":%s,"native_started_at_unix_ms":%s}\n' "$running" "$native_running" "$running" "$auth_enabled" "$auth_enabled" "$auth_enabled" "$wake_lock_enabled" "$active_connections" "$total_connections" "$bytes_in" "$bytes_out" "$network_available" "$network_generation" "$started_at" "$started_at"
	  fi
	}

state_bool() {
  field=$1
  if grep -E '"'$field'"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
    printf '%s\n' true
  else
    printf '%s\n' false
  fi
}

active_connections_value() {
  if [ "${PAWXY_TEST_ACTIVE_CONNECTIONS_STUCK:-0}" = "1" ]; then
    printf '%s\n' 1
  else
    printf '%s\n' 0
  fi
}

	started_at_value() {
	  if [ -f "$PAWXY_TEST_LOG/started-at" ]; then
	    cat "$PAWXY_TEST_LOG/started-at"
	  else
	    printf '%s\n' 1000
	  fi
	}

	network_available_value() {
	  if [ -f "$PAWXY_TEST_LOG/network-down" ]; then
	    printf '%s\n' false
	  else
	    printf '%s\n' true
	  fi
	}

	network_generation_value() {
	  if [ -f "$PAWXY_TEST_LOG/network-generation" ]; then
	    cat "$PAWXY_TEST_LOG/network-generation"
	  else
	    printf '%s\n' 3
	  fi
	}

	record_proxy_traffic() {
	  lock_dir=$PAWXY_TEST_LOG/traffic-count.lock
	  while ! mkdir "$lock_dir" 2>/dev/null; do
	    :
	  done
	  count=0
	  if [ -f "$traffic" ]; then
	    count=$(cat "$traffic")
	  fi
	  count=$((count + 1))
	  printf '%s\n' "$count" > "$traffic"
	  connections=$((4 + count))
	  bytes_out=$((1024 + count * 512))
	  auth_enabled=$(state_bool auth_enabled)
	  wake_lock_enabled=$(state_bool wake_lock_enabled)
	  active_connections=$(active_connections_value)
	  write_state true "$auth_enabled" "$wake_lock_enabled" "$active_connections" "$connections" "$bytes_out" > "$state"
	  rmdir "$lock_dir"
	}

	emit_response() {
  if [ -n "$out" ]; then
    case "$url" in
      *pawxy-bulk.bin)
        dd if=/dev/zero of="$out" bs=1024 count=1 >/dev/null 2>&1
        ;;
      *)
        printf '%s\n' "pawxy-smoke-ok" > "$out"
        ;;
    esac
    if [ -n "$write_out" ]; then
      printf '%s\n' "4096.0"
    fi
    exit 0
  fi
  printf '%s\n' "pawxy-smoke-ok"
  exit 0
}

printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/curl.log"
state=$PAWXY_TEST_LOG/state.json
traffic=$PAWXY_TEST_LOG/traffic-count
out=
url=
write_out=
uses_proxy=0
proxy_auth=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out=$2
      shift 2
      ;;
    -w|--write-out)
      write_out=$2
      shift 2
      ;;
    -x|--proxy|--socks5-hostname)
      uses_proxy=1
      case "$2" in
        *@*) proxy_auth=1 ;;
      esac
      shift 2
      ;;
    --proxy-user)
      uses_proxy=1
      proxy_auth=1
      shift 2
      ;;
    --max-time|--connect-timeout)
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
if [ "${PAWXY_TEST_FAIL_TARGET_SERVER:-0}" = "1" ] && [ "$uses_proxy" = "0" ]; then
  case "$url" in
    *pawxy-smoke.txt) exit 7 ;;
  esac
fi
if [ "$uses_proxy" = "0" ]; then
  emit_response
fi
if ! grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
  exit 56
fi
if [ "${PAWXY_TEST_FAIL_CURL:-0}" = "1" ] \
  || { [ "${PAWXY_TEST_FAIL_CURL_DURING_POWER:-0}" = "1" ] && [ -f "$PAWXY_TEST_LOG/power-mode-active" ]; } \
  || { [ "${PAWXY_TEST_FAIL_CURL_DURING_NETWORK:-0}" = "1" ] && [ -f "$PAWXY_TEST_LOG/network-down" ]; } \
  || { [ "${PAWXY_TEST_FAIL_CURL_DURING_NOTIFICATION:-0}" = "1" ] && [ -f "$PAWXY_TEST_LOG/notification-denied" ]; }; then
  exit 22
fi
if [ "$(state_bool auth_enabled)" = "true" ] && [ "$proxy_auth" != "1" ]; then
  exit 22
fi
record_proxy_traffic
emit_response
CURL
chmod 755 "$tmp/bin/curl"

cat > "$tmp/bin/adb" <<'ADB'
#!/bin/sh
write_state() {
  running=$1
  auth_enabled=$2
  wake_lock_enabled=$3
  active_connections=$4
  total_connections=$5
  bytes_out=$6
  bytes_in=$((bytes_out / 2))
	  started_at=$(started_at_value)
	  network_available=$(network_available_value)
	  network_generation=$(network_generation_value)
	  native_running=$running
	  if [ "${PAWXY_TEST_NATIVE_RUNNING_FALSE:-0}" = "1" ] && [ "$running" = "true" ]; then
	    native_running=false
	  fi
	  if [ "${PAWXY_TEST_SPACED_JSON:-0}" = "1" ]; then
	    printf '{ "running" : %s, "native_running" : %s, "service_started" : %s, "listen" : "127.0.0.1:3218", "native_listen" : "127.0.0.1:3218", "configured_listen" : "127.0.0.1:3218", "lan" : false, "native_lan" : false, "configured_lan" : false, "auth_enabled" : %s, "native_auth_enabled" : %s, "configured_auth_enabled" : %s, "wake_lock_enabled" : %s, "active_connections" : %s, "total_connections" : %s, "bytes_in" : %s, "bytes_out" : %s, "network_available" : %s, "network_transport" : "wifi", "network_generation" : %s, "started_at_unix_ms" : %s, "native_started_at_unix_ms" : %s }\n' "$running" "$native_running" "$running" "$auth_enabled" "$auth_enabled" "$auth_enabled" "$wake_lock_enabled" "$active_connections" "$total_connections" "$bytes_in" "$bytes_out" "$network_available" "$network_generation" "$started_at" "$started_at"
	  else
	    printf '{"running":%s,"native_running":%s,"service_started":%s,"listen":"127.0.0.1:3218","native_listen":"127.0.0.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":%s,"native_auth_enabled":%s,"configured_auth_enabled":%s,"wake_lock_enabled":%s,"active_connections":%s,"total_connections":%s,"bytes_in":%s,"bytes_out":%s,"network_available":%s,"network_transport":"wifi","network_generation":%s,"started_at_unix_ms":%s,"native_started_at_unix_ms":%s}\n' "$running" "$native_running" "$running" "$auth_enabled" "$auth_enabled" "$auth_enabled" "$wake_lock_enabled" "$active_connections" "$total_connections" "$bytes_in" "$bytes_out" "$network_available" "$network_generation" "$started_at" "$started_at"
	  fi
	}

state_bool() {
  field=$1
  if grep -E '"'$field'"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
    printf '%s\n' true
  else
    printf '%s\n' false
  fi
}

active_connections_value() {
  if [ "${PAWXY_TEST_ACTIVE_CONNECTIONS_STUCK:-0}" = "1" ]; then
    printf '%s\n' 1
  else
    printf '%s\n' 0
  fi
}

	started_at_value() {
	  if [ -f "$PAWXY_TEST_LOG/started-at" ]; then
	    cat "$PAWXY_TEST_LOG/started-at"
	  else
	    printf '%s\n' 1000
	  fi
	}

	network_available_value() {
	  if [ -f "$PAWXY_TEST_LOG/network-down" ]; then
	    printf '%s\n' false
	  else
	    printf '%s\n' true
	  fi
	}

	network_generation_value() {
	  if [ -f "$PAWXY_TEST_LOG/network-generation" ]; then
	    cat "$PAWXY_TEST_LOG/network-generation"
	  else
	    printf '%s\n' 3
	  fi
	}

	bump_network_generation() {
	  generation=$(network_generation_value)
	  generation=$((generation + 1))
	  printf '%s\n' "$generation" > "$PAWXY_TEST_LOG/network-generation"
	}

log=$PAWXY_TEST_LOG/adb.log
state=$PAWXY_TEST_LOG/state.json
pending_running=$PAWXY_TEST_LOG/pending-running
pending_stopped=$PAWXY_TEST_LOG/pending-stopped
status_count=$PAWXY_TEST_LOG/status-count
token_mismatch=$PAWXY_TEST_LOG/token-mismatch
pid_file=$PAWXY_TEST_LOG/pid
start_count=$PAWXY_TEST_LOG/start-count
printf '%s\n' "$*" >> "$log"

if [ "${1:-}" = "-s" ]; then
  shift 2
fi

cmd=$1
shift || true
case "$cmd" in
  get-state)
    printf '%s\n' "device"
    ;;
  devices)
    printf '%s\n\n' "List of devices attached"
    printf '%s\t%s\n' "FAKEPIXEL" "device"
    ;;
  install|push|forward|reverse)
    exit 0
    ;;
	  shell)
	    line=$*
	    case "$line" in
	      *"-c true"*)
	        [ "${PAWXY_TEST_RISH_PROBE_FAIL:-0}" = "1" ] && exit 42
	        exit 0
	        ;;
	      *"getprop ro.product.brand"*)
	        printf '%s\n' "brand=google"
	        printf '%s\n' "model=Pixel"
        printf '%s\n' "sdk=35"
        printf '%s\n' "build=google/pixel/fake"
        ;;
      *"id -u"*)
        printf '%s\n' "${PAWXY_TEST_SHELL_UID:-2000}"
        ;;
	      *"pm check-permission android.permission.DUMP com.android.shell"*)
	        printf '%s\n' "${PAWXY_TEST_DUMP_PERMISSION:-granted}"
	        ;;
	      *"pm path dev.pawxy"*)
	        if [ "${PAWXY_TEST_PM_PATH_MISSING:-0}" != "1" ]; then
	          printf '%s\n' "package:/data/app/dev.pawxy/base.apk"
	        fi
	        ;;
	      *"pidof dev.pawxy"*)
	        if [ -f "$pid_file" ]; then
	          cat "$pid_file"
        else
          printf '%s\n' "4242"
        fi
        ;;
      *"cat /proc/"*"/stat"*)
        ticks_file=$PAWXY_TEST_LOG/proc-ticks
        ticks=100
        if [ -f "$ticks_file" ]; then
          ticks=$(cat "$ticks_file")
          ticks=$((ticks + 1))
        fi
        printf '%s\n' "$ticks" > "$ticks_file"
        printf '4242 (dev.pawxy) S 1 1 1 0 0 0 0 0 0 0 %s 0 0 0 20 0 8 0 0 0\n' "$ticks"
        ;;
      *"VmRSS"*"/proc/"*"/status"*)
        printf '%s\n' "${PAWXY_TEST_RSS_KIB:-32768} kB"
        ;;
      *"FDSize"*"/proc/"*"/status"*)
        printf '%s\n' "${PAWXY_TEST_FD_SIZE:-64}"
        ;;
      *"command -v rish"*)
        exit 0
        ;;
      *"test -x /data/local/tmp/rish"*)
        exit 0
        ;;
      *"bad-token"*)
        exit 0
        ;;
      *"am crash dev.pawxy"*)
        if [ "${PAWXY_TEST_PROCESS_PID_STUCK:-0}" != "1" ]; then
          printf '%s\n' "4243" > "$pid_file"
        fi
        write_state true false false 0 4 1024 > "$state"
        exit 0
        ;;
	      *"sed -n '1p' /data/local/tmp/pawxy/token"*|*"sed -n 1p /data/local/tmp/pawxy/token"*)
	        printf '%s\n' "good-token"
	        ;;
	      *"--es listen not-a-socket"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/invalid-config-preserved"
	          if [ "${PAWXY_TEST_DRIFT_LISTEN_ON_INVALID:-0}" = "1" ]; then
	            printf '%s\n' '{"running":true,"native_running":true,"service_started":true,"listen":"192.0.2.1:3218","native_listen":"192.0.2.1:3218","configured_listen":"127.0.0.1:3218","lan":false,"native_lan":false,"configured_lan":false,"auth_enabled":false,"native_auth_enabled":false,"configured_auth_enabled":false,"wake_lock_enabled":false,"active_connections":0,"total_connections":4,"bytes_out":1024,"started_at_unix_ms":1000,"native_started_at_unix_ms":1000}' > "$state"
	          fi
	        fi
	        ;;
	      *"--ei max_connections 0"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/zero-config-preserved"
	        fi
	        ;;
	      *"--ei max_connections 2147483647"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/oversized-config-preserved"
	        fi
	        ;;
	      *"--es listen [::]:3218"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/ipv6-wildcard-preserved"
	        fi
	        ;;
	      *"--ez auth_enabled true"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/auth-config-preserved"
	        fi
	        ;;
	      *"--es listen 127.0.0.1:32180"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/bind-conflict-preserved"
	        fi
	        ;;
	      *"--es listen 192.0.2.1:3218"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/nonlocal-listen-preserved"
	        fi
	        ;;
	      *"--es listen 127.0.0.2:3218"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/loopback-alias-preserved"
	        fi
	        ;;
	      *"--es listen 127.0.0.1:80"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/low-port-preserved"
	        fi
	        ;;
	      *"--es listen [::1]:3218"*)
	        if grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1 \
	          && grep -E '"service_started"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
	          : > "$PAWXY_TEST_LOG/ipv6-loopback-preserved"
	        fi
	        ;;
	      *"printf '%s\n' good-token > /data/local/tmp/pawxy/token"*)
	        rm -f "$token_mismatch"
	        ;;
      *"/data/local/tmp/pawxy/token"*)
        : > "$token_mismatch"
        ;;
      *"pawxyctl start"*)
        if [ "${PAWXY_TEST_START_FAILS_AFTER_LAUNCH:-0}" = "1" ]; then
          write_state true false false 0 4 1024 > "$state"
          exit 42
        fi
        if [ "${PAWXY_TEST_START_IGNORED:-0}" = "1" ]; then
          exit 0
        fi
        count=0
        [ -f "$start_count" ] && count=$(cat "$start_count")
        count=$((count + 1))
        printf '%s\n' "$count" > "$start_count"
        if [ "$count" -gt 1 ] \
          && grep -E '"running"[[:space:]]*:[[:space:]]*true' "$state" >/dev/null 2>&1; then
          : > "$PAWXY_TEST_LOG/duplicate-start-preserved"
        fi
        if [ "${PAWXY_TEST_DELAY_RUNNING:-0}" = "1" ]; then
          write_state false false false 0 0 0 > "$state"
          printf '%s\n' "false" > "$pending_running"
        else
          write_state true false false 0 4 1024 > "$state"
        fi
        ;;
      *"pawxyctl restart"*|*"pawxyctl share off"*)
        if [ "${PAWXY_TEST_START_IGNORED:-0}" = "1" ]; then
          exit 0
        fi
        if [ "${PAWXY_TEST_DELAY_RUNNING:-0}" = "1" ]; then
          write_state false false false 0 0 0 > "$state"
          printf '%s\n' "false" > "$pending_running"
        else
          write_state true false false 0 4 1024 > "$state"
        fi
        ;;
      *"pawxyctl reset-token"*)
        if [ "${PAWXY_TEST_RESET_TOKEN_FAIL:-0}" = "1" ]; then
          exit 42
        fi
        rm -f "$token_mismatch"
        printf '%s\n' "control token reset"
        ;;
      *"pawxyctl share on"*)
        if [ "${PAWXY_TEST_DELAY_RUNNING:-0}" = "1" ]; then
          write_state false true false 0 0 0 > "$state"
          printf '%s\n' "true" > "$pending_running"
        else
          write_state true true false 0 5 2048 > "$state"
        fi
        ;;
      *"pawxyctl wake on"*)
        if [ -f "$state" ] && grep -E '"running"[[:space:]]*:[[:space:]]*false' "$state" >/dev/null 2>&1; then
          write_state false false false 0 4 1024 > "$state"
        else
          write_state true false true 0 4 1024 > "$state"
          if [ "${PAWXY_TEST_WAKE_STOPS_NATIVE:-0}" = "1" ]; then
            sed 's/"native_running":true/"native_running":false/g; s/"native_running" : true/"native_running" : false/g' "$state" > "$state.tmp"
            mv "$state.tmp" "$state"
          fi
        fi
        ;;
      *"pawxyctl wake off"*)
        if [ -f "$state" ] && grep -E '"running"[[:space:]]*:[[:space:]]*false' "$state" >/dev/null 2>&1; then
          write_state false false false 0 4 1024 > "$state"
        else
          write_state true false false 0 4 1024 > "$state"
        fi
        ;;
      *"toybox nc 127.0.0.1 3218"*)
        auth_enabled=$(state_bool auth_enabled)
        if [ "$auth_enabled" = "true" ]; then
          case "$line" in
            *"CONNECT 127.0.0.1:32180 HTTP/1.1"*"Proxy-Authorization: Basic cGF3eHk6MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="*)
              : > "$PAWXY_TEST_LOG/device-origin-auth-connect"
              ;;
            *"Proxy-Authorization: Basic cGF3eHk6MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="*)
              : > "$PAWXY_TEST_LOG/device-origin-auth-http"
              ;;
            *"\\001\\005pawxy\\0400123456789abcdef0123456789abcdef"*)
              : > "$PAWXY_TEST_LOG/device-origin-auth-socks"
              ;;
            *)
              exit 22
              ;;
          esac
        fi
        wake_lock_enabled=$(state_bool wake_lock_enabled)
        active_connections=$(active_connections_value)
        write_state true "$auth_enabled" "$wake_lock_enabled" "$active_connections" 6 4096 > "$state"
        printf '%s\n' "HTTP/1.1 200 OK"
        printf '%s\n' ""
        printf '%s\n' "pawxy-smoke-ok"
        ;;
      *"pawxyctl stop"*)
        if [ "${PAWXY_TEST_DELAY_STOPPED:-0}" = "1" ]; then
          write_state true false false 0 4 1024 > "$state"
          : > "$pending_stopped"
        else
          write_state false false false 0 4 1024 > "$state"
        fi
        ;;
      *"pawxyctl doctor"*)
        printf '%s\n' "doctor ok"
        ;;
      *"logcat -d -s Pawxy PawxyNative"*)
        printf '%s\n' "logcat ok"
        ;;
      *"dumpsys deviceidle"*)
        case "$line" in
          *"force-idle"*) : > "$PAWXY_TEST_LOG/power-mode-active" ;;
          *"unforce"*) rm -f "$PAWXY_TEST_LOG/power-mode-active" ;;
        esac
        printf '%s\n' "deviceidle ok"
        ;;
      *"am set-inactive dev.pawxy true"*)
        : > "$PAWXY_TEST_LOG/power-mode-active"
        ;;
      *"am set-inactive dev.pawxy false"*)
        rm -f "$PAWXY_TEST_LOG/power-mode-active"
        ;;
      *"am set-standby-bucket dev.pawxy rare"*)
        : > "$PAWXY_TEST_LOG/power-mode-active"
        ;;
      *"am set-standby-bucket dev.pawxy active"*)
        rm -f "$PAWXY_TEST_LOG/power-mode-active"
        ;;
      *"cmd appops set dev.pawxy RUN_ANY_IN_BACKGROUND ignore"*)
        : > "$PAWXY_TEST_LOG/power-mode-active"
        ;;
      *"cmd appops set dev.pawxy RUN_ANY_IN_BACKGROUND allow"*)
        rm -f "$PAWXY_TEST_LOG/power-mode-active"
        ;;
      *"settings put global low_power 1"*)
        : > "$PAWXY_TEST_LOG/power-mode-active"
        ;;
	      *"settings put global low_power 0"*)
	        rm -f "$PAWXY_TEST_LOG/power-mode-active"
	        ;;
		      *"cmd wifi set-wifi-enabled disabled"*|*"svc wifi disable"*|*"cmd connectivity airplane-mode enable"*|*"settings put global airplane_mode_on 1"*)
		        : > "$PAWXY_TEST_LOG/network-down"
		        bump_network_generation
		        ;;
		      *"cmd wifi set-wifi-enabled enabled"*|*"svc wifi enable"*|*"cmd connectivity airplane-mode disable"*|*"settings put global airplane_mode_on 0"*)
		        rm -f "$PAWXY_TEST_LOG/network-down"
		        bump_network_generation
		        ;;
		      *"cmd appops set dev.pawxy POST_NOTIFICATION ignore"*|*"appops set dev.pawxy POST_NOTIFICATION ignore"*|*"pm revoke dev.pawxy android.permission.POST_NOTIFICATIONS"*)
		        : > "$PAWXY_TEST_LOG/notification-denied"
		        ;;
		      *"cmd appops set dev.pawxy POST_NOTIFICATION allow"*|*"appops set dev.pawxy POST_NOTIFICATION allow"*|*"pm grant dev.pawxy android.permission.POST_NOTIFICATIONS"*)
		        rm -f "$PAWXY_TEST_LOG/notification-denied"
		        ;;
		      *"dumpsys power"*)
		        printf '%s\n' "power ok"
		        ;;
      *"dumpsys activity services dev.pawxy/.ProxyService"*)
        printf '%s\n' "service ok"
        ;;
      *"cmd appops get dev.pawxy POST_NOTIFICATION"*)
        printf '%s\n' "post notification ok"
        ;;
      *"pawxyctl status --json"*)
        if [ -f "$token_mismatch" ]; then
          printf '%s\n' '{"ok":false,"error":"unauthorized"}'
          exit 0
        fi
        if [ -f "$pending_stopped" ]; then
          count=0
          [ -f "$status_count" ] && count=$(cat "$status_count")
          count=$((count + 1))
          printf '%s\n' "$count" > "$status_count"
          if [ "$count" -ge 2 ]; then
            write_state false false false 0 4 1024 > "$state"
            rm -f "$pending_stopped" "$status_count"
          fi
        fi
        if [ -f "$pending_running" ]; then
          count=0
          [ -f "$status_count" ] && count=$(cat "$status_count")
          count=$((count + 1))
          printf '%s\n' "$count" > "$status_count"
          if [ "$count" -ge 2 ]; then
            auth_enabled=$(cat "$pending_running")
            if [ "$auth_enabled" = "true" ]; then
              write_state true true false 0 5 2048 > "$state"
            else
              write_state true false false 0 4 1024 > "$state"
            fi
            rm -f "$pending_running" "$status_count"
          fi
        fi
	        if [ -f "$state" ]; then
	          if [ -f "$PAWXY_TEST_LOG/started-at" ]; then
	            auth_enabled=$(state_bool auth_enabled)
	            wake_lock_enabled=$(state_bool wake_lock_enabled)
	            active_connections=$(active_connections_value)
	            write_state true "$auth_enabled" "$wake_lock_enabled" "$active_connections" 4 1024 > "$state"
	          fi
	          cat "$state"
	        else
          printf '%s\n' '{"ok":false,"error":"unauthorized"}'
        fi
        ;;
      *"LAN_PASSWORD"*)
        printf '%s\n' "0123456789abcdef0123456789abcdef"
        ;;
      *"chmod 755"*)
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
ADB
chmod 755 "$tmp/bin/adb"

run_smoke() {
  mode=$1
  logdir=$2
  serial=${3:-}
  hold_seconds=${4:-0}
  hold_interval=${5:-1}
  run_optional=${6:-1}
  if ! PATH="$tmp/bin:$PATH" \
    ADB="$tmp/bin/adb" \
    ANDROID_SERIAL="$serial" \
    PAWXY_APK="$tmp/files/app-debug.apk" \
    PAWXY_CTL="$tmp/files/pawxyctl" \
    PAWXY_TEST_LOG="$logdir" \
    PAWXY_CONTROL_MODE="$mode" \
    PAWXY_RISH="${PAWXY_RISH:-rish}" \
    PAWXY_RISH_RUNNER="${PAWXY_RISH_RUNNER:-}" \
    PAWXY_RISH_APPLICATION_ID="${PAWXY_RISH_APPLICATION_ID:-}" \
    PAWXY_ARTIFACT_DIR="${PAWXY_ARTIFACT_DIR:-}" \
    PAWXY_HOLD_SECONDS="$hold_seconds" \
	    PAWXY_HOLD_INTERVAL_SECONDS="$hold_interval" \
	    PAWXY_BULK_KIB=1 \
	    PAWXY_RUN_PARALLEL_BURST="${PAWXY_RUN_PARALLEL_BURST:-0}" \
	    PAWXY_PARALLEL_BURST_CONNECTIONS="${PAWXY_PARALLEL_BURST_CONNECTIONS:-3}" \
		    PAWXY_RUN_SHARE="$run_optional" \
		    PAWXY_RUN_WAKE="$run_optional" \
		    PAWXY_RUN_WAKE_HOLD="${PAWXY_RUN_WAKE_HOLD:-0}" \
		    PAWXY_RUN_SCREEN_OFF="${PAWXY_RUN_SCREEN_OFF:-0}" \
		    PAWXY_KEEP_SCREEN_OFF_DURING_HOLD="${PAWXY_KEEP_SCREEN_OFF_DURING_HOLD:-0}" \
		    PAWXY_RUN_DUPLICATE_START="$run_optional" \
	    PAWXY_RUN_RESTART="$run_optional" \
    PAWXY_RUN_PROCESS_RESTART="$run_optional" \
    PAWXY_RUN_STOP_START="$run_optional" \
	    PAWXY_RUN_BAD_TOKEN="$run_optional" \
	    PAWXY_RUN_UNKNOWN_ACTION="$run_optional" \
	    PAWXY_RUN_UNSAFE_LAN="$run_optional" \
	    PAWXY_RUN_INVALID_CONFIG="$run_optional" \
	    PAWXY_RUN_DEVICE_ORIGIN="${PAWXY_RUN_DEVICE_ORIGIN:-1}" \
	    PAWXY_RUN_CONTROL_PREFLIGHT="${PAWXY_RUN_CONTROL_PREFLIGHT:-1}" \
		    PAWXY_RUN_NOTIFICATION_DENIAL="${PAWXY_RUN_NOTIFICATION_DENIAL:-0}" \
		    PAWXY_RUN_DOZE="${PAWXY_RUN_DOZE:-0}" \
	    PAWXY_RUN_APP_STANDBY="${PAWXY_RUN_APP_STANDBY:-0}" \
	    PAWXY_RUN_STANDBY_BUCKET="${PAWXY_RUN_STANDBY_BUCKET:-0}" \
	    PAWXY_RUN_BACKGROUND_RESTRICTION="${PAWXY_RUN_BACKGROUND_RESTRICTION:-0}" \
	    PAWXY_RUN_BATTERY_SAVER="${PAWXY_RUN_BATTERY_SAVER:-0}" \
	    PAWXY_RUN_NETWORK_TOGGLE="${PAWXY_RUN_NETWORK_TOGGLE:-0}" \
	    PAWXY_NETWORK_TOGGLE_MODE="${PAWXY_NETWORK_TOGGLE_MODE:-wifi}" \
	    PAWXY_NETWORK_TOGGLE_SLEEP_SECONDS="${PAWXY_NETWORK_TOGGLE_SLEEP_SECONDS:-0}" \
	    PAWXY_TEST_DELAY_RUNNING="${PAWXY_TEST_DELAY_RUNNING:-0}" \
    PAWXY_TEST_DELAY_STOPPED="${PAWXY_TEST_DELAY_STOPPED:-0}" \
	    PAWXY_TEST_START_IGNORED="${PAWXY_TEST_START_IGNORED:-0}" \
	    PAWXY_TEST_START_FAILS_AFTER_LAUNCH="${PAWXY_TEST_START_FAILS_AFTER_LAUNCH:-0}" \
				    PAWXY_TEST_FAIL_TARGET_SERVER="${PAWXY_TEST_FAIL_TARGET_SERVER:-0}" \
		    PAWXY_TEST_FAIL_CURL_DURING_NETWORK="${PAWXY_TEST_FAIL_CURL_DURING_NETWORK:-0}" \
		    PAWXY_TEST_FAIL_CURL_DURING_NOTIFICATION="${PAWXY_TEST_FAIL_CURL_DURING_NOTIFICATION:-0}" \
			    PAWXY_TEST_PM_PATH_MISSING="${PAWXY_TEST_PM_PATH_MISSING:-0}" \
	    PAWXY_TEST_RISH_PROBE_FAIL="${PAWXY_TEST_RISH_PROBE_FAIL:-0}" \
	    PAWXY_TEST_WAKE_STOPS_NATIVE="${PAWXY_TEST_WAKE_STOPS_NATIVE:-0}" \
	    PAWXY_TEST_RESTART_AFTER_SLEEP_COUNT="${PAWXY_TEST_RESTART_AFTER_SLEEP_COUNT:-}" \
	      sh "$SCRIPT" >"$logdir/script.out" 2>"$logdir/script.err"; then
    sed 's/^/stdout: /' "$logdir/script.out" >&2
    sed 's/^/stderr: /' "$logdir/script.err" >&2
    return 1
  fi
}

run_smoke adb "$tmp/log-adb"
grep -F -- "verifying adb control identity and status channel" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must preflight the shell identity and status channel before starting Pawxy"
grep -F -- "status channel reachable before control token provisioning" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must accept fresh-install unauthorized status before the first START provisions the token"
grep -F -- "id -u" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must inspect the control shell uid"
grep -F -- "20 $tmp/bin/adb shell id -u" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must bound control channel probes with timeout"
grep -F -- "30 $tmp/bin/adb shell pm grant dev.pawxy android.permission.POST_NOTIFICATIONS" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must bound ordinary adb shell operations with timeout"
grep -F -- "120 $tmp/bin/adb install -r $tmp/files/app-debug.apk" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must bound APK install with timeout"
grep -F -- "30 $tmp/bin/adb shell pm path dev.pawxy" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must verify package visibility after APK install under timeout"
grep -F -- "120 $tmp/bin/adb push $tmp/files/pawxyctl /data/local/tmp/pawxyctl" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must bound control helper push with timeout"
grep -F -- "120 $tmp/bin/adb forward tcp:3218 tcp:3218" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must bound adb forward setup with timeout"
grep -F -- "120 $tmp/bin/adb reverse tcp:32180 tcp:32180" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must bound adb reverse setup with timeout"
grep -F -- "pm check-permission android.permission.DUMP com.android.shell" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify the shell package has DUMP permission"
grep -F -- "forward tcp:3218 tcp:3218" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must forward host proxy traffic"
grep -F -- "reverse tcp:32180 tcp:32180" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must reverse target traffic"
grep -F -- "bad-token" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must attempt an unauthorized control action"
grep -F -- "pawxyctl reset-token" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify token mismatch recovery"
grep -F -- "testing control token repair" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must log token repair coverage"
grep -F -- "verifying duplicate start keeps the running proxy in place" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must log duplicate start persistence coverage"
grep -F -- "pawxyctl start" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must start Pawxy through pawxyctl"
[ -f "$tmp/log-adb/duplicate-start-preserved" ] \
  || fail "adb smoke must verify duplicate starts do not restart the running proxy"
grep -F -- "started_at_unix_ms" "$tmp/log-adb/state.json" >/dev/null \
  || fail "adb smoke mock status must expose native started_at_unix_ms for duplicate start checks"
grep -F -- '"listen":"127.0.0.1:3218"' "$tmp/log-adb/state.json" >/dev/null \
  || fail "adb smoke mock status must expose the stable native listen endpoint"
grep -F -- "dev.pawxy.action.UNKNOWN" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify unknown control actions do not stop Pawxy"
grep -F -- "--es listen 0.0.0.0:3218" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify unsafe LAN listen is rejected without stopping Pawxy"
grep -F -- "--es listen not-a-socket --ei max_connections -1" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify malformed direct start configs cannot break Pawxy"
grep -F -- "--ei max_connections 0 --ei max_per_source_ip 0 --el handshake_timeout_ms 0 --el connect_timeout_ms 0 --el idle_timeout_ms 0" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify zero limit and timeout direct start configs cannot break Pawxy"
grep -F -- "--ei max_connections 2147483647 --ei max_per_source_ip 2147483647 --el handshake_timeout_ms 9223372036854775807 --el connect_timeout_ms 9223372036854775807 --el idle_timeout_ms 9223372036854775807" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify oversized direct start configs cannot break Pawxy"
grep -F -- "--ez auth_enabled true" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify auth-required direct start configs without credentials cannot break Pawxy"
grep -F -- "--es listen 127.0.0.1:32180" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify bind-conflicting direct start configs cannot break Pawxy"
grep -F -- "--es listen 192.0.2.1:3218" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify nonlocal listen direct start configs cannot break Pawxy"
grep -F -- "--es listen 127.0.0.2:3218" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify loopback-alias direct start configs cannot break Pawxy"
grep -F -- "--es listen 127.0.0.1:80" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify low-port direct start configs cannot break Pawxy"
grep -F -- "--es listen [::1]:3218" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify IPv6 loopback direct start configs cannot break Pawxy"
grep -F -- "--es listen [::]:3218 --ez auth_enabled true" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must verify IPv6 wildcard direct start configs cannot break Pawxy"
[ -f "$tmp/log-adb/invalid-config-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after malformed direct start configs"
[ -f "$tmp/log-adb/zero-config-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after zero limit and timeout direct start configs"
[ -f "$tmp/log-adb/oversized-config-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after oversized direct start configs"
[ -f "$tmp/log-adb/auth-config-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after auth-required direct start configs without credentials"
[ -f "$tmp/log-adb/bind-conflict-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after bind-conflicting direct start configs"
[ -f "$tmp/log-adb/nonlocal-listen-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after nonlocal listen direct start configs"
[ -f "$tmp/log-adb/loopback-alias-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after loopback-alias direct start configs"
[ -f "$tmp/log-adb/low-port-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after low-port direct start configs"
[ -f "$tmp/log-adb/ipv6-loopback-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after IPv6 loopback direct start configs"
[ -f "$tmp/log-adb/ipv6-wildcard-preserved" ] \
  || fail "adb smoke must verify Android service_started remains true after IPv6 wildcard direct start configs"
grep -F -- "pawxyctl restart" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test restart"
grep -F -- "am crash dev.pawxy" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test sticky restart after app process crash"
grep -F -- "waiting for proxy to recover after process restart" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must wait for proxy recovery after process restart"
grep -F -- "process restart: pid 4242 -> 4243" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must prove the process pid changed after crash"
grep -F -- "stopping and immediately starting without listener release race" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must test immediate stop/start"
grep -F -- "pawxyctl wake on" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test wake on"
grep -F -- "verifying wake lock cannot be enabled while proxy is stopped" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must verify wake on cannot create an idle foreground service after stop"
grep -F -- "pawxyctl share on" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test share on"
grep -F -- "--socks5-hostname 127.0.0.1:3218" "$tmp/log-adb/curl.log" >/dev/null \
  || fail "adb smoke must test SOCKS5 curl traffic"
grep -F -- "--proxytunnel" "$tmp/log-adb/curl.log" >/dev/null \
  || fail "adb smoke must test HTTP CONNECT curl traffic"
grep -F -- "--connect-timeout 5" "$tmp/log-adb/curl.log" >/dev/null \
  || fail "adb smoke proxy curl must use a bounded connection timeout"
grep -F -- "--max-time 30" "$tmp/log-adb/curl.log" >/dev/null \
  || fail "adb smoke proxy curl must use a bounded total transfer timeout"
grep -F -- "toybox nc 127.0.0.1 3218" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test device-origin proxy traffic without adb forward"
grep -F -- "15 $tmp/bin/adb shell" "$tmp/log-adb/timeout.log" >/dev/null \
  || fail "adb smoke must bound device-origin adb shell proxy probes with timeout"
grep -F -- "GET /pawxy-smoke.txt HTTP/1.1" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test device-origin SOCKS5 traffic"
grep -F -- "CONNECT 127.0.0.1:32180 HTTP/1.1" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test device-origin HTTP CONNECT traffic"
grep -F -- "http://pawxy:0123456789abcdef0123456789abcdef@127.0.0.1:3218" "$tmp/log-adb/curl.log" >/dev/null \
  || fail "adb smoke must test authenticated LAN proxy traffic"
grep -F -- "--proxy-user pawxy:0123456789abcdef0123456789abcdef" "$tmp/log-adb/curl.log" >/dev/null \
  || fail "adb smoke must test authenticated LAN SOCKS5 proxy traffic"
grep -F -- "Proxy-Authorization: Basic cGF3eHk6MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test authenticated device-origin LAN HTTP proxy traffic"
grep -F -- '\001\005pawxy\0400123456789abcdef0123456789abcdef' "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must test authenticated device-origin LAN SOCKS5 proxy traffic"
[ -f "$tmp/log-adb/device-origin-auth-http" ] \
  || fail "adb smoke mock must accept only authenticated device-origin LAN HTTP proxy traffic after share on"
[ -f "$tmp/log-adb/device-origin-auth-connect" ] \
  || fail "adb smoke mock must accept only authenticated device-origin LAN HTTP CONNECT proxy traffic after share on"
[ -f "$tmp/log-adb/device-origin-auth-socks" ] \
  || fail "adb smoke mock must accept only authenticated device-origin LAN SOCKS5 proxy traffic after share on"
grep -F -- "unauthenticated_lan_proxy_rejected" "$SCRIPT" >/dev/null \
  || fail "adb smoke must verify unauthenticated LAN proxy traffic is rejected"
grep -F -- "unauthenticated LAN HTTP proxy traffic unexpectedly succeeded" "$SCRIPT" >/dev/null \
  || fail "adb smoke must fail if unauthenticated LAN HTTP proxy traffic succeeds"
grep -F -- "unauthenticated LAN SOCKS5 proxy traffic unexpectedly succeeded" "$SCRIPT" >/dev/null \
  || fail "adb smoke must fail if unauthenticated LAN SOCKS5 proxy traffic succeeds"
grep -F -- "unauthenticated device-origin LAN HTTP proxy traffic unexpectedly succeeded" "$SCRIPT" >/dev/null \
  || fail "adb smoke must fail if unauthenticated device-origin LAN HTTP proxy traffic succeeds"
grep -F -- "unauthenticated device-origin LAN HTTP CONNECT proxy traffic unexpectedly succeeded" "$SCRIPT" >/dev/null \
  || fail "adb smoke must fail if unauthenticated device-origin LAN HTTP CONNECT proxy traffic succeeds"
grep -F -- "unauthenticated device-origin LAN SOCKS5 proxy traffic unexpectedly succeeded" "$SCRIPT" >/dev/null \
  || fail "adb smoke must fail if unauthenticated device-origin LAN SOCKS5 proxy traffic succeeds"
grep -F -- "total_connections" "$SCRIPT" >/dev/null \
  || fail "adb smoke must assert native connection metrics moved"
grep -F -- "bytes_in" "$SCRIPT" >/dev/null \
  || fail "adb smoke must assert native inbound byte metrics moved"
grep -F -- "bytes_out" "$SCRIPT" >/dev/null \
  || fail "adb smoke must assert native byte metrics moved"
grep -F -- "network_available" "$SCRIPT" >/dev/null \
  || fail "adb smoke must assert Android network status fields are present"
grep -F -- "wait_for_idle_connections" "$SCRIPT" >/dev/null \
  || fail "adb smoke must wait for active proxy connections to drain"
grep -F -- "sampling idle efficiency" "$tmp/log-adb/script.out" >/dev/null \
  || fail "adb smoke must sample idle efficiency after traffic drains"
grep -F -- "pidof dev.pawxy" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must locate the Pawxy process for idle efficiency sampling"
grep -F -- "/proc/4242/stat" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must read process CPU ticks for idle efficiency sampling"
grep -F -- "/proc/4242/status" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must read process RSS for idle efficiency sampling"
grep -F -- "FDSize" "$tmp/log-adb/adb.log" >/dev/null \
  || fail "adb smoke must read process FDSize for idle resource sampling"

PAWXY_TEST_SPACED_JSON=1 run_smoke adb "$tmp/log-spaced-json"
grep -F -- "pawxy device smoke ok" "$tmp/log-spaced-json/script.out" >/dev/null \
  || fail "device smoke must parse JSON status fields with whitespace around separators"

PAWXY_TEST_DELAY_RUNNING=1 PAWXY_RUN_SHARE=0 PAWXY_RUN_WAKE=0 PAWXY_RUN_RESTART=0 PAWXY_RUN_PROCESS_RESTART=0 PAWXY_RUN_STOP_START=0 PAWXY_RUN_BAD_TOKEN=0 PAWXY_RUN_UNKNOWN_ACTION=0 PAWXY_RUN_UNSAFE_LAN=0 run_smoke adb "$tmp/log-delayed-start" "" 0 1 0
grep -F -- "pawxy device smoke ok" "$tmp/log-delayed-start/script.out" >/dev/null \
  || fail "device smoke must wait for delayed startup status before traffic probes"
status_checks=$(grep -c -- "pawxyctl status --json" "$tmp/log-delayed-start/adb.log")
[ "$status_checks" -ge 2 ] \
  || fail "device smoke must retry status checks while Pawxy is still starting"

PAWXY_TEST_DELAY_STOPPED=1 run_smoke adb "$tmp/log-delayed-stop" "" 0 1 1
grep -F -- "pawxy device smoke ok" "$tmp/log-delayed-stop/script.out" >/dev/null \
  || fail "device smoke must wait for delayed stopped status before continuing"
delayed_stop_status_checks=$(grep -c -- "pawxyctl status --json" "$tmp/log-delayed-stop/adb.log")
[ "$delayed_stop_status_checks" -ge 2 ] \
  || fail "device smoke must retry status checks while Pawxy is still stopping"

if PAWXY_TEST_START_IGNORED=1 run_smoke adb "$tmp/log-start-ignored" "" 0 1 0; then
  fail "device smoke must fail when start does not report running=true"
fi
grep -F -- "initial start did not report running=true" "$tmp/log-start-ignored/script.err" >/dev/null \
  || fail "start ignored smoke must explain the missing running=true status"

if PAWXY_TEST_START_FAILS_AFTER_LAUNCH=1 run_smoke adb "$tmp/log-start-fails-after-launch" "" 0 1 0; then
  fail "device smoke must fail when the control start command fails after launching Pawxy"
fi
grep -F -- "failed to start local proxy through adb control" "$tmp/log-start-fails-after-launch/script.err" >/dev/null \
  || fail "start command failure smoke must explain that the selected control start failed"
grep -F -- "pawxyctl stop" "$tmp/log-start-fails-after-launch/adb.log" >/dev/null \
  || fail "start command failure smoke must stop Pawxy when start failed after launch"

if PAWXY_TEST_PM_PATH_MISSING=1 run_smoke adb "$tmp/log-package-missing" "" 0 1 0; then
  fail "device smoke must fail when the installed package is not visible"
fi
grep -F -- "Pawxy package dev.pawxy was not visible after install" "$tmp/log-package-missing/script.err" >/dev/null \
  || fail "package visibility smoke must explain pm path did not find dev.pawxy"
grep -F -- "status error=unauthorized" "$tmp/log-start-ignored/script.err" >/dev/null \
  || fail "start ignored smoke must summarize status error fields in wait failures"

if PAWXY_TEST_FAIL_TARGET_SERVER=1 run_smoke adb "$tmp/log-target-server-failure" "" 0 1 0; then
  fail "device smoke must fail before proxy start when the host target server is unreachable"
fi
grep -F -- "host target server did not become ready" "$tmp/log-target-server-failure/script.err" >/dev/null \
  || fail "device smoke must explain target server readiness failures"

run_smoke rish "$tmp/log-rish"
grep -F -- "verifying rish control identity and status channel" "$tmp/log-rish/script.out" >/dev/null \
  || fail "rish smoke must preflight the rish identity and status channel before starting Pawxy"
grep -F -- "status channel reachable before control token provisioning" "$tmp/log-rish/script.out" >/dev/null \
  || fail "rish smoke must accept fresh-install unauthorized status before the first START provisions the token"
grep -F -- "rish -c 'id -u'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must inspect the remote rish shell uid"
grep -F -- "rish -c 'pm check-permission android.permission.DUMP com.android.shell'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must verify DUMP permission through the selected rish channel"
grep -F -- "20 $tmp/bin/adb shell rish -c 'id -u'" "$tmp/log-rish/timeout.log" >/dev/null \
  || fail "rish smoke must bound the rish control channel with timeout"
grep -F -- "15 $tmp/bin/adb shell rish -c" "$tmp/log-rish/timeout.log" >/dev/null \
  || fail "rish smoke must bound device-origin proxy probes through the selected rish channel with the device-origin timeout"
grep -F -- "rish -c" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must route control commands through rish"
grep -F -- "rish -c 'printf" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must route device-origin proxy probes through rish"
grep -F -- "CONNECT 127.0.0.1:32180 HTTP/1.1" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must route device-origin HTTP CONNECT probes through rish"
grep -F -- "PAWXY_HOME=/data/local/tmp/pawxy" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must keep the stable token home"
grep -F -- "verifying duplicate start keeps the running proxy in place" "$tmp/log-rish/script.out" >/dev/null \
  || fail "rish smoke must log duplicate start persistence coverage"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.STOP --es token bad-token'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send unauthorized control attempts through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.UNKNOWN'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send unknown action attempts through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen 0.0.0.0:3218 --ez lan true --ez auth_enabled false'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send unsafe LAN attempts through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen not-a-socket --ei max_connections -1'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send malformed direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --ei max_connections 0 --ei max_per_source_ip 0 --el handshake_timeout_ms 0 --el connect_timeout_ms 0 --el idle_timeout_ms 0'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send zero limit and timeout direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --ei max_connections 2147483647 --ei max_per_source_ip 2147483647 --el handshake_timeout_ms 9223372036854775807 --el connect_timeout_ms 9223372036854775807 --el idle_timeout_ms 9223372036854775807'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send oversized direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --ez auth_enabled true'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send auth-required direct start configs without credentials through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen 127.0.0.1:32180'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send bind-conflicting direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen 192.0.2.1:3218'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send nonlocal listen direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen 127.0.0.2:3218'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send loopback-alias direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen 127.0.0.1:80'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send low-port direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen [::1]:3218'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send IPv6 loopback direct start configs through the selected rish channel"
grep -F -- "rish -c 'am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token good-token --es listen [::]:3218 --ez auth_enabled true --es username pawxy --es password ipv6-test'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must send IPv6 wildcard direct start configs through the selected rish channel"
grep -F -- "rish -c 'am crash dev.pawxy'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must inject process crashes through the selected rish channel"
grep -F -- "rish -c 'grep ^LAN_PASSWORD= /data/local/tmp/pawxy/config.env | sed -n 1p | cut -d= -f2-'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must read LAN share credentials through the selected rish channel"
grep -F -- "rish -c 'pidof dev.pawxy 2>/dev/null'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must read Pawxy process identity through the selected rish channel"
grep -F -- "rish -c 'cat /proc/4242/stat'" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must read idle CPU ticks through the selected rish channel"
grep -F -- "rish -c 'sed -n" "$tmp/log-rish/adb.log" >/dev/null \
  && grep -F -- "VmRSS" "$tmp/log-rish/adb.log" >/dev/null \
  && grep -F -- "/proc/4242/status" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must read idle RSS through the selected rish channel"
grep -F -- "rish -c 'sed -n" "$tmp/log-rish/adb.log" >/dev/null \
  && grep -F -- "FDSize" "$tmp/log-rish/adb.log" >/dev/null \
  && grep -F -- "/proc/4242/status" "$tmp/log-rish/adb.log" >/dev/null \
  || fail "rish smoke must read idle FDSize through the selected rish channel"

PAWXY_RISH=/data/local/tmp/rish run_smoke rish "$tmp/log-custom-rish"
grep -F -- "/data/local/tmp/rish -c" "$tmp/log-custom-rish/adb.log" >/dev/null \
  || fail "rish smoke must support a configurable rish command path"

PAWXY_RISH="/sdcard/Android/data/moe.shizuku.privileged.api/files/rish" PAWXY_RISH_RUNNER=sh run_smoke rish "$tmp/log-runner-rish"
grep -F -- "sh /sdcard/Android/data/moe.shizuku.privileged.api/files/rish -c" "$tmp/log-runner-rish/adb.log" >/dev/null \
  || fail "rish smoke must support a shell runner for storage-exported rish scripts"

PAWXY_RISH="/sdcard/Android/data/moe.shizuku.privileged.api/files/rish" PAWXY_RISH_RUNNER=sh PAWXY_RISH_APPLICATION_ID=com.termux run_smoke rish "$tmp/log-rish-application-id"
grep -F -- "RISH_APPLICATION_ID=com.termux sh /sdcard/Android/data/moe.shizuku.privileged.api/files/rish -c" "$tmp/log-rish-application-id/adb.log" >/dev/null \
  || fail "rish smoke must support configuring RISH_APPLICATION_ID for terminal-exported Shizuku rish scripts"

PAWXY_RISH="/data/local/tmp/rish helper" run_smoke rish "$tmp/log-spaced-rish"
grep -F -- "'/data/local/tmp/rish helper' -c" "$tmp/log-spaced-rish/adb.log" >/dev/null \
  || fail "rish smoke must shell-quote a configurable rish command path that contains spaces"

PAWXY_RISH="/data/local/tmp/ri'sh" run_smoke rish "$tmp/log-quoted-rish"
grep -F -- "'/data/local/tmp/ri'\''sh' -c" "$tmp/log-quoted-rish/adb.log" >/dev/null \
  || fail "rish smoke must shell-quote a configurable rish command path that contains single quotes"

if PAWXY_TEST_RISH_PROBE_FAIL=1 run_smoke rish "$tmp/log-rish-probe-failure"; then
  fail "rish smoke must fail before install when the selected rish command cannot run"
fi
grep -F -- "rish command failed" "$tmp/log-rish-probe-failure/script.err" >/dev/null \
  || fail "rish probe failure must explain that the selected rish command failed"
grep -F -- "set PAWXY_RISH" "$tmp/log-rish-probe-failure/script.err" >/dev/null \
  || fail "rish probe failure must tell users to set PAWXY_RISH"
grep -F -- "PAWXY_RISH_RUNNER=sh" "$tmp/log-rish-probe-failure/script.err" >/dev/null \
  || fail "rish probe failure must tell users how to run storage-exported rish scripts"
grep -F -- "PAWXY_RISH_APPLICATION_ID" "$tmp/log-rish-probe-failure/script.err" >/dev/null \
  || fail "rish probe failure must tell users how to select a Shizuku-authorized terminal package"
if grep -F -- "pawxyctl doctor" "$tmp/log-rish-probe-failure/adb.log" >/dev/null; then
  fail "rish probe failure must not run pawxyctl doctor through an unverified rish channel"
fi
if grep -F -- "pawxyctl stop" "$tmp/log-rish-probe-failure/adb.log" >/dev/null; then
  fail "rish probe failure must not run pawxyctl stop through an unverified rish channel"
fi

run_smoke adb "$tmp/log-serial" FAKEPIXEL
grep -F -- "-s FAKEPIXEL get-state" "$tmp/log-serial/adb.log" >/dev/null \
  || fail "serial smoke must validate the selected adb device"

run_smoke adb "$tmp/log-hold" "" 2 1 0
curl_count=$(grep -c -- "127.0.0.1:3218" "$tmp/log-hold/curl.log")
[ "$curl_count" -ge 4 ] \
  || fail "hold smoke must probe HTTP, CONNECT, and SOCKS5 traffic during the hold window"
device_origin_count=$(grep -c -- "toybox nc 127.0.0.1 3218" "$tmp/log-hold/adb.log")
[ "$device_origin_count" -ge 2 ] \
  || fail "hold smoke must probe device-origin proxy traffic during the hold window"
device_origin_socks_count=$(grep -c -- "GET /pawxy-smoke.txt HTTP/1.1" "$tmp/log-hold/adb.log" || true)
[ "$device_origin_socks_count" -ge 2 ] \
  || fail "hold smoke must probe device-origin SOCKS5 traffic during the hold window"
grep -F -- "pawxy-bulk.bin" "$tmp/log-hold/curl.log" >/dev/null \
  || fail "hold smoke must include a bulk transfer probe"
grep -F -- "bulk throughput" "$SCRIPT" >/dev/null \
  || fail "device smoke must report bulk throughput"
grep -F -- "hold sample: elapsed=" "$tmp/log-hold/script.out" >/dev/null \
  || fail "hold smoke must log per-interval status samples for long Pixel/Shizuku runs"
grep -F -- "hold sample: elapsed=" "$tmp/log-hold/script.out" \
  | grep -F -- "cpu_ticks=" \
  | grep -F -- "rss_kib=" \
  | grep -F -- "fd_size=" >/dev/null \
  || fail "hold smoke must log per-interval process resource samples for long Pixel/Shizuku runs"
grep -F -- "require_json_number_greater_than" "$SCRIPT" >/dev/null \
  || fail "device smoke must require native metrics to grow during the hold window"
grep -F -- "PAWXY_MIN_BULK_KIB_PER_SECOND" "$SCRIPT" >/dev/null \
  || fail "device smoke must support a configurable minimum bulk throughput"
grep -F -- "speed_download" "$SCRIPT" >/dev/null \
  || fail "device smoke must use curl transfer speed for bulk throughput"
grep -F -- "CLEANUP_DONE" "$SCRIPT" >/dev/null \
  || fail "device smoke cleanup must be idempotent for signal-triggered failures"

PAWXY_ARTIFACT_DIR="$tmp/log-artifact/artifacts" run_smoke adb "$tmp/log-artifact" "" 2 1 0
grep -F -- "artifact dir: $tmp/log-artifact/artifacts" "$tmp/log-artifact/script.out" >/dev/null \
  || fail "artifact smoke must log the selected artifact directory"
grep -F -- "control_mode=adb" "$tmp/log-artifact/artifacts/run-info.txt" >/dev/null \
  || fail "artifact smoke must persist run metadata"
awk -F '\t' 'NR == 1 && $1 == "elapsed_s" && $2 == "pid" && $3 == "cpu_ticks" && $4 == "rss_kib" && $5 == "fd_size" { found = 1 } END { exit found ? 0 : 1 }' "$tmp/log-artifact/artifacts/hold-samples.tsv" \
  || fail "artifact smoke must write hold sample headers"
grep -F -- "hold elapsed=" "$tmp/log-artifact/artifacts/status-samples.tsv" >/dev/null \
  || fail "artifact smoke must persist hold status samples"
grep -F -- "final" "$tmp/log-artifact/artifacts/status-samples.tsv" >/dev/null \
  || fail "artifact smoke must persist final status samples"
grep -F -- "exit_code=0" "$tmp/log-artifact/artifacts/summary.txt" >/dev/null \
  || fail "artifact smoke must persist a successful exit summary"
grep -F -- '"running":false' "$tmp/log-artifact/artifacts/final-status.json" >/dev/null \
  || fail "artifact smoke must persist final Pawxy status JSON"
unset PAWXY_ARTIFACT_DIR

PAWXY_RUN_PARALLEL_BURST=1 PAWXY_PARALLEL_BURST_CONNECTIONS=3 run_smoke adb "$tmp/log-parallel-burst" "" 0 1 0
grep -F -- "probing parallel proxy burst with 3 connections" "$tmp/log-parallel-burst/script.out" >/dev/null \
  || fail "parallel burst smoke must log concurrent proxy coverage"
grep -F -- "parallel proxy burst: 3 connections completed" "$tmp/log-parallel-burst/script.out" >/dev/null \
  || fail "parallel burst smoke must complete every concurrent proxy request"
parallel_proxy_count=$(grep -c -- "127.0.0.1:3218" "$tmp/log-parallel-burst/curl.log")
[ "$parallel_proxy_count" -ge 3 ] \
  || fail "parallel burst smoke must issue multiple proxied curl requests"

PAWXY_RUN_PARALLEL_BURST=1 PAWXY_PARALLEL_BURST_CONNECTIONS=3 run_smoke rish "$tmp/log-rish-parallel-burst" "" 0 1 0
grep -F -- "parallel proxy burst: 3 connections completed" "$tmp/log-rish-parallel-burst/script.out" >/dev/null \
  || fail "rish parallel burst smoke must complete under Shizuku/rish control"
grep -F -- "rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl status --json'" "$tmp/log-rish-parallel-burst/adb.log" >/dev/null \
  || fail "rish parallel burst smoke must observe status through the selected rish channel"

if PAWXY_RUN_PARALLEL_BURST=1 PAWXY_PARALLEL_BURST_CONNECTIONS=0 run_smoke adb "$tmp/log-invalid-parallel-burst" "" 0 1 0; then
  fail "device smoke must reject invalid parallel burst connection counts before testing"
fi
grep -F -- "PAWXY_PARALLEL_BURST_CONNECTIONS must be greater than zero" "$tmp/log-invalid-parallel-burst/script.err" >/dev/null \
  || fail "invalid parallel burst smoke must explain PAWXY_PARALLEL_BURST_CONNECTIONS"

PAWXY_RUN_NOTIFICATION_DENIAL=1 run_smoke adb "$tmp/log-notification-denial" "" 0 1 0
grep -F -- "denying notification permission and verifying foreground proxy restart" "$tmp/log-notification-denial/script.out" >/dev/null \
  || fail "notification-denial smoke must log foreground-service notification permission coverage"
grep -F -- "cmd appops set dev.pawxy POST_NOTIFICATION ignore" "$tmp/log-notification-denial/adb.log" >/dev/null \
  || fail "notification-denial smoke must deny notification permission through the selected control channel"
grep -F -- "pawxyctl restart" "$tmp/log-notification-denial/adb.log" >/dev/null \
  || fail "notification-denial smoke must restart the foreground service while notification permission is denied"
grep -F -- "cmd appops set dev.pawxy POST_NOTIFICATION allow" "$tmp/log-notification-denial/adb.log" >/dev/null \
  || fail "notification-denial smoke must restore notification app-op after verification"
grep -F -- "notification-denied traffic" "$SCRIPT" >/dev/null \
  || fail "device smoke must verify proxy traffic while notification permission is denied"

PAWXY_RUN_NOTIFICATION_DENIAL=1 run_smoke rish "$tmp/log-rish-notification-denial" "" 0 1 0
grep -F -- "rish -c 'cmd appops set dev.pawxy POST_NOTIFICATION ignore'" "$tmp/log-rish-notification-denial/adb.log" >/dev/null \
  || fail "rish notification-denial smoke must deny notification permission through the selected rish channel"
grep -F -- "rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl restart'" "$tmp/log-rish-notification-denial/adb.log" >/dev/null \
  || fail "rish notification-denial smoke must restart through the selected rish channel"
grep -F -- "rish -c 'cmd appops set dev.pawxy POST_NOTIFICATION allow'" "$tmp/log-rish-notification-denial/adb.log" >/dev/null \
  || fail "rish notification-denial smoke must restore notification app-op through the selected rish channel"

if PAWXY_RUN_NOTIFICATION_DENIAL=1 PAWXY_TEST_FAIL_CURL_DURING_NOTIFICATION=1 run_smoke adb "$tmp/log-notification-denial-failure" "" 0 1 0; then
  fail "notification-denial smoke must fail when proxy traffic fails while notification permission is denied"
fi
grep -F -- "cmd appops set dev.pawxy POST_NOTIFICATION allow" "$tmp/log-notification-denial-failure/adb.log" >/dev/null \
  || fail "notification-denial failure smoke must restore notification app-op during cleanup"
grant_count=$(grep -c -- "pm grant dev.pawxy android.permission.POST_NOTIFICATIONS" "$tmp/log-notification-denial-failure/adb.log")
[ "$grant_count" -ge 2 ] \
  || fail "notification-denial failure smoke must restore notification runtime permission during cleanup"
grep -F -- "pawxyctl stop" "$tmp/log-notification-denial-failure/adb.log" >/dev/null \
  || fail "notification-denial failure smoke must stop Pawxy after restoring notification permission"
notification_restore_line=$(grep -n -- "cmd appops set dev.pawxy POST_NOTIFICATION allow" "$tmp/log-notification-denial-failure/adb.log" | sed -n '1s/:.*//p')
notification_stop_line=$(grep -n -- "pawxyctl stop" "$tmp/log-notification-denial-failure/adb.log" | sed -n '1s/:.*//p')
[ "$notification_restore_line" -lt "$notification_stop_line" ] \
  || fail "notification-denial failure smoke must restore notification permission before stopping Pawxy"

if PAWXY_TEST_RESTART_AFTER_SLEEP_COUNT=2 run_smoke adb "$tmp/log-process-restart-during-hold" "" 2 1 0; then
  fail "hold smoke must fail when the Pawxy process restarts during the persistence hold"
fi
grep -F -- "Pawxy process restarted during persistence hold" "$tmp/log-process-restart-during-hold/script.err" >/dev/null \
  || fail "hold restart smoke must explain the Pawxy process restart during the persistence hold"

PAWXY_RUN_WAKE_HOLD=1 run_smoke adb "$tmp/log-wake-hold" "" 2 1 0
grep -F -- "enabling wake lock for persistence and power-mode stress" "$tmp/log-wake-hold/script.out" >/dev/null \
  || fail "wake-hold smoke must enable wake lock before the persistence hold"
grep -F -- "pawxyctl wake on" "$tmp/log-wake-hold/adb.log" >/dev/null \
  || fail "wake-hold smoke must turn wake lock on"
grep -F -- "pawxyctl wake off" "$tmp/log-wake-hold/adb.log" >/dev/null \
  || fail "wake-hold smoke must turn wake lock off after persistence coverage"
grep -F -- '"wake_lock_enabled":true' "$tmp/log-wake-hold/state.json" >/dev/null \
  && fail "wake-hold smoke must leave wake lock disabled after cleanup"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_SCREEN_OFF=1 run_smoke adb "$tmp/log-screen-off" "" 0 1 0
grep -F -- "turning screen off and verifying proxy bridge" "$tmp/log-screen-off/script.out" >/dev/null \
  || fail "screen-off smoke must log screen-off proxy bridge coverage"
grep -F -- "input keyevent KEYCODE_SLEEP" "$tmp/log-screen-off/adb.log" >/dev/null \
  || fail "screen-off smoke must turn the screen off through the selected control channel"
grep -F -- "input keyevent KEYCODE_WAKEUP" "$tmp/log-screen-off/adb.log" >/dev/null \
  || fail "screen-off smoke must wake the screen after proxy verification"
grep -F -- "waking screen after screen-off proxy verification" "$tmp/log-screen-off/script.out" >/dev/null \
  || fail "screen-off smoke must log screen restore after proxy verification"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_SCREEN_OFF=1 run_smoke rish "$tmp/log-rish-screen-off" "" 0 1 0
grep -F -- "rish -c 'input keyevent KEYCODE_SLEEP'" "$tmp/log-rish-screen-off/adb.log" >/dev/null \
  || fail "rish screen-off smoke must turn the screen off through the selected rish channel"
grep -F -- "rish -c 'input keyevent KEYCODE_WAKEUP'" "$tmp/log-rish-screen-off/adb.log" >/dev/null \
  || fail "rish screen-off smoke must wake the screen through the selected rish channel"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_SCREEN_OFF=1 PAWXY_KEEP_SCREEN_OFF_DURING_HOLD=1 run_smoke adb "$tmp/log-screen-off-hold" "" 2 1 0
grep -F -- "keeping screen off for persistence hold" "$tmp/log-screen-off-hold/script.out" >/dev/null \
  || fail "screen-off hold smoke must keep the screen off through the persistence hold"
grep -F -- "hold sample: elapsed=" "$tmp/log-screen-off-hold/script.out" >/dev/null \
  || fail "screen-off hold smoke must probe during the screen-off persistence hold"
grep -F -- "waking screen after screen-off persistence hold" "$tmp/log-screen-off-hold/script.out" >/dev/null \
  || fail "screen-off hold smoke must wake the screen after the persistence hold"
awk '
  /keeping screen off for persistence hold/ { keep = NR }
  /hold sample: elapsed=/ { hold = NR }
  /waking screen after screen-off persistence hold/ { wake = NR }
  END { exit (keep > 0 && hold > keep && wake > hold) ? 0 : 1 }
' "$tmp/log-screen-off-hold/script.out" \
  || fail "screen-off hold smoke must keep the screen off until after hold samples"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_SCREEN_OFF=1 PAWXY_KEEP_SCREEN_OFF_DURING_HOLD=1 run_smoke rish "$tmp/log-rish-screen-off-hold" "" 1 1 0
grep -F -- "rish -c 'input keyevent KEYCODE_SLEEP'" "$tmp/log-rish-screen-off-hold/adb.log" >/dev/null \
  || fail "rish screen-off hold smoke must turn the screen off through the selected rish channel"
grep -F -- "keeping screen off for persistence hold" "$tmp/log-rish-screen-off-hold/script.out" >/dev/null \
  || fail "rish screen-off hold smoke must keep the screen off through the persistence hold"
grep -F -- "rish -c 'input keyevent KEYCODE_WAKEUP'" "$tmp/log-rish-screen-off-hold/adb.log" >/dev/null \
  || fail "rish screen-off hold smoke must wake the screen through the selected rish channel after the hold"

if PAWXY_KEEP_SCREEN_OFF_DURING_HOLD=1 PAWXY_RUN_SCREEN_OFF=0 run_smoke adb "$tmp/log-invalid-screen-off-hold" "" 0 1 0; then
  fail "device smoke must reject screen-off hold without PAWXY_RUN_SCREEN_OFF=1"
fi
grep -F -- "PAWXY_KEEP_SCREEN_OFF_DURING_HOLD requires PAWXY_RUN_SCREEN_OFF=1" "$tmp/log-invalid-screen-off-hold/script.err" >/dev/null \
  || fail "invalid screen-off hold smoke must explain that PAWXY_RUN_SCREEN_OFF=1 is required"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_NETWORK_TOGGLE=1 run_smoke adb "$tmp/log-network-toggle" "" 0 1 0
grep -F -- "toggling wifi network state and verifying proxy bridge" "$tmp/log-network-toggle/script.out" >/dev/null \
  || fail "network toggle smoke must log network-change proxy bridge coverage"
grep -F -- "cmd wifi set-wifi-enabled disabled" "$tmp/log-network-toggle/adb.log" >/dev/null \
  || fail "network toggle smoke must disable Wi-Fi through the selected control channel"
grep -F -- "cmd wifi set-wifi-enabled enabled" "$tmp/log-network-toggle/adb.log" >/dev/null \
  || fail "network toggle smoke must restore Wi-Fi through the selected control channel"
grep -F -- "restoring wifi network state and verifying proxy remains stable" "$tmp/log-network-toggle/script.out" >/dev/null \
  || fail "network toggle smoke must verify proxy stability after network restore"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_NETWORK_TOGGLE=1 PAWXY_NETWORK_TOGGLE_MODE=wifi,airplane run_smoke adb "$tmp/log-dual-network-toggle" "" 0 1 0
grep -F -- "toggling wifi network state and verifying proxy bridge" "$tmp/log-dual-network-toggle/script.out" >/dev/null \
  || fail "dual network toggle smoke must cover Wi-Fi mode"
grep -F -- "toggling airplane network state and verifying proxy bridge" "$tmp/log-dual-network-toggle/script.out" >/dev/null \
  || fail "dual network toggle smoke must cover airplane mode"
grep -F -- "cmd connectivity airplane-mode enable" "$tmp/log-dual-network-toggle/adb.log" >/dev/null \
  || fail "dual network toggle smoke must enable airplane mode"
grep -F -- "cmd connectivity airplane-mode disable" "$tmp/log-dual-network-toggle/adb.log" >/dev/null \
  || fail "dual network toggle smoke must restore airplane mode"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_NETWORK_TOGGLE=1 run_smoke rish "$tmp/log-rish-network-toggle" "" 0 1 0
grep -F -- "rish -c 'cmd wifi set-wifi-enabled disabled'" "$tmp/log-rish-network-toggle/adb.log" >/dev/null \
  || fail "rish network toggle smoke must disable Wi-Fi through the selected rish channel"
grep -F -- "rish -c 'cmd wifi set-wifi-enabled enabled'" "$tmp/log-rish-network-toggle/adb.log" >/dev/null \
  || fail "rish network toggle smoke must restore Wi-Fi through the selected rish channel"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_NETWORK_TOGGLE=1 PAWXY_NETWORK_TOGGLE_MODE=airplane run_smoke rish "$tmp/log-rish-airplane-network-toggle" "" 0 1 0
grep -F -- "rish -c 'cmd connectivity airplane-mode enable'" "$tmp/log-rish-airplane-network-toggle/adb.log" >/dev/null \
  || fail "rish airplane network toggle smoke must enable airplane mode through the selected rish channel"
grep -F -- "rish -c 'cmd connectivity airplane-mode disable'" "$tmp/log-rish-airplane-network-toggle/adb.log" >/dev/null \
  || fail "rish airplane network toggle smoke must restore airplane mode through the selected rish channel"

if PAWXY_RUN_NETWORK_TOGGLE=1 PAWXY_NETWORK_TOGGLE_MODE=bluetooth run_smoke adb "$tmp/log-invalid-network-mode" "" 0 1 0; then
  fail "device smoke must reject invalid network toggle modes before testing"
fi
grep -F -- "PAWXY_NETWORK_TOGGLE_MODE must be wifi, airplane, or a comma-separated list of those modes" "$tmp/log-invalid-network-mode/script.err" >/dev/null \
  || fail "invalid network toggle smoke must explain supported PAWXY_NETWORK_TOGGLE_MODE values"

if PAWXY_RUN_NETWORK_TOGGLE=1 PAWXY_TEST_FAIL_CURL_DURING_NETWORK=1 run_smoke adb "$tmp/log-network-toggle-failure" "" 0 1 0; then
  fail "network toggle smoke must fail when proxy traffic fails during network change"
fi
grep -F -- "cmd wifi set-wifi-enabled enabled" "$tmp/log-network-toggle-failure/adb.log" >/dev/null \
  || fail "network toggle failure smoke must restore Wi-Fi during cleanup"
grep -F -- "pawxyctl stop" "$tmp/log-network-toggle-failure/adb.log" >/dev/null \
  || fail "network toggle failure smoke must stop Pawxy after restoring the network"

if PAWXY_TEST_WAKE_STOPS_NATIVE=1 run_smoke adb "$tmp/log-wake-native-drift" "" 0 1 1; then
  fail "wake toggle smoke must fail when wake on stops the native runtime"
fi
grep -F -- "expected status field native_running=true" "$tmp/log-wake-native-drift/script.err" >/dev/null \
  || fail "wake native drift smoke must explain that wake on lost native_running=true"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_DOZE=1 PAWXY_RUN_APP_STANDBY=1 PAWXY_RUN_STANDBY_BUCKET=1 PAWXY_RUN_BACKGROUND_RESTRICTION=1 PAWXY_RUN_BATTERY_SAVER=1 run_smoke adb "$tmp/log-power" "" 0 1 0
grep -F -- "dumpsys deviceidle force-idle" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must force Doze mode"
grep -F -- "pawxyctl wake on" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must keep wake lock enabled during forced power modes"
grep -F -- "pawxyctl wake off" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must disable wake lock after forced power modes"
grep -F -- "dumpsys deviceidle unforce" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must restore forced Doze mode"
grep -F -- "restoring Doze mode and verifying proxy remains stable" "$tmp/log-power/script.out" >/dev/null \
  || fail "power smoke must verify proxy stability after forced Doze restore"
grep -F -- "dumpsys battery reset" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must restore simulated battery state"
grep -F -- "am set-inactive dev.pawxy true" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must force App Standby"
grep -F -- "am set-inactive dev.pawxy false" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must restore App Standby"
grep -F -- "am set-standby-bucket dev.pawxy rare" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must force rare App Standby Bucket"
grep -F -- "am set-standby-bucket dev.pawxy active" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must restore active App Standby Bucket"
grep -F -- "cmd appops set dev.pawxy RUN_ANY_IN_BACKGROUND ignore" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must apply background restriction"
grep -F -- "cmd appops set dev.pawxy RUN_ANY_IN_BACKGROUND allow" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must restore background restriction"
grep -F -- "settings put global low_power 1" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must force battery saver"
grep -F -- "settings put global low_power 0" "$tmp/log-power/adb.log" >/dev/null \
  || fail "power smoke must restore battery saver"

PAWXY_RUN_WAKE_HOLD=1 PAWXY_RUN_DOZE=1 PAWXY_RUN_APP_STANDBY=1 PAWXY_RUN_STANDBY_BUCKET=1 PAWXY_RUN_BACKGROUND_RESTRICTION=1 PAWXY_RUN_BATTERY_SAVER=1 run_smoke rish "$tmp/log-rish-power" "" 0 1 0
grep -F -- "rish -c 'dumpsys battery unplug'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must force unplugged battery state through the selected rish channel"
grep -F -- "rish -c 'dumpsys deviceidle force-idle'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must force Doze through the selected rish channel"
grep -F -- "rish -c 'dumpsys deviceidle unforce'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must restore Doze through the selected rish channel"
grep -F -- "rish -c 'am set-inactive dev.pawxy true'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must force App Standby through the selected rish channel"
grep -F -- "rish -c 'am set-standby-bucket dev.pawxy rare'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must force rare standby bucket through the selected rish channel"
grep -F -- "rish -c 'cmd appops set dev.pawxy RUN_ANY_IN_BACKGROUND ignore'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must force background restriction through the selected rish channel"
grep -F -- "rish -c 'settings put global low_power 1'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must force battery saver through the selected rish channel"
grep -F -- "rish -c 'dumpsys battery reset'" "$tmp/log-rish-power/adb.log" >/dev/null \
  || fail "rish power smoke must restore battery state through the selected rish channel"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-power-failure" \
  PAWXY_TEST_FAIL_CURL_DURING_POWER=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_RUN_DOZE=1 \
  PAWXY_RUN_SHARE=0 \
  PAWXY_RUN_WAKE=0 \
  PAWXY_RUN_RESTART=0 \
  PAWXY_RUN_PROCESS_RESTART=0 \
  PAWXY_RUN_STOP_START=0 \
  PAWXY_RUN_BAD_TOKEN=0 \
  PAWXY_RUN_UNKNOWN_ACTION=0 \
  PAWXY_RUN_UNSAFE_LAN=0 \
    sh "$SCRIPT" >"$tmp/log-power-failure/script.out" 2>"$tmp/log-power-failure/script.err"; then
  fail "power failure smoke must fail when proxy traffic fails during forced Doze"
fi
grep -F -- "dumpsys deviceidle unforce" "$tmp/log-power-failure/adb.log" >/dev/null \
  || fail "power failure smoke must restore forced Doze mode during cleanup"
grep -F -- "dumpsys battery reset" "$tmp/log-power-failure/adb.log" >/dev/null \
  || fail "power failure smoke must reset simulated battery state during cleanup"
grep -F -- "pawxyctl stop" "$tmp/log-power-failure/adb.log" >/dev/null \
  || fail "power failure smoke must stop Pawxy after restoring power modes"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-background-restriction-failure" \
  PAWXY_TEST_FAIL_CURL_DURING_POWER=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_RUN_BACKGROUND_RESTRICTION=1 \
  PAWXY_RUN_SHARE=0 \
  PAWXY_RUN_WAKE=0 \
  PAWXY_RUN_RESTART=0 \
  PAWXY_RUN_PROCESS_RESTART=0 \
  PAWXY_RUN_STOP_START=0 \
  PAWXY_RUN_BAD_TOKEN=0 \
  PAWXY_RUN_UNKNOWN_ACTION=0 \
  PAWXY_RUN_UNSAFE_LAN=0 \
    sh "$SCRIPT" >"$tmp/log-background-restriction-failure/script.out" 2>"$tmp/log-background-restriction-failure/script.err"; then
  fail "background restriction failure smoke must fail when proxy traffic fails during forced background restriction"
fi
grep -F -- "cmd appops set dev.pawxy RUN_ANY_IN_BACKGROUND allow" "$tmp/log-background-restriction-failure/adb.log" >/dev/null \
  || fail "background restriction failure smoke must restore background restriction during cleanup"
grep -F -- "dumpsys battery reset" "$tmp/log-background-restriction-failure/adb.log" >/dev/null \
  || fail "background restriction failure smoke must reset simulated battery state during cleanup"
grep -F -- "pawxyctl stop" "$tmp/log-background-restriction-failure/adb.log" >/dev/null \
  || fail "background restriction failure smoke must stop Pawxy after restoring background restriction"
restore_line=$(grep -n -- "cmd appops set dev.pawxy RUN_ANY_IN_BACKGROUND allow" "$tmp/log-background-restriction-failure/adb.log" | sed -n '1s/:.*//p')
stop_line=$(grep -n -- "pawxyctl stop" "$tmp/log-background-restriction-failure/adb.log" | sed -n '1s/:.*//p')
[ "$restore_line" -lt "$stop_line" ] \
  || fail "background restriction failure smoke must restore background restriction before stopping Pawxy"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-bad-uid" \
  PAWXY_TEST_SHELL_UID=10000 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >"$tmp/log-bad-uid/script.out" 2>"$tmp/log-bad-uid/script.err"; then
  fail "control preflight must reject app-like shell uids before starting Pawxy"
fi
grep -F -- "control shell uid" "$tmp/log-bad-uid/script.err" >/dev/null \
  || fail "bad uid smoke must explain the rejected control shell uid"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-invalid-hold" \
  PAWXY_HOLD_SECONDS=not-a-number \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >"$tmp/log-invalid-hold/script.out" 2>"$tmp/log-invalid-hold/script.err"; then
  fail "device smoke must reject invalid numeric persistence settings before testing"
fi
grep -F -- "PAWXY_HOLD_SECONDS must be a non-negative integer" "$tmp/log-invalid-hold/script.err" >/dev/null \
  || fail "invalid hold smoke must explain the rejected PAWXY_HOLD_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-invalid-adb-timeout" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_ADB_TIMEOUT_SECONDS=0 \
    sh "$SCRIPT" >"$tmp/log-invalid-adb-timeout/script.out" 2>"$tmp/log-invalid-adb-timeout/script.err"; then
  fail "device smoke must reject invalid adb command timeout settings before testing"
fi
grep -F -- "PAWXY_ADB_TIMEOUT_SECONDS must be greater than zero" "$tmp/log-invalid-adb-timeout/script.err" >/dev/null \
  || fail "invalid adb timeout smoke must explain the rejected PAWXY_ADB_TIMEOUT_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-invalid-control-timeout" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_CONTROL_TIMEOUT_SECONDS=0 \
    sh "$SCRIPT" >"$tmp/log-invalid-control-timeout/script.out" 2>"$tmp/log-invalid-control-timeout/script.err"; then
  fail "device smoke must reject invalid control timeout settings before testing"
fi
grep -F -- "PAWXY_CONTROL_TIMEOUT_SECONDS must be greater than zero" "$tmp/log-invalid-control-timeout/script.err" >/dev/null \
  || fail "invalid control timeout smoke must explain the rejected PAWXY_CONTROL_TIMEOUT_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-invalid-device-shell-timeout" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS=0 \
    sh "$SCRIPT" >"$tmp/log-invalid-device-shell-timeout/script.out" 2>"$tmp/log-invalid-device-shell-timeout/script.err"; then
  fail "device smoke must reject invalid ordinary adb shell timeout settings before testing"
fi
grep -F -- "PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS must be greater than zero" "$tmp/log-invalid-device-shell-timeout/script.err" >/dev/null \
  || fail "invalid ordinary adb shell timeout smoke must explain the rejected PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-invalid-curl-timeout" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_CURL_MAX_TIME_SECONDS=0 \
    sh "$SCRIPT" >"$tmp/log-invalid-curl-timeout/script.out" 2>"$tmp/log-invalid-curl-timeout/script.err"; then
  fail "device smoke must reject invalid curl timeout settings before testing"
fi
grep -F -- "PAWXY_CURL_MAX_TIME_SECONDS must be greater than zero" "$tmp/log-invalid-curl-timeout/script.err" >/dev/null \
  || fail "invalid curl timeout smoke must explain the rejected PAWXY_CURL_MAX_TIME_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-invalid-device-origin-timeout" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_DEVICE_ORIGIN_TIMEOUT_SECONDS=0 \
    sh "$SCRIPT" >"$tmp/log-invalid-device-origin-timeout/script.out" 2>"$tmp/log-invalid-device-origin-timeout/script.err"; then
  fail "device smoke must reject invalid device-origin timeout settings before testing"
fi
grep -F -- "PAWXY_DEVICE_ORIGIN_TIMEOUT_SECONDS must be greater than zero" "$tmp/log-invalid-device-origin-timeout/script.err" >/dev/null \
  || fail "invalid device-origin timeout smoke must explain the rejected PAWXY_DEVICE_ORIGIN_TIMEOUT_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-invalid-run-flag" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_RUN_DOZE=true \
    sh "$SCRIPT" >"$tmp/log-invalid-run-flag/script.out" 2>"$tmp/log-invalid-run-flag/script.err"; then
  fail "device smoke must reject non-0/1 run flags before testing"
fi
grep -F -- "PAWXY_RUN_DOZE must be 0 or 1" "$tmp/log-invalid-run-flag/script.err" >/dev/null \
  || fail "invalid run-flag smoke must explain the rejected PAWXY_RUN_DOZE value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-port-conflict" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_HOST_PROXY_PORT=3218 \
  PAWXY_HOST_TARGET_PORT=3218 \
    sh "$SCRIPT" >"$tmp/log-port-conflict/script.out" 2>"$tmp/log-port-conflict/script.err"; then
  fail "device smoke must reject conflicting host proxy and target ports before testing"
fi
grep -F -- "PAWXY_HOST_PROXY_PORT and PAWXY_HOST_TARGET_PORT must be different" "$tmp/log-port-conflict/script.err" >/dev/null \
  || fail "port conflict smoke must explain the rejected host port configuration"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-token-repair-failure" \
  PAWXY_TEST_RESET_TOKEN_FAIL=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >"$tmp/log-token-repair-failure/script.out" 2>"$tmp/log-token-repair-failure/script.err"; then
  fail "token repair failure smoke must fail when reset-token fails"
fi
grep -F -- "control token reset failed; restored token file" "$tmp/log-token-repair-failure/script.err" >/dev/null \
  || fail "token repair failure smoke must explain that the original token was restored"
grep -F -- "printf '%s\n' good-token > /data/local/tmp/pawxy/token" "$tmp/log-token-repair-failure/adb.log" >/dev/null \
  || fail "token repair failure smoke must restore the original control token file"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-listen-drift" \
  PAWXY_TEST_DRIFT_LISTEN_ON_INVALID=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >"$tmp/log-listen-drift/script.out" 2>"$tmp/log-listen-drift/script.err"; then
  fail "listen drift smoke must fail when hostile direct starts change the proxy listen endpoint"
fi
grep -F -- "malformed direct start changed the proxy listen endpoint" "$tmp/log-listen-drift/script.err" >/dev/null \
  || fail "listen drift smoke must explain that a hostile direct start changed the proxy listen endpoint"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-native-running-drift" \
  PAWXY_TEST_NATIVE_RUNNING_FALSE=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >"$tmp/log-native-running-drift/script.out" 2>"$tmp/log-native-running-drift/script.err"; then
  fail "native-running drift smoke must fail when native runtime is not running behind a running service status"
fi
grep -F -- "did not report running=true/native_running=true" "$tmp/log-native-running-drift/script.err" >/dev/null \
  || fail "native-running drift smoke must explain that native_running did not become true"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-process-pid-stuck" \
  PAWXY_TEST_PROCESS_PID_STUCK=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >"$tmp/log-process-pid-stuck/script.out" 2>"$tmp/log-process-pid-stuck/script.err"; then
  fail "process restart smoke must fail when crash injection does not change the process pid"
fi
grep -F -- "Pawxy process pid did not change after crash injection" "$tmp/log-process-pid-stuck/script.err" >/dev/null \
  || fail "process pid stuck smoke must explain that crash injection did not restart the process"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-native-restart-during-hold" \
  PAWXY_TEST_NATIVE_RESTART_AFTER_SLEEP_COUNT=1 \
  PAWXY_HOLD_SECONDS=2 \
  PAWXY_HOLD_INTERVAL_SECONDS=1 \
  PAWXY_BULK_KIB=1 \
  PAWXY_RUN_IDLE_EFFICIENCY=0 \
  PAWXY_RUN_DUPLICATE_START=0 \
  PAWXY_RUN_RESTART=0 \
  PAWXY_RUN_PROCESS_RESTART=0 \
  PAWXY_RUN_TOKEN_REPAIR=0 \
  PAWXY_RUN_STOP_START=0 \
  PAWXY_RUN_BAD_TOKEN=0 \
  PAWXY_RUN_UNKNOWN_ACTION=0 \
  PAWXY_RUN_UNSAFE_LAN=0 \
  PAWXY_RUN_INVALID_CONFIG=0 \
  PAWXY_RUN_WAKE=0 \
  PAWXY_RUN_SHARE=0 \
    sh "$SCRIPT" >"$tmp/log-native-restart-during-hold/script.out" 2>"$tmp/log-native-restart-during-hold/script.err"; then
  fail "hold smoke must fail when the native proxy restarts without an app process restart"
fi
grep -F -- "persistence hold restarted the native proxy" "$tmp/log-native-restart-during-hold/script.err" >/dev/null \
  || fail "native restart smoke must explain started_at_unix_ms drift during persistence hold"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-hold-fd" \
  PAWXY_HOLD_SECONDS=1 \
  PAWXY_HOLD_INTERVAL_SECONDS=1 \
  PAWXY_MAX_HOLD_FD_SIZE=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_RUN_IDLE_EFFICIENCY=0 \
  PAWXY_RUN_DUPLICATE_START=0 \
  PAWXY_RUN_RESTART=0 \
  PAWXY_RUN_PROCESS_RESTART=0 \
  PAWXY_RUN_TOKEN_REPAIR=0 \
  PAWXY_RUN_STOP_START=0 \
  PAWXY_RUN_BAD_TOKEN=0 \
  PAWXY_RUN_UNKNOWN_ACTION=0 \
  PAWXY_RUN_UNSAFE_LAN=0 \
  PAWXY_RUN_INVALID_CONFIG=0 \
  PAWXY_RUN_WAKE=0 \
  PAWXY_RUN_SHARE=0 \
    sh "$SCRIPT" >"$tmp/log-hold-fd/script.out" 2>"$tmp/log-hold-fd/script.err"; then
  fail "hold resource smoke must fail when process FDSize exceeds the configured hold threshold"
fi
grep -F -- "FDSize during persistence hold sample exceeds" "$tmp/log-hold-fd/script.err" >/dev/null \
  || fail "hold resource smoke must explain excessive process FD table size during persistence holds"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-active-connection-leak" \
  PAWXY_TEST_ACTIVE_CONNECTIONS_STUCK=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >"$tmp/log-active-connection-leak/script.out" 2>"$tmp/log-active-connection-leak/script.err"; then
  fail "active-connection leak smoke must fail when native active connection metrics never drain"
fi
grep -F -- "expected status field active_connections <= 0" "$tmp/log-active-connection-leak/script.err" >/dev/null \
  || fail "active-connection leak smoke must explain that active proxy connections did not drain"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-idle-cpu" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_MAX_IDLE_CPU_TICKS=0 \
    sh "$SCRIPT" >"$tmp/log-idle-cpu/script.out" 2>"$tmp/log-idle-cpu/script.err"; then
  fail "idle efficiency smoke must fail when idle CPU growth exceeds the configured threshold"
fi
grep -F -- "idle CPU growth exceeds" "$tmp/log-idle-cpu/script.err" >/dev/null \
  || fail "idle CPU smoke must explain excessive idle CPU growth"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-idle-fd" \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
  PAWXY_MAX_IDLE_FD_SIZE=0 \
    sh "$SCRIPT" >"$tmp/log-idle-fd/script.out" 2>"$tmp/log-idle-fd/script.err"; then
  fail "idle FDSize smoke must fail when process FDSize exceeds the configured threshold"
fi
grep -F -- "FDSize before idle sample exceeds" "$tmp/log-idle-fd/script.err" >/dev/null \
  || fail "idle FDSize smoke must explain excessive process FD table size"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-failure" \
  PAWXY_ARTIFACT_DIR="$tmp/log-failure/artifacts" \
  PAWXY_TEST_FAIL_CURL=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >/dev/null 2>&1; then
  fail "failure smoke must fail when proxy traffic fails"
fi
grep -F -- "pawxyctl doctor" "$tmp/log-failure/adb.log" >/dev/null \
  || fail "failure smoke must collect pawxyctl doctor output"
grep -F -- "logcat -d -s Pawxy PawxyNative" "$tmp/log-failure/adb.log" >/dev/null \
  || fail "failure smoke must collect Pawxy logcat output"
grep -F -- "dumpsys deviceidle" "$tmp/log-failure/adb.log" >/dev/null \
  || fail "failure smoke must collect device idle diagnostics"
grep -F -- "dumpsys power" "$tmp/log-failure/adb.log" >/dev/null \
  || fail "failure smoke must collect power diagnostics"
grep -F -- "dumpsys activity services dev.pawxy/.ProxyService" "$tmp/log-failure/adb.log" >/dev/null \
  || fail "failure smoke must collect service diagnostics"
grep -F -- "cmd appops get dev.pawxy POST_NOTIFICATION" "$tmp/log-failure/adb.log" >/dev/null \
  || fail "failure smoke must collect notification app-op diagnostics"
grep -F -- "pawxyctl stop" "$tmp/log-failure/adb.log" >/dev/null \
  || fail "failure smoke must attempt to stop Pawxy after diagnostics"
grep -F -- "doctor ok" "$tmp/log-failure/artifacts/diagnostics/pawxyctl-doctor-via-adb.txt" >/dev/null \
  || fail "failure smoke must persist pawxyctl doctor diagnostics as an artifact"
grep -F -- "logcat ok" "$tmp/log-failure/artifacts/diagnostics/pawxy-logcat.txt" >/dev/null \
  || fail "failure smoke must persist Pawxy logcat diagnostics as an artifact"
grep -F -- "exit_code=1" "$tmp/log-failure/artifacts/summary.txt" >/dev/null \
  || fail "failure smoke must persist a failing exit summary"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_APK="$tmp/files/app-debug.apk" \
  PAWXY_CTL="$tmp/files/pawxyctl" \
  PAWXY_TEST_LOG="$tmp/log-rish-failure" \
  PAWXY_CONTROL_MODE=rish \
  PAWXY_TEST_FAIL_CURL=1 \
  PAWXY_HOLD_SECONDS=0 \
  PAWXY_BULK_KIB=1 \
    sh "$SCRIPT" >/dev/null 2>&1; then
  fail "rish failure smoke must fail when proxy traffic fails"
fi
grep -F -- "rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl doctor'" "$tmp/log-rish-failure/adb.log" >/dev/null \
  || fail "rish failure diagnostics must run pawxyctl doctor through the selected rish control channel"
grep -F -- "rish -c 'logcat -d -s Pawxy PawxyNative | tail -n 200'" "$tmp/log-rish-failure/adb.log" >/dev/null \
  || fail "rish failure diagnostics must collect Pawxy logcat through the selected rish channel"
grep -F -- "rish -c 'dumpsys deviceidle | head -n 80'" "$tmp/log-rish-failure/adb.log" >/dev/null \
  || fail "rish failure diagnostics must collect device idle state through the selected rish channel"
grep -F -- "rish -c 'dumpsys power | head -n 80'" "$tmp/log-rish-failure/adb.log" >/dev/null \
  || fail "rish failure diagnostics must collect power state through the selected rish channel"
grep -F -- "rish -c 'cmd appops get dev.pawxy POST_NOTIFICATION'" "$tmp/log-rish-failure/adb.log" >/dev/null \
  || fail "rish failure diagnostics must collect notification app-op state through the selected rish channel"

printf '%s\n' "android device smoke mock ok"
