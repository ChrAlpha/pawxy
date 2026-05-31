#!/bin/sh
set -eu

REPO=${PAWXY_REPO:-ChrAlpha/pawxy}
VERSION=${PAWXY_VERSION:-latest}
INSTALL_DIR=${PAWXY_INSTALL_DIR:-/data/local/tmp}
TMPDIR_BASE=${TMPDIR:-/data/local/tmp}
AUTH_TOKEN=${PAWXY_GITHUB_TOKEN:-${GITHUB_PERSONAL_ACCESS_TOKEN:-${GITHUB_TOKEN:-}}}
ASSET_DIR=${PAWXY_ASSET_DIR:-}
STARTUP_RETRIES=${PAWXY_STARTUP_RETRIES:-20}
STARTUP_SLEEP_SECONDS=${PAWXY_STARTUP_SLEEP_SECONDS:-1}
START_SENT=0

CTL=pawxyctl
SUMS=SHA256SUMS
PKG=dev.pawxy
if [ "$VERSION" = "latest" ]; then
  DEFAULT_BASE_URL=https://github.com/$REPO/releases/latest/download
else
  DEFAULT_BASE_URL=https://github.com/$REPO/releases/download/$VERSION
fi
BASE_URL=${PAWXY_DOWNLOAD_BASE:-$DEFAULT_BASE_URL}
API_MODE=0
RELEASE_JSON=

die() {
  printf '%s\n' "pawxy install: $*" >&2
  exit 1
}

warn() {
  printf '%s\n' "pawxy install: warning: $*" >&2
}

info() {
  printf '%s\n' "pawxy install: $*" >&2
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

need_cmd() {
  has_cmd "$1" || die "$1 command not found"
}

json_bool_field() {
  field=$1
  json=$2
  printf '%s\n' "$json" | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | sed -n '1p'
}

json_string_field() {
  field=$1
  json=$2
  printf '%s\n' "$json" | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p'
}

require_non_negative_int() {
  name=$1
  value=$2
  case "$value" in
    ''|*[!0-9]*) die "$name must be a non-negative integer" ;;
  esac
}

run_step() {
  label=$1
  shift
  if output=$("$@" 2>&1); then
    [ -z "$output" ] || printf '%s\n' "$output" >&2
  else
    rc=$?
    [ -z "$output" ] || printf '%s\n' "$output" >&2
    die "$label failed (exit $rc)"
  fi
}

verify_checksums() {
  if output=$(cd "$work" && sha256sum -c "$SUMS" 2>&1); then
    return
  fi
  rc=$?
  [ -z "$output" ] || printf '%s\n' "$output" >&2
  die "SHA256 verification failed (exit $rc)"
}

base64_decode() {
  if has_cmd base64; then
    base64 -d
  elif has_cmd toybox; then
    toybox base64 -d
  else
    die "base64 or toybox is required to extract embedded release assets"
  fi
}

# PAWXY_EMBEDDED_ASSETS_BEGIN
embedded_asset() {
  return 1
}
# PAWXY_EMBEDDED_ASSETS_END

shell_dump_permission() {
  result=$(pm check-permission android.permission.DUMP com.android.shell 2>/dev/null || true)
  case "$result" in
    granted*|denied*)
      printf '%s\n' "$result"
      return
      ;;
  esac

  if has_cmd cmd; then
    fallback=$(cmd package check-permission android.permission.DUMP com.android.shell 2>/dev/null || true)
    case "$fallback" in
      granted*|denied*)
        printf '%s\n' "$fallback"
        return
        ;;
    esac
    [ -z "$fallback" ] || result=$fallback
  fi

  printf '%s\n' "unknown"
}

verify_android_shell_permissions() {
  uid=$(id -u 2>/dev/null || true)
  case "$uid" in
    0|2000)
      ;;
    *)
      die "installer must run as Android shell or root; got uid ${uid:-unknown}. Run through adb shell or Shizuku/rish."
      ;;
  esac

  if [ "$uid" = "2000" ]; then
    dump_permission=$(shell_dump_permission)
    case "$dump_permission" in
      granted*)
        ;;
      denied*)
        die "com.android.shell lacks android.permission.DUMP: $dump_permission. Run through adb shell or Shizuku/rish."
        ;;
      *)
        warn "could not verify com.android.shell android.permission.DUMP; continuing and relying on startup verification."
        ;;
    esac
  fi
}

