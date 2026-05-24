# Pawxy MVP Superpowers Spec

> **For agentic workers:** This is the controlling MVP specification for Pawxy.
> Treat every `MUST`, `MUST NOT`, and acceptance gate as a hard development
> constraint. Before changing runtime behavior, derive tests from this spec,
> update this document if the product contract changes, and run the verification
> gates listed below.

**Goal:** Pawxy is a CLI-only Android-native mixed-port direct forwarder. It
runs as an Android Foreground Service with an embedded Rust forwarding core,
exposes one TCP port, accepts both HTTP proxy and SOCKS5 proxy traffic on that
port, and directly forwards each connection to its target address.

**Architecture:** Rust owns protocol parsing, TCP forwarding, auth, metrics,
timeouts, and limits. JNI is used only for lifecycle control and status. Android
owns foreground-service lifecycle, token-protected CLI control, status provider,
minimal notification, wake-lock state, and default-network observability.

**Tech Stack:** Rust, Tokio, JNI, Kotlin Android, Gradle, POSIX `sh`.

---

## 1. Scope Contract

### 1.1 Product Identity

Pawxy MUST remain:

- CLI-only.
- Android-native.
- A direct TCP forwarder.
- A mixed-port HTTP proxy + SOCKS5 proxy listener.
- Local-first by default.
- Minimal, readable, and boring.

Pawxy MUST NOT become:

- A VPN, TUN, or transparent proxy.
- A programmable proxy engine.
- A routing/rule engine.
- A subscription client.
- An upstream proxy manager.
- A DNS hijacker.
- A TLS MITM tool.
- An Android global-proxy configurator.
- A UI application.
- A Termux-bound runtime.

### 1.2 UI Prohibition

The Android app MUST NOT contain:

- Activity declarations.
- Launcher screen.
- Compose.
- XML layouts.
- Dashboard.
- WebView.
- Settings screen.
- Runtime notification-permission UI.

The required Android foreground-service notification is allowed and required.
It MUST remain minimal and persistent.

### 1.3 Termux Boundary

Termux MUST NOT be a runtime dependency. `scripts/pawxyctl` MAY be run from
Termux, but it MUST also work from `adb shell` and other Android shell
environments when the standard Android shell commands are present.

---

## 2. Repository Contract

The repository MUST keep these source files and responsibilities:

```text
Cargo.toml
crates/
  pawxy-core/
    Cargo.toml
    src/
      lib.rs          # public Rust core exports
      config.rs       # config model and validation
      error.rs        # error model
      metrics.rs      # status and counters
      server.rs       # accept loop and proxy protocol dispatch
      sniff.rs        # mixed-port protocol classification
      http_proxy.rs   # HTTP proxy parsing/auth/rewrite helpers
      socks5.rs       # SOCKS5 parsing/auth helpers
      tunnel.rs       # bidirectional TCP tunnel
      auth.rs         # shared auth helpers
    tests/
      proxy.rs        # end-to-end Rust proxy integration tests
  pawxy-jni/
    Cargo.toml
    src/lib.rs        # nativeStart/nativeStop/nativeStatus only
  pawxy-cli/
    Cargo.toml
    src/main.rs       # desktop/local dev server
android/
  settings.gradle.kts
  build.gradle.kts
  gradlew
  gradlew.bat
  gradle/wrapper/
    gradle-wrapper.jar
    gradle-wrapper.properties
  app/
    build.gradle.kts
    src/main/
      AndroidManifest.xml
      java/dev/pawxy/
        ProxyService.kt
        PawxyNative.kt
        StatusProvider.kt
        ControlToken.kt
        NotificationHelper.kt
      res/drawable/ic_stat_pawxy.xml
      res/values/strings.xml
scripts/
  pawxyctl
  build-android.sh
  install-apk-adb.sh
  check-best-practices.sh
.github/
  workflows/
    package-android.yml
docs/
  mvp.md
  best-practices.md
README.md
```

Build outputs MUST stay ignored:

- `target/`
- `android/.gradle/`
- `android/app/build/`
- `android/app/src/main/jniLibs/`

---

## 3. Architecture Contract

### 3.1 Rust Core

