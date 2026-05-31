#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ADB=${ADB:-adb}
EMULATOR=${PAWXY_EMULATOR:-}
AVD=${PAWXY_AVD:-}
GSI_SYSTEM_IMG=${PAWXY_GSI_SYSTEM_IMG:-}
DEVICE_SMOKE=${PAWXY_DEVICE_SMOKE:-$ROOT/scripts/test-android-device.sh}
BOOT_TIMEOUT_SECONDS=${PAWXY_VM_BOOT_TIMEOUT_SECONDS:-300}
BOOT_INTERVAL_SECONDS=${PAWXY_VM_BOOT_INTERVAL_SECONDS:-5}
ADB_TIMEOUT_SECONDS=${PAWXY_VM_ADB_TIMEOUT_SECONDS:-120}
EMULATOR_TIMEOUT_SECONDS=${PAWXY_VM_EMULATOR_TIMEOUT_SECONDS:-30}
VM_HOLD_SECONDS=${PAWXY_VM_HOLD_SECONDS:-300}
VM_HOLD_INTERVAL_SECONDS=${PAWXY_VM_HOLD_INTERVAL_SECONDS:-30}
EMULATOR_ACCEL=${PAWXY_EMULATOR_ACCEL:-}
KVM_DEVICE=${PAWXY_VM_KVM_DEVICE:-/dev/kvm}
NO_SNAPSHOT=${PAWXY_VM_NO_SNAPSHOT:-1}
WIPE_DATA=${PAWXY_VM_WIPE_DATA:-0}
EMULATOR_LOG=${PAWXY_VM_EMULATOR_LOG:-}
EMULATOR_LOG_AUTO=0
SELECTED_SERIAL=${ANDROID_SERIAL:-}
EMULATOR_PID=
EMULATOR_STARTED=0
CLEANUP_DONE=0
PRELAUNCH_DEVICES=

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

fail_no_android_runtime() {
  print_runtime_inventory
  print_runtime_setup_hint
  fail "No booted Android VM/device was found. Start or select a runtime, then retry. Existing GSI/VM: ANDROID_SERIAL=<serial> scripts/test-android-vm.sh. Existing AVD: PAWXY_AVD=<avd_name> scripts/test-android-vm.sh. GSI through Android Emulator: PAWXY_AVD=<avd_name> PAWXY_GSI_SYSTEM_IMG=/path/to/system.img scripts/test-android-vm.sh"
}

note() {
  printf '%s\n' "pawxy android vm smoke: $*"
}

run_boot_diag() {
  label=$1
  shift
  note "boot diagnostic: $label"
  "$@" 2>&1 | sed 's/^/  /' || true
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_runnable() {
  command -v "$1" >/dev/null 2>&1 || [ -x "$1" ]
}

emulator_avd_exists() {
  emulator_cmd -list-avds 2>/dev/null | awk -v avd="$AVD" '$0 == avd { found = 1 } END { exit found ? 0 : 1 }'
}

avd_config_file() {
  if [ -n "${ANDROID_AVD_HOME:-}" ] && [ -f "$ANDROID_AVD_HOME/$AVD.avd/config.ini" ]; then
    printf '%s\n' "$ANDROID_AVD_HOME/$AVD.avd/config.ini"
    return 0
  fi
  if [ -n "${ANDROID_SDK_HOME:-}" ] && [ -f "$ANDROID_SDK_HOME/.android/avd/$AVD.avd/config.ini" ]; then
    printf '%s\n' "$ANDROID_SDK_HOME/.android/avd/$AVD.avd/config.ini"
    return 0
  fi
  if [ -n "${HOME:-}" ] && [ -f "$HOME/.android/avd/$AVD.avd/config.ini" ]; then
    printf '%s\n' "$HOME/.android/avd/$AVD.avd/config.ini"
    return 0
  fi
  return 1
}

normalize_arch_hint() {
  value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$value" in
    *x86_64*) printf '%s\n' "x86_64" ;;
    *arm64*|*aarch64*) printf '%s\n' "arm64" ;;
  esac
}