verify_package_installed() {
  package_path=$(pm path "$PKG" 2>/dev/null | awk '/^package:/ { print; exit }')
  [ -n "$package_path" ] \
    || die "Pawxy package $PKG was not visible after install; pm path returned empty"
}

stop_started_service() {
  [ "$START_SENT" = "1" ] || return 0
  PAWXY_HOME=${PAWXY_HOME:-$INSTALL_DIR/pawxy} "$INSTALL_DIR/$CTL" stop >/dev/null 2>&1 || true
}

wait_for_running_status() {
  attempt=0
  status_json=
  status_error=
  while [ "$attempt" -le "$STARTUP_RETRIES" ]; do
    status_json=$("$INSTALL_DIR/$CTL" status --json 2>/dev/null || true)
    if [ "$(json_bool_field running "$status_json")" = "true" ] \
      && [ "$(json_bool_field native_running "$status_json")" = "true" ] \
      && [ "$(json_bool_field auth_enabled "$status_json")" = "false" ] \
      && [ "$(json_bool_field native_auth_enabled "$status_json")" = "false" ] \
      && [ "$(json_bool_field configured_auth_enabled "$status_json")" = "false" ]; then
      return 0
    fi
    current_error=$(json_string_field error "$status_json")
    if [ -z "$current_error" ] || [ "$current_error" = "null" ]; then
      current_error=$(json_string_field last_error "$status_json")
    fi
    [ -z "$current_error" ] || status_error=$current_error
    attempt=$((attempt + 1))
    [ "$attempt" -le "$STARTUP_RETRIES" ] || break
    sleep "$STARTUP_SLEEP_SECONDS"
  done
  if [ -n "$status_error" ]; then
    stop_started_service
    die "Pawxy did not report running=true/native_running=true after start; status error=$status_error: ${status_json:-empty status}"
  fi
  stop_started_service
  die "Pawxy did not report running=true/native_running=true after start: ${status_json:-empty status}"
}

download() {
  asset=$1
  out=$2
  if [ "$API_MODE" = "1" ]; then
    url=$(asset_api_url "$asset")
    [ -n "$url" ] || die "release asset not found: $asset"
    curl_accept='Accept: application/octet-stream'
  else
    url=$BASE_URL/$asset
    curl_accept='Accept: */*'
  fi
  if has_cmd curl; then
    if [ -n "$AUTH_TOKEN" ]; then
      curl -fsSL -H "Authorization: Bearer $AUTH_TOKEN" -H "$curl_accept" -o "$out" "$url"
    else
      curl -fsSL -o "$out" "$url"
    fi
  elif has_cmd wget; then
    if [ -n "$AUTH_TOKEN" ]; then
      wget -q --header="Authorization: Bearer $AUTH_TOKEN" --header="$curl_accept" -O "$out" "$url"
    else
      wget -q -O "$out" "$url"
    fi
  else
    die "curl or wget is required unless PAWXY_ASSET_DIR points to local release assets"
  fi
}

download_release_json() {
  out=$1
  if [ "$VERSION" = "latest" ]; then
    url=https://api.github.com/repos/$REPO/releases/latest
  else
    url=https://api.github.com/repos/$REPO/releases/tags/$VERSION
  fi
  if has_cmd curl; then
    curl -fsSL -H "Authorization: Bearer $AUTH_TOKEN" -H "Accept: application/vnd.github+json" -o "$out" "$url"
  elif has_cmd wget; then
    wget -q --header="Authorization: Bearer $AUTH_TOKEN" --header="Accept: application/vnd.github+json" -O "$out" "$url"
  else
    die "curl or wget is required"
  fi
}

