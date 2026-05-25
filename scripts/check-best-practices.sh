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
CTL=$ROOT/scripts/pawxyctl
INSTALLER=$ROOT/scripts/install-android.sh
BEST_PRACTICES=$ROOT/docs/best-practices.md
README=$ROOT/README.md

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

[ -f "$INSTALLER" ] || fail "Android install-and-start script must exist"
contains "$INSTALLER" "pm install -r" \
  || fail "Android installer must install the APK with pm install -r"
contains "$INSTALLER" "sha256sum -c" \
  || fail "Android installer must verify release downloads"
contains "$INSTALLER" '"$INSTALL_DIR/$CTL" start' \
  || fail "Android installer must start through installed pawxyctl"
contains "$INSTALLER" "PAWXY_GITHUB_TOKEN" \
  || fail "Android installer must support private release token downloads"
contains "$INSTALLER" "PAWXY_ASSET_DIR" \
  || fail "Android installer must support local release assets for Shizuku/rish shells"
contains "$CTL" "shell uid:" \
  || fail "pawxyctl doctor must show the Android shell uid"
contains "$CTL" "Shizuku/rish behaves like adb shell" \
  || fail "pawxyctl doctor must document Shizuku/rish shell semantics"
contains "$README" "rish -c" \
  || fail "README must document Shizuku/rish control examples"

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
contains "$WORKFLOW" "scripts/install-android.sh" \
  || fail "Packaging workflow must verify and package the Android install script"
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
