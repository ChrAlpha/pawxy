#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/test-android-vm.sh

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "scripts/test-android-vm.sh must exist"
sh -n "$SCRIPT"

tmp=${TMPDIR:-/tmp}/pawxy-android-vm-smoke-test.$$
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/bin-no-emulator" "$tmp/android-home/emulator" "$tmp/android-home/cmdline-tools/latest/bin" "$tmp/log-existing" "$tmp/log-existing-gsi-serial" "$tmp/log-avd" "$tmp/log-avd-wipe-data" "$tmp/log-avd-exits" "$tmp/log-avd-with-serial" "$tmp/log-missing-avd" "$tmp/log-avd-with-existing-device" "$tmp/log-avd-delayed-registration" "$tmp/log-sdk-emulator" "$tmp/log-sdk-tools" "$tmp/log-gsi" "$tmp/log-gsi-arch-match" "$tmp/log-gsi-arch-mismatch" "$tmp/log-gsi-dir" "$tmp/log-gsi-dir-missing" "$tmp/log-gsi-zip" "$tmp/log-missing-gsi" "$tmp/log-no-runtime" "$tmp/log-boot-timeout" "$tmp/log-invalid-adb-timeout" "$tmp/log-invalid-emulator-timeout" "$tmp/log-invalid-vm-flag"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cat > "$tmp/bin/adb" <<'ADB'
#!/bin/sh
log=$PAWXY_TEST_LOG/adb.log
boot=$PAWXY_TEST_LOG/boot-count
waited=$PAWXY_TEST_LOG/waited
device_polls=$PAWXY_TEST_LOG/device-polls
printf '%s\n' "$*" >> "$log"

if [ "${1:-}" = "-s" ]; then
  shift 2
fi

cmd=${1:-}
[ "$#" -gt 0 ] && shift || true
case "$cmd" in
  devices)
    count=0
    [ -f "$device_polls" ] && count=$(cat "$device_polls")
    count=$((count + 1))
    printf '%s\n' "$count" > "$device_polls"
    printf '%s\n\n' "List of devices attached"
    if [ "${PAWXY_TEST_NO_DEVICES:-0}" = "1" ]; then
      exit 0
    fi
    if [ -n "${PAWXY_AVD:-}" ] && [ ! -f "$PAWXY_TEST_LOG/emulator-started" ]; then
      if [ "${PAWXY_TEST_EXISTING_DEVICE_DURING_AVD:-0}" = "1" ]; then
        printf '%s\t%s\n' "FAKEPIXEL" "device"
      fi
      exit 0
    fi
    if [ "${PAWXY_TEST_EXISTING_DEVICE_DURING_AVD:-0}" = "1" ]; then
      printf '%s\t%s\n' "FAKEPIXEL" "device"
      if [ "${PAWXY_TEST_DELAY_NEW_EMULATOR_DEVICES:-0}" = "1" ] && [ "$count" -lt 3 ]; then
        exit 0
      fi
    fi
    printf '%s\t%s\n' "emulator-5554" "device"
    ;;
  get-state)
    printf '%s\n' "device"
    ;;
  wait-for-device)
    : > "$waited"
    exit 0
    ;;
  shell)
    line=$*
    case "$line" in
      *"getprop sys.boot_completed"*)
        count=0
        [ -f "$boot" ] && count=$(cat "$boot")
        count=$((count + 1))
        printf '%s\n' "$count" > "$boot"
        if [ "${PAWXY_TEST_BOOT_NEVER_COMPLETES:-0}" = "1" ]; then
          printf '%s\n' "0"
          exit 0
        fi
        if [ "$count" -ge 2 ]; then
          printf '%s\n' "1"
        fi
        ;;
      *"getprop dev.bootcomplete"*)
        printf '%s\n' "1"
        ;;
      *"getprop init.svc.bootanim"*)
        printf '%s\n' "stopped"
        ;;
      *"getprop ro.product.brand"*)
        printf '%s\n' "brand=google"
        printf '%s\n' "model=Android SDK built for x86_64"
        printf '%s\n' "sdk=35"
        printf '%s\n' "build=google/sdk_gphone64_x86_64/fake"
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  emu)
    [ "${1:-}" = "kill" ] || exit 0
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
ADB
chmod 755 "$tmp/bin/adb"