`crates/pawxy-core` MUST be platform-independent. It MUST own:

- TCP listener and accept loop.
- Mixed-port protocol sniffing.
- HTTP proxy handling.
- SOCKS5 handling.
- Proxy authentication.
- Connection limits.
- Timeouts.
- TCP tunneling.
- Metrics and status state.

The Rust core MUST NOT depend on Android APIs, JNI, Termux paths, Gradle, or
Kotlin.

### 3.2 JNI Bridge

`crates/pawxy-jni` MUST build a `cdylib` named `libpawxy_jni.so`.

JNI MUST expose only:

```text
Java_dev_pawxy_PawxyNative_nativeStart
Java_dev_pawxy_PawxyNative_nativeStop
Java_dev_pawxy_PawxyNative_nativeStatus
```

Kotlin declaration MUST remain:

```kotlin
object PawxyNative {
    init { System.loadLibrary("pawxy_jni") }
    external fun nativeStart(configJson: String): String
    external fun nativeStop(): String
    external fun nativeStatus(): String
}
```

JNI MUST NOT run per connection. JNI is lifecycle/status only.

### 3.3 Android Service

`android/app` MUST be a Kotlin Android app with no UI.

`ProxyService` MUST be an exported foreground service controlled by explicit
CLI intents. It MUST load `libpawxy_jni.so` through `PawxyNative` and call only
`nativeStart`, `nativeStop`, and `nativeStatus`.

`ProxyService` MUST call `startForeground` before native startup work that can
block or fail.

### 3.4 CLI

`scripts/pawxyctl` MUST be POSIX `sh`. It MUST control Android using:

- `am start-foreground-service`
- `content query`
- `logcat`

The CLI MUST NOT run the proxy itself. The CLI only controls the Android
foreground service.

---

## 4. Rust Core Spec

### 4.1 Dependencies

Keep dependencies small. The MVP-approved core dependency set is:

```toml
tokio = { version = "1", features = ["rt-multi-thread", "net", "io-util", "time", "sync", "macros"] }
bytes = "1"
httparse = "1"
memchr = "2"
base64 = "0.22"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
tracing = "0.1"
socket2 = "0.5"
```

New dependencies require a documented reason in `docs/best-practices.md` or a
future spec update.

### 4.2 Public API

The core MUST expose:

```rust
pub struct PawxyConfig;
pub struct AuthConfig;
pub struct PawxyStatus;
pub struct PawxyServer;

impl PawxyServer {
    pub async fn run(config: PawxyConfig, shutdown: ShutdownSignal) -> Result<()>;
}
```

Additional public helpers are allowed only when they support JNI, CLI, or tests
without leaking implementation details.

### 4.3 Config

`PawxyConfig` MUST include:

```text
listen: SocketAddr
auth: Option<AuthConfig>
max_connections: usize
max_per_source_ip: usize
handshake_timeout: Duration
connect_timeout: Duration
idle_timeout: Duration
tcp_nodelay: bool
tcp_keepalive: bool
```

Defaults MUST be:

```text
listen = 127.0.0.1:7890
auth = None
max_connections = 256
max_per_source_ip = 64
handshake_timeout = 5000 ms
connect_timeout = 10000 ms
idle_timeout = 1800000 ms
tcp_nodelay = true
tcp_keepalive = true
```

`AuthConfig` MUST be:

```text
username: String
password: String
```

Config validation MUST reject wildcard listen addresses without authentication:

- `0.0.0.0:*` with `auth = None`
- `[::]:*` with `auth = None`

### 4.4 Protocol Detection

For every accepted TCP connection, the core MUST:

1. Read a small initial prefix with `handshake_timeout`.
2. Read at most 512 bytes for the initial sniff.
3. Preserve every consumed byte for the selected handler.
4. Classify:
   - first byte `0x05` as SOCKS5.
   - prefix starting with `CONNECT`, `GET`, `POST`, `PUT`, `DELETE`,
     `PATCH`, `HEAD`, or `OPTIONS` as HTTP proxy.
   - anything else as invalid and closed without forwarding.

### 4.5 HTTP Proxy

The HTTP proxy MUST support:

