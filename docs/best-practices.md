# Pawxy Engineering Best-Practices Superpowers Spec

> **For agentic workers:** This document constrains how Pawxy should evolve
> after the MVP. It is not a loose recommendation list. Treat every mandatory
> rule as a future-development guardrail unless a later spec update deliberately
> changes the product boundary.

**Goal:** Preserve Pawxy as a low-loss, Android-native, CLI-only mixed-port
direct forwarder while making future work predictable, testable, and resistant
to accidental scope creep.

**Architecture:** Keep forwarding hot paths in Rust, lifecycle/status control in
JNI, Android OS integration in Kotlin, and command/control in POSIX shell.
Minimize cross-layer coupling.

**Verification:** Best-practice compliance MUST be checked with
`scripts/check-best-practices.sh` plus the full gates in `docs/mvp.md`.

---

## 1. Authority and Change Process

### 1.1 Source of Truth

Development MUST read these documents in order:

1. `docs/mvp.md` for product scope and acceptance criteria.
2. `docs/best-practices.md` for engineering guardrails.
3. `README.md` for user-facing operational docs.
4. Current source and tests for implementation details.

If code contradicts the docs, do not silently adapt to the code. Either fix the
code or update the spec first with a clear rationale.

### 1.2 Superpowers Workflow

For non-trivial behavior changes:

- Use a spec-first workflow.
- Add or update tests before production code.
- Keep implementation tasks small and reviewable.
- Run verification before claiming completion.

For documentation-only changes:

- Keep wording normative.
- Avoid ambiguous, hedged, or uncertain wording.
- Include concrete commands when a claim needs verification.

### 1.3 Dependency Policy

New dependencies MUST meet all of these conditions:

- They solve a concrete problem already described in a spec or issue.
- They do not expand Pawxy into a non-goal.
- They do not add UI, web server, routing engine, VPN, or Termux runtime
  coupling.
- They are smaller or safer than local code for the same job.
- The verification gate still works in a clean checkout.

Dependencies that require a background daemon, external service, or privileged
Android integration are disallowed for MVP-compatible work.

---

## 2. Network-Layer Best Practices

### 2.1 Hot Path Shape

Pawxy MUST keep the network hot path simple:

- One listener per running proxy instance.
- One async task per accepted client connection.
- No per-packet JNI.
- No app-level packet scheduler.
- No proxy-rule engine.
- No upstream proxy chain.

The forwarding path MUST remain Rust-only after Android starts the core.

### 2.2 Protocol Sniffing

Mixed-port classification MUST stay bounded:

- Read only the initial prefix required to classify HTTP proxy vs SOCKS5.
- Preserve all consumed bytes for the selected handler.
- Keep the initial sniff maximum at 512 bytes unless a spec update proves a
  larger value is needed.
- Close unknown prefixes without forwarding.

Do not add deep inspection after the proxy handshake. Pawxy is not a DPI engine.

### 2.3 Timeouts

Timeouts MUST protect resources without changing stream semantics:

- Handshake timeout limits slow clients and scans.
- Connect timeout limits dead targets.
- Idle timeout is per-read inactivity.
- Idle timeout is not a total session lifetime.
- Established tunnel timeout MUST NOT be used as a retry trigger.

Timeout changes require test coverage for the changed behavior.

### 2.4 TCP Semantics

The tunnel MUST preserve TCP behavior as closely as practical:

- Continue to support half-close.
- Shutdown only the opposite write half after EOF when possible.
- Count bytes by direction.
- Do not parse payload after the proxy handshake.
- Do not insert heartbeats into proxied streams.

Never retry an established TCP tunnel transparently after a network drop.
Transparent retry can duplicate, reorder, or corrupt bytes and breaks what
clients expect from TCP.

### 2.5 Loss and Efficiency

The default implementation SHOULD remain the minimum-loss path:

- `TCP_NODELAY` enabled by default for lower interactive latency.
- OS TCP keepalive enabled when supported.
- Approximately 32 KiB copy buffers per direction.
- Atomics for hot metrics.
- Locking only for low-frequency state such as `last_error`.
- No extra heap copies after handshake beyond the copy buffers and preserved
  already-read bytes.

Do not add compression, buffering, batching, or request coalescing. Those change
proxy semantics and can add latency or memory pressure.

### 2.6 Network Volatility

Pawxy's volatility model is:

- Existing TCP tunnels may fail if Android changes the default network, VPN, or
  route.
- New outbound connections should use Android's current process default network.
- The service should stay alive and visible so clients can reconnect.
- Network transitions should be visible in status/logs.

Do not bind outbound sockets to a specific Android `Network`. Binding would make
new connections stale after Wi-Fi, cellular, or VPN changes.

Do not auto-restart the Rust core for every network callback. The listener and
future outbound connections do not need a restart just because Android's default
route changed.

### 2.7 DNS and Address Handling

Pawxy MUST NOT implement DNS hijacking or custom DNS policy.

Allowed behavior:

- SOCKS5 domain targets may be passed to normal OS resolution through
  `TcpStream::connect`.
