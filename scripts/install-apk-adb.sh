#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

APK=android/app/build/outputs/apk/debug/app-debug.apk
[ -f "$APK" ] || {
  printf '%s\n' "APK not found at $APK. Run scripts/build-android.sh first." >&2
  exit 1
}

adb install -r "$APK"
adb push scripts/pawxyctl /data/local/tmp/pawxyctl
adb shell chmod 755 /data/local/tmp/pawxyctl

cat <<'USAGE'
Installed Pawxy.

Examples:
  adb shell /data/local/tmp/pawxyctl start
  adb shell /data/local/tmp/pawxyctl status
  adb shell /data/local/tmp/pawxyctl share on

Direct intent example:
  adb shell am start-foreground-service -n dev.pawxy/.ProxyService -a dev.pawxy.action.START --es token "$(adb shell cat /data/local/tmp/pawxy/token 2>/dev/null)"
USAGE