cat > "$tmp/bin/timeout" <<'TIMEOUT'
#!/bin/sh
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/timeout.log"
duration=$1
shift
exec "$@"
TIMEOUT
chmod 755 "$tmp/bin/timeout"

cat > "$tmp/bin/sdkmanager" <<'SDKMANAGER'
#!/bin/sh
exit 0
SDKMANAGER
chmod 755 "$tmp/bin/sdkmanager"

cat > "$tmp/bin/avdmanager" <<'AVDMANAGER'
#!/bin/sh
exit 0
AVDMANAGER
chmod 755 "$tmp/bin/avdmanager"

cat > "$tmp/bin/test-android-device.sh" <<'DEVICE'
#!/bin/sh
printf '%s\n' "$ANDROID_SERIAL" > "$PAWXY_TEST_LOG/device-serial"
printf '%s\n' "${PAWXY_HOLD_SECONDS:-}" > "$PAWXY_TEST_LOG/hold-seconds"
printf '%s\n' "${PAWXY_RUN_WAKE_HOLD:-}" > "$PAWXY_TEST_LOG/run-wake-hold"
printf '%s\n' "${PAWXY_RUN_SCREEN_OFF:-}" > "$PAWXY_TEST_LOG/run-screen-off"
printf '%s\n' "${PAWXY_KEEP_SCREEN_OFF_DURING_HOLD:-}" > "$PAWXY_TEST_LOG/keep-screen-off-during-hold"
printf '%s\n' "${PAWXY_RUN_PARALLEL_BURST:-}" > "$PAWXY_TEST_LOG/run-parallel-burst"
printf '%s\n' "${PAWXY_RUN_NOTIFICATION_DENIAL:-}" > "$PAWXY_TEST_LOG/run-notification-denial"
printf '%s\n' "${PAWXY_RUN_NETWORK_TOGGLE:-}" > "$PAWXY_TEST_LOG/run-network-toggle"
printf '%s\n' "${PAWXY_NETWORK_TOGGLE_MODE:-}" > "$PAWXY_TEST_LOG/network-toggle-mode"
printf '%s\n' "${PAWXY_RUN_DOZE:-}" > "$PAWXY_TEST_LOG/run-doze"
printf '%s\n' "${PAWXY_RUN_APP_STANDBY:-}" > "$PAWXY_TEST_LOG/run-app-standby"
printf '%s\n' "${PAWXY_RUN_STANDBY_BUCKET:-}" > "$PAWXY_TEST_LOG/run-standby-bucket"
printf '%s\n' "${PAWXY_RUN_BACKGROUND_RESTRICTION:-}" > "$PAWXY_TEST_LOG/run-background-restriction"
printf '%s\n' "${PAWXY_RUN_BATTERY_SAVER:-}" > "$PAWXY_TEST_LOG/run-battery-saver"
printf '%s\n' "device smoke invoked"
DEVICE
chmod 755 "$tmp/bin/test-android-device.sh"
ln -s "$tmp/bin/adb" "$tmp/bin-no-emulator/adb"
ln -s "$tmp/bin/timeout" "$tmp/bin-no-emulator/timeout"
ln -s "$tmp/bin/test-android-device.sh" "$tmp/bin-no-emulator/test-android-device.sh"

PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-existing" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -F -- "wait-for-device" "$tmp/log-existing/adb.log" >/dev/null \
  || fail "VM smoke must wait for an existing ADB device"
grep -F -- "120 $tmp/bin/adb -s emulator-5554 wait-for-device" "$tmp/log-existing/timeout.log" >/dev/null \
  || fail "VM smoke must bound adb wait-for-device with timeout"
grep -F -- "120 $tmp/bin/adb devices" "$tmp/log-existing/timeout.log" >/dev/null \
  || fail "VM smoke must bound adb device discovery with timeout"
grep -F -- "120 $tmp/bin/adb -s emulator-5554 shell getprop sys.boot_completed" "$tmp/log-existing/timeout.log" >/dev/null \
  || fail "VM smoke must bound boot property polling with timeout"
grep -F -- "getprop sys.boot_completed" "$tmp/log-existing/adb.log" >/dev/null \
  || fail "VM smoke must poll Android boot completion"
grep -Fx -- "emulator-5554" "$tmp/log-existing/device-serial" >/dev/null \
  || fail "VM smoke must pass the selected serial into the device smoke"
grep -Fx -- "300" "$tmp/log-existing/hold-seconds" >/dev/null \
  || fail "VM smoke must default to a longer persistence hold"