avd_arch_hint() {
  config=$(avd_config_file || true)
  [ -n "$config" ] || return 0
  awk -F= '
    $1 == "abi.type" { print $2; found = 1; exit }
    $1 == "hw.cpu.arch" { arch = $2 }
    END { if (!found && arch != "") print arch }
  ' "$config" | tr -d '\r' | awk 'NF { print; exit }'
}

gsi_arch_hint() {
  normalize_arch_hint "$GSI_SYSTEM_IMG"
}

check_gsi_avd_arch_compat() {
  [ -n "$GSI_SYSTEM_IMG" ] || return 0
  avd_arch=$(normalize_arch_hint "$(avd_arch_hint)")
  gsi_arch=$(gsi_arch_hint)
  [ -n "$avd_arch" ] || return 0
  [ -n "$gsi_arch" ] || return 0
  [ "$avd_arch" = "$gsi_arch" ] || fail "PAWXY_GSI_SYSTEM_IMG appears to be $gsi_arch but PAWXY_AVD=$AVD appears to be $avd_arch; use a $avd_arch GSI for this AVD, or test the GSI on a matching runtime with ANDROID_SERIAL"
}

resolve_emulator() {
  if [ -n "$EMULATOR" ]; then
    return 0
  fi
  if has_cmd emulator; then
    EMULATOR=emulator
    return 0
  fi
  for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "${HOME:-}/Android/Sdk" /opt/android-sdk /usr/local/lib/android/sdk; do
    [ -n "$sdk_root" ] || continue
    if [ -x "$sdk_root/emulator/emulator" ]; then
      EMULATOR=$sdk_root/emulator/emulator
      return 0
    fi
  done
  EMULATOR=emulator
}

sdk_tool_cmd() {
  tool=$1
  if has_cmd "$tool"; then
    printf '%s\n' "$tool"
    return 0
  fi
  for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "${HOME:-}/Android/Sdk" /opt/android-sdk /usr/local/lib/android/sdk; do
    [ -n "$sdk_root" ] || continue
    if [ -x "$sdk_root/cmdline-tools/latest/bin/$tool" ]; then
      printf '%s\n' "$sdk_root/cmdline-tools/latest/bin/$tool"
      return 0
    fi
  done
  return 1
}

adb_cmd() {
  timeout "$ADB_TIMEOUT_SECONDS" "$ADB" "$@"
}

emulator_cmd() {
  timeout "$EMULATOR_TIMEOUT_SECONDS" "$EMULATOR" "$@"
}

resolve_gsi_system_img() {
  [ -n "$GSI_SYSTEM_IMG" ] || return 0
  case "$GSI_SYSTEM_IMG" in
    *.[Zz][Ii][Pp])
      fail "PAWXY_GSI_SYSTEM_IMG must point to an extracted system.img, not a zip archive: $GSI_SYSTEM_IMG"
      ;;
  esac
  if [ -d "$GSI_SYSTEM_IMG" ]; then
    if [ -f "$GSI_SYSTEM_IMG/system.img" ]; then
      GSI_SYSTEM_IMG=$GSI_SYSTEM_IMG/system.img
      return 0
    fi
    fail "PAWXY_GSI_SYSTEM_IMG directory does not contain system.img: $GSI_SYSTEM_IMG"
  fi
  [ -f "$GSI_SYSTEM_IMG" ] || fail "PAWXY_GSI_SYSTEM_IMG does not exist: $GSI_SYSTEM_IMG"
}

prepare_emulator_log() {
  if [ -z "$EMULATOR_LOG" ]; then
    EMULATOR_LOG=${TMPDIR:-/tmp}/pawxy-android-emulator.$$.log
    EMULATOR_LOG_AUTO=1
  fi
  : > "$EMULATOR_LOG" || fail "cannot write emulator log: $EMULATOR_LOG"
  note "emulator output log: $EMULATOR_LOG"
}

print_emulator_log_tail() {
  [ -n "$EMULATOR_LOG" ] || return 0
  [ -f "$EMULATOR_LOG" ] || return 0
  note "emulator log tail: $EMULATOR_LOG"
  tail -n 80 "$EMULATOR_LOG" 2>&1 | sed 's/^/  /' || true
}