- `CONNECT host:port HTTP/1.1`
- Absolute-form HTTP/1.1 requests:
  - `GET http://host/path HTTP/1.1`
  - `POST http://host/path HTTP/1.1`
  - `PUT http://host/path HTTP/1.1`
  - `PATCH http://host/path HTTP/1.1`
  - `DELETE http://host/path HTTP/1.1`
  - `HEAD http://host/path HTTP/1.1`
  - `OPTIONS http://host/path HTTP/1.1`

The HTTP proxy MUST NOT support:

- HTTP/2 proxying.
- CONNECT-UDP.
- HTTPS absolute-form URLs.
- TLS MITM.
- Header rewriting beyond the minimum required for absolute-form forwarding.

HTTP parser requirements:

- Read until `\r\n\r\n`.
- Header limit is 16 KiB.
- Use `httparse`.
- Return clear `400` or `502` responses where appropriate.

HTTP auth requirements:

- If auth is configured, require:

```text
Proxy-Authorization: Basic base64(username:password)
```

- If missing or wrong, return:

```text
HTTP/1.1 407 Proxy Authentication Required
Proxy-Authenticate: Basic realm="Pawxy"
Connection: close
```

`CONNECT` behavior:

1. Parse `host:port` from request target.
2. Apply auth if configured.
3. Connect to target with `connect_timeout`.
4. Return `HTTP/1.1 200 Connection Established\r\n\r\n`.
5. Tunnel client and target.

Absolute-form HTTP behavior:

1. Parse full URL.
2. Support only `http://`.
3. Extract host, port default `80`, and path/query.
4. Rewrite request line to origin-form:

```text
METHOD /path?query HTTP/1.1
```

5. Drop proxy-only headers:
   - `Proxy-Authorization`
   - `Proxy-Connection`
6. Preserve other headers.
7. Preserve already-read body bytes.
8. Forward rewritten request to target.
9. Tunnel client and target.

### 4.6 SOCKS5

SOCKS5 MUST support only:

- `VER = 0x05`
- `CMD = CONNECT`
- `ATYP = IPv4`, `IPv6`, or `DOMAIN`
- no-auth when `config.auth` is `None`
- username/password when `config.auth` is `Some`

SOCKS5 MUST NOT support:

- `BIND`
- `UDP ASSOCIATE`
- SOCKS4

If auth is configured, Pawxy MUST choose method `0x02` and implement RFC1929
username/password sub-negotiation:

```text
VER = 0x01
ULEN
UNAME
PLEN
PASSWD
```

Wrong SOCKS5 auth MUST return failure and close.

SOCKS5 connect behavior:

1. Parse target host and port.
2. Connect to target with `connect_timeout`.
3. Reply success with `BND.ADDR = 0.0.0.0` and `BND.PORT = 0`.
4. Tunnel client and target.

### 4.7 Tunneling

The tunnel MUST:

- Stop parsing after the initial proxy handshake/request.
- Use two directional copy loops.
- Use per-read idle timeout, not total session timeout.
- Preserve TCP half-close where possible.
- Count bytes in both directions.
- Decrement active connection count on completion.
- Record total connection count.
- Log connection errors at debug/warn level, not fatal.

Tunnel implementation SHOULD use:

- around 32 KiB buffer per direction.
- `TCP_NODELAY` enabled by default.
- OS `SO_KEEPALIVE` when supported.
- `connect_timeout = 10s`.
- `idle_timeout = 30min`.

Transparent reconnect of an established TCP tunnel MUST NOT be implemented.
Retried byte streams can duplicate, reorder, or corrupt client-visible data.

### 4.8 Limits and Metrics

Connection limits:

- Global `max_connections` default is `256`.
- Per-source-IP `max_per_source_ip` default is `64`.
- Over-limit connections MUST be closed gracefully.
- Unauthenticated LAN scans MUST NOT be able to exhaust unbounded resources.

Metrics MUST use atomics where possible:

- `active_connections`
- `total_connections`
- `bytes_in`
- `bytes_out`
- `started_at_unix_ms`

`last_error` MAY be lock-protected.

---

## 5. JNI Spec

`nativeStart(configJson: String)` MUST:

1. Parse config JSON.
2. Validate core config.
3. Stop any existing server first.
4. Spawn a dedicated Rust runtime thread.
5. Start `pawxy-core`.
6. Return JSON:

```json
{"ok":true,"running":true}
```

or:

```json
{"ok":false,"error":"..."}
```

`nativeStop()` MUST:

- Signal shutdown.
- Join or detach safely without blocking Android indefinitely.
- Return current JSON status.

`nativeStatus()` MUST:

- Return current JSON status even if stopped.
- Include errors visible enough for `pawxyctl status --json`.

---

## 6. Android Spec

### 6.1 Package and Manifest

Android package MUST be:

```text
dev.pawxy
```

Manifest MUST include:

- `android.permission.INTERNET`
- `android.permission.ACCESS_NETWORK_STATE`
- `android.permission.FOREGROUND_SERVICE`
- `android.permission.FOREGROUND_SERVICE_SPECIAL_USE`
- `android.permission.WAKE_LOCK`
- `android.permission.POST_NOTIFICATIONS`

Manifest MUST NOT declare any Activity.

`ProxyService` declaration MUST include:

```xml
<service
    android:name=".ProxyService"
    android:exported="true"
    android:foregroundServiceType="specialUse">
```

Intent actions MUST include:

- `dev.pawxy.action.START`
- `dev.pawxy.action.STOP`
- `dev.pawxy.action.RESTART`
- `dev.pawxy.action.WAKE_ON`
- `dev.pawxy.action.WAKE_OFF`

Special-use subtype property MUST be:

```text
android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE = "local_mixed_port_proxy_server"
```

`StatusProvider` declaration MUST be:

```xml
<provider
    android:name=".StatusProvider"
    android:authorities="dev.pawxy.status"
    android:exported="true" />
```

### 6.2 Control Token

Because service and provider are exported, control MUST be protected by a shared
token.

CLI token path:

```text
${PAWXY_HOME:-$HOME/.config/pawxy}/token
```

If `$HOME` is empty or not writable, CLI MUST fall back to:

```text
/data/local/tmp/pawxy/token
```

Token rules:

- `pawxyctl` MUST generate a random 32-byte hex token if missing.
- Token generation MUST fail closed if `/dev/urandom` plus `od` or `hexdump`
  is unavailable.
- Every control intent MUST include `--es token "$TOKEN"`.
- `ProxyService` MUST store the first valid non-empty START token in
  SharedPreferences key `control_token`.
- After provisioning, START, STOP, RESTART, WAKE_ON, and WAKE_OFF MUST reject
  missing or mismatched tokens.
- Rejected commands MUST log a warning and perform no proxy action.
- Token reset is out of scope; users may clear app data or reinstall.

### 6.3 ProxyService

`ProxyService` MUST:

- Extend `Service`.
- Return `null` from `onBind`.
- Handle START, STOP, RESTART, WAKE_ON, and WAKE_OFF.
- Validate token before action execution.
- Reject wildcard listen without auth before saving config or starting native
  code.

START MUST:

1. Build config JSON from intent extras.
2. Save config in SharedPreferences.
3. Call `startForeground` with minimal notification.
4. Call `PawxyNative.nativeStart(configJson)`.
5. Return `START_STICKY`.

Null intent after service restart MUST:

1. Load last saved config.
2. Call `startForeground`.
3. Call `nativeStart(lastConfig)`.
4. Return `START_STICKY` if config exists.

STOP MUST:

1. Call `nativeStop`.
2. Release wake lock.
3. Clear service-started and wake-lock state.
4. Stop foreground notification.
5. Stop service.

RESTART MUST:

1. Validate token.
2. Call `nativeStop`.
3. Start using the new config.

### 6.4 Wake Lock

Wake lock behavior:

- Default is off.
- Wake lock is controlled only by `pawxyctl wake on/off`.
- Use `PARTIAL_WAKE_LOCK`.
- Do not enable wake lock automatically.
- Notification text MUST show wake-lock state when enabled.
- STOP and service destroy MUST release wake lock.

### 6.5 Notification

Notification requirements:

- Channel id: `pawxy`.
- Title: `Pawxy running`.
- Text: `HTTP + SOCKS5 on <listen>` with wake-lock suffix when enabled.
- Small icon: `ic_stat_pawxy.xml`.
- Persistent/ongoing.
- No Activity-backed actions.

### 6.6 Default Network Observability

Pawxy MUST observe Android default network changes for status/logging only.

Implementation requirements:

- Declare `ACCESS_NETWORK_STATE`.
- Use `ConnectivityManager.registerDefaultNetworkCallback`.
- Unregister callback on service destroy.
- Expose Android-side status fields:
  - `network_available`
  - `network_transport`
  - `network_generation`

Pawxy MUST NOT:

- Bind outbound sockets to a captured Android `Network`.
- Auto-restart the proxy on every network transition.
- Claim existing TCP tunnels survive route or VPN replacement.

### 6.7 StatusProvider

Status query URI format:

```text
content://dev.pawxy.status/status/<token>
```

If token is missing or mismatched, return one row:

```json
{"ok":false,"error":"unauthorized"}
```

If authorized:

- Return one row.
- Return one column named `json`.
- Include native status plus Android-side fields.

Status JSON MUST include at least:

```text
ok
running
listen
lan
auth_enabled
active_connections
total_connections
bytes_in
bytes_out
started_at_unix_ms
last_error
version
wake_lock_enabled
service_started
network_available
network_transport
network_generation
```

---

## 7. CLI Spec

### 7.1 Commands

`scripts/pawxyctl` MUST implement:

```text
pawxyctl start
pawxyctl stop
pawxyctl restart
pawxyctl status
pawxyctl status --json
pawxyctl logs
pawxyctl share on
pawxyctl share off
pawxyctl wake on
pawxyctl wake off
pawxyctl doctor
```

### 7.2 Local Mode

`pawxyctl start` MUST start local-only mode:

```text
listen = 127.0.0.1:7890
auth_enabled = false
max_connections = 256
max_per_source_ip = 64
handshake_timeout_ms = 5000
connect_timeout_ms = 10000
idle_timeout_ms = 1800000
wake_lock = unchanged/off by default
```

### 7.3 LAN Mode

`pawxyctl share on` MUST start or restart with:

```text
listen = 0.0.0.0:7890
lan = true
auth_enabled = true
username = pawxy
password = random generated password stored in CLI config
wake_lock = unchanged
```

`pawxyctl share off` MUST start or restart with:

```text
listen = 127.0.0.1:7890
lan = false
auth_enabled = false
```

Wildcard listen without auth MUST be impossible through:

- CLI behavior.
- Android service guard.
- Rust config validation.

### 7.4 Status and Doctor

`pawxyctl status --json` MUST print raw status JSON.

Human-readable `pawxyctl status` MUST print:

```text
pawxy: running/stopped
listen: ...
mixed: http + socks5
lan: on/off
auth: on/off
active: N
total: N
bytes: in/out
wake-lock: on/off
network: available/transport gen=N
last-error: ...
```

`pawxyctl logs` MUST run:

```sh
logcat -s Pawxy PawxyNative
```

`pawxyctl doctor` MUST be non-interactive and print:

- package installed via `pm path dev.pawxy`.
- `am` availability.
- `content` availability.
- token path.
- current status.
- notification permission state if `pm` supports checking it.
- wake-lock status.
- network status.
- notes that Pawxy has no UI and LAN mode always requires auth.

### 7.5 POSIX Shell Constraints

`pawxyctl` MUST:

- Use POSIX `sh`.
- Not require Bash.
- Not use Termux-only commands.
- Not use `eval` to assemble `am` commands.
- Not source writable config files as shell code.
- Fail closed if secure random token generation is unavailable.

---

## 8. Build Spec

### 8.1 Rust Workspace

Root `Cargo.toml` MUST include workspace members:

- `crates/pawxy-core`
- `crates/pawxy-jni`
- `crates/pawxy-cli`

Release profile MUST include:

```toml
[profile.release]
lto = true
codegen-units = 1
strip = true
panic = "abort"
```

### 8.2 Android Gradle

Android build MUST:

