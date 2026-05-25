# Pawxy

Pawxy is a CLI-only Android-native mixed-port direct forwarder. It runs as an
Android Foreground Service with an embedded Rust forwarding core and exposes one
TCP port that accepts both HTTP proxy and SOCKS5 proxy traffic.

Pawxy is not a VPN, TUN, transparent proxy, dashboard, subscription client, rule
router, upstream proxy manager, DNS hijacker, TLS MITM tool, or Termux-bound
runtime. It has no Activity, launcher screen, layouts, Compose, WebView, or
settings UI. The only Android UI surface is the required persistent foreground
service notification.

## Build

Rust local checks:

```sh
cargo test -p pawxy-core
cargo run -p pawxy-cli -- serve --listen 127.0.0.1:7890
```

Android debug APK:

```sh
cargo install cargo-ndk
scripts/build-android.sh
scripts/install-apk-adb.sh
```

Install and start on Android in one command:

```sh
curl -fsSL https://github.com/ChrAlpha/pawxy/releases/latest/download/install-android.sh | sh
```

For this private repository, pass a GitHub token for both the script download
and release asset downloads:

```sh
curl -fsSL -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" https://raw.githubusercontent.com/ChrAlpha/pawxy/main/scripts/install-android.sh | PAWXY_GITHUB_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN" sh
```

GitHub packaging is also available from Actions:

- Run **Package Android** manually to download APK, `pawxyctl`,
  `install-android.sh`, and checksums as a workflow artifact.
- Publish a GitHub Release to build the same files and attach them to the
  release automatically.

## CLI

The Android service is controlled with `scripts/pawxyctl`, which can run from
`adb shell`, Termux, or another Android shell when the standard Android `am`,
`content`, and `logcat` commands are available.

```sh
pawxyctl start
pawxyctl status
pawxyctl status --json
pawxyctl share on
pawxyctl wake on
pawxyctl stop
```

Defaults are local-only and unauthenticated:

```text
listen = 127.0.0.1:7890
auth = off
max_connections = 256
max_per_source_ip = 64
```

LAN sharing uses `0.0.0.0:7890`, forces authentication, and stores the generated
password in `${PAWXY_HOME:-$HOME/.config/pawxy}/config.env` or
`/data/local/tmp/pawxy/config.env` when `$HOME` is unavailable.

## Test Traffic

```sh
curl -x http://127.0.0.1:7890 http://example.com
curl -x http://127.0.0.1:7890 https://example.com
curl --socks5-hostname 127.0.0.1:7890 https://example.com
```

## Security Defaults

Local mode binds `127.0.0.1:7890` with auth off. LAN mode always requires proxy
auth, and core config validation rejects `0.0.0.0` or `::` without auth.

The foreground service keeps Pawxy visible to Android. Wake lock is optional via
`pawxyctl wake on`; it is not enabled automatically. Vendor ROMs may still kill
background services, so Pawxy does not promise impossible keepalive guarantees.

Network and Android hardening consensus is tracked in
[`docs/best-practices.md`](docs/best-practices.md).