print_runtime_inventory() {
  note "runtime inventory: adb devices"
  adb_cmd devices -l 2>&1 | sed 's/^/  /' || true

  resolve_emulator
  if is_runnable "$EMULATOR"; then
    note "runtime inventory: emulator=$EMULATOR"
    avds=$(emulator_cmd -list-avds 2>/dev/null || true)
    if [ -n "$avds" ]; then
      printf '%s\n' "$avds" | sed 's/^/  avd: /'
    else
      note "runtime inventory: no AVDs reported by $EMULATOR -list-avds"
    fi
  else
    note "runtime inventory: emulator binary not found: $EMULATOR"
  fi

  if [ -e "$KVM_DEVICE" ]; then
    note "runtime inventory: $KVM_DEVICE is available"
  else
    note "runtime inventory: $KVM_DEVICE is unavailable; AVD launch will use software acceleration unless PAWXY_EMULATOR_ACCEL is set"
  fi

  if [ -n "$GSI_SYSTEM_IMG" ]; then
    note "runtime inventory: PAWXY_GSI_SYSTEM_IMG=$GSI_SYSTEM_IMG"
  else
    note "runtime inventory: PAWXY_GSI_SYSTEM_IMG is not set"
  fi
}

print_runtime_setup_hint() {
  note "runtime setup hint: prepare an Android Emulator AVD, then rerun this wrapper"
  sdkmanager_cmd=$(sdk_tool_cmd sdkmanager || true)
  if [ -n "$sdkmanager_cmd" ]; then
    note "runtime setup hint: $sdkmanager_cmd \"emulator\" \"system-images;android-35;google_apis;x86_64\""
  else
    note "runtime setup hint: sdkmanager not found; install Android command-line tools or add sdkmanager to PATH"
  fi
  avdmanager_cmd=$(sdk_tool_cmd avdmanager || true)
  if [ -n "$avdmanager_cmd" ]; then
    note "runtime setup hint: echo \"no\" | $avdmanager_cmd create avd -n pawxy-api35 -k \"system-images;android-35;google_apis;x86_64\" --device pixel_7"
  else
    note "runtime setup hint: avdmanager not found; install Android command-line tools or add avdmanager to PATH"
  fi
  note "runtime setup hint: PAWXY_AVD=pawxy-api35 scripts/test-android-vm.sh"
  note "runtime setup hint: PAWXY_AVD=pawxy-api35 PAWXY_GSI_SYSTEM_IMG=/path/to/system.img scripts/test-android-vm.sh"
  note "runtime setup hint: for Android Emulator, use an extracted x86_64 GSI system.img that matches the AVD ABI; for Pixel hardware, boot an ARM64 GSI/DSU runtime and rerun with ANDROID_SERIAL"
  note "runtime setup hint: Pixel + Shizuku/rish: ANDROID_SERIAL=<pixel_serial> PAWXY_CONTROL_MODE=rish PAWXY_RISH=/sdcard/Android/data/moe.shizuku.privileged.api/files/rish PAWXY_RISH_RUNNER=sh PAWXY_RISH_APPLICATION_ID=<authorized_package> scripts/test-public-readiness.sh"
  if [ ! -e "$KVM_DEVICE" ]; then
    note "runtime setup hint: $KVM_DEVICE is unavailable here; emulator launch will use PAWXY_EMULATOR_ACCEL=off and may be slow"
  fi
}

adb_base() {
  if [ -n "$SELECTED_SERIAL" ]; then
    adb_cmd -s "$SELECTED_SERIAL" "$@"
  else
    adb_cmd "$@"
  fi
}

list_adb_device_serials() {
  adb_cmd devices | awk '$2 == "device" { print $1 }'
}

serial_in_list() {
  serial=$1
  list=$2
  printf '%s\n' "$list" | grep -Fx -- "$serial" >/dev/null 2>&1
}

record_prelaunch_devices() {
  [ -n "$AVD" ] || return 0
  [ -z "${ANDROID_SERIAL:-}" ] || return 0
  PRELAUNCH_DEVICES=$(list_adb_device_serials)
}

newly_launched_device_serials() {
  devices=$(list_adb_device_serials)
  for serial in $devices; do
    if ! serial_in_list "$serial" "$PRELAUNCH_DEVICES"; then
      printf '%s\n' "$serial"
    fi
  done
}