grep -Fx -- "1" "$tmp/log-existing/run-wake-hold" >/dev/null \
  || fail "VM smoke must default to wake-lock hold coverage"
grep -Fx -- "1" "$tmp/log-existing/run-screen-off" >/dev/null \
  || fail "VM smoke must default to screen-off persistence coverage"
grep -Fx -- "1" "$tmp/log-existing/keep-screen-off-during-hold" >/dev/null \
  || fail "VM smoke must default to keeping the screen off through the persistence hold"
grep -Fx -- "1" "$tmp/log-existing/run-parallel-burst" >/dev/null \
  || fail "VM smoke must default to parallel proxy burst coverage"
grep -Fx -- "1" "$tmp/log-existing/run-notification-denial" >/dev/null \
  || fail "VM smoke must default to notification-denial foreground-service coverage"
grep -Fx -- "1" "$tmp/log-existing/run-network-toggle" >/dev/null \
  || fail "VM smoke must default to network-toggle persistence coverage"
grep -Fx -- "wifi,airplane" "$tmp/log-existing/network-toggle-mode" >/dev/null \
  || fail "VM smoke must default to both Wi-Fi and airplane network-toggle modes"
grep -Fx -- "1" "$tmp/log-existing/run-doze" >/dev/null \
  || fail "VM smoke must default to Doze stress coverage"
grep -Fx -- "1" "$tmp/log-existing/run-app-standby" >/dev/null \
  || fail "VM smoke must default to App Standby stress coverage"
grep -Fx -- "1" "$tmp/log-existing/run-standby-bucket" >/dev/null \
  || fail "VM smoke must default to standby bucket stress coverage"
grep -Fx -- "1" "$tmp/log-existing/run-background-restriction" >/dev/null \
  || fail "VM smoke must default to background restriction stress coverage"
grep -Fx -- "1" "$tmp/log-existing/run-battery-saver" >/dev/null \
  || fail "VM smoke must default to battery saver stress coverage"

printf '%s\n' "already booted gsi" > "$tmp/existing-system.img"
PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  ANDROID_SERIAL=emulator-5554 \
  PAWXY_GSI_SYSTEM_IMG="$tmp/existing-system.img" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-existing-gsi-serial" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -Fx -- "emulator-5554" "$tmp/log-existing-gsi-serial/device-serial" >/dev/null \
  || fail "VM smoke must allow PAWXY_GSI_SYSTEM_IMG with an already booted ANDROID_SERIAL runtime"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_EMULATOR="$tmp/missing-emulator" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-no-runtime" \
  PAWXY_TEST_NO_DEVICES=1 \
  sh "$SCRIPT" >"$tmp/log-no-runtime/script.out" 2>"$tmp/log-no-runtime/script.err"; then
  fail "VM smoke must fail when neither a booted adb VM nor PAWXY_AVD is available"
fi
grep -F -- "runtime inventory: adb devices" "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke must print adb device inventory when no runtime is available"
grep -F -- "runtime inventory: emulator binary not found: $tmp/missing-emulator" "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke must explain when the Android emulator binary is missing"
grep -F -- "No booted Android VM/device was found" "$tmp/log-no-runtime/script.err" >/dev/null \
  || fail "VM smoke must explain that no booted Android VM/device was found"
grep -F -- "PAWXY_AVD=<avd_name> PAWXY_GSI_SYSTEM_IMG=/path/to/system.img" "$tmp/log-no-runtime/script.err" >/dev/null \
  || fail "VM smoke must show how to run a GSI system.img through an AVD"
grep -F -- 'runtime setup hint: sdkmanager "emulator" "system-images;android-35;google_apis;x86_64"' "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must show the SDK package install command"
grep -F -- 'runtime setup hint: echo "no" | avdmanager create avd -n pawxy-api35 -k "system-images;android-35;google_apis;x86_64" --device pixel_7' "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must show the AVD creation command"
grep -F -- "runtime setup hint: PAWXY_AVD=pawxy-api35 PAWXY_GSI_SYSTEM_IMG=/path/to/system.img scripts/test-android-vm.sh" "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must show the GSI rerun command"
grep -F -- "runtime setup hint: for Android Emulator, use an extracted x86_64 GSI system.img that matches the AVD ABI" "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must explain the GSI architecture expected by an x86_64 AVD"
grep -F -- "runtime setup hint: Pixel + Shizuku/rish: ANDROID_SERIAL=<pixel_serial> PAWXY_CONTROL_MODE=rish" "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must show the Pixel + Shizuku/rish rerun command"
grep -F -- "PAWXY_RISH_APPLICATION_ID=<authorized_package>" "$tmp/log-no-runtime/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must show how to select the Shizuku-authorized rish package"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-invalid-adb-timeout" \
  PAWXY_VM_ADB_TIMEOUT_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-invalid-adb-timeout/script.out" 2>"$tmp/log-invalid-adb-timeout/script.err"; then
  fail "VM smoke must reject invalid adb timeout settings before testing"
