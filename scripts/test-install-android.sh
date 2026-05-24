#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/install-android.sh

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail "scripts/install-android.sh must exist"
sh -n "$SCRIPT"

tmp=${TMPDIR:-/tmp}/pawxy-install-test.$$
rm -rf "$tmp"
mkdir -p "$tmp/bin" "$tmp/log" "$tmp/release" "$tmp/install" "$tmp/tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

printf 'fake apk\n' > "$tmp/release/pawxy-0.1.0-debug.apk"
cat > "$tmp/release/pawxyctl" <<'CTL'
#!/bin/sh
printf '%s\n' "$*" > "$PAWXY_TEST_LOG/pawxyctl.args"
CTL
chmod 755 "$tmp/release/pawxyctl"
(
  cd "$tmp/release"
  sha256sum pawxy-0.1.0-debug.apk pawxyctl > SHA256SUMS
)

cat > "$tmp/bin/curl" <<'CURL'
#!/bin/sh
out=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out=$2
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
[ -n "$out" ] || exit 2
asset=${url##*/}
cp "$PAWXY_TEST_RELEASE/$asset" "$out"
CURL
chmod 755 "$tmp/bin/curl"

cat > "$tmp/bin/pm" <<'PM'
#!/bin/sh
printf '%s\n' "$*" > "$PAWXY_TEST_LOG/pm.args"
PM
chmod 755 "$tmp/bin/pm"

PATH="$tmp/bin:$PATH" \
PAWXY_VERSION=0.1.0 \
PAWXY_INSTALL_DIR="$tmp/install" \
PAWXY_TEST_RELEASE="$tmp/release" \
PAWXY_TEST_LOG="$tmp/log" \
TMPDIR="$tmp/tmp" \
  sh "$SCRIPT" >/dev/null

grep -F -- "install -r" "$tmp/log/pm.args" >/dev/null \
  || fail "installer must call pm install -r"
grep -Fx -- "start" "$tmp/log/pawxyctl.args" >/dev/null \
  || fail "installer must start pawxy through installed pawxyctl"
[ -x "$tmp/install/pawxyctl" ] || fail "installer must install executable pawxyctl"

printf '%s\n' "install-android test ok"