require_launched_emulator_alive() {
  phase=$1
  [ "$EMULATOR_STARTED" = "1" ] || return 0
  [ -n "$EMULATOR_PID" ] || return 0
  if kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
    return 0
  fi
  print_emulator_log_tail
  fail "emulator process exited before $phase; inspect emulator output, PAWXY_GSI_SYSTEM_IMG, and PAWXY_EMULATOR_ACCEL"
}

collect_boot_diagnostics() {
  note "collecting Android VM boot diagnostics"
  run_boot_diag "adb devices" adb_cmd devices -l
  run_boot_diag "boot properties" adb_base shell 'printf "sys.boot_completed=%s\ndev.bootcomplete=%s\nbootanim=%s\nmodel=%s\nfingerprint=%s\n" "$(getprop sys.boot_completed)" "$(getprop dev.bootcomplete)" "$(getprop init.svc.bootanim)" "$(getprop ro.product.model)" "$(getprop ro.build.fingerprint)"'
  run_boot_diag "logcat tail" adb_base logcat -d -t 200
  print_emulator_log_tail
}

cleanup() {
  code=$?
  if [ "$CLEANUP_DONE" = "1" ]; then
    exit "$code"
  fi
  CLEANUP_DONE=1
  if [ "$EMULATOR_STARTED" = "1" ]; then
    if [ -n "$SELECTED_SERIAL" ]; then
      adb_cmd -s "$SELECTED_SERIAL" emu kill >/dev/null 2>&1 || true
    fi
    if [ -n "$EMULATOR_PID" ]; then
      kill "$EMULATOR_PID" >/dev/null 2>&1 || true
    fi
  fi
  if [ "$code" = "0" ] && [ "$EMULATOR_LOG_AUTO" = "1" ] && [ -n "$EMULATOR_LOG" ]; then
    rm -f "$EMULATOR_LOG" >/dev/null 2>&1 || true
  fi
  exit "$code"
}
trap cleanup EXIT HUP INT TERM

select_single_device() {
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    SELECTED_SERIAL=$ANDROID_SERIAL
    state=$(adb_base get-state 2>/dev/null || true)
    [ "$state" = "device" ] || fail "ANDROID_SERIAL=$ANDROID_SERIAL is not in device state: ${state:-unknown}"
    return 0
  fi

  if [ "$EMULATOR_STARTED" = "1" ]; then
    launched_devices=$(newly_launched_device_serials)
    count=$(printf '%s\n' "$launched_devices" | awk 'NF { count += 1 } END { print count + 0 }')
    if [ "$count" = "1" ]; then
      SELECTED_SERIAL=$(printf '%s\n' "$launched_devices" | awk 'NF { print; exit }')
      return 0
    fi
    [ "$count" != "0" ] || fail "launched AVD did not register a new adb device"
    fail "launched AVD registered multiple new adb devices: $(printf '%s' "$launched_devices" | tr '\n' ' ')"
  fi

  devices=$(list_adb_device_serials)
  count=$(printf '%s\n' "$devices" | awk 'NF { count += 1 } END { print count + 0 }')
  if [ "$count" != "1" ]; then
    if [ "$count" = "0" ] && [ -z "$AVD" ]; then
      fail_no_android_runtime
    fi
    fail "expected exactly one booted adb device or ANDROID_SERIAL, found $count"
  fi
  SELECTED_SERIAL=$(printf '%s\n' "$devices" | awk 'NF { print; exit }')
}