- HTTP authority hosts may be resolved by the OS through the normal connect
  path.

Disallowed behavior:

- Embedded DNS server.
- DoH/DoT resolver.
- DNS rewrite rules.
- DNS cache with routing policy.
- Synthetic domain interception.

---

## 3. Android Best Practices

### 3.1 Foreground Service

The Android runtime MUST remain a foreground service:

- `ProxyService` is explicitly started by CLI intent.
- `startForeground` is called before native startup work.
- Notification is minimal, ongoing, and service-category.
- No Activity is introduced to satisfy notification or permission flows.

Foreground service type MUST remain `specialUse` with subtype:

```text
local_mixed_port_proxy_server
```

### 3.2 No UI

The no-UI rule is a product identity constraint, not an implementation detail.

Future changes MUST NOT add:

- Activity.
- Launcher icon flow.
- Compose.
- XML layouts.
- WebView.
- Settings screen.
- Dashboard.
- In-app permission prompt.

If a user needs to configure Pawxy, the configuration path is CLI intent extras,
CLI config files, or documented shell commands.

### 3.3 CLI Compatibility

`pawxyctl` MUST remain broadly shell-compatible:

- POSIX `sh`.
- No Bash arrays or Bash-only substitutions.
- No Python, Node, Perl, Ruby, jq, or Termux-only dependency.
- No `eval` for command construction.
- No sourcing writable config as shell code.
- Token generation uses `/dev/urandom` plus `od` or `hexdump`.
- If secure random generation is unavailable, fail closed.

This keeps `pawxyctl` viable from `adb shell`, Termux, and other Android shell
environments.

### 3.4 One-Command Build

The Android project MUST include a Gradle wrapper.

`scripts/build-android.sh` MUST work from a clean checkout when these tools are
available:

- Rust toolchain.
- Android SDK/NDK configured for `cargo-ndk`.
- `cargo-ndk`.
- Network access only if Gradle wrapper distribution or dependencies are not
  already cached.

The script MUST prefer `android/gradlew` over a globally installed `gradle`
command.

### 3.4.1 Android One-Command Install

The repository SHOULD provide `scripts/install-android.sh` as the user-facing
Android install-and-start path:

```sh
curl -fsSL https://github.com/ChrAlpha/pawxy/releases/latest/download/install-android.sh | sh
```

For private repositories, the documented path MUST pass a GitHub token to both
the script download and the release asset downloads:

```sh
curl -fsSL -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" https://raw.githubusercontent.com/ChrAlpha/pawxy/main/scripts/install-android.sh | PAWXY_GITHUB_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN" sh
```

This command MUST be described as install-and-start, not no-install startup.
Android Foreground Service registration, manifest permissions, notification
behavior, and package identity require APK installation.

The script MUST:

- Remain POSIX shell.
- Download the release APK, `pawxyctl`, and `SHA256SUMS`.
- Verify release downloads before installing.
- Install with `pm install -r`.
- Copy `pawxyctl` to `/data/local/tmp/pawxyctl` by default.
- Start Pawxy through `pawxyctl start`.
- Support a token environment variable for private release downloads.

### 3.4.2 GitHub Actions Packaging

The repository MUST include a manual and release-triggered Android packaging
workflow at `.github/workflows/package-android.yml`.

The workflow MUST:

- Support `workflow_dispatch`.
- Run when a GitHub Release is published.
- Explicitly select JDK 17 instead of depending on the runner default.
- Cache Gradle and Rust build inputs to reduce repeated network and compile
  cost.
- Build through `scripts/build-android.sh`.
- Run source verification gates before packaging.
- Upload APK, `pawxyctl`, `install-android.sh`, and `SHA256SUMS` as a workflow
  artifact. `SHA256SUMS` MUST cover the APK and `pawxyctl` installation inputs.
- Keep the build/package job at read-only repository permission.
- Upload the same files to the GitHub Release on release events from a separate
  job that downloads the workflow artifact.
- Use `GITHUB_TOKEN` with `contents: write` only in the release asset upload
  job.
- Pass `--repo "${GITHUB_REPOSITORY}"` to `gh release upload`, because the
  upload job intentionally does not check out the repository.
- Track current official GitHub action major tags in the best-practice checker
  when the workflow is updated.

The workflow SHOULD avoid third-party release actions. The preferred release
asset upload path is GitHub CLI `gh release upload`, because it is available on
GitHub-hosted runners and uses the built-in token.

### 3.5 Status Surface

Status is the main observability surface. It MUST stay machine-readable through
`pawxyctl status --json` and compact for humans through `pawxyctl status`.

Status SHOULD include:

- Native core running state.
- Listen address.
- LAN/auth mode.
- Active/total connections.
- Byte counters.
- Last error.
- Wake-lock state.
- Service-started state.
- Default-network state.
- Network transport.
- Network generation.

Do not make status depend on log scraping.

### 3.6 Default Network Observation

Android default-network observation MUST be status/logging only:

