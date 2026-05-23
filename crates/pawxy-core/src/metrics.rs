use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::config::PawxyConfig;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct PawxyStatus {
    pub ok: bool,
    pub running: bool,
    pub listen: String,
    pub lan: bool,
    pub auth_enabled: bool,
    pub active_connections: u64,
    pub total_connections: u64,
    pub bytes_in: u64,
    pub bytes_out: u64,
    pub started_at_unix_ms: u64,
    pub last_error: Option<String>,
    pub version: String,
}

#[derive(Debug)]
pub struct Metrics {
    running: AtomicBool,
    listen: Mutex<String>,
    lan: AtomicBool,
    auth_enabled: AtomicBool,
    active_connections: AtomicU64,
    total_connections: AtomicU64,
    bytes_in: AtomicU64,
    bytes_out: AtomicU64,
    started_at_unix_ms: AtomicU64,
    last_error: Mutex<Option<String>>,
}

impl Metrics {
    pub fn new(config: &PawxyConfig) -> Self {
        Self {
            running: AtomicBool::new(false),
            listen: Mutex::new(config.listen.to_string()),
            lan: AtomicBool::new(config.listen.ip().is_unspecified()),
            auth_enabled: AtomicBool::new(config.auth.is_some()),
            active_connections: AtomicU64::new(0),
            total_connections: AtomicU64::new(0),
            bytes_in: AtomicU64::new(0),
            bytes_out: AtomicU64::new(0),
            started_at_unix_ms: AtomicU64::new(0),
            last_error: Mutex::new(None),
        }
    }

    pub fn mark_started(&self, listen: String, config: &PawxyConfig) {
        *self.listen.lock().expect("metrics listen lock") = listen;
        self.lan
            .store(config.listen.ip().is_unspecified(), Ordering::Relaxed);
        self.auth_enabled
            .store(config.auth.is_some(), Ordering::Relaxed);
        self.started_at_unix_ms
            .store(unix_ms_now(), Ordering::Relaxed);
        self.running.store(true, Ordering::Relaxed);
        self.set_last_error(None);
    }

    pub fn mark_stopped(&self) {
        self.running.store(false, Ordering::Relaxed);
    }

    pub fn connection_started(&self) {
        self.active_connections.fetch_add(1, Ordering::Relaxed);
        self.total_connections.fetch_add(1, Ordering::Relaxed);
    }

    pub fn connection_finished(&self) {
        self.active_connections.fetch_sub(1, Ordering::Relaxed);
    }

    pub fn add_bytes_in(&self, amount: u64) {
        self.bytes_in.fetch_add(amount, Ordering::Relaxed);
    }

    pub fn add_bytes_out(&self, amount: u64) {
        self.bytes_out.fetch_add(amount, Ordering::Relaxed);
    }

    pub fn active_connections(&self) -> u64 {
        self.active_connections.load(Ordering::Relaxed)
    }

    pub fn set_last_error(&self, error: Option<String>) {
        *self.last_error.lock().expect("metrics error lock") = error;
    }

    pub fn snapshot(&self) -> PawxyStatus {
        PawxyStatus {
            ok: true,
            running: self.running.load(Ordering::Relaxed),
            listen: self.listen.lock().expect("metrics listen lock").clone(),
            lan: self.lan.load(Ordering::Relaxed),
            auth_enabled: self.auth_enabled.load(Ordering::Relaxed),
            active_connections: self.active_connections.load(Ordering::Relaxed),
            total_connections: self.total_connections.load(Ordering::Relaxed),
            bytes_in: self.bytes_in.load(Ordering::Relaxed),
            bytes_out: self.bytes_out.load(Ordering::Relaxed),
            started_at_unix_ms: self.started_at_unix_ms.load(Ordering::Relaxed),
            last_error: self.last_error.lock().expect("metrics error lock").clone(),
            version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }
}

fn unix_ms_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
