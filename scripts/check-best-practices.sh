#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

contains() {
  file=$1
  text=$2
  grep -F -- "$text" "$file" >/dev/null 2>&1
}

not_contains() {
  file=$1
  text=$2
  ! grep -F -- "$text" "$file" >/dev/null 2>&1
}

MANIFEST=$ROOT/android/app/src/main/AndroidManifest.xml
SERVICE=$ROOT/android/app/src/main/java/dev/pawxy/ProxyService.kt
PROVIDER=$ROOT/android/app/src/main/java/dev/pawxy/StatusProvider.kt
CONTROL_TOKEN=$ROOT/android/app/src/main/java/dev/pawxy/ControlToken.kt
CTL=$ROOT/scripts/pawxyctl
CTL_TEST=$ROOT/scripts/test-pawxyctl.sh
ANDROID_PACKAGE=$ROOT/scripts/package-android.sh
ANDROID_PACKAGE_TEST=$ROOT/scripts/test-package-android.sh
ADB_INSTALLER=$ROOT/scripts/install-apk-adb.sh
ADB_INSTALLER_TEST=$ROOT/scripts/test-install-apk-adb.sh
INSTALLER=$ROOT/scripts/install-android.sh
ANDROID_BUILD=$ROOT/scripts/build-android.sh
APK_COMPAT=$ROOT/scripts/check-android-apk-compat.sh
PKG=dev.pawxy
DEVICE_SMOKE=$ROOT/scripts/test-android-device.sh
DEVICE_SMOKE_TEST=$ROOT/scripts/test-android-device-mock.sh
DEVICE_VM_SMOKE=$ROOT/scripts/test-android-vm.sh
DEVICE_VM_SMOKE_TEST=$ROOT/scripts/test-android-vm-mock.sh
PUBLIC_READINESS=$ROOT/scripts/test-public-readiness.sh
BEST_PRACTICES=$ROOT/docs/best-practices.md
README=$ROOT/README.md

contains "$MANIFEST" "android.permission.ACCESS_NETWORK_STATE" \
  || fail "Android service must declare ACCESS_NETWORK_STATE for default-network observation"