wait_for_boot() {
  note "waiting for adb device"
  adb_base wait-for-device

  elapsed=0
  while [ "$elapsed" -le "$BOOT_TIMEOUT_SECONDS" ]; do
    require_launched_emulator_alive "Android boot completed"
    sys_boot=$(adb_base shell 'getprop sys.boot_completed' 2>/dev/null | tr -d '\r' | awk 'NF { value = $0 } END { print value }')
    dev_boot=$(adb_base shell 'getprop dev.bootcomplete' 2>/dev/null | tr -d '\r' | awk 'NF { value = $0 } END { print value }')
    bootanim=$(adb_base shell 'getprop init.svc.bootanim' 2>/dev/null | tr -d '\r' | awk 'NF { value = $0 } END { print value }')
    if [ "$sys_boot" = "1" ]; then
      note "boot completed: sys.boot_completed=$sys_boot dev.bootcomplete=${dev_boot:-unknown} bootanim=${bootanim:-unknown}"
      return 0
    fi
    if [ "$BOOT_INTERVAL_SECONDS" -gt 0 ] 2>/dev/null; then
      sleep "$BOOT_INTERVAL_SECONDS"
      elapsed=$((elapsed + BOOT_INTERVAL_SECONDS))
    else
      elapsed=$((elapsed + 1))
    fi
  done

  collect_boot_diagnostics
  fail "Android boot did not complete within ${BOOT_TIMEOUT_SECONDS}s"
}

wait_for_launched_device_registration() {
  [ "$EMULATOR_STARTED" = "1" ] || return 0
  note "waiting for launched AVD to register with adb"

  elapsed=0
  while [ "$elapsed" -le "$BOOT_TIMEOUT_SECONDS" ]; do
    require_launched_emulator_alive "adb registration"
    launched_devices=$(newly_launched_device_serials)
    count=$(printf '%s\n' "$launched_devices" | awk 'NF { count += 1 } END { print count + 0 }')
    if [ "$count" -gt 0 ]; then
      return 0
    fi
    if [ "$BOOT_INTERVAL_SECONDS" -gt 0 ] 2>/dev/null; then
      sleep "$BOOT_INTERVAL_SECONDS"
      elapsed=$((elapsed + BOOT_INTERVAL_SECONDS))
    else
      elapsed=$((elapsed + 1))
    fi
  done

  fail "launched AVD did not register a new adb device"
}

launch_avd_if_requested() {
  [ -n "$AVD" ] || return 0
  resolve_emulator
  is_runnable "$EMULATOR" || fail "PAWXY_AVD=$AVD was set, but emulator binary was not found: $EMULATOR"
  emulator_avd_exists || fail "PAWXY_AVD=$AVD was set, but that AVD is not installed or not visible to the emulator: $EMULATOR -list-avds"
  resolve_gsi_system_img
  check_gsi_avd_arch_compat

  if [ -z "$EMULATOR_ACCEL" ] && [ ! -e "$KVM_DEVICE" ]; then
    EMULATOR_ACCEL=off
  fi

  note "launching AVD $AVD"
  prepare_emulator_log
  set -- "@$AVD" -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect
  if [ "$NO_SNAPSHOT" = "1" ]; then
    set -- "$@" -no-snapshot
  fi
  if [ "$WIPE_DATA" = "1" ]; then
    note "wiping AVD user data before VM smoke"
    set -- "$@" -wipe-data
  fi
  if [ -n "$GSI_SYSTEM_IMG" ]; then
    note "using GSI system image $GSI_SYSTEM_IMG"
    set -- "$@" -system "$GSI_SYSTEM_IMG"
  fi
  if [ -n "$EMULATOR_ACCEL" ]; then
    set -- "$@" -accel "$EMULATOR_ACCEL"
  fi
  "$EMULATOR" "$@" >"$EMULATOR_LOG" 2>&1 &
  EMULATOR_PID=$!
  EMULATOR_STARTED=1
}

[ -f "$DEVICE_SMOKE" ] || fail "device smoke script not found: $DEVICE_SMOKE"
has_cmd "$ADB" || fail "adb not found: $ADB"
has_cmd timeout || fail "host timeout is required for bounded adb probes"
case "$BOOT_TIMEOUT_SECONDS" in
  ''|*[!0-9]*) fail "PAWXY_VM_BOOT_TIMEOUT_SECONDS must be a non-negative integer" ;;
esac
case "$BOOT_INTERVAL_SECONDS" in
  ''|*[!0-9]*) fail "PAWXY_VM_BOOT_INTERVAL_SECONDS must be a non-negative integer" ;;
esac
case "$ADB_TIMEOUT_SECONDS" in
  ''|*[!0-9]*) fail "PAWXY_VM_ADB_TIMEOUT_SECONDS must be a positive integer" ;;