- Use Android application plugin.
- Use Kotlin Android plugin.
- Use `minSdk = 26`.
- Use `targetSdk = 35` or newer stable value when deliberately updated.
- Use no UI dependencies.
- Include JNI libraries from `android/app/src/main/jniLibs`.
- Include a Gradle wrapper so clean-checkout builds do not require a global
  `gradle` command.

### 8.3 Build Scripts

`scripts/build-android.sh` MUST:

1. Build Rust JNI libs for:
   - `arm64-v8a`
   - `armeabi-v7a`
   - `x86_64`
2. Use `cargo-ndk` if available.
3. Output native libs to:

```text
android/app/src/main/jniLibs/<abi>/libpawxy_jni.so
```

4. Build debug APK through `android/gradlew` when present.

`scripts/install-apk-adb.sh` MUST:

1. Install:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

2. Push `scripts/pawxyctl` to `/data/local/tmp/pawxyctl`.
3. Print example `adb shell /data/local/tmp/pawxyctl ...` commands.

`scripts/install-android.sh` MUST:

1. Be POSIX shell and run on Android shell environments with `curl` or `wget`.
2. Download release assets:
   - `pawxy-<version>-debug.apk`
   - `pawxyctl`
   - `SHA256SUMS`
3. Accept `PAWXY_VERSION` to override the default release version.
4. Accept `PAWXY_REPO` to override the GitHub repository.
5. Accept `PAWXY_GITHUB_TOKEN`, `GITHUB_PERSONAL_ACCESS_TOKEN`, or
   `GITHUB_TOKEN` for private release downloads.
6. Verify downloaded files with `sha256sum -c SHA256SUMS` before installing.
7. Install the APK with `pm install -r`.
8. Copy `pawxyctl` to `/data/local/tmp/pawxyctl` by default.
9. Start Pawxy with the installed `pawxyctl start`.

This script is an install-and-start path. It MUST NOT claim that Android APK
installation can be skipped.

### 8.4 GitHub Actions Packaging

`.github/workflows/package-android.yml` MUST package Android artifacts when:

- manually triggered with `workflow_dispatch`.
- a GitHub Release is published.

The workflow MUST:

1. Check out the repository.
2. Explicitly select JDK 17.
3. Cache Gradle and Rust build inputs without changing build outputs.
4. Install or select Android SDK/NDK pieces required for `cargo-ndk`.
5. Add Rust Android targets:
   - `aarch64-linux-android`
   - `armv7-linux-androideabi`
   - `x86_64-linux-android`
6. Install the pinned `cargo-ndk` version.
7. Run local verification gates:
   - `cargo fmt --all -- --check`
   - `cargo clippy --workspace --all-targets -- -D warnings`
   - `cargo test --workspace`
   - shell syntax checks
   - `scripts/check-best-practices.sh`
8. Run `scripts/build-android.sh`.
9. Assemble `dist/` with:
   - debug APK named for the ref.
   - `pawxyctl`.
   - `install-android.sh`.
   - `SHA256SUMS` covering the APK and `pawxyctl` installation inputs.
10. Upload `dist/*` as a workflow artifact.
11. Keep the build/package job at read-only repository permission.
12. On release events, run a separate upload job that:
    - depends on the package job.
    - downloads the packaged workflow artifact.
    - explicitly requests `contents: write`.
    - uploads `dist/*` to the GitHub Release with an explicit
      `--repo "${GITHUB_REPOSITORY}"` argument.

Until signing keys and release-channel policy exist, the workflow MUST package
the debug APK produced by the MVP build script. Release signing is a separate
future spec change.

---

## 9. pawxy-cli Spec

`pawxy-cli` is for desktop/local development and protocol tests. It MUST NOT be
used by Android runtime.

It MUST support:

```sh
pawxy-cli serve --listen 127.0.0.1:7890
pawxy-cli serve --listen 0.0.0.0:7890 --auth pawxy:pass
```

It MUST call `pawxy-core` directly.

---

## 10. Documentation Spec

README MUST document:

- What Pawxy is.
- What Pawxy is not.
- No UI; CLI-only.
- Android-native foreground service.
- Rust mixed-port forwarding core.
- Build/install instructions.
- CLI examples:
  - `pawxyctl start`
  - `pawxyctl status`
  - `pawxyctl share on`
  - `pawxyctl stop`