service_manifest_block=$(awk '
  /<service/ { inside = 1 }
  inside {
    print
    if ($0 ~ /<\/service>/) exit
  }
' "$MANIFEST")
printf '%s\n' "$service_manifest_block" | grep -F 'android:permission="android.permission.DUMP"' >/dev/null 2>&1 \
  || fail "Exported ProxyService must require android.permission.DUMP so third-party apps cannot claim the first control token"
printf '%s\n' "$service_manifest_block" | grep -F 'dev.pawxy.action.RESET_TOKEN' >/dev/null 2>&1 \
  || fail "ProxyService manifest must expose the DUMP-protected reset-token recovery action"

provider_manifest_block=$(awk '
  /<provider/ { inside = 1 }
  inside {
    print
    if ($0 ~ /\/>/ || $0 ~ /<\/provider>/) exit
  }
' "$MANIFEST")
printf '%s\n' "$provider_manifest_block" | grep -F 'android:permission="android.permission.DUMP"' >/dev/null 2>&1 \
  || fail "Exported StatusProvider must require android.permission.DUMP in addition to token authorization"

contains "$SERVICE" "registerDefaultNetworkCallback" \
  || fail "ProxyService must register a default-network callback"
contains "$SERVICE" "unregisterNetworkCallback" \
  || fail "ProxyService must unregister the default-network callback"
contains "$SERVICE" "ConnectivityManager.NetworkCallback" \
  || fail "ProxyService must observe default network changes without binding sockets"

for field in network_available network_transport network_generation; do
  contains "$PROVIDER" "$field" || fail "StatusProvider must expose $field"
  contains "$CTL" "$field" || fail "pawxyctl status/doctor must surface $field"
done
for field in native_running native_listen native_lan native_auth_enabled native_started_at_unix_ms; do
  contains "$PROVIDER" "$field" || fail "StatusProvider must expose $field from native runtime status"
done
for field in configured_listen configured_lan configured_auth_enabled; do
  contains "$PROVIDER" "$field" || fail "StatusProvider must expose persisted $field without masking native runtime status"
done
not_contains "$PROVIDER" '.put("listen", prefs' \
  || fail "StatusProvider must not mask the native listen endpoint with persisted prefs"
not_contains "$PROVIDER" '.put("lan", prefs' \
  || fail "StatusProvider must not mask the native LAN flag with persisted prefs"
not_contains "$PROVIDER" '.put("auth_enabled",' \
  || fail "StatusProvider must not mask native auth_enabled with persisted prefs"

not_contains "$CTL" "eval " \
  || fail "pawxyctl must not use eval to build am commands"
not_contains "$CTL" "date +%s" \
  || fail "pawxyctl token generation must fail closed instead of using timestamp fallback"

[ -f "$ROOT/android/gradlew" ] \
  || fail "Android project must include android/gradlew for one-command builds"
[ -f "$ROOT/android/gradle/wrapper/gradle-wrapper.properties" ] \
  || fail "Android project must include gradle-wrapper.properties"
[ -f "$ROOT/android/gradle/wrapper/gradle-wrapper.jar" ] \
  || fail "Android project must include gradle-wrapper.jar"

[ -f "$INSTALLER" ] || fail "Android install-and-start script must exist"
[ -f "$ANDROID_PACKAGE" ] || fail "Android package assembly script must exist"
[ -f "$ANDROID_PACKAGE_TEST" ] || fail "Android package assembly mock test must exist"
[ -f "$ADB_INSTALLER" ] || fail "Android adb debug install script must exist"
[ -f "$ADB_INSTALLER_TEST" ] || fail "Android adb debug install mock test must exist"
[ -f "$ANDROID_BUILD" ] || fail "Android build script must exist"
[ -f "$APK_COMPAT" ] || fail "Android APK compatibility gate must exist"
contains "$ANDROID_BUILD" "max-page-size=16384" \
  || fail "Android JNI build must explicitly request 16 KB ELF LOAD segment alignment"
contains "$ANDROID_BUILD" "common-page-size=16384" \
  || fail "Android JNI build must explicitly request 16 KB common page alignment"
contains "$APK_COMPAT" "-c -P 16 -v 4" \
  || fail "Android APK compatibility gate must verify 16 KB APK zip alignment"
contains "$APK_COMPAT" "llvm-objdump" \
  || fail "Android APK compatibility gate must inspect native ELF LOAD segment alignment"
contains "$APK_COMPAT" "targetSdkVersion:'35'" \
  || fail "Android APK compatibility gate must verify targetSdkVersion for Pixel/Android 15 behavior"
contains "$APK_COMPAT" "PROPERTY_SPECIAL_USE_FGS_SUBTYPE" \
  || fail "Android APK compatibility gate must verify the specialUse foreground-service subtype"
contains "$APK_COMPAT" "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'" \
  || fail "Android APK compatibility gate must verify packaged native ABI badging"
contains "$APK_COMPAT" "android.permission.DUMP" \
  || fail "Android APK compatibility gate must verify DUMP-protected control components"
contains "$APK_COMPAT" "dev.pawxy.action.RESET_TOKEN" \
  || fail "Android APK compatibility gate must verify reset-token action packaging"
contains "$ANDROID_PACKAGE" "SHA256SUMS" \
  || fail "Android package script must write SHA256SUMS"
contains "$ANDROID_PACKAGE" 'sha256sum "$apk_name" pawxyctl > SHA256SUMS' \
  || fail "Android package script must checksum only APK and pawxyctl install inputs"
contains "$ANDROID_PACKAGE" "refusing unsafe PAWXY_DIST_DIR" \
  || fail "Android package script must reject unsafe output directories before rm -rf"
contains "$ANDROID_PACKAGE" "refusing output directory without a pawxy/dist name" \
  || fail "Android package script must reject broad arbitrary output directories"
contains "$ANDROID_PACKAGE_TEST" "unsafe PAWXY_DIST_DIR" \
  || fail "Android package mock test must cover unsafe output directory rejection"
contains "$ANDROID_PACKAGE_TEST" "pawxy-named output directories" \
  || fail "Android package mock test must cover explicit safe output directories"
contains "$ANDROID_PACKAGE" "install-android.sh" \
  || fail "Android package script must include the installer as a release asset"
contains "$ANDROID_PACKAGE_TEST" "must not checksum install-android.sh itself" \
  || fail "Android package mock test must prevent installer self-checksum drift"
contains "$ADB_INSTALLER" "PAWXY_ADB_TIMEOUT_SECONDS" \
  || fail "Android adb debug installer must bound adb operations"
contains "$ADB_INSTALLER" "ANDROID_SERIAL" \
  || fail "Android adb debug installer must honor an explicit ANDROID_SERIAL"
contains "$ADB_INSTALLER" "select_device" \
  || fail "Android adb debug installer must select exactly one adb device before installing"
contains "$ADB_INSTALLER" "get-state" \
  || fail "Android adb debug installer must validate explicit ANDROID_SERIAL state"
contains "$ADB_INSTALLER" "expected exactly one adb device or ANDROID_SERIAL" \
  || fail "Android adb debug installer must fail clearly when zero or multiple adb devices are connected"
contains "$ADB_INSTALLER" "verify_android_shell_permissions" \
  || fail "Android adb debug installer must preflight adb/Shizuku shell privileges"
contains "$ADB_INSTALLER" "pm check-permission android.permission.DUMP com.android.shell" \
  || fail "Android adb debug installer must verify shell DUMP permission before install"
contains "$ADB_INSTALLER" "verify_package_installed" \
  || fail "Android adb debug installer must verify package visibility after adb install"
contains "$ADB_INSTALLER" "pm path dev.pawxy" \
  || fail "Android adb debug installer must use pm path to confirm the installed package"
contains "$ADB_INSTALLER" "PAWXY_HOME=\$DEVICE_HOME \$DEVICE_CTL start" \
  || fail "Android adb debug installer must start Pawxy through the pushed pawxyctl"
contains "$ADB_INSTALLER" "wait_for_running_status" \
  || fail "Android adb debug installer must verify Pawxy status after starting"
contains "$ADB_INSTALLER" "native_running" \
  || fail "Android adb debug installer must verify the native proxy is running after install"
contains "$ADB_INSTALLER" "stop_started_service" \
  || fail "Android adb debug installer must stop Pawxy when startup verification fails"
contains "$ADB_INSTALLER" "json_string_field \"\$status_json_text\" last_error" \
  || fail "Android adb debug installer startup failures must surface native last_error fields"
contains "$ADB_INSTALLER" "rish -c 'PAWXY_HOME=/data/local/tmp/pawxy /data/local/tmp/pawxyctl start'" \
  || fail "Android adb debug installer must print Shizuku/rish control examples"
contains "$ADB_INSTALLER" "RISH_APPLICATION_ID=com.termux" \
  || fail "Android adb debug installer must print a terminal-exported Shizuku rish example"
contains "$ADB_INSTALLER_TEST" "PAWXY_TEST_SHELL_UID=10000" \
  || fail "Android adb debug installer mock must cover app-like uid rejection"
contains "$ADB_INSTALLER_TEST" "PAWXY_TEST_DUMP_PERMISSION=denied" \
  || fail "Android adb debug installer mock must cover missing shell DUMP permission"
contains "$ADB_INSTALLER_TEST" "PAWXY_TEST_PM_PATH_MISSING=1" \
  || fail "Android adb debug installer mock must cover package visibility failures after install"
contains "$ADB_INSTALLER_TEST" "Installed and started Pawxy." \
  || fail "Android adb debug installer mock must assert install-and-start output"
contains "$ADB_INSTALLER_TEST" "terminal-exported Shizuku rish example" \
  || fail "Android adb debug installer mock must assert RISH_APPLICATION_ID example output"
contains "$ADB_INSTALLER_TEST" "did not report running=true/native_running=true after adb install" \
  || fail "Android adb debug installer mock must cover native runtime status failures"
contains "$ADB_INSTALLER_TEST" "status error=bind preflight failed" \
  || fail "Android adb debug installer mock must cover native last_error diagnostics"
contains "$ADB_INSTALLER_TEST" "status failure must stop Pawxy after failed startup verification" \
  || fail "Android adb debug installer mock must assert cleanup after startup verification failures"
contains "$ADB_INSTALLER_TEST" "start failure must stop Pawxy after partial startup" \
  || fail "Android adb debug installer mock must assert cleanup after partial start failures"
contains "$ADB_INSTALLER_TEST" "PAWXY_TEST_DEVICE_COUNT=0" \
  || fail "Android adb debug installer mock must cover no-device diagnostics"
contains "$ADB_INSTALLER_TEST" "PAWXY_TEST_DEVICE_COUNT=2" \
  || fail "Android adb debug installer mock must cover multiple-device diagnostics"
contains "$ADB_INSTALLER_TEST" "PAWXY_TEST_BAD_SERIAL=1" \
  || fail "Android adb debug installer mock must cover bad ANDROID_SERIAL diagnostics"
contains "$INSTALLER" "pm install -r" \
  || fail "Android installer must install the APK with pm install -r"
contains "$INSTALLER" "verify_package_installed" \
  || fail "Android installer must verify package visibility after install"
contains "$INSTALLER" "pm path \"\$PKG\"" \
  || fail "Android installer must use pm path to confirm the installed package"
contains "$INSTALLER" "sha256sum -c" \
  || fail "Android installer must verify release downloads"
contains "$INSTALLER" '"$INSTALL_DIR/$CTL" start' \
  || fail "Android installer must start through installed pawxyctl"
contains "$INSTALLER" '"$INSTALL_DIR/$CTL" status --json' \
  || fail "Android installer must verify status after starting Pawxy"
contains "$INSTALLER" "json_bool_field" \
  || fail "Android installer must parse status JSON booleans without depending on compact formatting"
contains "$INSTALLER" "json_string_field" \
  || fail "Android installer must parse status JSON error strings for startup diagnostics"
contains "$INSTALLER" "wait_for_running_status" \
  || fail "Android installer must wait for Pawxy to report running after start"
contains "$INSTALLER" "stop_started_service" \
  || fail "Android installer must stop Pawxy when startup verification fails"
contains "$INSTALLER" "PAWXY_STARTUP_RETRIES" \
  || fail "Android installer startup wait must be configurable"
contains "$INSTALLER" "running=true after start" \
  || fail "Android installer must fail when Pawxy does not report running after start"
contains "$INSTALLER" "native_running" \
  || fail "Android installer must verify the native proxy is running after start"
contains "$INSTALLER" "native_auth_enabled" \
  || fail "Android installer must verify native auth state after default start"
contains "$INSTALLER" "configured_auth_enabled" \
  || fail "Android installer must verify persisted auth state after default start"
contains "$INSTALLER" "status error=" \
  || fail "Android installer startup failures must surface status error fields"
contains "$INSTALLER" "json_string_field last_error" \
  || fail "Android installer startup failures must surface native last_error fields"
contains "$INSTALLER" "POST_NOTIFICATIONS" \
  || fail "Android installer must opportunistically grant notification permission for no-UI installs"
contains "$INSTALLER" "verify_android_shell_permissions" \
  || fail "Android installer must preflight adb/Shizuku shell privileges before install/start"
contains "$INSTALLER" "id -u" \
  || fail "Android installer must reject app-like shells before install/start"
contains "$INSTALLER" "pm check-permission android.permission.DUMP com.android.shell" \
  || fail "Android installer must verify shell DUMP permission before starting Pawxy"
contains "$INSTALLER" "Run through adb shell or Shizuku/rish" \
  || fail "Android installer shell-preflight failures must tell users to run through adb shell or Shizuku/rish"
contains "$INSTALLER" "PAWXY_GITHUB_TOKEN" \
  || fail "Android installer must support private release token downloads"
contains "$INSTALLER" "PAWXY_ASSET_DIR" \
  || fail "Android installer must support local release assets for Shizuku/rish shells"
contains "$INSTALLER" "PAWXY_HOME=\$PAWXY_HOME \$INSTALL_DIR/\$CTL status" \
  || fail "Android installer output must show stable PAWXY_HOME control commands"
contains "$ROOT/scripts/test-install-android.sh" "PAWXY_TEST_SHELL_UID=10000" \
  || fail "Android installer mock test must cover app-like uid rejection"
contains "$ROOT/scripts/test-install-android.sh" "PAWXY_TEST_DUMP_PERMISSION=denied" \
  || fail "Android installer mock test must cover missing shell DUMP permission"
contains "$ROOT/scripts/test-install-android.sh" "PAWXY_TEST_PM_PATH_MISSING=1" \
  || fail "Android installer mock test must cover package visibility failures after install"
contains "$ROOT/scripts/test-install-android.sh" "status error=unauthorized" \
  || fail "Android installer mock test must cover provider/status error diagnostics"
contains "$ROOT/scripts/test-install-android.sh" "status error=bind preflight failed" \
  || fail "Android installer mock test must cover native last_error diagnostics"
contains "$ROOT/scripts/test-install-android.sh" "status failure must stop Pawxy after failed startup verification" \
  || fail "Android installer mock test must assert cleanup after startup verification failures"
contains "$ROOT/scripts/test-install-android.sh" "start failure must stop Pawxy after partial startup" \
  || fail "Android installer mock test must assert cleanup after partial start failures"
contains "$ROOT/scripts/test-install-android.sh" "wrapper status reports running but native proxy is not running" \
  || fail "Android installer mock test must fail when wrapper status masks a stopped native runtime"
contains "$ROOT/scripts/test-install-android.sh" "did not report running=true/native_running=true" \
  || fail "Android installer mock test must explain missing native_running startup status"
contains "$ROOT/scripts/test-install-android.sh" "stable PAWXY_HOME control commands" \
  || fail "Android installer mock test must assert stable PAWXY_HOME output"
contains "$CTL" "shell uid:" \
  || fail "pawxyctl doctor must show the Android shell uid"
contains "$CTL" "shell DUMP permission:" \
  || fail "pawxyctl doctor must show whether com.android.shell has DUMP permission"
contains "$CTL_TEST" "PAWXY_TEST_DUMP_PERMISSION=denied" \
  || fail "pawxyctl mock test must cover missing shell DUMP permission diagnostics"
contains "$CTL" "Shizuku/rish behaves like adb shell" \
  || fail "pawxyctl doctor must document Shizuku/rish shell semantics"
contains "$CTL" "[[:space:]]*:[[:space:]]*" \
  || fail "pawxyctl status parser must tolerate whitespace around JSON separators"
contains "$CTL" "state=unknown" \
  || fail "pawxyctl status must not report stopped when status lacks a running field"
contains "$CTL" "status_error" \
  || fail "pawxyctl status must surface provider/status JSON error messages"
contains "$CTL" "native: running=" \
  || fail "pawxyctl status/doctor must print native runtime state for Shizuku/rish diagnostics"
contains "$CTL" "configured: listen=" \
  || fail "pawxyctl status/doctor must print persisted configured state for drift diagnostics"
contains "$CTL" "native_started_at_unix_ms" \
  || fail "pawxyctl status/doctor must expose native started_at for restart diagnostics"
contains "$CTL" "query_status_json" \
  || fail "pawxyctl status must be able to retry status after token synchronization"
contains "$CTL" "content query failed" \
  || fail "pawxyctl status must distinguish content-provider query failures from empty status output"
contains "$CTL" "print_status_json" \
  || fail "pawxyctl doctor must reuse one status query for efficient Shizuku/rish diagnostics"
contains "$CTL" "is_hex_len" \
  || fail "pawxyctl must validate persisted token and LAN password shape before reuse"
contains "$CTL" "chmod 600" \
  || fail "pawxyctl must keep token and LAN password files private when possible"
contains "$CTL" "failed to start LAN sharing" \
  || fail "pawxyctl share on must fail closed when Android service start fails"
contains "$CTL" "failed to disable LAN sharing" \
  || fail "pawxyctl share off must fail closed when Android service start fails"
contains "$CTL" "failed to start proxy" \
  || fail "pawxyctl start must fail closed when Android service start fails"
contains "$CTL" "am start-foreground-service \\" \
  || fail "pawxyctl start/restart/share controls must use foreground-service startup"
contains "$CTL" '--es password "$password" || return 1' \
  || fail "pawxyctl authenticated starts must fail immediately when am service start fails"
contains "$CTL" "--el idle_timeout_ms 1800000 || return 1" \
  || fail "pawxyctl unauthenticated starts must fail immediately when am service start fails"
contains "$CTL" "failed to stop proxy" \
  || fail "pawxyctl stop must fail closed when Android service stop fails"
contains "$CTL" "failed to restart proxy" \
  || fail "pawxyctl restart must fail closed when Android service restart fails"
contains "$CTL" "failed to enable wake lock" \
  || fail "pawxyctl wake on must fail closed when Android service wake action fails"
contains "$CTL" "failed to disable wake lock" \
  || fail "pawxyctl wake off must fail closed when Android service wake action fails"
contains "$CTL" "reset-token" \
  || fail "pawxyctl must expose a reset-token recovery command for adb/Shizuku token mismatch"
contains "$CTL" "dev.pawxy.action.RESET_TOKEN" \
  || fail "pawxyctl reset-token must use the DUMP-protected Android reset-token action"
contains "$CTL" "am startservice -n \"\$SERVICE\" -a \"\$ACTION_RESET_TOKEN\"" \
  || fail "pawxyctl reset-token must avoid foreground-service startup for token-only recovery"
not_contains "$CTL" "am start-foreground-service -n \"\$SERVICE\" -a \"\$ACTION_RESET_TOKEN\"" \
  || fail "pawxyctl reset-token must not enter foreground-service startup for token-only recovery"
contains "$CTL" "wait_for_status_key running reset-token" \
  || fail "pawxyctl reset-token must verify provider authorization after sending the reset action"
contains "$CTL" "control token reset did not restore status authorization" \
  || fail "pawxyctl reset-token must fail clearly when provider authorization remains unavailable"
contains "$CTL" "sync_control_token" \
  || fail "pawxyctl control actions must synchronize the token before sending start/stop/wake commands"
contains "$CTL" "wait_for_token_authorized" \
  || fail "pawxyctl token synchronization must wait until the provider accepts the reset token"
contains "$CTL" "wait_for_start_status" \
  || fail "pawxyctl start/restart/share commands must wait for provider status after service intents"
contains "$CTL" "wait_for_stop_status" \
  || fail "pawxyctl stop must wait for a combined stopped provider status"
contains "$CTL" "am startservice -n \"\$SERVICE\" -a \"\$action\"" \
  || fail "pawxyctl stop/wake short controls must avoid foreground-service startup"
contains "$CTL" "PAWXY_STARTUP_RETRIES" \
  || fail "pawxyctl status waits must expose configurable retries for slow Pixel/Shizuku starts"
contains "$CTL" 'running" = "true"' \
  || fail "pawxyctl start/restart/share commands must wait for running=true"
contains "$CTL" 'native_running" = "true"' \
  || fail "pawxyctl start/restart/share commands must wait for native_running=true"
contains "$CTL" 'running" = "false"' \
  || fail "pawxyctl stop must wait for running=false"
contains "$CTL" 'native_running" = "false"' \
  || fail "pawxyctl stop must wait for native_running=false"
contains "$CTL" 'auth_enabled" = "$expected_auth"' \
  || fail "pawxyctl share mode changes must wait for the requested auth state"
contains "$CTL" 'native_auth_enabled" = "$expected_auth"' \
  || fail "pawxyctl share mode changes must wait for native auth state"
contains "$CTL" 'configured_auth_enabled" = "$expected_auth"' \
  || fail "pawxyctl share mode changes must wait for persisted accepted auth state"
contains "$CTL" "wait_for_wake_status" \
  || fail "pawxyctl wake commands must wait for combined wake/native status"
contains "$CTL" 'wake_lock_enabled" = "$expected_wake"' \
  || fail "pawxyctl wake commands must wait for the requested wake-lock state"
[ -f "$CTL_TEST" ] || fail "pawxyctl mock test must exist"
contains "$CTL_TEST" "{ \"running\" : true" \
  || fail "pawxyctl mock test must cover spaced status JSON"
contains "$CTL_TEST" "status must surface native runtime state" \
  || fail "pawxyctl mock test must cover human-readable native runtime diagnostics"
contains "$CTL_TEST" "doctor must surface persisted configured state" \
  || fail "pawxyctl mock test must cover doctor configured-state diagnostics"
contains "$CTL_TEST" "PAWXY_TEST_STATUS_JSON" \
  || fail "pawxyctl mock test must cover provider status error JSON"
contains "$CTL_TEST" "PAWXY_TEST_STATUS_UNAUTHORIZED_ONCE" \
  || fail "pawxyctl mock test must cover status token synchronization after unauthorized"
contains "$CTL_TEST" "status must synchronize the control token when the provider reports unauthorized" \
  || fail "pawxyctl mock test must assert status token synchronization"
contains "$CTL_TEST" "status unavailable" \
  || fail "pawxyctl mock test must cover unavailable provider status diagnostics"
contains "$CTL_TEST" "PAWXY_TEST_CONTENT_FAIL" \
  || fail "pawxyctl mock test must cover content-provider query failures"
contains "$CTL_TEST" "doctor must query status once" \
  || fail "pawxyctl mock test must cover single-query doctor diagnostics"
contains "$CTL_TEST" "bad/token value" \
  || fail "pawxyctl mock test must cover invalid persisted control-token repair"
contains "$CTL_TEST" "LAN_PASSWORD=a" \
  || fail "pawxyctl mock test must cover weak persisted LAN password repair"
contains "$CTL_TEST" "PAWXY_TEST_AM_FAIL" \
  || fail "pawxyctl mock test must cover Android am command failures"
contains "$CTL_TEST" "pawxyctl start must explain the failed proxy start" \
  || fail "pawxyctl mock test must cover start failure diagnostics"
contains "$CTL_TEST" "pawxyctl wake off must explain the failed wake-lock disable" \
  || fail "pawxyctl mock test must cover wake failure diagnostics"
contains "$CTL_TEST" "reset-token" \
  || fail "pawxyctl mock test must cover reset-token control recovery"
contains "$CTL_TEST" "reset-token must verify the status provider with the repaired control token" \
  || fail "pawxyctl mock test must cover reset-token provider verification"
contains "$CTL_TEST" "reset-token must avoid foreground-service startup for token-only recovery" \
  || fail "pawxyctl mock test must assert reset-token uses a short normal service start"
contains "$CTL_TEST" "reset-token must fail when provider authorization is still unavailable" \
  || fail "pawxyctl mock test must cover reset-token authorization failure"
contains "$CTL_TEST" "start must synchronize the control token before starting" \
  || fail "pawxyctl mock test must cover pre-start token synchronization"
contains "$CTL_TEST" "start must not send START before token synchronization is verified" \
  || fail "pawxyctl mock test must cover token-sync races before service start"
contains "$CTL_TEST" "start must wait for running=true status" \
  || fail "pawxyctl mock test must cover start status waits"
contains "$CTL_TEST" "start must wait for native_running=true status" \
  || fail "pawxyctl mock test must cover native runtime status waits"
contains "$CTL_TEST" "start must use foreground-service startup" \
  || fail "pawxyctl mock test must assert start uses foreground-service startup"
contains "$CTL_TEST" "wrapper status reports running=true but native_running=false" \
  || fail "pawxyctl mock test must fail when wrapper status masks a stopped native runtime"
contains "$CTL_TEST" "share on must wait for configured_auth_enabled=true status" \
  || fail "pawxyctl mock test must cover persisted share-on auth waits"
contains "$CTL_TEST" "share on must use foreground-service startup" \
  || fail "pawxyctl mock test must assert share-on uses foreground-service startup"
contains "$CTL_TEST" "share off must wait for native_auth_enabled=false status" \
  || fail "pawxyctl mock test must cover native share-off auth waits"
contains "$CTL_TEST" "share off must use foreground-service startup" \
  || fail "pawxyctl mock test must assert share-off uses foreground-service startup"
contains "$CTL_TEST" "token sync and startup fields with bounded status queries" \
  || fail "pawxyctl mock test must assert start/share status waits remain bounded after token sync"
contains "$CTL_TEST" "token sync and stopped fields with bounded status queries" \
  || fail "pawxyctl mock test must assert stop status waits remain bounded after token sync"
contains "$CTL_TEST" "wake on must preserve native_running=true status" \
  || fail "pawxyctl mock test must assert wake-on preserves native runtime status"
contains "$CTL_TEST" "wake off must preserve native_running=true status" \
  || fail "pawxyctl mock test must assert wake-off preserves native runtime status"
contains "$CTL_TEST" "wake on native status failure" \
  || fail "pawxyctl mock test must cover wake native status failure diagnostics"
contains "$CTL_TEST" "status failure must surface status errors" \
  || fail "pawxyctl mock test must cover start status failure diagnostics"
contains "$CTL_TEST" "share off must wait for auth_enabled=false status" \
  || fail "pawxyctl mock test must cover share-off status waits"
contains "$CTL_TEST" "stop must synchronize the control token before stopping" \
  || fail "pawxyctl mock test must cover pre-stop token synchronization"
contains "$CTL_TEST" "stop must use normal service start for short control" \
  || fail "pawxyctl mock test must assert stop avoids foreground-service startup"
contains "$CTL_TEST" "wake on must use normal service start for short control" \
  || fail "pawxyctl mock test must assert wake-on avoids foreground-service startup"
contains "$CTL_TEST" "wake off must use normal service start for short control" \
  || fail "pawxyctl mock test must assert wake-off avoids foreground-service startup"
contains "$CTL_TEST" "restart must use foreground-service startup" \
  || fail "pawxyctl mock test must assert restart uses foreground-service startup"
contains "$README" "rish -c" \
  || fail "README must document Shizuku/rish control examples"

[ -f "$DEVICE_SMOKE" ] || fail "Pixel/Shizuku device smoke test script must exist"
[ -f "$DEVICE_SMOKE_TEST" ] || fail "Pixel/Shizuku device smoke test mock harness must exist"
[ -f "$DEVICE_VM_SMOKE" ] || fail "Android VM/GSI smoke test wrapper must exist"
[ -f "$DEVICE_VM_SMOKE_TEST" ] || fail "Android VM/GSI smoke test mock harness must exist"
[ -f "$PUBLIC_READINESS" ] || fail "Public readiness gate script must exist"
contains "$PUBLIC_READINESS" "scripts/test-android-vm.sh" \
  || fail "Public readiness gate must attempt the real Pixel/GSI/VM runtime smoke by default"
contains "$PUBLIC_READINESS" "PAWXY_SKIP_RUNTIME" \
  || fail "Public readiness gate must make missing-runtime skips explicit"
contains "$PUBLIC_READINESS" "scripts/check-android-apk-compat.sh" \
  || fail "Public readiness gate must include APK compatibility checks"
contains "$PUBLIC_READINESS" "scripts/test-android-device-mock.sh" \
  || fail "Public readiness gate must include Pixel/Shizuku smoke mock coverage"
contains "$PUBLIC_READINESS" "scripts/package-android.sh" \
  || fail "Public readiness gate must assemble release package assets"
contains "$PUBLIC_READINESS" "scripts/test-package-android.sh" \
  || fail "Public readiness gate must include Android package assembly mock coverage"
contains "$PUBLIC_READINESS" "cargo clippy --workspace --all-targets -- -D warnings" \
  || fail "Public readiness gate must include Rust clippy warnings-as-errors"
contains "$DEVICE_SMOKE" "forward \"tcp:\$HOST_PROXY_PORT\"" \
  || fail "Device smoke test must forward host traffic into the device proxy"
contains "$DEVICE_SMOKE" "reverse \"tcp:\$HOST_TARGET_PORT\"" \
  || fail "Device smoke test must reverse local target traffic back to the host"
contains "$DEVICE_SMOKE" "PAWXY_HOME=/data/local/tmp/pawxy" \
  || fail "Device smoke test must use the stable adb/Shizuku token home"
contains "$DEVICE_SMOKE" "--socks5-hostname" \
  || fail "Device smoke test must cover SOCKS5 proxy traffic"
contains "$DEVICE_SMOKE" "--proxytunnel" \
  || fail "Device smoke test must cover HTTP CONNECT proxy traffic"
contains "$DEVICE_SMOKE" "--proxy-user" \
  || fail "Device smoke test must cover authenticated SOCKS5 LAN proxy traffic"
contains "$DEVICE_SMOKE" "probe_unauthenticated_lan_proxy_rejected" \
  || fail "Device smoke test must reject unauthenticated LAN proxy traffic after share on"
contains "$DEVICE_SMOKE" "probe_unauthenticated_device_origin_lan_proxy_rejected" \
  || fail "Device smoke test must reject unauthenticated device-origin LAN proxy traffic after share on"
contains "$DEVICE_SMOKE" "probe_device_origin_authenticated_proxy_traffic" \
  || fail "Device smoke test must cover authenticated device-origin LAN proxy traffic after share on"
contains "$DEVICE_SMOKE" "Proxy-Authorization: Basic" \
  || fail "Device smoke test must send HTTP Basic auth from device-origin LAN probes"
contains "$DEVICE_SMOKE" "host base64 is required for authenticated device-origin LAN proxy probes" \
  || fail "Device smoke test must fail early when host base64 is unavailable for authenticated device-origin probes"
contains "$DEVICE_SMOKE" "unauthenticated LAN HTTP proxy traffic unexpectedly succeeded" \
  || fail "Device smoke test must fail if unauthenticated LAN HTTP proxy traffic succeeds"
contains "$DEVICE_SMOKE" "unauthenticated LAN SOCKS5 proxy traffic unexpectedly succeeded" \
  || fail "Device smoke test must fail if unauthenticated LAN SOCKS5 proxy traffic succeeds"
contains "$DEVICE_SMOKE" "unauthenticated device-origin LAN HTTP proxy traffic unexpectedly succeeded" \
  || fail "Device smoke test must fail if unauthenticated device-origin LAN HTTP proxy traffic succeeds"
contains "$DEVICE_SMOKE" "unauthenticated device-origin LAN SOCKS5 proxy traffic unexpectedly succeeded" \
  || fail "Device smoke test must fail if unauthenticated device-origin LAN SOCKS5 proxy traffic succeeds"
contains "$DEVICE_SMOKE" "verifying duplicate start keeps the running proxy in place" \
  || fail "Device smoke test must verify duplicate starts keep the native proxy in place"
contains "$DEVICE_SMOKE" "started_at_unix_ms" \
  || fail "Device smoke test must compare native started_at_unix_ms across duplicate starts"
contains "$DEVICE_SMOKE" "require_stable_listen" \
  || fail "Device smoke test must verify hostile control attempts do not drift the proxy listen endpoint"
contains "$DEVICE_SMOKE" "native_listen" \
  || fail "Device smoke test must verify the actual native listen endpoint, not only persisted config"
contains "$DEVICE_SMOKE" "native_running" \
  || fail "Device smoke test must verify the native proxy is running, not only the service wrapper"
contains "$DEVICE_SMOKE" "configured_listen" \
  || fail "Device smoke test must verify rejected controls do not drift persisted listen config"
contains "$DEVICE_SMOKE" "configured_auth_enabled" \
  || fail "Device smoke test must verify accepted and rejected auth transitions through persisted config"
contains "$DEVICE_SMOKE" "changed the proxy listen endpoint" \
  || fail "Device smoke test must explain listen drift after hostile control attempts"
contains "$DEVICE_SMOKE" "bad-token" \
  || fail "Device smoke test must verify unauthorized intents do not stop Pawxy"
contains "$DEVICE_SMOKE" "dev.pawxy.action.UNKNOWN" \
  || fail "Device smoke test must verify unknown intents do not stop Pawxy"
contains "$DEVICE_SMOKE" "0.0.0.0:3218" \
  || fail "Device smoke test must verify unsafe LAN listen cannot stop Pawxy"
contains "$DEVICE_SMOKE" "not-a-socket" \
  || fail "Device smoke test must verify malformed direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "max_connections 0" \
  || fail "Device smoke test must verify zero connection-limit direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "handshake_timeout_ms 0" \
  || fail "Device smoke test must verify zero timeout direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "2147483647" \
  || fail "Device smoke test must verify oversized direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "auth_enabled true" \
  || fail "Device smoke test must verify auth-required direct start configs without credentials cannot stop Pawxy"
contains "$DEVICE_SMOKE" "127.0.0.1:\$HOST_TARGET_PORT" \
  || fail "Device smoke test must verify bind-conflicting direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "192.0.2.1:3218" \
  || fail "Device smoke test must verify nonlocal listen direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "127.0.0.2:3218" \
  || fail "Device smoke test must verify loopback-alias direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "127.0.0.1:80" \
  || fail "Device smoke test must verify low-port direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "[::1]:3218" \
  || fail "Device smoke test must verify IPv6 loopback direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "[::]:3218" \
  || fail "Device smoke test must verify IPv6 wildcard direct start configs cannot stop Pawxy"
contains "$DEVICE_SMOKE" "service_started true" \
  || fail "Device smoke test must verify malformed direct start configs keep the Android service state intact"
contains "$DEVICE_SMOKE" "POST_NOTIFICATIONS" \
  || fail "Device smoke test must grant notification permission when shell can grant it"
contains "$DEVICE_SMOKE" "PAWXY_RUN_NOTIFICATION_DENIAL" \
  || fail "Device smoke test must expose Android 13+ notification-denial foreground-service coverage"
contains "$DEVICE_SMOKE" "cmd appops set \$PKG POST_NOTIFICATION ignore" \
  || fail "Device smoke test must be able to deny notification permission during foreground-service testing"
contains "$DEVICE_SMOKE" "restore_notification_permission" \
  || fail "Device smoke cleanup must restore notification permission after notification-denial testing"
contains "$DEVICE_SMOKE" "verify_package_installed" \
  || fail "Device smoke test must verify package visibility after APK install"
contains "$DEVICE_SMOKE" "pm path \$PKG" \
  || fail "Device smoke test must use pm path to confirm the installed package"
contains "$DEVICE_SMOKE" "PAWXY_CONTROL_MODE" \
  || fail "Device smoke test must expose an adb/rish control-mode switch"
contains "$DEVICE_SMOKE" "PAWXY_ADB_TIMEOUT_SECONDS" \
  || fail "Device smoke test must bound non-shell adb operations"
contains "$DEVICE_SMOKE" "timeout \"\$ADB_TIMEOUT_SECONDS\"" \
  || fail "Device smoke test must route non-shell adb operations through host-side timeout"
contains "$DEVICE_SMOKE" "PAWXY_CONTROL_TIMEOUT_SECONDS" \
  || fail "Device smoke test must bound adb/rish control-channel probes"
contains "$DEVICE_SMOKE" "device_sh_control" \
  || fail "Device smoke test must route adb/rish control commands through host-side timeout"
contains "$DEVICE_SMOKE" "PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS" \
  || fail "Device smoke test must bound ordinary adb shell probes"
contains "$DEVICE_SMOKE" "timeout \"\$DEVICE_SHELL_TIMEOUT_SECONDS\"" \
  || fail "Device smoke test must route ordinary adb shell commands through host-side timeout"
contains "$DEVICE_SMOKE" "json_bool_field" \
  || fail "Device smoke test must parse boolean status fields without depending on compact JSON"
contains "$DEVICE_SMOKE" "[[:space:]]*:[[:space:]]*" \
  || fail "Device smoke test must tolerate whitespace around JSON field separators"
contains "$DEVICE_SMOKE" "PAWXY_RISH" \
  || fail "Device smoke test must allow the rish command path to be configured"
contains "$DEVICE_SMOKE" "PAWXY_RISH_RUNNER" \
  || fail "Device smoke test must allow storage-exported rish scripts to run through a shell runner"
contains "$DEVICE_SMOKE" "PAWXY_RISH_APPLICATION_ID" \
  || fail "Device smoke test must allow terminal-exported Shizuku rish scripts to select RISH_APPLICATION_ID"
contains "$DEVICE_SMOKE" "shell_word" \
  || fail "Device smoke test must shell-quote the configured rish command path"
contains "$DEVICE_SMOKE" "rish_shell" \
  || fail "Device smoke test must centralize Shizuku/rish command construction"
contains "$DEVICE_SMOKE" "control_shell" \
  || fail "Device smoke test must run privileged preflight and adversarial controls through the selected adb/rish channel"
contains "$DEVICE_SMOKE" "observability_shell" \
  || fail "Device smoke test must collect process observability through the selected adb/rish channel"
contains "$DEVICE_SMOKE" "power_shell" \
  || fail "Device smoke test must run forced power-mode commands through the selected adb/rish control channel"
contains "$DEVICE_SMOKE" "CONTROL_READY" \
  || fail "Device smoke test must track verified adb/rish control readiness before control cleanup"
contains "$DEVICE_SMOKE" "SERVICE_STOP_NEEDED" \
  || fail "Device smoke test must only stop Pawxy during cleanup after a start was actually sent"
contains "$DEVICE_SMOKE_TEST" "rish helper" \
  || fail "Device smoke mock must cover a configurable rish command path that contains spaces"
contains "$DEVICE_SMOKE_TEST" "ri'sh" \
  || fail "Device smoke mock must cover a configurable rish command path that contains single quotes"
contains "$DEVICE_SMOKE_TEST" "PAWXY_RISH_RUNNER=sh" \
  || fail "Device smoke mock must cover storage-exported rish scripts that need a shell runner"
contains "$DEVICE_SMOKE_TEST" "RISH_APPLICATION_ID=com.termux" \
  || fail "Device smoke mock must cover terminal-exported Shizuku rish scripts that need RISH_APPLICATION_ID"
contains "$DEVICE_SMOKE_TEST" "rish probe failure must tell users how to select a Shizuku-authorized terminal package" \
  || fail "Device smoke mock must assert rish probe failures mention PAWXY_RISH_APPLICATION_ID"
contains "$DEVICE_SMOKE_TEST" "rish smoke must fail before install when the selected rish command cannot run" \
  || fail "Device smoke mock must cover rish probe failures before install"
contains "$DEVICE_SMOKE_TEST" "set PAWXY_RISH" \
  || fail "Device smoke mock must assert rish probe failures tell users how to select the rish command"
contains "$DEVICE_SMOKE_TEST" "must not run pawxyctl doctor through an unverified rish channel" \
  || fail "Device smoke mock must assert rish probe failures avoid slow unverified control diagnostics"
contains "$DEVICE_SMOKE" "PAWXY_RUN_CONTROL_PREFLIGHT" \
  || fail "Device smoke test must expose control-channel preflight for adb/rish modes"
contains "$DEVICE_SMOKE" "control_shell_uid" \
  || fail "Device smoke test must inspect the effective adb/rish control shell uid"
contains "$DEVICE_SMOKE" "pm check-permission android.permission.DUMP com.android.shell" \
  || fail "Device smoke test must verify shell can access DUMP-protected Pawxy components"
contains "$DEVICE_SMOKE" "verifying \$CONTROL_MODE control identity and status channel" \
  || fail "Device smoke test must preflight the selected control channel before starting Pawxy"
contains "$DEVICE_SMOKE" "pre-start unauthorized error" \
  || fail "Device smoke preflight must accept a fresh-install unauthorized status before the first START provisions the token"
contains "$DEVICE_SMOKE_TEST" "fresh-install unauthorized status before the first START" \
  || fail "Device smoke mock must cover fresh-install status preflight before control-token provisioning"
contains "$DEVICE_SMOKE" "PAWXY_HOLD_INTERVAL_SECONDS" \
  || fail "Device smoke test must make persistence probe cadence configurable"
contains "$DEVICE_SMOKE" "PAWXY_STARTUP_RETRIES" \
  || fail "Device smoke test must make startup wait retries configurable"
contains "$DEVICE_SMOKE" "PAWXY_TARGET_SERVER_RETRIES" \
  || fail "Device smoke test must make host target server readiness retries configurable"
contains "$DEVICE_SMOKE" "wait_for_target_server" \
  || fail "Device smoke test must verify the host target server before proxy traffic probes"
contains "$DEVICE_SMOKE" "host target server did not become ready" \
  || fail "Device smoke test must explain host target server readiness failures distinctly from proxy failures"
contains "$DEVICE_SMOKE" "validate_config" \
  || fail "Device smoke test must validate long-run and stress-test configuration before starting"
contains "$DEVICE_SMOKE" "PAWXY_HOST_PROXY_PORT and PAWXY_HOST_TARGET_PORT must be different" \
  || fail "Device smoke test must reject host proxy/target port conflicts before starting"
contains "$DEVICE_SMOKE" "require_non_negative_int_setting PAWXY_HOLD_SECONDS" \
  || fail "Device smoke test must reject invalid persistence hold settings"
contains "$DEVICE_SMOKE" "require_flag_setting PAWXY_RUN_DOZE" \
  || fail "Device smoke test must reject non-0/1 stress-test flags"
contains "$DEVICE_SMOKE" "initial start" \
  || fail "Device smoke test must wait for initial proxy startup before traffic probes"
contains "$DEVICE_SMOKE" "PAWXY_RUN_TOKEN_REPAIR" \
  || fail "Device smoke test must expose token mismatch repair coverage"
contains "$DEVICE_SMOKE" "testing control token repair" \
  || fail "Device smoke test must verify control token mismatch recovery"
contains "$DEVICE_SMOKE" "control token reset failed; restored token file" \
  || fail "Device smoke test must restore the original token file when reset-token recovery fails"
contains "$DEVICE_SMOKE" "PAWXY_RUN_STOP_START" \
  || fail "Device smoke test must expose immediate stop/start race coverage"
contains "$DEVICE_SMOKE" "stopping and immediately starting without listener release race" \
  || fail "Device smoke test must verify stop/start does not hit listener release races"
contains "$DEVICE_SMOKE" "wait_for_stopped_status" \
  || fail "Device smoke test must wait for Android service stop status instead of assuming it is synchronous"
contains "$DEVICE_SMOKE" "status_error_detail" \
  || fail "Device smoke wait failures must summarize status error and native last_error fields"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_DELAY_STOPPED" \
  || fail "Device smoke mock must cover delayed running=false stop status"
contains "$DEVICE_SMOKE" "PAWXY_RUN_PROCESS_RESTART" \
  || fail "Device smoke test must expose process restart persistence coverage"
contains "$DEVICE_SMOKE" "am crash \$PKG" \
  || fail "Device smoke test must inject an app process crash for sticky restart coverage"
contains "$DEVICE_SMOKE" "waiting for proxy to recover after process restart" \
  || fail "Device smoke test must wait for proxy recovery after process restart"
contains "$DEVICE_SMOKE" "Pawxy process pid did not change after crash injection" \
  || fail "Device smoke test must prove crash injection restarted the app process"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_PROCESS_PID_STUCK" \
  || fail "Device smoke mock must cover blocked crash injection with unchanged process pid"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_ACTIVE_CONNECTIONS_STUCK" \
  || fail "Device smoke mock must cover active proxy connections that never drain"
contains "$DEVICE_SMOKE_TEST" "adb smoke must test HTTP CONNECT curl traffic" \
  || fail "Device smoke mock must assert HTTP CONNECT end-to-end coverage"
contains "$DEVICE_SMOKE" "device-origin HTTP CONNECT proxy traffic did not reach loopback target" \
  || fail "Device smoke test must cover HTTP CONNECT traffic from the Android device/rish origin"
contains "$DEVICE_SMOKE_TEST" "adb smoke must test device-origin HTTP CONNECT traffic" \
  || fail "Device smoke mock must assert device-origin HTTP CONNECT coverage"
contains "$DEVICE_SMOKE_TEST" "authenticated LAN SOCKS5 proxy traffic" \
  || fail "Device smoke mock must assert authenticated SOCKS5 LAN coverage"
contains "$DEVICE_SMOKE_TEST" "authenticated device-origin LAN HTTP proxy traffic" \
  || fail "Device smoke mock must assert authenticated device-origin LAN HTTP coverage"
contains "$DEVICE_SMOKE_TEST" "authenticated device-origin LAN HTTP CONNECT proxy traffic" \
  || fail "Device smoke mock must assert authenticated device-origin LAN HTTP CONNECT coverage"
contains "$DEVICE_SMOKE_TEST" "authenticated device-origin LAN SOCKS5 proxy traffic" \
  || fail "Device smoke mock must assert authenticated device-origin LAN SOCKS5 coverage"
contains "$DEVICE_SMOKE_TEST" "device-origin-auth-http" \
  || fail "Device smoke mock must reject unauthenticated device-origin LAN HTTP probes after share on"
contains "$DEVICE_SMOKE_TEST" "device-origin-auth-connect" \
  || fail "Device smoke mock must reject unauthenticated device-origin LAN HTTP CONNECT probes after share on"
contains "$DEVICE_SMOKE_TEST" "device-origin-auth-socks" \
  || fail "Device smoke mock must reject unauthenticated device-origin LAN SOCKS5 probes after share on"
contains "$DEVICE_SMOKE_TEST" "rish smoke must route device-origin proxy probes through rish" \
  || fail "Device smoke mock must assert device-origin proxy probes use Shizuku/rish in rish mode"
contains "$DEVICE_SMOKE_TEST" "rish smoke must route device-origin HTTP CONNECT probes through rish" \
  || fail "Device smoke mock must assert device-origin HTTP CONNECT probes use Shizuku/rish in rish mode"
contains "$DEVICE_SMOKE_TEST" "rish smoke must bound device-origin proxy probes through the selected rish channel" \
  || fail "Device smoke mock must assert rish device-origin proxy probes use the device-origin timeout"
contains "$DEVICE_SMOKE_TEST" "unauthenticated LAN proxy traffic is rejected" \
  || fail "Device smoke mock must assert unauthenticated LAN proxy rejection coverage"
contains "$DEVICE_SMOKE_TEST" "proxy_auth" \
  || fail "Device smoke mock curl must distinguish authenticated and unauthenticated proxy requests"
contains "$DEVICE_SMOKE_TEST" "active-connection leak smoke must explain that active proxy connections did not drain" \
  || fail "Device smoke mock must assert active-connection leak diagnostics"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_DELAY_RUNNING" \
  || fail "Device smoke mock must cover delayed running=true startup status"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_FAIL_TARGET_SERVER" \
  || fail "Device smoke mock must cover host target server readiness failures"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_PM_PATH_MISSING" \
  || fail "Device smoke mock must cover package visibility failures after APK install"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_START_IGNORED" \
  || fail "Device smoke mock must fail when start does not produce running=true status"
contains "$DEVICE_SMOKE" "failed to start local proxy through \$CONTROL_MODE control" \
  || fail "Device smoke must fail clearly when the selected control start command fails"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_START_FAILS_AFTER_LAUNCH" \
  || fail "Device smoke mock must cover cleanup when start fails after launching Pawxy"
contains "$DEVICE_SMOKE_TEST" "start command failure smoke must stop Pawxy when start failed after launch" \
  || fail "Device smoke mock must assert cleanup stops Pawxy after a partial start failure"
wake_toggle_block=$(awk '
  /if \[ "\$RUN_WAKE" = "1" \]/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (inside && $0 ~ /^fi$/) exit
  }
' "$DEVICE_SMOKE")
printf '%s\n' "$wake_toggle_block" | grep -F 'require_proxy_running "$json"' >/dev/null 2>&1 \
  || fail "Device smoke wake toggle must verify the native proxy is still running after wake changes"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_WAKE_STOPS_NATIVE" \
  || fail "Device smoke mock must cover wake changes that lose native_running=true"
contains "$DEVICE_SMOKE_TEST" "wake native drift smoke must explain that wake on lost native_running=true" \
  || fail "Device smoke mock must assert wake native drift diagnostics"
contains "$DEVICE_SMOKE" "PAWXY_RUN_WAKE_HOLD" \
  || fail "Device smoke test must expose wake-lock persistence coverage"
contains "$DEVICE_SMOKE" "enabling wake lock for persistence and power-mode stress" \
  || fail "Device smoke test must support holding a wake lock through persistence and power-mode stress"
contains "$DEVICE_SMOKE" "PAWXY_RUN_SCREEN_OFF" \
  || fail "Device smoke test must expose screen-off persistence coverage"
contains "$DEVICE_SMOKE" "PAWXY_KEEP_SCREEN_OFF_DURING_HOLD" \
  || fail "Device smoke test must expose long screen-off hold coverage"
contains "$DEVICE_SMOKE" "input keyevent KEYCODE_SLEEP" \
  || fail "Device smoke test must be able to turn the screen off during persistence testing"
contains "$DEVICE_SMOKE" "restore_screen_state" \
  || fail "Device smoke cleanup must wake the screen after screen-off persistence testing"
contains "$DEVICE_SMOKE" "keeping screen off for persistence hold" \
  || fail "Device smoke test must be able to keep the screen off during long persistence holds"
contains "$DEVICE_SMOKE" "waking screen after screen-off persistence hold" \
  || fail "Device smoke test must restore the screen after long screen-off holds"
contains "$DEVICE_SMOKE_TEST" "screen-off smoke must turn the screen off through the selected control channel" \
  || fail "Device smoke mock must cover screen-off persistence through adb"
contains "$DEVICE_SMOKE_TEST" "rish screen-off smoke must turn the screen off through the selected rish channel" \
  || fail "Device smoke mock must cover screen-off persistence through Shizuku/rish"
contains "$DEVICE_SMOKE_TEST" "screen-off hold smoke must keep the screen off through the persistence hold" \
  || fail "Device smoke mock must cover long screen-off persistence holds"
contains "$DEVICE_SMOKE_TEST" "rish screen-off hold smoke must keep the screen off through the persistence hold" \
  || fail "Device smoke mock must cover long screen-off persistence holds through Shizuku/rish"
contains "$DEVICE_SMOKE_TEST" "PAWXY_RUN_WAKE_HOLD=1" \
  || fail "Device smoke mock must cover wake-lock hold persistence"
contains "$DEVICE_SMOKE_TEST" "wake-hold smoke must enable wake lock before the persistence hold" \
  || fail "Device smoke mock must assert wake-lock hold coverage runs before persistence probes"
contains "$DEVICE_SMOKE" "PAWXY_RUN_NETWORK_TOGGLE" \
  || fail "Device smoke test must expose network-toggle persistence coverage"
contains "$DEVICE_SMOKE" "PAWXY_NETWORK_TOGGLE_MODE" \
  || fail "Device smoke test must let Pixel/GSI runs choose the network toggle mode"
contains "$DEVICE_SMOKE" "validate_network_toggle_modes" \
  || fail "Device smoke test must validate comma-separated network-toggle modes before testing"
contains "$DEVICE_SMOKE" "cmd wifi set-wifi-enabled disabled" \
  || fail "Device smoke test must be able to disable Wi-Fi during persistence testing"
contains "$DEVICE_SMOKE" "cmd wifi set-wifi-enabled enabled" \
  || fail "Device smoke test must restore Wi-Fi after network-toggle testing"
contains "$DEVICE_SMOKE" "svc wifi disable" \
  || fail "Device smoke test must include a svc wifi fallback for older Android shells"
contains "$DEVICE_SMOKE" "cmd connectivity airplane-mode enable" \
  || fail "Device smoke test must be able to enable airplane mode during persistence testing"
contains "$DEVICE_SMOKE" "settings put global airplane_mode_on 1" \
  || fail "Device smoke test must include an airplane-mode fallback for older Android shells"
contains "$DEVICE_SMOKE" "restore_network_state" \
  || fail "Device smoke cleanup must restore network state after network-toggle failures"
contains "$DEVICE_SMOKE_TEST" "network toggle smoke must disable Wi-Fi through the selected control channel" \
  || fail "Device smoke mock must cover network-toggle persistence through adb"
contains "$DEVICE_SMOKE_TEST" "rish network toggle smoke must disable Wi-Fi through the selected rish channel" \
  || fail "Device smoke mock must cover network-toggle persistence through Shizuku/rish"
contains "$DEVICE_SMOKE_TEST" "network toggle failure smoke must restore Wi-Fi during cleanup" \
  || fail "Device smoke mock must assert network state is restored after network-toggle failures"
contains "$DEVICE_SMOKE_TEST" "dual network toggle smoke must cover airplane mode" \
  || fail "Device smoke mock must cover comma-separated Wi-Fi and airplane network-toggle modes"
contains "$DEVICE_SMOKE_TEST" "rish airplane network toggle smoke must enable airplane mode through the selected rish channel" \
  || fail "Device smoke mock must cover airplane-mode network toggles through Shizuku/rish"
contains "$DEVICE_SMOKE_TEST" "PAWXY_ADB_TIMEOUT_SECONDS=0" \
  || fail "Device smoke mock must cover invalid non-shell adb timeout rejection"
contains "$DEVICE_SMOKE_TEST" "notification-denial smoke must restart the foreground service while notification permission is denied" \
  || fail "Device smoke mock must cover notification-denied foreground-service restarts"
contains "$DEVICE_SMOKE_TEST" "rish notification-denial smoke must restart through the selected rish channel" \
  || fail "Device smoke mock must cover notification-denied foreground-service restarts through Shizuku/rish"
contains "$DEVICE_SMOKE_TEST" "notification-denial failure smoke must restore notification permission before stopping Pawxy" \
  || fail "Device smoke mock must assert notification permission restoration during failure cleanup"
contains "$DEVICE_SMOKE_TEST" "120 \$tmp/bin/adb install -r \$tmp/files/app-debug.apk" \
  || fail "Device smoke mock must assert APK install runs under host timeout"
contains "$DEVICE_SMOKE_TEST" "30 \$tmp/bin/adb shell pm path dev.pawxy" \
  || fail "Device smoke mock must assert package visibility checks run under host timeout"
contains "$DEVICE_SMOKE_TEST" "120 \$tmp/bin/adb forward tcp:3218 tcp:3218" \
  || fail "Device smoke mock must assert adb forward setup runs under host timeout"
contains "$DEVICE_SMOKE_TEST" "PAWXY_CONTROL_TIMEOUT_SECONDS=0" \
  || fail "Device smoke mock must cover invalid control timeout rejection"
contains "$DEVICE_SMOKE_TEST" "PAWXY_DEVICE_SHELL_TIMEOUT_SECONDS=0" \
  || fail "Device smoke mock must cover invalid ordinary adb shell timeout rejection"
contains "$DEVICE_SMOKE_TEST" "30 \$tmp/bin/adb shell pm grant dev.pawxy android.permission.POST_NOTIFICATIONS" \
  || fail "Device smoke mock must assert ordinary adb shell operations run under host timeout"
contains "$DEVICE_SMOKE_TEST" "20 \$tmp/bin/adb shell rish -c 'id -u'" \
  || fail "Device smoke mock must assert rish control probes run under host timeout"
contains "$DEVICE_SMOKE_TEST" "rish smoke must verify DUMP permission through the selected rish channel" \
  || fail "Device smoke mock must assert rish DUMP preflight uses the selected rish channel"
contains "$DEVICE_SMOKE_TEST" "rish smoke must send unauthorized control attempts through the selected rish channel" \
  || fail "Device smoke mock must assert adversarial control actions use the selected rish channel"
contains "$DEVICE_SMOKE_TEST" "rish smoke must inject process crashes through the selected rish channel" \
  || fail "Device smoke mock must assert process crash injection uses the selected rish channel"
contains "$DEVICE_SMOKE_TEST" "rish smoke must read LAN share credentials through the selected rish channel" \
  || fail "Device smoke mock must assert LAN share credential reads use the selected rish channel"
contains "$DEVICE_SMOKE_TEST" "uses_proxy" \
  || fail "Device smoke mock curl must distinguish host target preflight from proxy traffic"
contains "$DEVICE_SMOKE_TEST" "exit 56" \
  || fail "Device smoke mock proxy curl must fail when Pawxy is not running"
contains "$DEVICE_SMOKE_TEST" "PAWXY_HOLD_SECONDS=not-a-number" \
  || fail "Device smoke mock must cover invalid numeric configuration rejection"
contains "$DEVICE_SMOKE_TEST" "PAWXY_RUN_DOZE=true" \
  || fail "Device smoke mock must cover invalid run-flag rejection"
contains "$DEVICE_SMOKE_TEST" "PAWXY_HOST_PROXY_PORT=3218" \
  || fail "Device smoke mock must cover host proxy/target port conflict rejection"
contains "$DEVICE_SMOKE_TEST" "token-mismatch" \
  || fail "Device smoke mock must cover token mismatch status failures"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_RESET_TOKEN_FAIL" \
  || fail "Device smoke mock must cover reset-token failure recovery"
contains "$DEVICE_SMOKE_TEST" "pawxyctl reset-token" \
  || fail "Device smoke mock must cover reset-token recovery"
contains "$DEVICE_SMOKE" "probe_local_proxy_traffic" \
  || fail "Device smoke test must probe proxy traffic during the persistence hold"
contains "$DEVICE_SMOKE" "probe_host_proxy_traffic" \
  || fail "Device smoke test must keep host-origin proxy probes distinct from device-origin probes"
contains "$DEVICE_SMOKE" "PAWXY_RUN_DEVICE_ORIGIN" \
  || fail "Device smoke test must expose an opt-out device-origin proxy probe"
contains "$DEVICE_SMOKE" "PAWXY_DEVICE_ORIGIN_TIMEOUT_SECONDS" \
  || fail "Device smoke test must bound device-origin adb shell proxy probes"
contains "$DEVICE_SMOKE" "device_sh_timeout" \
  || fail "Device smoke test must route device-origin proxy probes through host-side timeout"
contains "$DEVICE_SMOKE" "device_origin_shell" \
  || fail "Device smoke test must route device-origin probes through Shizuku/rish when that control mode is selected"
contains "$DEVICE_SMOKE" "toybox nc 127.0.0.1 3218" \
  || fail "Device smoke test must probe the proxy from the device shell, not only through adb forward"
contains "$DEVICE_SMOKE" '\005\001\000\005' \
  || fail "Device smoke test must probe SOCKS5 traffic from the device shell"
contains "$DEVICE_SMOKE" "PAWXY_BULK_KIB" \
  || fail "Device smoke test must include configurable bulk transfer coverage"
contains "$DEVICE_SMOKE" "probe_bulk_proxy_transfer" \
  || fail "Device smoke test must verify bulk proxy transfer byte counts"
contains "$DEVICE_SMOKE" "bulk throughput" \
  || fail "Device smoke test must report bulk transfer throughput"
contains "$DEVICE_SMOKE" "PAWXY_RUN_PARALLEL_BURST" \
  || fail "Device smoke test must expose concurrent proxy burst coverage"
contains "$DEVICE_SMOKE" "PAWXY_PARALLEL_BURST_CONNECTIONS" \
  || fail "Device smoke test must let Pixel/GSI runs choose the concurrent burst size"
contains "$DEVICE_SMOKE" "probe_parallel_proxy_burst" \
  || fail "Device smoke test must exercise concurrent proxy requests"
contains "$DEVICE_SMOKE" "parallel proxy burst:" \
  || fail "Device smoke test must log completed concurrent proxy bursts"
contains "$DEVICE_SMOKE_TEST" "parallel burst smoke must complete every concurrent proxy request" \
  || fail "Device smoke mock must cover concurrent proxy burst completion"
contains "$DEVICE_SMOKE_TEST" "rish parallel burst smoke must complete under Shizuku/rish control" \
  || fail "Device smoke mock must cover concurrent proxy bursts under Shizuku/rish control"
contains "$DEVICE_SMOKE" "PAWXY_MIN_BULK_KIB_PER_SECOND" \
  || fail "Device smoke test must support a configurable minimum bulk throughput"
contains "$DEVICE_SMOKE" "PAWXY_CURL_CONNECT_TIMEOUT_SECONDS" \
  || fail "Device smoke test must bound proxy curl connection attempts"
contains "$DEVICE_SMOKE" "PAWXY_CURL_MAX_TIME_SECONDS" \
  || fail "Device smoke test must bound proxy curl total transfer time"
contains "$DEVICE_SMOKE_TEST" "--connect-timeout 5" \
  || fail "Device smoke mock must assert proxy curls use the default connection timeout"
contains "$DEVICE_SMOKE_TEST" "--max-time 30" \
  || fail "Device smoke mock must assert proxy curls use the default total timeout"
contains "$DEVICE_SMOKE_TEST" "PAWXY_CURL_MAX_TIME_SECONDS=0" \
  || fail "Device smoke mock must cover invalid curl timeout rejection"
contains "$DEVICE_SMOKE_TEST" "PAWXY_DEVICE_ORIGIN_TIMEOUT_SECONDS=0" \
  || fail "Device smoke mock must cover invalid device-origin timeout rejection"
contains "$DEVICE_SMOKE_TEST" "timeout.log" \
  || fail "Device smoke mock must assert device-origin proxy probes run under host timeout"
contains "$DEVICE_SMOKE" "speed_download" \
  || fail "Device smoke test must use curl transfer speed for bulk throughput"
contains "$DEVICE_SMOKE" "PAWXY_RUN_IDLE_EFFICIENCY" \
  || fail "Device smoke test must expose idle efficiency coverage"
contains "$DEVICE_SMOKE" "PAWXY_MAX_IDLE_CPU_TICKS" \
  || fail "Device smoke test must bound idle CPU growth"
contains "$DEVICE_SMOKE" "PAWXY_MAX_IDLE_RSS_KIB" \
  || fail "Device smoke test must bound idle RSS"
contains "$DEVICE_SMOKE" "PAWXY_MAX_IDLE_FD_SIZE" \
  || fail "Device smoke test must bound process FD table size"
contains "$DEVICE_SMOKE" "sampling idle efficiency" \
  || fail "Device smoke test must log idle efficiency samples"
contains "$DEVICE_SMOKE" "/proc/\$pid/stat" \
  || fail "Device smoke test must read process CPU ticks from procfs"
contains "$DEVICE_SMOKE" "/proc/\$pid/status" \
  || fail "Device smoke test must read process RSS from procfs"
contains "$DEVICE_SMOKE" "process_fd_size" \
  || fail "Device smoke test must expose process FDSize sampling"
contains "$DEVICE_SMOKE" "FDSize" \
  || fail "Device smoke test must read process FDSize from procfs"
contains "$DEVICE_SMOKE" "fd_size=" \
  || fail "Device smoke test must log process FDSize in idle efficiency summaries"
contains "$DEVICE_SMOKE_TEST" "rish smoke must read Pawxy process identity through the selected rish channel" \
  || fail "Device smoke mock must assert Shizuku/rish process identity observability"
contains "$DEVICE_SMOKE_TEST" "rish smoke must read idle CPU ticks through the selected rish channel" \
  || fail "Device smoke mock must assert Shizuku/rish CPU observability"
contains "$DEVICE_SMOKE_TEST" "rish smoke must read idle RSS through the selected rish channel" \
  || fail "Device smoke mock must assert Shizuku/rish RSS observability"
contains "$DEVICE_SMOKE_TEST" "adb smoke must read process FDSize for idle resource sampling" \
  || fail "Device smoke mock must assert adb FDSize observability"
contains "$DEVICE_SMOKE_TEST" "rish smoke must read idle FDSize through the selected rish channel" \
  || fail "Device smoke mock must assert Shizuku/rish FDSize observability"
contains "$DEVICE_SMOKE_TEST" "idle FDSize smoke must explain excessive process FD table size" \
  || fail "Device smoke mock must cover excessive process FDSize diagnostics"
contains "$DEVICE_SMOKE" "total_connections" \
  || fail "Device smoke test must assert native connection metrics moved"
contains "$DEVICE_SMOKE" "bytes_in" \
  || fail "Device smoke test must assert native inbound byte metrics moved"
contains "$DEVICE_SMOKE" "bytes_out" \
  || fail "Device smoke test must assert native byte metrics moved"
contains "$DEVICE_SMOKE" "network_available" \
  || fail "Device smoke test must verify Android network callback status is observable"
contains "$DEVICE_SMOKE" "require_status_observability" \
  || fail "Device smoke test must validate the full runtime status observability surface"
contains "$DEVICE_SMOKE" "active_connections" \
  || fail "Device smoke test must assert active connection metrics drain"
contains "$DEVICE_SMOKE" "wait_for_idle_connections" \
  || fail "Device smoke test must wait for active proxy connections to drain after traffic probes"
contains "$DEVICE_SMOKE" "require_json_number_greater_than" \
  || fail "Device smoke test must verify native metrics keep moving during persistence holds"
contains "$DEVICE_SMOKE" "hold sample: elapsed=" \
  || fail "Device smoke test must log per-interval hold samples for long Pixel/Shizuku runs"
contains "$DEVICE_SMOKE" "PAWXY_MAX_HOLD_RSS_KIB" \
  || fail "Device smoke test must bound process RSS during long persistence holds"
contains "$DEVICE_SMOKE" "PAWXY_MAX_HOLD_FD_SIZE" \
  || fail "Device smoke test must bound process FD table size during long persistence holds"
contains "$DEVICE_SMOKE" "require_process_resource_caps" \
  || fail "Device smoke test must sample process resources during persistence holds"
contains "$DEVICE_SMOKE" "cpu_ticks=" \
  || fail "Device smoke test must log process CPU ticks in hold samples"
contains "$DEVICE_SMOKE" "rss_kib=" \
  || fail "Device smoke test must log process RSS in hold samples"
contains "$DEVICE_SMOKE" "fd_size=" \
  || fail "Device smoke test must log process FDSize in hold samples"
contains "$DEVICE_SMOKE" "PAWXY_ARTIFACT_DIR" \
  || fail "Device smoke test must allow long Pixel/Shizuku runs to persist test artifacts"
contains "$DEVICE_SMOKE" "hold-samples.tsv" \
  || fail "Device smoke test must persist long-hold resource samples when artifacts are enabled"
contains "$DEVICE_SMOKE" "status-samples.tsv" \
  || fail "Device smoke test must persist status samples when artifacts are enabled"
contains "$DEVICE_SMOKE" "final-status.json" \
  || fail "Device smoke test must persist final status when artifacts are enabled"
contains "$DEVICE_SMOKE" "require_stable_started_at" \
  || fail "Device smoke test must verify native started_at_unix_ms stability during persistence checks"
contains "$DEVICE_SMOKE" "restarted the native proxy" \
  || fail "Device smoke test must explain native proxy restarts detected through started_at_unix_ms drift"
contains "$DEVICE_SMOKE_TEST" "duplicate starts do not restart the running proxy" \
  || fail "Device smoke mock must cover duplicate start persistence checks"
contains "$DEVICE_SMOKE_TEST" "started_at_unix_ms" \
  || fail "Device smoke mock must expose native started_at_unix_ms for duplicate start checks"
contains "$DEVICE_SMOKE_TEST" "stable native listen endpoint" \
  || fail "Device smoke mock must expose the stable native listen endpoint for drift checks"
contains "$DEVICE_SMOKE_TEST" "native_started_at_unix_ms" \
  || fail "Device smoke mock must expose native started_at_unix_ms for native restart checks"
contains "$DEVICE_SMOKE_TEST" "listen drift smoke must fail" \
  || fail "Device smoke mock must fail when hostile control attempts drift the proxy listen endpoint"
contains "$DEVICE_SMOKE_TEST" "malformed direct start changed the proxy listen endpoint" \
  || fail "Device smoke mock must assert listen-drift diagnostics"
contains "$DEVICE_SMOKE_TEST" "native-running drift smoke must fail" \
  || fail "Device smoke mock must fail when wrapper status masks a stopped native runtime"
contains "$DEVICE_SMOKE_TEST" "did not report running=true/native_running=true" \
  || fail "Device smoke mock must explain native_running startup failures"
contains "$DEVICE_SMOKE_TEST" "status error=unauthorized" \
  || fail "Device smoke mock must assert wait failures summarize provider status errors"
contains "$DEVICE_SMOKE_TEST" "malformed direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover malformed direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "zero limit and timeout direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover zero limit and timeout direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "oversized direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover oversized direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "auth-required direct start configs without credentials cannot break Pawxy" \
  || fail "Device smoke mock must cover auth-required direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "bind-conflicting direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover bind-conflicting direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "nonlocal listen direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover nonlocal listen direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "loopback-alias direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover loopback-alias direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "low-port direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover low-port direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "IPv6 loopback direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover IPv6 loopback direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "IPv6 wildcard direct start configs cannot break Pawxy" \
  || fail "Device smoke mock must cover IPv6 wildcard direct start config rejection"
contains "$DEVICE_SMOKE_TEST" "service_started remains true" \
  || fail "Device smoke mock must assert malformed direct start configs keep Android service state true"
contains "$DEVICE_SMOKE" "require_same_process_pid" \
  || fail "Device smoke test must fail when the Pawxy process restarts during persistence holds"
contains "$DEVICE_SMOKE" 'require_same_process_pid "persistence hold"' \
  || fail "Device smoke test must check process stability during persistence holds"
contains "$DEVICE_SMOKE_TEST" "hold smoke must fail when the Pawxy process restarts during the persistence hold" \
  || fail "Device smoke mock must cover process restarts during persistence holds"
contains "$DEVICE_SMOKE_TEST" "hold smoke must log per-interval status samples" \
  || fail "Device smoke mock must assert long-hold sample logging"
contains "$DEVICE_SMOKE_TEST" "hold smoke must log per-interval process resource samples" \
  || fail "Device smoke mock must assert long-hold resource sample logging"
contains "$DEVICE_SMOKE_TEST" "artifact smoke must persist hold status samples" \
  || fail "Device smoke mock must assert long-hold artifact status persistence"
contains "$DEVICE_SMOKE_TEST" "artifact smoke must persist final Pawxy status JSON" \
  || fail "Device smoke mock must assert final status artifact persistence"
contains "$DEVICE_SMOKE_TEST" "hold resource smoke must explain excessive process FD table size" \
  || fail "Device smoke mock must cover excessive process FDSize diagnostics during persistence holds"
contains "$DEVICE_SMOKE_TEST" "hold smoke must fail when the native proxy restarts without an app process restart" \
  || fail "Device smoke mock must cover native restarts during persistence holds"
contains "$DEVICE_SMOKE_TEST" "persistence hold restarted the native proxy" \
  || fail "Device smoke mock must assert started_at_unix_ms drift diagnostics during persistence holds"
contains "$DEVICE_SMOKE" "PAWXY_RUN_DOZE" \
  || fail "Device smoke test must expose an opt-in Doze stress path for Pixel persistence testing"
contains "$DEVICE_SMOKE" "dumpsys deviceidle force-idle" \
  || fail "Device smoke test must be able to force Doze mode during persistence testing"
contains "$DEVICE_SMOKE" "dumpsys deviceidle unforce" \
  || fail "Device smoke test must restore forced Doze mode"
contains "$DEVICE_SMOKE" "dumpsys battery reset" \
  || fail "Device smoke test must restore simulated battery state after power-mode testing"
contains "$DEVICE_SMOKE" "restoring \$power_label and verifying proxy remains stable" \
  || fail "Device smoke test must verify proxy stability after restoring forced power modes"
contains "$DEVICE_SMOKE" "require_same_process_pid \"\$power_label restore\" \"\$power_stable_pid\"" \
  || fail "Device smoke test must assert app process stability after forced power-mode restore"
contains "$DEVICE_SMOKE" "require_stable_started_at \"\$json\" \"\$power_started_at\" \"\$power_label restore\"" \
  || fail "Device smoke test must assert native runtime stability after forced power-mode restore"
contains "$DEVICE_SMOKE" "power_label=\$2" \
  || fail "Device smoke power-mode restore checks must avoid global shell label pollution"
contains "$DEVICE_SMOKE" "PAWXY_RUN_APP_STANDBY" \
  || fail "Device smoke test must expose an opt-in App Standby stress path"
contains "$DEVICE_SMOKE" "am set-inactive \$PKG true" \
  || fail "Device smoke test must be able to force App Standby for Pawxy"
contains "$DEVICE_SMOKE" "am set-inactive \$PKG false" \
  || fail "Device smoke test must restore App Standby state"
contains "$DEVICE_SMOKE" "PAWXY_RUN_STANDBY_BUCKET" \
  || fail "Device smoke test must expose an opt-in App Standby Bucket stress path"
contains "$DEVICE_SMOKE" "am set-standby-bucket \$PKG rare" \
  || fail "Device smoke test must be able to force Pawxy into the rare standby bucket"
contains "$DEVICE_SMOKE" "am set-standby-bucket \$PKG active" \
  || fail "Device smoke test must restore Pawxy to the active standby bucket"
contains "$DEVICE_SMOKE" "PAWXY_RUN_BACKGROUND_RESTRICTION" \
  || fail "Device smoke test must expose an opt-in background restriction stress path"
contains "$DEVICE_SMOKE" "cmd appops set \$PKG RUN_ANY_IN_BACKGROUND ignore" \
  || fail "Device smoke test must be able to apply background execution restriction"
contains "$DEVICE_SMOKE" "cmd appops set \$PKG RUN_ANY_IN_BACKGROUND allow" \
  || fail "Device smoke test must restore background execution restriction"
contains "$DEVICE_SMOKE" "PAWXY_RUN_BATTERY_SAVER" \
  || fail "Device smoke test must expose an opt-in battery saver stress path"
contains "$DEVICE_SMOKE" "settings put global low_power 1" \
  || fail "Device smoke test must be able to force battery saver"
contains "$DEVICE_SMOKE" "settings put global low_power 0" \
  || fail "Device smoke test must restore battery saver"
contains "$DEVICE_SMOKE" "cleanup_power_modes" \
  || fail "Device smoke cleanup must restore power modes after failures"
contains "$DEVICE_SMOKE_TEST" "PAWXY_TEST_FAIL_CURL_DURING_POWER" \
  || fail "Device smoke mock must cover cleanup after traffic failure during forced power modes"
contains "$DEVICE_SMOKE_TEST" "power failure smoke must restore forced Doze mode during cleanup" \
  || fail "Device smoke mock must assert forced power modes are restored after power-mode failures"
contains "$DEVICE_SMOKE_TEST" "proxy stability after forced Doze restore" \
  || fail "Device smoke mock must assert forced power-mode restore stability coverage"
contains "$DEVICE_SMOKE_TEST" "rish power smoke must force Doze through the selected rish channel" \
  || fail "Device smoke mock must cover forced power-mode testing through Shizuku/rish"
contains "$DEVICE_SMOKE_TEST" "rish power smoke must restore battery state through the selected rish channel" \
  || fail "Device smoke mock must cover forced power-mode cleanup through Shizuku/rish"
contains "$DEVICE_SMOKE_TEST" "background restriction failure smoke must restore background restriction before stopping Pawxy" \
  || fail "Device smoke mock must assert background restriction is restored before cleanup stops Pawxy"
contains "$DEVICE_SMOKE" "collect_failure_diagnostics" \
  || fail "Device smoke test must collect diagnostics on device-run failures"
contains "$DEVICE_SMOKE" "run_control_diag" \
  || fail "Device smoke test must run pawxyctl diagnostics through the selected adb/rish control channel"
contains "$DEVICE_SMOKE" "diagnostic_shell" \
  || fail "Device smoke test must collect failure diagnostics through the verified adb/rish channel"
contains "$DEVICE_SMOKE" "pawxyctl doctor via \$CONTROL_MODE" \
  || fail "Device smoke diagnostics must label the selected adb/rish control channel"
contains "$DEVICE_SMOKE" "pawxyctl doctor" \
  || fail "Device smoke test must collect pawxyctl doctor output on failures"
contains "$DEVICE_SMOKE" "logcat -d -s Pawxy PawxyNative" \
  || fail "Device smoke test must collect Pawxy logcat output on failures"
contains "$DEVICE_SMOKE" "dumpsys deviceidle" \
  || fail "Device smoke test must collect device idle diagnostics on failures"
contains "$DEVICE_SMOKE" "cmd appops get" \
  || fail "Device smoke test must collect notification app-op diagnostics on failures"
contains "$DEVICE_SMOKE" "CLEANUP_DONE" \
  || fail "Device smoke cleanup must be idempotent for signal-triggered failures"
contains "$DEVICE_SMOKE" "cleanup_device_service" \
  || fail "Device smoke cleanup must attempt to stop Pawxy after a failed device run"
contains "$DEVICE_SMOKE" "diagnostics/" \
  || fail "Device smoke test must persist failure diagnostics when artifacts are enabled"
contains "$DEVICE_SMOKE_TEST" "failure smoke must persist pawxyctl doctor diagnostics as an artifact" \
  || fail "Device smoke mock must assert pawxyctl doctor diagnostic artifacts"
contains "$DEVICE_SMOKE_TEST" "failure smoke must persist Pawxy logcat diagnostics as an artifact" \
  || fail "Device smoke mock must assert logcat diagnostic artifacts"
contains "$DEVICE_SMOKE_TEST" "rish failure diagnostics must run pawxyctl doctor through the selected rish control channel" \
  || fail "Device smoke mock must cover rish-channel failure diagnostics"
contains "$DEVICE_SMOKE_TEST" "rish failure diagnostics must collect Pawxy logcat through the selected rish channel" \
  || fail "Device smoke mock must cover rish-channel device diagnostics"
contains "$DEVICE_SMOKE" "wake lock cannot be enabled while proxy is stopped" \
  || fail "Device smoke test must verify wake on cannot create an idle foreground service after stop"
contains "$DEVICE_VM_SMOKE" "PAWXY_AVD" \
  || fail "Android VM smoke must be able to launch an existing AVD"
contains "$DEVICE_VM_SMOKE" "PAWXY_AVD and ANDROID_SERIAL are mutually exclusive" \
  || fail "Android VM smoke must reject ambiguous launch-vs-existing-runtime selection"
contains "$DEVICE_VM_SMOKE" "PAWXY_GSI_SYSTEM_IMG" \
  || fail "Android VM smoke must be able to launch an AVD with a supplied GSI system.img"
contains "$DEVICE_VM_SMOKE" '&& [ -z "${ANDROID_SERIAL:-}" ]' \
  || fail "Android VM smoke must allow an already booted ANDROID_SERIAL GSI/VM even when PAWXY_GSI_SYSTEM_IMG is set"
contains "$DEVICE_VM_SMOKE" "-system" \
  || fail "Android VM smoke must pass the supplied GSI system.img to the Android Emulator"
contains "$DEVICE_VM_SMOKE" "resolve_gsi_system_img" \
  || fail "Android VM smoke must resolve and validate supplied GSI image paths before launch"
contains "$DEVICE_VM_SMOKE" "directory does not contain system.img" \
  || fail "Android VM smoke must explain extracted GSI directories that are missing system.img"
contains "$DEVICE_VM_SMOKE" "not a zip archive" \
  || fail "Android VM smoke must reject GSI zip archives before launching the emulator"
contains "$DEVICE_VM_SMOKE" "check_gsi_avd_arch_compat" \
  || fail "Android VM smoke must fail fast on obvious GSI and AVD architecture mismatches"
contains "$DEVICE_VM_SMOKE" "ANDROID_AVD_HOME" \
  || fail "Android VM smoke must inspect local AVD config when checking GSI architecture compatibility"
contains "$DEVICE_VM_SMOKE" "use an extracted x86_64 GSI system.img that matches the AVD ABI" \
  || fail "Android VM smoke setup hints must explain the GSI architecture expected by Android Emulator"
contains "$DEVICE_VM_SMOKE" "ANDROID_HOME" \
  || fail "Android VM smoke must discover emulator binaries installed under ANDROID_HOME"
contains "$DEVICE_VM_SMOKE" "ANDROID_SDK_ROOT" \
  || fail "Android VM smoke must discover emulator binaries installed under ANDROID_SDK_ROOT"
contains "$DEVICE_VM_SMOKE" "PAWXY_VM_ADB_TIMEOUT_SECONDS" \
  || fail "Android VM smoke must bound adb commands while waiting for GSI/AVD boot"
contains "$DEVICE_VM_SMOKE" "timeout \"\$ADB_TIMEOUT_SECONDS\"" \
  || fail "Android VM smoke must route adb commands through host-side timeout"
contains "$DEVICE_VM_SMOKE" "PAWXY_VM_EMULATOR_TIMEOUT_SECONDS" \
  || fail "Android VM smoke must bound emulator discovery commands"
contains "$DEVICE_VM_SMOKE" "timeout \"\$EMULATOR_TIMEOUT_SECONDS\"" \
  || fail "Android VM smoke must route emulator discovery through host-side timeout"
contains "$DEVICE_VM_SMOKE" "PAWXY_VM_EMULATOR_LOG" \
  || fail "Android VM smoke must let GSI/AVD runs persist emulator stdout and stderr"
contains "$DEVICE_VM_SMOKE" "PAWXY_VM_NO_SNAPSHOT" \
  || fail "Android VM smoke must expose snapshot reuse control for reproducible GSI/AVD runs"
contains "$DEVICE_VM_SMOKE" "-no-snapshot" \
  || fail "Android VM smoke must avoid Quick Boot snapshot reuse by default"
contains "$DEVICE_VM_SMOKE" "PAWXY_VM_WIPE_DATA" \
  || fail "Android VM smoke must expose opt-in AVD user-data wiping for clean GSI runs"
contains "$DEVICE_VM_SMOKE" "-wipe-data" \
  || fail "Android VM smoke must pass opt-in user-data wiping to the emulator"
contains "$DEVICE_VM_SMOKE" "emulator log tail" \
  || fail "Android VM smoke must print captured emulator output when GSI/AVD launch fails"
contains "$DEVICE_VM_SMOKE" "-list-avds" \
  || fail "Android VM smoke must validate the requested AVD exists before waiting for boot"
contains "$DEVICE_VM_SMOKE" "No booted Android VM/device was found" \
  || fail "Android VM smoke must explain the missing local runtime before GSI/AVD testing"
contains "$DEVICE_VM_SMOKE" "runtime inventory: adb devices" \
  || fail "Android VM smoke must print adb device inventory when no runtime is available"
contains "$DEVICE_VM_SMOKE" "runtime inventory: emulator binary not found" \
  || fail "Android VM smoke must explain when the Android emulator binary is missing"
contains "$DEVICE_VM_SMOKE" "PAWXY_GSI_SYSTEM_IMG is not set" \
  || fail "Android VM smoke must report whether a GSI system.img was supplied"
contains "$DEVICE_VM_SMOKE" "PAWXY_AVD=<avd_name> PAWXY_GSI_SYSTEM_IMG=/path/to/system.img" \
  || fail "Android VM smoke must print the GSI-through-AVD invocation shape"
contains "$DEVICE_VM_SMOKE" "runtime setup hint" \
  || fail "Android VM smoke must print actionable runtime setup hints when emulator/GSI testing cannot start"
contains "$DEVICE_VM_SMOKE" "Pixel + Shizuku/rish" \
  || fail "Android VM smoke no-runtime hints must show the Pixel + Shizuku/rish test entrypoint"
contains "$DEVICE_VM_SMOKE" "PAWXY_RISH_APPLICATION_ID=<authorized_package>" \
  || fail "Android VM smoke no-runtime hints must show how to select the Shizuku-authorized rish package"
contains "$DEVICE_VM_SMOKE" "sdk_tool_cmd sdkmanager" \
  || fail "Android VM smoke must discover sdkmanager from PATH or common SDK roots"
contains "$DEVICE_VM_SMOKE" "system-images;android-35;google_apis;x86_64" \
  || fail "Android VM smoke must show the Android Emulator/system-image install command"
contains "$DEVICE_VM_SMOKE" "sdk_tool_cmd avdmanager" \
  || fail "Android VM smoke must discover avdmanager from PATH or common SDK roots"
contains "$DEVICE_VM_SMOKE" "create avd" \
  || fail "Android VM smoke must show the AVD creation command"
contains "$DEVICE_VM_SMOKE" "wait-for-device" \
  || fail "Android VM smoke must wait for ADB device availability"
contains "$DEVICE_VM_SMOKE" "sys.boot_completed" \
  || fail "Android VM smoke must wait for Android boot completion before testing"
contains "$DEVICE_VM_SMOKE" "collecting Android VM boot diagnostics" \
  || fail "Android VM smoke must collect boot diagnostics when a GSI/AVD boot times out"
contains "$DEVICE_VM_SMOKE" "logcat -d -t 200" \
  || fail "Android VM smoke boot diagnostics must include a logcat tail"
contains "$DEVICE_VM_SMOKE" "PAWXY_DEVICE_SMOKE" \
  || fail "Android VM smoke must delegate to the real device smoke script"
contains "$DEVICE_VM_SMOKE" "PAWXY_VM_HOLD_SECONDS" \
  || fail "Android VM smoke must default to a longer persistence hold"
contains "$DEVICE_VM_SMOKE" 'PAWXY_RUN_WAKE_HOLD=${PAWXY_RUN_WAKE_HOLD:-1}' \
  || fail "Android VM smoke must enable wake-lock hold coverage by default"
contains "$DEVICE_VM_SMOKE" 'PAWXY_RUN_SCREEN_OFF=${PAWXY_RUN_SCREEN_OFF:-1}' \
  || fail "Android VM smoke must enable screen-off persistence coverage by default"
contains "$DEVICE_VM_SMOKE" 'PAWXY_KEEP_SCREEN_OFF_DURING_HOLD=${PAWXY_KEEP_SCREEN_OFF_DURING_HOLD:-1}' \
  || fail "Android VM smoke must keep the screen off during the default persistence hold"
contains "$DEVICE_VM_SMOKE_TEST" "keep-screen-off-during-hold" \
  || fail "Android VM smoke mock must assert default long screen-off hold coverage"
contains "$DEVICE_VM_SMOKE" 'PAWXY_RUN_PARALLEL_BURST=${PAWXY_RUN_PARALLEL_BURST:-1}' \
  || fail "Android VM smoke must enable concurrent proxy burst coverage by default"
contains "$DEVICE_VM_SMOKE_TEST" "run-parallel-burst" \
  || fail "Android VM smoke mock must assert default concurrent proxy burst coverage"
contains "$DEVICE_VM_SMOKE" 'PAWXY_RUN_NOTIFICATION_DENIAL=${PAWXY_RUN_NOTIFICATION_DENIAL:-1}' \
  || fail "Android VM smoke must enable notification-denial foreground-service coverage by default"
contains "$DEVICE_VM_SMOKE_TEST" "run-notification-denial" \
  || fail "Android VM smoke mock must assert default notification-denial coverage"
contains "$DEVICE_VM_SMOKE" 'PAWXY_RUN_NETWORK_TOGGLE=${PAWXY_RUN_NETWORK_TOGGLE:-1}' \
  || fail "Android VM smoke must enable network-toggle persistence coverage by default"
contains "$DEVICE_VM_SMOKE" 'PAWXY_NETWORK_TOGGLE_MODE=${PAWXY_NETWORK_TOGGLE_MODE:-wifi,airplane}' \
  || fail "Android VM smoke must default to both Wi-Fi and airplane network-toggle modes"
contains "$DEVICE_VM_SMOKE_TEST" "run-network-toggle" \
  || fail "Android VM smoke mock must assert default network-toggle coverage"
contains "$DEVICE_VM_SMOKE_TEST" "network-toggle-mode" \
  || fail "Android VM smoke mock must assert default network-toggle mode selection"
contains "$DEVICE_VM_SMOKE" "PAWXY_RUN_DOZE" \
  || fail "Android VM smoke must enable Doze stress coverage by default"
contains "$DEVICE_VM_SMOKE" "PAWXY_RUN_APP_STANDBY" \
  || fail "Android VM smoke must enable App Standby stress coverage by default"
contains "$DEVICE_VM_SMOKE" "PAWXY_RUN_STANDBY_BUCKET" \
  || fail "Android VM smoke must enable standby bucket stress coverage by default"
contains "$DEVICE_VM_SMOKE" "PAWXY_RUN_BACKGROUND_RESTRICTION" \
  || fail "Android VM smoke must enable background restriction stress coverage by default"
contains "$DEVICE_VM_SMOKE" "PAWXY_RUN_BATTERY_SAVER" \
  || fail "Android VM smoke must enable battery saver stress coverage by default"
contains "$DEVICE_VM_SMOKE" "emu kill" \
  || fail "Android VM smoke must clean up a launched emulator"
contains "$DEVICE_VM_SMOKE" "record_prelaunch_devices" \
  || fail "Android VM smoke must record existing adb devices before launching an AVD"
contains "$DEVICE_VM_SMOKE" "newly_launched_device_serials" \
  || fail "Android VM smoke must identify the launched emulator by new adb serial"
contains "$DEVICE_VM_SMOKE" "launched AVD did not register a new adb device" \
  || fail "Android VM smoke must select the newly launched emulator when other devices are connected"
contains "$DEVICE_VM_SMOKE" "require_launched_emulator_alive" \
  || fail "Android VM smoke must fail fast when a launched emulator exits early"
contains "$DEVICE_VM_SMOKE" "emulator process exited before" \
  || fail "Android VM smoke must report early emulator process exits clearly"
contains "$DEVICE_VM_SMOKE" "PAWXY_EMULATOR_ACCEL" \
  || fail "Android VM smoke early-exit diagnostics must mention emulator acceleration"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_TEST_BOOT_NEVER_COMPLETES" \
  || fail "Android VM smoke mock must cover boot timeout diagnostics"
contains "$DEVICE_VM_SMOKE_TEST" "logcat -d -t 200" \
  || fail "Android VM smoke mock must cover boot-timeout logcat diagnostics"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_TEST_EXISTING_DEVICE_DURING_AVD" \
  || fail "Android VM smoke mock must cover launching an AVD while another adb device is connected"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_TEST_DELAY_NEW_EMULATOR_DEVICES" \
  || fail "Android VM smoke mock must cover adb wait-for-device returning for an existing Pixel before the launched emulator registers"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_TEST_EMULATOR_EXIT_IMMEDIATELY" \
  || fail "Android VM smoke mock must cover emulator processes that exit before adb registration"
contains "$DEVICE_VM_SMOKE_TEST" "emulator process exited before adb registration" \
  || fail "Android VM smoke mock must assert early emulator-exit diagnostics"
contains "$DEVICE_VM_SMOKE_TEST" "must not wait for adb registration before checking whether the launched emulator exited" \
  || fail "Android VM smoke mock must assert early emulator exits are checked before adb wait-for-device"
contains "$DEVICE_VM_SMOKE_TEST" "fake emulator output:" \
  || fail "Android VM smoke mock must assert captured emulator output diagnostics"
contains "$DEVICE_VM_SMOKE_TEST" "emulator-output.log" \
  || fail "Android VM smoke mock must assert PAWXY_VM_EMULATOR_LOG capture"
contains "$DEVICE_VM_SMOKE_TEST" "without snapshot reuse by default" \
  || fail "Android VM smoke mock must assert default no-snapshot launch"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_VM_WIPE_DATA=1" \
  || fail "Android VM smoke mock must assert opt-in clean user-data launch"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_VM_WIPE_DATA must be 0 or 1" \
  || fail "Android VM smoke mock must cover invalid VM launch flag rejection"
contains "$DEVICE_VM_SMOKE_TEST" "run-wake-hold" \
  || fail "Android VM smoke mock must assert wake-lock hold coverage is passed to device smoke"
contains "$DEVICE_VM_SMOKE_TEST" "run-screen-off" \
  || fail "Android VM smoke mock must assert screen-off persistence coverage is passed to device smoke"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_VM_ADB_TIMEOUT_SECONDS=0" \
  || fail "Android VM smoke mock must cover invalid adb timeout rejection"
contains "$DEVICE_VM_SMOKE_TEST" "120 \$tmp/bin/adb -s emulator-5554 wait-for-device" \
  || fail "Android VM smoke mock must assert adb wait-for-device runs under host timeout"
contains "$DEVICE_VM_SMOKE_TEST" "PAWXY_VM_EMULATOR_TIMEOUT_SECONDS=0" \
  || fail "Android VM smoke mock must cover invalid emulator timeout rejection"
contains "$DEVICE_VM_SMOKE_TEST" "30 emulator -list-avds" \
  || fail "Android VM smoke mock must assert emulator AVD listing runs under host timeout"
contains "$DEVICE_VM_SMOKE_TEST" "ANDROID_HOME" \
  || fail "Android VM smoke mock must cover Android SDK emulator fallback discovery"
contains "$DEVICE_VM_SMOKE_TEST" "ambiguous VM runtime smoke" \
  || fail "Android VM smoke mock must cover PAWXY_AVD plus ANDROID_SERIAL rejection"
contains "$DEVICE_VM_SMOKE_TEST" "cmdline-tools/latest/bin/sdkmanager" \
  || fail "Android VM smoke mock must cover Android SDK command-line tool fallback discovery"
contains "$DEVICE_VM_SMOKE_TEST" "already booted ANDROID_SERIAL runtime" \
  || fail "Android VM smoke mock must cover existing GSI/VM runtimes selected by ANDROID_SERIAL"
contains "$DEVICE_VM_SMOKE_TEST" "extracted GSI directory containing system.img" \
  || fail "Android VM smoke mock must cover extracted GSI directories containing system.img"
contains "$DEVICE_VM_SMOKE_TEST" "zip archive" \
  || fail "Android VM smoke mock must cover GSI zip archive rejection"
contains "$DEVICE_VM_SMOKE_TEST" "ARM64 GSI is paired with an x86_64 AVD" \
  || fail "Android VM smoke mock must cover obvious GSI and AVD architecture mismatches"
contains "$DEVICE_VM_SMOKE_TEST" "allow an x86_64 GSI to launch with an x86_64 AVD config" \
  || fail "Android VM smoke mock must cover architecture-compatible GSI and AVD launches"
contains "$DEVICE_VM_SMOKE_TEST" "missing-avd" \
  || fail "Android VM smoke mock must cover missing requested AVD diagnostics"
contains "$DEVICE_VM_SMOKE_TEST" "VM smoke no-runtime diagnostics must show the SDK package install command" \
  || fail "Android VM smoke mock must cover no-runtime setup hints"

reject_block=$(awk '
  /private fun rejectUnauthorized/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
printf '%s\n' "$reject_block" | grep -F "stopSelf" >/dev/null 2>&1 \
  && fail "Rejected control actions must not stop an already running proxy service"
printf '%s\n' "$reject_block" | grep -F "foregroundStarted" >/dev/null 2>&1 \
  || fail "Rejected control actions must preserve only a currently foregrounded proxy service"

contains "$SERVICE" "private var foregroundStarted" \
  || fail "ProxyService must track foreground state in process, not only persisted service state"
contains "$SERVICE" "foregroundStarted = true" \
  || fail "ProxyService must mark foreground state after startForeground"
contains "$SERVICE" "foregroundStarted = false" \
  || fail "ProxyService must clear foreground state after stop/failure"

on_create_block=$(awk '
  /override fun onCreate/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
printf '%s\n' "$on_create_block" | grep -F "setWakeLock(true)" >/dev/null 2>&1 \
  && fail "ProxyService onCreate must not acquire a wake lock before native proxy startup succeeds"
contains "$SERVICE" "syncWakeLockWithPreference()" \
  || fail "ProxyService must restore persisted wake-lock state only after native startup succeeds"

contains "$SERVICE" "rejectUnknownAction(intent.action, startId)" \
  || fail "Unknown actions must use the same preserving rejection path as unauthorized controls"
contains "$SERVICE" "ACTION_RESET_TOKEN" \
  || fail "ProxyService must implement reset-token recovery for adb/Shizuku token mismatch"
contains "$SERVICE" "controlToken.replace(token)" \
  || fail "ProxyService reset-token recovery must replace the persisted app control token"
contains "$CONTROL_TOKEN" "token.length != 64" \
  || fail "Android ControlToken must reject malformed control tokens before provisioning or reset"
contains "$CONTROL_TOKEN" "it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F'" \
  || fail "Android ControlToken must only accept hex control tokens"
contains "$CONTROL_TOKEN" ".commit()" \
  || fail "Android ControlToken must synchronously persist adb/Shizuku control-token changes"
not_contains "$CONTROL_TOKEN" ".apply()" \
  || fail "Android ControlToken must not asynchronously persist critical control-token changes"

restart_block=$(awk '
  /ACTION_RESTART ->/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
printf '%s\n' "$restart_block" | grep -F "PawxyNative.nativeStop()" >/dev/null 2>&1 \
  && fail "RESTART must let nativeStart synchronously stop the old listener before rebinding"
contains "$SERVICE" "nativeStartSucceeded(result)" \
  || fail "ProxyService must verify nativeStart reports a running core before keeping the service started"
contains "$SERVICE" "handleNativeStartFailure(result, startId)" \
  || fail "ProxyService must clear foreground started state when nativeStart fails"
contains "$SERVICE" "Keeping existing native proxy after rejected start" \
  || fail "ProxyService must preserve a running native proxy when malformed direct start configs are rejected before native restart"
contains "$SERVICE" "putString(KEY_CONFIG_JSON, persistedConfigJson(config))" \
  || fail "ProxyService must persist a sanitized accepted config after native startup succeeds"
contains "$SERVICE" "persistAcceptedConfig" \
  || fail "ProxyService must centralize accepted-config persistence after native startup"
contains "$SERVICE" "editor.commit()" \
  || fail "ProxyService must synchronously persist critical service state for crash-resistant Pixel restarts"
contains "$SERVICE" "handleAcceptedConfigPersistFailure(startId)" \
  || fail "ProxyService must stop the native proxy if accepted startup state cannot be persisted"
contains "$SERVICE" "nativeStop after persistence failure" \
  || fail "ProxyService must log native cleanup after accepted-config persistence failure"
contains "$SERVICE" "persisted.remove(\"force_restart\")" \
  || fail "ProxyService must not persist one-shot restart semantics into sticky service restore config"
contains "$SERVICE" "forceRestart = true" \
  || fail "ProxyService RESTART must tell native startup to force an explicit listener replacement"
contains "$SERVICE" ".put(\"force_restart\", forceRestart)" \
  || fail "ProxyService must pass restart intent semantics into native startup"
contains "$SERVICE" "safeNativeStart" \
  || fail "ProxyService must convert nativeStart exceptions into normal startup failures"
contains "$SERVICE" "Native proxy threw during startup" \
  || fail "ProxyService must log nativeStart exceptions before clearing sticky service state"
contains "$SERVICE" "safeNativeStop" \
  || fail "ProxyService must convert nativeStop exceptions into normal shutdown failures"
contains "$SERVICE" "Native proxy threw during stop" \
  || fail "ProxyService must log nativeStop exceptions before clearing wake-lock and sticky service state"
contains "$SERVICE" "startForegroundSafely" \
  || fail "ProxyService must convert foreground-service entry failures into normal startup failures"
contains "$SERVICE" "Could not enter foreground service" \
  || fail "ProxyService must log foreground-service entry failures before clearing sticky service state"
contains "$SERVICE" "handleForegroundStartFailure(startId)" \
  || fail "ProxyService must clear sticky service state when foreground-service entry fails"
contains "$SERVICE" "safeStopForeground" \
  || fail "ProxyService must shield shutdown cleanup from stopForeground failures"
contains "$SERVICE" "Could not leave foreground service" \
  || fail "ProxyService must log stopForeground failures without interrupting cleanup"
contains "$SERVICE" "rejectUnsafeLanListen(listen, startId)" \
  || fail "ProxyService must route unsafe wildcard listen through a preserving rejection helper"
contains "$SERVICE" "validateConfigBeforeForeground(config)" \
  || fail "ProxyService must preflight hostile direct-start configs before foreground notification updates"
contains "$SERVICE" "Rejected invalid start config before foreground update" \
  || fail "ProxyService must log pre-foreground config rejections"
contains "$SERVICE" "MAX_CONNECTIONS_LIMIT = 4096L" \
  || fail "ProxyService preflight must mirror the native max_connections operational cap"
contains "$SERVICE" "MAX_PER_SOURCE_IP_LIMIT = 1024L" \
  || fail "ProxyService preflight must mirror the native per-source connection cap"
contains "$SERVICE" "MAX_HANDSHAKE_TIMEOUT_MS = 60_000L" \
  || fail "ProxyService preflight must mirror the native handshake timeout cap"
contains "$SERVICE" "MAX_CONNECT_TIMEOUT_MS = 60_000L" \
  || fail "ProxyService preflight must mirror the native connect timeout cap"
contains "$SERVICE" "MAX_IDLE_TIMEOUT_MS = 86_400_000L" \
  || fail "ProxyService preflight must mirror the native idle timeout cap"
contains "$SERVICE" "auth password is required" \
  || fail "ProxyService preflight must reject auth-enabled direct starts without a password"

start_from_intent_block=$(awk '
  /private fun startFromIntent/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
preflight_line=$(printf '%s\n' "$start_from_intent_block" | awk '/validateConfigBeforeForeground\(config\)/ { print NR; exit }')
foreground_line=$(printf '%s\n' "$start_from_intent_block" | awk '/startForegroundSafely/ { print NR; exit }')
[ -n "$preflight_line" ] || fail "ProxyService startFromIntent must call validateConfigBeforeForeground"
[ -n "$foreground_line" ] || fail "ProxyService startFromIntent must enter foreground through startForegroundSafely"
[ "$preflight_line" -lt "$foreground_line" ] \
  || fail "ProxyService must reject invalid direct-start configs before updating the foreground notification"

invalid_config_reject_block=$(awk '
  /private fun rejectInvalidStartConfig/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
printf '%s\n' "$invalid_config_reject_block" | grep -F "foregroundStarted" >/dev/null 2>&1 \
  || fail "Invalid config rejection must preserve only a currently foregrounded proxy service"
printf '%s\n' "$invalid_config_reject_block" | grep -F "stopUnauthorizedStart(startId)" >/dev/null 2>&1 \
  || fail "Invalid config rejection must stop a new failed foreground-service launch"

saved_restart_block=$(awk '
  /private fun restartFromSavedConfig/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
printf '%s\n' "$saved_restart_block" | grep -F "prefs.getBoolean(KEY_SERVICE_STARTED, false)" >/dev/null 2>&1 \
  || fail "Null-intent service restart must respect service_started before restoring saved config"
printf '%s\n' "$saved_restart_block" | grep -F "KEY_WAKE_LOCK_ENABLED, false" >/dev/null 2>&1 \
  || fail "Null-intent service restart in stopped state must clear stale wake-lock preference"

contains "$SERVICE" "handleWakeAction(true, startId)" \
  || fail "Wake-on control must route through the running-proxy guard"
contains "$SERVICE" "handleWakeAction(false, startId)" \
  || fail "Wake-off control must route through the running-proxy guard"
contains "$SERVICE" "private fun isNativeRunning" \
  || fail "Wake lock control must verify native proxy runtime state"
contains "$SERVICE" "Ignored wake lock change while proxy is not running" \
  || fail "Wake lock control must reject idle foreground-service creation when proxy is stopped"
contains "$SERVICE" "Could not enable wake lock" \
  || fail "Wake lock enable failures must be logged without crashing the running proxy"
contains "$SERVICE" "Could not disable wake lock" \
  || fail "Wake lock release failures must be logged without crashing shutdown cleanup"
contains "$SERVICE" "putBoolean(KEY_WAKE_LOCK_ENABLED, enabled)" \
  && fail "Wake-on control must persist the actual wake-lock state, not the requested state"

contains "$ROOT/crates/pawxy-jni/src/lib.rs" "stopping_thread" \
  || fail "JNI stop must retain a pending runtime join handle for immediate stop/start races"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "join_stopping_thread" \
  || fail "JNI start must join any runtime still exiting after nativeStop"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "start_after_stop_waits_for_parked_stop_thread_before_returning" \
  || fail "JNI tests must cover immediate start after nativeStop"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "bind preflight failed" \
  || fail "JNI start must pre-bind different-port replacements before stopping a running proxy"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "should_reuse_running_proxy" \
  || fail "JNI start must keep duplicate-start reuse decisions testable"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "current_config == Some(next_config)" \
  || fail "JNI duplicate-start reuse must compare the full effective config, including auth credentials and limits"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "duplicate_start_reuses_running_proxy_only_for_same_effective_config" \
  || fail "JNI tests must cover duplicate-start reuse decisions"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "changed_auth_password" \
  || fail "JNI tests must reject duplicate-start reuse after LAN auth password changes"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "changed_limits" \
  || fail "JNI tests must reject duplicate-start reuse after runtime limit changes"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "should_prebind_replacement" \
  || fail "JNI start must keep the prebind replacement decision testable"
contains "$ROOT/crates/pawxy-jni/src/lib.rs" "prebind_replacement_preserves_running_proxy_for_different_ports" \
  || fail "JNI tests must cover prebind-preserving replacement decisions"
contains "$ROOT/crates/pawxy-core/src/server.rs" "run_bound_with_metrics" \
  || fail "Proxy server must be able to run from a listener pre-bound before old proxy shutdown"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "max_connections_closes_excess_clients" \
  || fail "Proxy tests must cover global connection-limit rejection"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "max_per_source_ip_closes_excess_clients" \
  || fail "Proxy tests must cover per-source connection-limit rejection"
contains "$ROOT/crates/pawxy-core/src/server.rs" "max_connections limit reached" \
  || fail "Proxy server must surface global connection-limit rejection through native last_error"
contains "$ROOT/crates/pawxy-core/src/server.rs" "max_per_source_ip limit reached" \
  || fail "Proxy server must surface per-source connection-limit rejection through native last_error"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "assert_last_error_contains" \
  || fail "Proxy tests must assert connection-limit rejections update native last_error"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "http_connect_updates_bidirectional_metrics" \
  || fail "Proxy tests must cover CONNECT tunnel byte counters"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "auth_required_absolute_form_http_rejects_missing_auth_and_strips_correct_auth" \
  || fail "Proxy tests must cover authenticated absolute-form HTTP proxy traffic"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "assert_tunnel_metrics" \
  || fail "Proxy tests must assert active bidirectional CONNECT metrics"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "status.bytes_in >= bytes" \
  || fail "Proxy tests must assert client-to-target tunnel bytes"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "status.bytes_out >= bytes" \
  || fail "Proxy tests must assert target-to-client tunnel bytes"
contains "$ROOT/crates/pawxy-core/tests/proxy.rs" "http_connect_preserves_target_to_client_after_client_half_close" \
  || fail "Proxy tests must cover CONNECT target-to-client delivery after client half-close"
contains "$ROOT/crates/pawxy-core/src/config.rs" "max_connections must be greater than zero" \
  || fail "Proxy config validation must reject zero global connection limits"
contains "$ROOT/crates/pawxy-core/src/config.rs" "max_per_source_ip must be greater than zero" \
  || fail "Proxy config validation must reject zero per-source connection limits"
contains "$ROOT/crates/pawxy-core/src/config.rs" "handshake_timeout_ms must be greater than zero" \
  || fail "Proxy config validation must reject zero handshake timeouts"
contains "$ROOT/crates/pawxy-core/src/config.rs" "connect_timeout_ms must be greater than zero" \
  || fail "Proxy config validation must reject zero connect timeouts"
contains "$ROOT/crates/pawxy-core/src/config.rs" "idle_timeout_ms must be greater than zero" \
  || fail "Proxy config validation must reject zero idle timeouts"
contains "$ROOT/crates/pawxy-core/src/config.rs" "listen address must be 127.0.0.1 or 0.0.0.0" \
  || fail "Proxy config validation must reject arbitrary listen addresses outside the supported Android bridge surface"
contains "$ROOT/crates/pawxy-core/src/config.rs" "127.0.0.2:3218" \
  || fail "Proxy config tests must reject loopback aliases that would break adb forward assumptions"
contains "$ROOT/crates/pawxy-core/src/config.rs" "[::1]:3218" \
  || fail "Proxy config tests must reject IPv6 loopback listens until the Android bridge supports them explicitly"
contains "$ROOT/crates/pawxy-core/src/config.rs" "listen port must be explicit" \
  || fail "Proxy config validation must reject ephemeral listen ports"
contains "$ROOT/crates/pawxy-core/src/config.rs" "listen port must be at least 1024" \
  || fail "Proxy config validation must reject privileged listen ports"
contains "$ROOT/crates/pawxy-core/src/config.rs" "from_json_rejects_unsupported_listen_addresses_and_ports" \
  || fail "Proxy config tests must cover unsupported listen addresses and ports"
contains "$ROOT/crates/pawxy-core/src/config.rs" "from_json_rejects_zero_limits_and_timeouts" \
  || fail "Proxy config tests must cover zero limit and timeout JSON rejection"
contains "$ROOT/crates/pawxy-core/src/config.rs" "MAX_CONNECTIONS_LIMIT: usize = 4096" \
  || fail "Proxy config validation must cap global connection limits for Android resource safety"
contains "$ROOT/crates/pawxy-core/src/config.rs" "MAX_HANDSHAKE_TIMEOUT_MS: u64 = 60_000" \
  || fail "Proxy config validation must cap handshake timeouts for hostile direct starts"
contains "$ROOT/crates/pawxy-core/src/config.rs" "MAX_IDLE_TIMEOUT_MS: u64 = 86_400_000" \
  || fail "Proxy config validation must cap idle timeouts while allowing long-lived proxy traffic"
contains "$ROOT/crates/pawxy-core/src/config.rs" "from_json_rejects_values_above_operational_caps" \
  || fail "Proxy config tests must cover oversized limit and timeout JSON rejection"
contains "$ROOT/crates/pawxy-core/src/config.rs" "from_json_rejects_enabled_auth_without_nonempty_credentials" \
  || fail "Proxy config tests must cover auth-enabled JSON rejection without credentials"

native_failure_block=$(awk '
  /private fun handleNativeStartFailure/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
printf '%s\n' "$native_failure_block" | grep -F "setWakeLock(false)" >/dev/null 2>&1 \
  || fail "Native start failure must release any held wake lock"
printf '%s\n' "$native_failure_block" | grep -F "KEY_WAKE_LOCK_ENABLED, false" >/dev/null 2>&1 \
  || fail "Native start failure must clear wake-lock preference"

unsafe_lan_block=$(awk '
  /private fun rejectUnsafeLanListen/ { inside = 1 }
  inside {
    print
    opens += gsub(/{/, "{")
    closes += gsub(/}/, "}")
    if (opens > 0 && opens == closes) exit
  }
' "$SERVICE")
printf '%s\n' "$unsafe_lan_block" | grep -F "KEY_SERVICE_STARTED" >/dev/null 2>&1 \
  && fail "Unsafe LAN rejection must not rely on persisted service state"
printf '%s\n' "$unsafe_lan_block" | grep -F "foregroundStarted" >/dev/null 2>&1 \
  || fail "Unsafe LAN rejection must preserve only a currently foregrounded proxy service"
printf '%s\n' "$unsafe_lan_block" | grep -F "stopSelf()" >/dev/null 2>&1 \
  && fail "Unsafe LAN rejection must not unconditionally stop a running proxy service"

WORKFLOW=$ROOT/.github/workflows/package-android.yml
[ -f "$WORKFLOW" ] || fail "GitHub Actions Android packaging workflow must exist"
contains "$WORKFLOW" "workflow_dispatch:" \
  || fail "Packaging workflow must support manual workflow_dispatch runs"
contains "$WORKFLOW" "release:" \
  || fail "Packaging workflow must run on release events"
contains "$WORKFLOW" "contents: read" \
  || fail "Packaging workflow build job must default to read-only contents permission"
contains "$WORKFLOW" "contents: write" \
  || fail "Packaging workflow release upload job must explicitly request write permission"
contains "$WORKFLOW" "actions/checkout@v6" \
  || fail "Packaging workflow must use the current official checkout action major"
contains "$WORKFLOW" "actions/setup-java@v5" \
  || fail "Packaging workflow must explicitly select JDK 17"
contains "$WORKFLOW" "actions/cache@v5" \
  || fail "Packaging workflow must cache Rust build inputs"
contains "$WORKFLOW" "actions/download-artifact@v8" \
  || fail "Packaging workflow must download artifacts in the release upload job"
contains "$WORKFLOW" "scripts/build-android.sh" \
  || fail "Packaging workflow must use the repository Android build script"
contains "$WORKFLOW" "scripts/test-pawxyctl.sh" \
  || fail "Packaging workflow must run the pawxyctl mock test"
contains "$WORKFLOW" "scripts/test-package-android.sh" \
  || fail "Packaging workflow must run the Android package assembly mock test"
contains "$WORKFLOW" "scripts/test-install-apk-adb.sh" \
  || fail "Packaging workflow must run the adb debug installer mock test"
contains "$WORKFLOW" "scripts/check-android-apk-compat.sh" \
  || fail "Packaging workflow must run the APK compatibility gate after building"
contains "$WORKFLOW" "scripts/install-android.sh" \
  || fail "Packaging workflow must verify and package the Android install script"
contains "$WORKFLOW" "scripts/package-android.sh" \
  || fail "Packaging workflow must assemble release assets through the repository package script"
contains "$WORKFLOW" "scripts/test-android-device.sh" \
  || fail "Packaging workflow must syntax-check the Android device smoke script"
contains "$WORKFLOW" "scripts/test-android-device-mock.sh" \
  || fail "Packaging workflow must mock-test the Android device smoke script"
contains "$WORKFLOW" "scripts/test-android-vm.sh" \
  || fail "Packaging workflow must syntax-check the Android VM smoke wrapper"
contains "$WORKFLOW" "scripts/test-android-vm-mock.sh" \
  || fail "Packaging workflow must mock-test the Android VM smoke wrapper"
contains "$WORKFLOW" "scripts/test-public-readiness.sh" \
  || fail "Packaging workflow must run the public readiness gate after APK build"
contains "$WORKFLOW" "actions/upload-artifact@v7" \
  || fail "Packaging workflow must upload workflow artifacts"
contains "$WORKFLOW" "gh release upload" \
  || fail "Packaging workflow must upload assets to GitHub releases"
contains "$WORKFLOW" '--repo "${GITHUB_REPOSITORY}"' \
  || fail "Packaging workflow release upload must be explicit about the repository without checkout"

contains "$BEST_PRACTICES" "Never retry an established TCP tunnel transparently" \
  || fail "best-practice doc must forbid transparent TCP tunnel retry"
contains "$BEST_PRACTICES" 'Do not bind outbound sockets to a specific Android `Network`' \
  || fail "best-practice doc must forbid binding outbound sockets to a captured Android Network"
contains "$BEST_PRACTICES" "Wake lock is opt-in only" \
  || fail "best-practice doc must document opt-in wake lock semantics"
contains "$BEST_PRACTICES" "install-and-start, not no-install startup" \
  || fail "best-practice doc must document install-and-start wording"
contains "$BEST_PRACTICES" "PAWXY_GITHUB_TOKEN" \
  || fail "best-practice doc must document private release token usage"
contains "$BEST_PRACTICES" "Shizuku/rish behaves like adb shell" \
  || fail "best-practice doc must document Shizuku/rish shell semantics"
contains "$BEST_PRACTICES" "PAWXY_ASSET_DIR" \
  || fail "best-practice doc must document local asset installs"

printf '%s\n' "best-practice contract ok"
