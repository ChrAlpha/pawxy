use std::net::{SocketAddr, TcpListener as StdTcpListener};
use std::ptr;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use pawxy_core::{Metrics, PawxyConfig, PawxyServer, PawxyStatus, ShutdownHandle, ShutdownSignal};
use serde::Deserialize;
use serde_json::json;

static STATE: Lazy<Mutex<NativeState>> = Lazy::new(|| Mutex::new(NativeState::new()));
static TRACING: Lazy<()> = Lazy::new(|| {
    let _ = tracing_subscriber::fmt()
        .with_target(false)
        .with_thread_ids(false)
        .try_init();
});

struct NativeState {
    shutdown: Option<ShutdownHandle>,
    thread: Option<JoinHandle<()>>,
    stopping_thread: Option<JoinHandle<()>>,
    config: Option<PawxyConfig>,
    metrics: Arc<Metrics>,
}

enum StopMode {
    Join,
    ParkForNextStart,
}

#[derive(Debug, Default, Deserialize)]
struct NativeStartOptions {
    force_restart: Option<bool>,
}

impl NativeState {
    fn new() -> Self {
        let config = PawxyConfig::default();
        Self {
            shutdown: None,
            thread: None,
            stopping_thread: None,
            config: None,
            metrics: Arc::new(Metrics::new(&config)),
        }
    }

    fn stop_existing_for_start(&mut self) {
        self.join_stopping_thread();
        self.stop_existing(StopMode::Join);
    }

    fn stop_existing_for_stop(&mut self) {
        self.stop_existing(StopMode::ParkForNextStart);
    }

    fn stop_existing(&mut self, mode: StopMode) {
        if let Some(shutdown) = self.shutdown.take() {
            shutdown.shutdown();
        }
        if let Some(thread) = self.thread.take() {
            match mode {
                StopMode::Join => {
                    let _ = thread.join();
                }
                StopMode::ParkForNextStart => {
                    self.stopping_thread = Some(thread);
                }
            }
        }
        self.config = None;
        self.metrics.mark_stopped();
    }