- Test traffic examples:

```sh
curl -x http://127.0.0.1:7890 http://example.com
curl -x http://127.0.0.1:7890 https://example.com
curl --socks5-hostname 127.0.0.1:7890 https://example.com
```

- Security defaults:
  - local-only no auth by default.
  - LAN requires auth.
  - wildcard listen without auth is forbidden.
- Keepalive reality:
  - foreground service by default.
  - wake lock optional via `pawxyctl wake on`.
  - vendor ROMs, Doze, app standby, and notification permission can still affect
    runtime behavior.
  - do not promise impossible guarantees.

`docs/best-practices.md` MUST capture future-development guardrails and MUST be
updated when a best-practice decision changes.

---

## 11. Verification Gates

### 11.1 Required Local Gates

Before claiming MVP work is complete or healthy, run:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
sh -n scripts/pawxyctl
sh -n scripts/build-android.sh
sh -n scripts/install-apk-adb.sh
sh -n scripts/check-best-practices.sh
scripts/check-best-practices.sh
scripts/build-android.sh
```

### 11.2 Rust Test Requirements

Unit tests MUST cover:

- SOCKS5 greeting no-auth.
- SOCKS5 username/password success and failure.
- SOCKS5 IPv4/IPv6/domain target parsing.
- HTTP CONNECT target parsing.
- HTTP Basic auth success and failure.
- HTTP absolute-form rewrite:

```text
GET http://example.com/a?b=1 HTTP/1.1
```

to:

```text
GET /a?b=1 HTTP/1.1
```

- invalid protocol prefix rejection.
- headers larger than 16 KiB rejection.

Integration tests MUST use local Tokio TCP test servers and cover:

1. HTTP CONNECT through Pawxy to echo server.
2. SOCKS5 CONNECT through Pawxy to echo server.
3. HTTP absolute-form request through Pawxy to local HTTP test server.
4. Auth required:
   - wrong auth fails.
   - correct auth succeeds.

### 11.3 Android Gates

Android APK build success proves compile/package health only. If no Android
device is connected, runtime behavior remains unproven.

Runtime validation SHOULD include:

```sh
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb push scripts/pawxyctl /data/local/tmp/pawxyctl
adb shell chmod 755 /data/local/tmp/pawxyctl
adb shell /data/local/tmp/pawxyctl start
adb shell /data/local/tmp/pawxyctl status --json
adb shell /data/local/tmp/pawxyctl share on
adb shell /data/local/tmp/pawxyctl wake on
adb shell /data/local/tmp/pawxyctl wake off
adb shell /data/local/tmp/pawxyctl stop
```

---

## 12. Acceptance Criteria

The MVP is accepted only when current evidence proves:

- Required repository structure exists.
- No Activity exists in AndroidManifest.
- No UI framework or layout files are added.
- APK starts only via CLI intent.
- `pawxyctl start` starts a foreground service.
- `pawxyctl status` returns useful status.
- HTTP CONNECT works.
- HTTP absolute-form forwarding works.
- SOCKS5 CONNECT works.
- Local-only mode defaults to `127.0.0.1:7890` with no auth.
- LAN mode binds `0.0.0.0:7890` and always requires auth.
- Wildcard listen without auth is impossible through CLI, service, and native
  validation.
- Android default-network changes are visible in status/logs.
- Rust tests pass.
- Android debug APK builds.
- Code remains minimal and does not add proxy features beyond this spec.

---

## 13. Future Development Rules

Future work MUST follow these rules:

- Use this file and `docs/best-practices.md` as the first source of truth.
- Keep non-goals intact unless the spec is deliberately changed first.
- Add or update tests before behavior changes.
- Do not add dependencies without documenting why.
- Do not introduce UI surfaces.
- Do not implement VPN/TUN, transparent proxying, DNS hijacking, UDP ASSOCIATE,
  QUIC, HTTP/2 proxying, TLS MITM, subscription support, rule routing, or
  upstream proxy support under the MVP name.
- Do not turn `pawxyctl` into a proxy runtime.
- Prefer small, reviewable changes with explicit verification output.

If a future requirement conflicts with this spec, update the spec first and make
the tradeoff explicit.
