use std::ptr;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use pawxy_core::{Metrics, PawxyConfig, PawxyServer, ShutdownHandle, ShutdownSignal};
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
    metrics: Arc<Metrics>,
}

impl NativeState {
    fn new() -> Self {
        let config = PawxyConfig::default();
        Self {
            shutdown: None,
            thread: None,
            metrics: Arc::new(Metrics::new(&config)),
        }
    }

    fn stop_existing(&mut self) {
        if let Some(shutdown) = self.shutdown.take() {
            shutdown.shutdown();
        }
        if let Some(thread) = self.thread.take() {
            std::thread::spawn(move || {
                let _ = thread.join();
            });
        }
        self.metrics.mark_stopped();
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
    state.stop_existing();
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

    {
        let mut state = STATE.lock();
        state.stop_existing();
    }

    let metrics = Arc::new(Metrics::new(&config));
    let thread_metrics = metrics.clone();
    let thread_config = config.clone();
    let (shutdown, signal) = ShutdownSignal::new();
    let thread = std::thread::spawn(move || {
        let runtime = match tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
        {
            Ok(runtime) => runtime,
            Err(error) => {
                thread_metrics.set_last_error(Some(error.to_string()));
                thread_metrics.mark_stopped();
                return;
            }
        };
        if let Err(error) = runtime.block_on(PawxyServer::run_with_metrics(
            thread_config,
            signal,
            thread_metrics.clone(),
        )) {
            thread_metrics.set_last_error(Some(error.to_string()));
        }
        thread_metrics.mark_stopped();
    });

    {
        let mut state = STATE.lock();
        state.shutdown = Some(shutdown);
        state.thread = Some(thread);
        state.metrics = metrics.clone();
    }

    std::thread::sleep(Duration::from_millis(20));
    serde_json::to_string(&metrics.snapshot())
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