    fn join_stopping_thread(&mut self) {
        if let Some(thread) = self.stopping_thread.take() {
            let _ = thread.join();
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_dev_pawxy_PawxyNative_nativeStart(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
    config_json: JString<'_>,
) -> jstring {
    Lazy::force(&TRACING);
    let result = native_start(&mut env, config_json);
    java_json(&mut env, result)
}

#[no_mangle]
pub extern "system" fn Java_dev_pawxy_PawxyNative_nativeStop(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
) -> jstring {
    let mut state = STATE.lock();
    state.stop_existing_for_stop();
    java_json(&mut env, serde_json::to_string(&state.metrics.snapshot()))
}

#[no_mangle]
pub extern "system" fn Java_dev_pawxy_PawxyNative_nativeStatus(
    mut env: JNIEnv<'_>,
    _class: JClass<'_>,
) -> jstring {
    let state = STATE.lock();
    java_json(&mut env, serde_json::to_string(&state.metrics.snapshot()))
}

fn native_start(env: &mut JNIEnv<'_>, config_json: JString<'_>) -> serde_json::Result<String> {
    let config_text = match env.get_string(&config_json) {
        Ok(value) => value.to_string_lossy().into_owned(),
        Err(error) => return Ok(error_json(&format!("invalid JNI string: {error}"))),
    };
    let config = match PawxyConfig::from_json(&config_text) {
        Ok(config) => config,
        Err(error) => return Ok(error_json(&error.to_string())),
    };
    let force_restart = serde_json::from_str::<NativeStartOptions>(&config_text)
        .ok()
        .and_then(|options| options.force_restart)
        .unwrap_or(false);

    let (current_status, current_config) = {
        let state = STATE.lock();
        (state.metrics.snapshot(), state.config.clone())
    };
    if should_reuse_running_proxy(
        &current_status,
        current_config.as_ref(),
        &config,
        force_restart,
    ) {
        return serde_json::to_string(&current_status);
    }

    let prebound_listener =
        if should_prebind_replacement(&current_status.listen, config.listen, force_restart) {
            match StdTcpListener::bind(config.listen).and_then(|listener| {
                listener.set_nonblocking(true)?;
                Ok(listener)
            }) {
                Ok(listener) => Some(listener),
                Err(error) => return Ok(error_json(&format!("bind preflight failed: {error}"))),
            }
        } else {
            None
        };

    {
        let mut state = STATE.lock();
        state.stop_existing_for_start();
    }

    let metrics = Arc::new(Metrics::new(&config));
    let thread_metrics = metrics.clone();
    let thread_config = config.clone();
    let (shutdown, signal) = ShutdownSignal::new();
    let thread = std::thread::spawn(move || {
        let runtime = match tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(4)
            .max_blocking_threads(1)
            .build()
        {
            Ok(runtime) => runtime,
            Err(error) => {
                thread_metrics.set_last_error(Some(error.to_string()));
                thread_metrics.mark_stopped();
                return;
            }
        };
        let runtime_metrics = thread_metrics.clone();
        let result = runtime.block_on(async move {
            if let Some(listener) = prebound_listener {
                let listener = tokio::net::TcpListener::from_std(listener)?;
                PawxyServer::run_bound_with_metrics(
                    thread_config,
                    listener,
                    signal,
                    runtime_metrics.clone(),
                )
                .await
            } else {
                PawxyServer::run_with_metrics(thread_config, signal, runtime_metrics.clone()).await
            }
        });
        if let Err(error) = result {
            thread_metrics.set_last_error(Some(error.to_string()));
        }
        thread_metrics.mark_stopped();
    });

    {
        let mut state = STATE.lock();
        state.shutdown = Some(shutdown);
        state.thread = Some(thread);
        state.config = Some(config);
        state.metrics = metrics.clone();
    }

    serde_json::to_string(&wait_for_startup_status(&metrics, Duration::from_secs(2)))
}

fn same_listen_port(current_listen: &str, next_listen: SocketAddr) -> bool {
    current_listen
        .parse::<SocketAddr>()
        .map(|current| current.port() == next_listen.port())
        .unwrap_or(false)
}

fn should_prebind_replacement(
    current_listen: &str,
    next_listen: SocketAddr,
    force_restart: bool,
) -> bool {
    !force_restart && !same_listen_port(current_listen, next_listen)
}

fn should_reuse_running_proxy(
    current_status: &PawxyStatus,
    current_config: Option<&PawxyConfig>,
    next_config: &PawxyConfig,
    force_restart: bool,
) -> bool {
    current_status.running && !force_restart && current_config == Some(next_config)
}

fn wait_for_startup_status(
    metrics: &Metrics,
    startup_timeout: Duration,
) -> pawxy_core::PawxyStatus {
    let deadline = Instant::now() + startup_timeout;
    loop {
        let status = metrics.snapshot();
        if status.running || status.last_error.is_some() || Instant::now() >= deadline {
            return status;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn java_json(env: &mut JNIEnv<'_>, result: serde_json::Result<String>) -> jstring {
    let value = result.unwrap_or_else(|error| error_json(&error.to_string()));
    match env.new_string(value) {
        Ok(output) => output.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn error_json(message: &str) -> String {
    json!({
        "ok": false,
        "error": message
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Instant;

    use super::*;

    #[test]
    fn stop_existing_for_start_joins_existing_thread_before_returning() {
        let mut state = NativeState::new();
        let (shutdown, _signal) = ShutdownSignal::new();
        let joined = Arc::new(AtomicBool::new(false));
        let thread_joined = joined.clone();
        state.shutdown = Some(shutdown);
        state.thread = Some(std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(25));
            thread_joined.store(true, Ordering::SeqCst);
        }));

        state.stop_existing_for_start();

        assert!(joined.load(Ordering::SeqCst));
        assert!(state.shutdown.is_none());
        assert!(state.thread.is_none());
        assert!(!state.metrics.snapshot().running);
    }

    #[test]
    fn start_after_stop_waits_for_parked_stop_thread_before_returning() {
        let mut state = NativeState::new();
        let (shutdown, _signal) = ShutdownSignal::new();
        let joined = Arc::new(AtomicBool::new(false));
        let thread_joined = joined.clone();
        state.shutdown = Some(shutdown);
        state.thread = Some(std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(30));
            thread_joined.store(true, Ordering::SeqCst);
        }));

        state.stop_existing_for_stop();
        let started_waiting = Instant::now();
        state.stop_existing_for_start();

        assert!(joined.load(Ordering::SeqCst));
        assert!(started_waiting.elapsed() >= Duration::from_millis(20));
        assert!(state.shutdown.is_none());
        assert!(state.thread.is_none());
        assert!(!state.metrics.snapshot().running);
    }

    #[test]
    fn wait_for_startup_status_returns_when_core_is_running() {
        let config = PawxyConfig::default();
        let metrics = Metrics::new(&config);

        metrics.mark_started(config.listen.to_string(), &config);
        let status = wait_for_startup_status(&metrics, Duration::from_secs(2));

        assert!(status.running);
        assert_eq!(status.listen, "127.0.0.1:3218");
    }

    #[test]
    fn wait_for_startup_status_returns_startup_error() {
        let config = PawxyConfig::default();
        let metrics = Metrics::new(&config);

        metrics.set_last_error(Some("bind failed".to_string()));
        let status = wait_for_startup_status(&metrics, Duration::from_secs(2));

        assert!(!status.running);
        assert_eq!(status.last_error.as_deref(), Some("bind failed"));
    }

    #[test]
    fn prebind_replacement_preserves_running_proxy_for_different_ports() {
        let next_listen: SocketAddr = "127.0.0.1:32180".parse().unwrap();

        assert!(should_prebind_replacement(
            "127.0.0.1:3218",
            next_listen,
            false
        ));
        assert!(!should_prebind_replacement(
            "127.0.0.1:32180",
            next_listen,
            false
        ));
        assert!(!should_prebind_replacement(
            "127.0.0.1:3218",
            next_listen,
            true
        ));
    }

    #[test]
    fn duplicate_start_reuses_running_proxy_only_for_same_effective_config() {
        let config = PawxyConfig::default();
        let mut status = PawxyStatus {
            running: true,
            listen: config.listen.to_string(),
            auth_enabled: false,
            started_at_unix_ms: 1234,
            ..PawxyStatus::default()
        };

        assert!(should_reuse_running_proxy(
            &status,
            Some(&config),
            &config,
            false
        ));
        assert!(!should_reuse_running_proxy(
            &status,
            Some(&config),
            &config,
            true
        ));

        status.running = false;
        assert!(!should_reuse_running_proxy(
            &status,
            Some(&config),
            &config,
            false
        ));

        status.running = true;
        let auth_config = PawxyConfig::from_json(
            r#"{"auth_enabled":true,"username":"pawxy","password":"secret"}"#,
        )
        .unwrap();
        assert!(!should_reuse_running_proxy(
            &status,
            Some(&config),
            &auth_config,
            false
        ));

        let changed_auth_password = PawxyConfig::from_json(
            r#"{"auth_enabled":true,"username":"pawxy","password":"changed"}"#,
        )
        .unwrap();
        assert!(!should_reuse_running_proxy(
            &status,
            Some(&auth_config),
            &changed_auth_password,
            false
        ));

        let changed_limits =
            PawxyConfig::from_json(r#"{"max_connections":128,"max_per_source_ip":32}"#).unwrap();
        assert!(!should_reuse_running_proxy(
            &status,
            Some(&config),
            &changed_limits,
            false
        ));

        let different_listen = PawxyConfig::from_json(r#"{"listen":"127.0.0.1:3219"}"#).unwrap();
        assert!(!should_reuse_running_proxy(
            &status,
            Some(&config),
            &different_listen,
            false
        ));

        assert!(!should_reuse_running_proxy(&status, None, &config, false));
    }
}
