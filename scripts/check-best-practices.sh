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
  grep -F "$text" "$file" >/dev/null 2>&1
}

not_contains() {
  file=$1
  text=$2
  ! grep -F "$text" "$file" >/dev/null 2>&1
}

MANIFEST=$ROOT/android/app/src/main/AndroidManifest.xml
SERVICE=$ROOT/android/app/src/main/java/dev/pawxy/ProxyService.kt
PROVIDER=$ROOT/android/app/src/main/java/dev/pawxy/StatusProvider.kt
CTL=$ROOT/scripts/pawxyctl
BEST_PRACTICES=$ROOT/docs/best-practices.md

contains "$MANIFEST" "android.permission.ACCESS_NETWORK_STATE" \
  || fail "Android service must declare ACCESS_NETWORK_STATE for default-network observation"

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
contains "$WORKFLOW" "actions/upload-artifact@v7" \
  || fail "Packaging workflow must upload workflow artifacts"
contains "$WORKFLOW" "gh release upload" \
  || fail "Packaging workflow must upload assets to GitHub releases"

contains "$BEST_PRACTICES" "Never retry an established TCP tunnel transparently" \
  || fail "best-practice doc must forbid transparent TCP tunnel retry"
contains "$BEST_PRACTICES" 'Do not bind outbound sockets to a specific Android `Network`' \
  || fail "best-practice doc must forbid binding outbound sockets to a captured Android Network"
contains "$BEST_PRACTICES" "Wake lock is opt-in only" \
  || fail "best-practice doc must document opt-in wake lock semantics"

printf '%s\n' "best-practice contract ok"
