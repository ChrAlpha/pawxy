#!/bin/sh
set -eu

REPO=${PAWXY_REPO:-ChrAlpha/pawxy}
VERSION=${PAWXY_VERSION:-latest}
INSTALL_DIR=${PAWXY_INSTALL_DIR:-/data/local/tmp}
TMPDIR_BASE=${TMPDIR:-/data/local/tmp}
AUTH_TOKEN=${PAWXY_GITHUB_TOKEN:-${GITHUB_PERSONAL_ACCESS_TOKEN:-${GITHUB_TOKEN:-}}}
ASSET_DIR=${PAWXY_ASSET_DIR:-}

CTL=pawxyctl
SUMS=SHA256SUMS
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

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

need_cmd() {
  has_cmd "$1" || die "$1 command not found"
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
  else
    download "$asset" "$out"
  fi
}

need_cmd pm
need_cmd cp
need_cmd chmod
need_cmd sha256sum

work=$TMPDIR_BASE/pawxy-install.$$
rm -rf "$work"
mkdir -p "$work" "$INSTALL_DIR" || die "cannot create install directory"
trap 'rm -rf "$work"' EXIT HUP INT TERM

LOCAL_ASSET_DIR=$(find_local_asset_dir)

if [ -z "$LOCAL_ASSET_DIR" ] && [ -n "$AUTH_TOKEN" ] && [ -z "${PAWXY_DOWNLOAD_BASE:-}" ]; then
  API_MODE=1
  RELEASE_JSON=$work/release.json
  download_release_json "$RELEASE_JSON"
fi

fetch_asset "$SUMS" "$work/$SUMS"
APK=$(sed -n 's/^.*  \(pawxy-.*-debug\.apk\)$/\1/p' "$work/$SUMS" | sed -n '1p')
[ -n "$APK" ] || die "could not find Pawxy APK name in $SUMS"
fetch_asset "$APK" "$work/$APK"
fetch_asset "$CTL" "$work/$CTL"

(
  cd "$work"
  sha256sum -c "$SUMS"
) >/dev/null

pm install -r "$work/$APK"
cp "$work/$CTL" "$INSTALL_DIR/$CTL"
chmod 755 "$INSTALL_DIR/$CTL"
PAWXY_HOME=${PAWXY_HOME:-$INSTALL_DIR/pawxy}
export PAWXY_HOME
"$INSTALL_DIR/$CTL" start

INSTALLED_VERSION=${APK#pawxy-}
INSTALLED_VERSION=${INSTALLED_VERSION%-debug.apk}

cat <<EOF
Pawxy $INSTALLED_VERSION installed and started.

Control:
  $INSTALL_DIR/$CTL status
  $INSTALL_DIR/$CTL share on
  $INSTALL_DIR/$CTL stop
EOF