esac
[ "$ADB_TIMEOUT_SECONDS" -gt 0 ] 2>/dev/null || fail "PAWXY_VM_ADB_TIMEOUT_SECONDS must be greater than zero"
case "$EMULATOR_TIMEOUT_SECONDS" in
  ''|*[!0-9]*) fail "PAWXY_VM_EMULATOR_TIMEOUT_SECONDS must be a positive integer" ;;
esac
[ "$EMULATOR_TIMEOUT_SECONDS" -gt 0 ] 2>/dev/null || fail "PAWXY_VM_EMULATOR_TIMEOUT_SECONDS must be greater than zero"
case "$NO_SNAPSHOT" in
  0|1) ;;
  *) fail "PAWXY_VM_NO_SNAPSHOT must be 0 or 1" ;;
esac
case "$WIPE_DATA" in
  0|1) ;;
  *) fail "PAWXY_VM_WIPE_DATA must be 0 or 1" ;;
esac
if [ -n "$GSI_SYSTEM_IMG" ] && [ -z "$AVD" ] && [ -z "${ANDROID_SERIAL:-}" ]; then
  fail "PAWXY_GSI_SYSTEM_IMG requires PAWXY_AVD so the GSI can be passed to a launched emulator; for an already booted GSI/VM, set ANDROID_SERIAL"
fi
if [ -n "$AVD" ] && [ -n "${ANDROID_SERIAL:-}" ]; then
  fail "PAWXY_AVD and ANDROID_SERIAL are mutually exclusive; use PAWXY_AVD to launch a test runtime or ANDROID_SERIAL to test an already booted Pixel/GSI/VM"
fi

record_prelaunch_devices
launch_avd_if_requested
wait_for_launched_device_registration
select_single_device
wait_for_boot

note "device identity"
adb_base shell 'printf "brand=%s\nmodel=%s\nsdk=%s\nbuild=%s\n" "$(getprop ro.product.brand)" "$(getprop ro.product.model)" "$(getprop ro.build.version.sdk)" "$(getprop ro.build.fingerprint)"'

note "running device smoke on $SELECTED_SERIAL"
ANDROID_SERIAL=$SELECTED_SERIAL \
  PAWXY_HOLD_SECONDS=${PAWXY_HOLD_SECONDS:-$VM_HOLD_SECONDS} \
  PAWXY_HOLD_INTERVAL_SECONDS=${PAWXY_HOLD_INTERVAL_SECONDS:-$VM_HOLD_INTERVAL_SECONDS} \
	  PAWXY_RUN_WAKE_HOLD=${PAWXY_RUN_WAKE_HOLD:-1} \
	  PAWXY_RUN_SCREEN_OFF=${PAWXY_RUN_SCREEN_OFF:-1} \
	  PAWXY_KEEP_SCREEN_OFF_DURING_HOLD=${PAWXY_KEEP_SCREEN_OFF_DURING_HOLD:-1} \
		  PAWXY_RUN_PARALLEL_BURST=${PAWXY_RUN_PARALLEL_BURST:-1} \
		  PAWXY_RUN_NOTIFICATION_DENIAL=${PAWXY_RUN_NOTIFICATION_DENIAL:-1} \
		  PAWXY_RUN_NETWORK_TOGGLE=${PAWXY_RUN_NETWORK_TOGGLE:-1} \
		  PAWXY_NETWORK_TOGGLE_MODE=${PAWXY_NETWORK_TOGGLE_MODE:-wifi,airplane} \
	  PAWXY_RUN_DOZE=${PAWXY_RUN_DOZE:-1} \
  PAWXY_RUN_APP_STANDBY=${PAWXY_RUN_APP_STANDBY:-1} \
  PAWXY_RUN_STANDBY_BUCKET=${PAWXY_RUN_STANDBY_BUCKET:-1} \
  PAWXY_RUN_BACKGROUND_RESTRICTION=${PAWXY_RUN_BACKGROUND_RESTRICTION:-1} \
  PAWXY_RUN_BATTERY_SAVER=${PAWXY_RUN_BATTERY_SAVER:-1} \
  sh "$DEVICE_SMOKE"

printf '%s\n' "pawxy android vm smoke ok"
