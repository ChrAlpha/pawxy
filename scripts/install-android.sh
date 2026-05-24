#!/bin/sh
set -eu

REPO=${PAWXY_REPO:-ChrAlpha/pawxy}
VERSION=${PAWXY_VERSION:-latest}
INSTALL_DIR=${PAWXY_INSTALL_DIR:-/data/local/tmp}
TMPDIR_BASE=${TMPDIR:-/data/local/tmp}
AUTH_TOKEN=${PAWXY_GITHUB_TOKEN:-${GITHUB_PERSONAL_ACCESS_TOKEN:-${GITHUB_TOKEN:-}}}

CTL=pawxyctl
SUMS=SHA256SUMS
if [ "$VERSION" = "latest" ]; then
  DEFAULT_BASE_URL=https://github.com/$REPO/releases/latest/download
else
  DEFAULT_BASE_URL=https://github.com/$REPO/releases/download/$VERSION
fi
BASE_URL=${PAWXY_DOWNLOAD_BASE:-$DEFAULT_BASE_URL}

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
  url=$BASE_URL/$asset
  if has_cmd curl; then
    if [ -n "$AUTH_TOKEN" ]; then
      curl -fsSL -H "Authorization: Bearer $AUTH_TOKEN" -o "$out" "$url"
    else
      curl -fsSL -o "$out" "$url"
    fi
  elif has_cmd wget; then
    if [ -n "$AUTH_TOKEN" ]; then
      wget -q --header="Authorization: Bearer $AUTH_TOKEN" -O "$out" "$url"
    else
      wget -q -O "$out" "$url"
    fi
  else
    die "curl or wget is required"
  fi
}

need_cmd pm
need_cmd chmod
need_cmd sha256sum

work=$TMPDIR_BASE/pawxy-install.$$
rm -rf "$work"
mkdir -p "$work" "$INSTALL_DIR" || die "cannot create install directory"
trap 'rm -rf "$work"' EXIT HUP INT TERM

download "$SUMS" "$work/$SUMS"
APK=$(sed -n 's/^.*  \(pawxy-.*-debug\.apk\)$/\1/p' "$work/$SUMS" | sed -n '1p')
[ -n "$APK" ] || die "could not find Pawxy APK name in $SUMS"
download "$APK" "$work/$APK"
download "$CTL" "$work/$CTL"

(
  cd "$work"
  sha256sum -c "$SUMS"
) >/dev/null

pm install -r "$work/$APK"
cp "$work/$CTL" "$INSTALL_DIR/$CTL"
chmod 755 "$INSTALL_DIR/$CTL"
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