fi
grep -F -- "PAWXY_VM_ADB_TIMEOUT_SECONDS must be greater than zero" "$tmp/log-invalid-adb-timeout/script.err" >/dev/null \
  || fail "invalid VM adb timeout smoke must explain the rejected PAWXY_VM_ADB_TIMEOUT_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-invalid-emulator-timeout" \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_VM_EMULATOR_TIMEOUT_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-invalid-emulator-timeout/script.out" 2>"$tmp/log-invalid-emulator-timeout/script.err"; then
  fail "VM smoke must reject invalid emulator probe timeout settings before testing"
fi
grep -F -- "PAWXY_VM_EMULATOR_TIMEOUT_SECONDS must be greater than zero" "$tmp/log-invalid-emulator-timeout/script.err" >/dev/null \
  || fail "invalid VM emulator timeout smoke must explain the rejected PAWXY_VM_EMULATOR_TIMEOUT_SECONDS value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-invalid-vm-flag" \
  PAWXY_VM_WIPE_DATA=yes \
  sh "$SCRIPT" >"$tmp/log-invalid-vm-flag/script.out" 2>"$tmp/log-invalid-vm-flag/script.err"; then
  fail "VM smoke must reject invalid boolean VM launch flags before testing"
fi
grep -F -- "PAWXY_VM_WIPE_DATA must be 0 or 1" "$tmp/log-invalid-vm-flag/script.err" >/dev/null \
  || fail "invalid VM launch flag smoke must explain the rejected PAWXY_VM_WIPE_DATA value"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  ANDROID_SERIAL=FAKEPIXEL \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-avd-with-serial" \
  PAWXY_AVD=pawxy-api35 \
  sh "$SCRIPT" >"$tmp/log-avd-with-serial/script.out" 2>"$tmp/log-avd-with-serial/script.err"; then
  fail "VM smoke must reject ambiguous PAWXY_AVD plus ANDROID_SERIAL configuration"
fi
grep -F -- "PAWXY_AVD and ANDROID_SERIAL are mutually exclusive" "$tmp/log-avd-with-serial/script.err" >/dev/null \
  || fail "ambiguous VM runtime smoke must explain PAWXY_AVD and ANDROID_SERIAL are mutually exclusive"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-boot-timeout" \
  PAWXY_TEST_BOOT_NEVER_COMPLETES=1 \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=1 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-boot-timeout/script.out" 2>"$tmp/log-boot-timeout/script.err"; then
  fail "VM smoke must fail when Android boot never completes"
fi
grep -F -- "Android boot did not complete within 1s" "$tmp/log-boot-timeout/script.err" >/dev/null \
  || fail "VM smoke must report the boot timeout"
grep -F -- "collecting Android VM boot diagnostics" "$tmp/log-boot-timeout/script.out" >/dev/null \
  || fail "VM smoke must collect boot diagnostics on boot timeout"
grep -F -- "devices -l" "$tmp/log-boot-timeout/adb.log" >/dev/null \
  || fail "VM smoke boot diagnostics must include adb device state"
grep -F -- "getprop ro.build.fingerprint" "$tmp/log-boot-timeout/adb.log" >/dev/null \
  || fail "VM smoke boot diagnostics must include boot properties"
grep -F -- "logcat -d -t 200" "$tmp/log-boot-timeout/adb.log" >/dev/null \
  || fail "VM smoke boot diagnostics must include a logcat tail"

cat > "$tmp/android-home/emulator/emulator" <<'SDK_EMULATOR'
#!/bin/sh
if [ "${1:-}" = "-list-avds" ]; then
  printf '%s\n' "pawxy-api35"
  exit 0