asset_api_url() {
  asset=$1
  awk -v wanted="$asset" '
    /"url": "https:\/\/api.github.com\/repos\/.*\/releases\/assets\// {
      url = $2
      gsub(/[",]/, "", url)
    }
    /"name":/ {
      name = $2
      gsub(/[",]/, "", name)
      if (name == wanted) {
        print url
        exit
      }
    }
  ' "$RELEASE_JSON"
}

script_dir() {
  case "$0" in
    */*)
      dir=${0%/*}
      [ -n "$dir" ] || dir=/
      CDPATH= cd "$dir" && pwd
      ;;
    *)
      return 1
      ;;
  esac
}

find_local_asset_dir() {
  if [ -n "$ASSET_DIR" ]; then
    [ -d "$ASSET_DIR" ] || die "PAWXY_ASSET_DIR not found: $ASSET_DIR"
    printf '%s\n' "$ASSET_DIR"
    return
  fi
  if [ -f "$SUMS" ] && [ -f "$CTL" ]; then
    pwd
    return
  fi
  dir=$(script_dir 2>/dev/null || true)
  if [ -n "$dir" ] && [ -f "$dir/$SUMS" ] && [ -f "$dir/$CTL" ]; then
    printf '%s\n' "$dir"
    return
  fi
}

copy_local_asset() {
  asset=$1
  out=$2
  [ -f "$LOCAL_ASSET_DIR/$asset" ] || die "local release asset not found: $LOCAL_ASSET_DIR/$asset"
  cp "$LOCAL_ASSET_DIR/$asset" "$out" || die "cannot copy local release asset: $asset"
}

fetch_asset() {
  asset=$1
  out=$2
  if [ -n "$LOCAL_ASSET_DIR" ]; then
    copy_local_asset "$asset" "$out"
  elif embedded_asset "$asset" "$out"; then
    :
  else
    download "$asset" "$out"
  fi
}

need_cmd pm
need_cmd cp
need_cmd chmod
need_cmd sha256sum
need_cmd id
require_non_negative_int PAWXY_STARTUP_RETRIES "$STARTUP_RETRIES"
require_non_negative_int PAWXY_STARTUP_SLEEP_SECONDS "$STARTUP_SLEEP_SECONDS"
verify_android_shell_permissions

work=$TMPDIR_BASE/pawxy-install.$$
rm -rf "$work"
mkdir -p "$work" "$INSTALL_DIR" || die "cannot create install directory"
trap 'rm -rf "$work"' EXIT HUP INT TERM

LOCAL_ASSET_DIR=$(find_local_asset_dir)
EMBEDDED_SUMS_READY=0
if [ -z "$LOCAL_ASSET_DIR" ] && embedded_asset "$SUMS" "$work/$SUMS"; then
  EMBEDDED_SUMS_READY=1
fi

if [ "$EMBEDDED_SUMS_READY" = "0" ] \
  && [ -z "$LOCAL_ASSET_DIR" ] \
  && [ -n "$AUTH_TOKEN" ] \
  && [ -z "${PAWXY_DOWNLOAD_BASE:-}" ]; then
  API_MODE=1
  RELEASE_JSON=$work/release.json
  download_release_json "$RELEASE_JSON"
fi

if [ "$EMBEDDED_SUMS_READY" = "0" ]; then
  fetch_asset "$SUMS" "$work/$SUMS"
fi
APK=$(sed -n 's/^.*  \(pawxy-.*-debug\.apk\)$/\1/p' "$work/$SUMS" | sed -n '1p')
[ -n "$APK" ] || die "could not find Pawxy APK name in $SUMS"
fetch_asset "$APK" "$work/$APK"
fetch_asset "$CTL" "$work/$CTL"

info "verifying release assets"
verify_checksums
info "installing $APK"
run_step "pm install" pm install -r "$work/$APK"
verify_package_installed
pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
info "installing pawxyctl to $INSTALL_DIR/$CTL"
run_step "copy pawxyctl" cp "$work/$CTL" "$INSTALL_DIR/$CTL"
run_step "chmod pawxyctl" chmod 755 "$INSTALL_DIR/$CTL"
PAWXY_HOME=${PAWXY_HOME:-$INSTALL_DIR/pawxy}
export PAWXY_HOME
START_SENT=1
info "starting Pawxy"
"$INSTALL_DIR/$CTL" start \
  || {
    stop_started_service
    die "failed to start Pawxy through installed pawxyctl"
  }
wait_for_running_status

INSTALLED_VERSION=${APK#pawxy-}
INSTALLED_VERSION=${INSTALLED_VERSION%-debug.apk}

cat <<EOF
Pawxy $INSTALLED_VERSION installed and started.

Control:
  PAWXY_HOME=$PAWXY_HOME $INSTALL_DIR/$CTL status
  PAWXY_HOME=$PAWXY_HOME $INSTALL_DIR/$CTL share on
  PAWXY_HOME=$PAWXY_HOME $INSTALL_DIR/$CTL stop
EOF