- Register `ConnectivityManager.NetworkCallback` when service starts.
- Unregister it on service destroy.
- Record whether a default network is available.
- Record transport hints such as VPN, Wi-Fi, cellular, ethernet, or bluetooth.
- Increment generation on observed network state changes.

Do not bind sockets to the callback's `Network`.
Do not restart the proxy automatically from the callback.
Do not claim VPN changes are hidden from TCP clients.

### 3.7 Wake Lock and Keepalive

Wake lock is opt-in only. It MUST be controlled only by `pawxyctl wake on/off`.

Wake lock rules:

- Use `PARTIAL_WAKE_LOCK`.
- Do not enable it during `start` or `share on`.
- Persist its requested state only as Android-side service state.
- Release it on STOP and service destroy.
- Show wake-lock state in notification/status.

Do not promise impossible background survival. Android Doze, app standby,
notification permission state, OEM task killers, battery optimization, and user
actions can still stop or restrict the app.

### 3.8 VPN and Route Changes

Pawxy is not a VPN. VPN changes are route changes below Pawxy.

Allowed:

- Let new outbound TCP connects follow Android's current default route.
- Report transport as `vpn` when Android exposes that capability.
- Document that existing streams can fail across route replacement.

Disallowed:

- `VpnService`.
- TUN device.
- Transparent proxy.
- Android global proxy setting.
- Capturing or redirecting traffic outside explicit client proxy use.

---

## 4. Security Best Practices

### 4.1 Control Surface

The exported service and provider MUST remain token-protected.

Rules:

- First non-empty START token provisions the app token.
- All later control actions require the same token.
- Provider queries require token in path.
- Unauthorized commands log a warning and do nothing.
- Unauthorized provider queries return JSON error, not native status.

Do not add unauthenticated convenience actions.

### 4.2 LAN Sharing

LAN sharing MUST be explicitly enabled and authenticated.

Required enforcement layers:

- `pawxyctl share on` always sends auth.
- `pawxyctl share off` returns to local-only no-auth mode.
- `ProxyService` rejects wildcard listen without auth before saving config.
- Rust config validation rejects wildcard listen without auth.

Wildcard listen without auth is a release-blocking defect.

### 4.3 Secrets

Token and LAN password storage MUST stay local to shell/app storage:

- CLI token: `${PAWXY_HOME:-$HOME/.config/pawxy}/token` or
  `/data/local/tmp/pawxy/token`.
- CLI LAN password: `$PAWXY_HOME/config.env`.
- Android token: SharedPreferences key `control_token`.

Do not log tokens or LAN passwords.
Do not print LAN password except when user explicitly runs the command that
creates or enables LAN sharing.

---

## 5. Testing and Verification Best Practices

### 5.1 Required Gates

Before claiming code is complete or healthy, run:

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

### 5.2 Static Contract Checks

`scripts/check-best-practices.sh` MUST remain POSIX shell and MUST NOT require
Python or other extra runtimes.

The checker SHOULD enforce:

- Android no-UI invariants when practical.
- `ACCESS_NETWORK_STATE` and network callback presence.
- Status fields for network observability.
- No `eval` in `pawxyctl`.
- No timestamp fallback for token generation.
- Gradle wrapper presence.
- GitHub Actions packaging workflow presence and triggers.
- Critical best-practice phrases in this document.

If a guardrail becomes important enough to regress, add it to this checker.

### 5.3 Runtime Validation

When a device is available, validate the actual Android control path:

```sh
scripts/build-android.sh
scripts/install-apk-adb.sh
adb shell /data/local/tmp/pawxyctl start
adb shell /data/local/tmp/pawxyctl status --json
adb shell /data/local/tmp/pawxyctl share on
adb shell /data/local/tmp/pawxyctl wake on
adb shell /data/local/tmp/pawxyctl wake off
adb shell /data/local/tmp/pawxyctl stop
```

If no device is connected, state that runtime Android behavior is unverified.
APK build success is not a substitute for service lifecycle validation.

### 5.4 Regression Tests

Add or update Rust tests for network behavior changes. Required test style:

- Use local Tokio TCP servers.
- Avoid external network dependencies.
- Test client-visible proxy behavior, not mocks.
- Verify failing behavior before production changes when changing behavior.

Android service logic that cannot be tested locally MUST be covered by static
contract checks and APK build at minimum.

---

## 6. Review Checklist

Before merging future changes, answer these questions from current evidence:

- Did the change preserve CLI-only/no-UI identity?
- Did it keep the proxy direct and mixed-port only?
- Did it avoid VPN/TUN, transparent proxying, DNS hijacking, rules, upstream
  proxy support, and subscriptions?
- Did it avoid per-connection JNI?
- Did it preserve wildcard-listen auth enforcement?
- Did it preserve token-protected exported components?
- Did it preserve POSIX-shell control scripts?
- Did it keep build/test commands runnable from a clean checkout?
- Did it update docs when changing product or engineering contracts?
- Did the required verification gates pass?

If any answer is "no" or "not verified", the change is not ready.