fi
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/sdk-emulator.log"
: > "$PAWXY_TEST_LOG/emulator-started"
sleep 1
SDK_EMULATOR
chmod 755 "$tmp/android-home/emulator/emulator"

cat > "$tmp/android-home/cmdline-tools/latest/bin/sdkmanager" <<'SDKMANAGER_FALLBACK'
#!/bin/sh
exit 0
SDKMANAGER_FALLBACK
chmod 755 "$tmp/android-home/cmdline-tools/latest/bin/sdkmanager"

cat > "$tmp/android-home/cmdline-tools/latest/bin/avdmanager" <<'AVDMANAGER_FALLBACK'
#!/bin/sh
exit 0
AVDMANAGER_FALLBACK
chmod 755 "$tmp/android-home/cmdline-tools/latest/bin/avdmanager"

if PATH="$tmp/bin-no-emulator:/usr/bin:/bin" \
  ADB="$tmp/bin-no-emulator/adb" \
  ANDROID_HOME="$tmp/android-home" \
  PAWXY_EMULATOR="$tmp/missing-emulator" \
  PAWXY_DEVICE_SMOKE="$tmp/bin-no-emulator/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-sdk-tools" \
  PAWXY_TEST_NO_DEVICES=1 \
  sh "$SCRIPT" >"$tmp/log-sdk-tools/script.out" 2>"$tmp/log-sdk-tools/script.err"; then
  fail "VM smoke must fail when SDK tools exist but no runtime is available"
fi
grep -F -- "$tmp/android-home/cmdline-tools/latest/bin/sdkmanager \"emulator\" \"system-images;android-35;google_apis;x86_64\"" "$tmp/log-sdk-tools/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must discover sdkmanager under ANDROID_HOME"
grep -F -- "echo \"no\" | $tmp/android-home/cmdline-tools/latest/bin/avdmanager create avd" "$tmp/log-sdk-tools/script.out" >/dev/null \
  || fail "VM smoke no-runtime diagnostics must discover avdmanager under ANDROID_HOME"

PATH="$tmp/bin-no-emulator:$PATH" \
  ADB="$tmp/bin-no-emulator/adb" \
  ANDROID_HOME="$tmp/android-home" \
  PAWXY_DEVICE_SMOKE="$tmp/bin-no-emulator/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-sdk-emulator" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -F -- "@pawxy-api35" "$tmp/log-sdk-emulator/sdk-emulator.log" >/dev/null \
  || fail "VM smoke must discover emulator under ANDROID_HOME when it is not on PATH"
grep -F -- "30 $tmp/android-home/emulator/emulator -list-avds" "$tmp/log-sdk-emulator/timeout.log" >/dev/null \
  || fail "VM smoke must bound Android SDK emulator AVD listing with timeout"

cat > "$tmp/bin/emulator" <<'EMULATOR'
#!/bin/sh
if [ "${1:-}" = "-list-avds" ]; then
  printf '%s\n' "pawxy-api35"
  exit 0
fi
printf '%s\n' "$*" >> "$PAWXY_TEST_LOG/emulator.log"
printf '%s\n' "fake emulator output: $*" >&2
: > "$PAWXY_TEST_LOG/emulator-started"
if [ "${PAWXY_TEST_EMULATOR_EXIT_IMMEDIATELY:-0}" = "1" ]; then
  exit 42
fi
sleep 1
EMULATOR
chmod 755 "$tmp/bin/emulator"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-missing-avd" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=missing-avd \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-missing-avd/script.out" 2>"$tmp/log-missing-avd/script.err"; then
  fail "VM smoke must fail before launch when PAWXY_AVD is not installed"
fi
grep -F -- "PAWXY_AVD=missing-avd" "$tmp/log-missing-avd/script.err" >/dev/null \
  || fail "VM smoke must name the missing AVD in diagnostics"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-avd-exits" \
  PAWXY_TEST_EMULATOR_EXIT_IMMEDIATELY=1 \
  PAWXY_TEST_NO_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-avd-exits/script.out" 2>"$tmp/log-avd-exits/script.err"; then
  fail "VM smoke must fail fast when a launched emulator exits before adb registration"
fi
grep -F -- "emulator process exited before adb registration" "$tmp/log-avd-exits/script.err" >/dev/null \
  || fail "VM smoke must report early emulator exit before waiting for the full boot timeout"
grep -F -- "PAWXY_GSI_SYSTEM_IMG" "$tmp/log-avd-exits/script.err" >/dev/null \
  || fail "VM smoke early-exit diagnostics must mention GSI image selection"
grep -F -- "PAWXY_EMULATOR_ACCEL" "$tmp/log-avd-exits/script.err" >/dev/null \
  || fail "VM smoke early-exit diagnostics must mention emulator acceleration"
grep -F -- "emulator log tail:" "$tmp/log-avd-exits/script.out" >/dev/null \
  || fail "VM smoke early-exit diagnostics must print the emulator output log tail"
grep -F -- "fake emulator output:" "$tmp/log-avd-exits/script.out" >/dev/null \
  || fail "VM smoke early-exit diagnostics must include captured emulator output"
if grep -F -- "wait-for-device" "$tmp/log-avd-exits/adb.log" >/dev/null; then
  fail "VM smoke must not wait for adb registration before checking whether the launched emulator exited"
fi

PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-avd" \
  PAWXY_VM_EMULATOR_LOG="$tmp/log-avd/emulator-output.log" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -F -- "@pawxy-api35" "$tmp/log-avd/emulator.log" >/dev/null \
  || fail "VM smoke must launch the requested AVD when PAWXY_AVD is set"
grep -F -- "30 emulator -list-avds" "$tmp/log-avd/timeout.log" >/dev/null \
  || fail "VM smoke must bound emulator AVD listing with timeout"
grep -F -- "-no-window" "$tmp/log-avd/emulator.log" >/dev/null \
  || fail "VM smoke must launch AVDs headlessly by default"
grep -F -- "-no-snapshot" "$tmp/log-avd/emulator.log" >/dev/null \
  || fail "VM smoke must launch AVDs without snapshot reuse by default"
grep -F -- "-accel off" "$tmp/log-avd/emulator.log" >/dev/null \
  || fail "VM smoke must fall back to software acceleration when /dev/kvm is unavailable"
grep -F -- "fake emulator output:" "$tmp/log-avd/emulator-output.log" >/dev/null \
  || fail "VM smoke must capture emulator stdout and stderr in PAWXY_VM_EMULATOR_LOG"
grep -F -- "emu kill" "$tmp/log-avd/adb.log" >/dev/null \
  || fail "VM smoke must stop a launched emulator during cleanup"

PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-avd-wipe-data" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_VM_WIPE_DATA=1 \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -F -- "-wipe-data" "$tmp/log-avd-wipe-data/emulator.log" >/dev/null \
  || fail "VM smoke must support opt-in AVD user-data wiping for clean GSI runs"

PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-avd-with-existing-device" \
  PAWXY_TEST_EXISTING_DEVICE_DURING_AVD=1 \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -Fx -- "emulator-5554" "$tmp/log-avd-with-existing-device/device-serial" >/dev/null \
  || fail "VM smoke must select the newly launched emulator when another adb device is already connected"

PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-avd-delayed-registration" \
  PAWXY_TEST_EXISTING_DEVICE_DURING_AVD=1 \
  PAWXY_TEST_DELAY_NEW_EMULATOR_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -Fx -- "emulator-5554" "$tmp/log-avd-delayed-registration/device-serial" >/dev/null \
  || fail "VM smoke must wait for the newly launched emulator when adb wait-for-device returns for an existing Pixel"

if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-missing-gsi" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_GSI_SYSTEM_IMG="$tmp/missing system.img" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-missing-gsi/script.out" 2>"$tmp/log-missing-gsi/script.err"; then
  fail "VM smoke must fail before launch when PAWXY_GSI_SYSTEM_IMG does not exist"
fi
grep -F -- "PAWXY_GSI_SYSTEM_IMG does not exist: $tmp/missing system.img" "$tmp/log-missing-gsi/script.err" >/dev/null \
  || fail "VM smoke must name the missing GSI system image in diagnostics"

missing_gsi_dir="$tmp/gsi-assets/missing-system-dir"
mkdir -p "$missing_gsi_dir"
if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-gsi-dir-missing" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_GSI_SYSTEM_IMG="$missing_gsi_dir" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-gsi-dir-missing/script.out" 2>"$tmp/log-gsi-dir-missing/script.err"; then
  fail "VM smoke must fail before launch when a supplied GSI directory has no system.img"
fi
grep -F -- "PAWXY_GSI_SYSTEM_IMG directory does not contain system.img: $missing_gsi_dir" "$tmp/log-gsi-dir-missing/script.err" >/dev/null \
  || fail "VM smoke must explain when a supplied GSI directory has no system.img"

gsi_zip="$tmp/gsi-assets/gsi.zip"
printf '%s\n' "fake zipped gsi" > "$gsi_zip"
if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-gsi-zip" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_GSI_SYSTEM_IMG="$gsi_zip" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-gsi-zip/script.out" 2>"$tmp/log-gsi-zip/script.err"; then
  fail "VM smoke must fail before launch when PAWXY_GSI_SYSTEM_IMG points to a zip archive"
fi
grep -F -- "PAWXY_GSI_SYSTEM_IMG must point to an extracted system.img, not a zip archive: $gsi_zip" "$tmp/log-gsi-zip/script.err" >/dev/null \
  || fail "VM smoke must tell users to pass an extracted GSI system.img instead of a zip archive"

avd_home="$tmp/avd-home"
mkdir -p "$avd_home/pawxy-api35.avd"
printf '%s\n' "abi.type=x86_64" > "$avd_home/pawxy-api35.avd/config.ini"

arm64_gsi_dir="$tmp/gsi-assets/aosp_arm64"
mkdir -p "$arm64_gsi_dir"
printf '%s\n' "fake arm64 gsi" > "$arm64_gsi_dir/system.img"
if PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  ANDROID_AVD_HOME="$avd_home" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-gsi-arch-mismatch" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_GSI_SYSTEM_IMG="$arm64_gsi_dir" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >"$tmp/log-gsi-arch-mismatch/script.out" 2>"$tmp/log-gsi-arch-mismatch/script.err"; then
  fail "VM smoke must fail before launch when an ARM64 GSI is paired with an x86_64 AVD"
fi
grep -F -- "PAWXY_GSI_SYSTEM_IMG appears to be arm64 but PAWXY_AVD=pawxy-api35 appears to be x86_64" "$tmp/log-gsi-arch-mismatch/script.err" >/dev/null \
  || fail "VM smoke must explain obvious GSI and AVD architecture mismatches"

x86_64_gsi_dir="$tmp/gsi-assets/aosp_x86_64"
mkdir -p "$x86_64_gsi_dir"
printf '%s\n' "fake x86_64 gsi" > "$x86_64_gsi_dir/system.img"
PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  ANDROID_AVD_HOME="$avd_home" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-gsi-arch-match" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_GSI_SYSTEM_IMG="$x86_64_gsi_dir" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -F -- "-system $x86_64_gsi_dir/system.img" "$tmp/log-gsi-arch-match/emulator.log" >/dev/null \
  || fail "VM smoke must allow an x86_64 GSI to launch with an x86_64 AVD config"

gsi_with_space="$tmp/gsi-assets/system test.img"
mkdir -p "$tmp/gsi-assets"
printf '%s\n' "fake gsi" > "$gsi_with_space"
PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-gsi" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_GSI_SYSTEM_IMG="$gsi_with_space" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -F -- "-system $gsi_with_space" "$tmp/log-gsi/emulator.log" >/dev/null \
  || fail "VM smoke must be able to launch an AVD with a supplied GSI system.img path containing spaces"

gsi_dir_with_space="$tmp/gsi-assets/extracted gsi"
mkdir -p "$gsi_dir_with_space"
printf '%s\n' "fake gsi" > "$gsi_dir_with_space/system.img"
PATH="$tmp/bin:$PATH" \
  ADB="$tmp/bin/adb" \
  PAWXY_DEVICE_SMOKE="$tmp/bin/test-android-device.sh" \
  PAWXY_TEST_LOG="$tmp/log-gsi-dir" \
  PAWXY_TEST_REQUIRE_WAIT_BEFORE_DEVICES=1 \
  PAWXY_AVD=pawxy-api35 \
  PAWXY_GSI_SYSTEM_IMG="$gsi_dir_with_space" \
  PAWXY_VM_BOOT_TIMEOUT_SECONDS=5 \
  PAWXY_VM_BOOT_INTERVAL_SECONDS=0 \
  sh "$SCRIPT" >/dev/null

grep -F -- "-system $gsi_dir_with_space/system.img" "$tmp/log-gsi-dir/emulator.log" >/dev/null \
  || fail "VM smoke must accept an extracted GSI directory containing system.img"

printf '%s\n' "android vm smoke mock ok"
