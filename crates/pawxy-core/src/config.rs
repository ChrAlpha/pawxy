use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::error::{PawxyError, Result};

const MAX_CONNECTIONS_LIMIT: usize = 4096;
const MAX_PER_SOURCE_IP_LIMIT: usize = 1024;
const MAX_HANDSHAKE_TIMEOUT_MS: u64 = 60_000;
const MAX_CONNECT_TIMEOUT_MS: u64 = 60_000;
const MAX_IDLE_TIMEOUT_MS: u64 = 86_400_000;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuthConfig {
    pub username: String,
    pub password: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PawxyConfig {
    pub listen: SocketAddr,
    pub auth: Option<AuthConfig>,
    pub max_connections: usize,
    pub max_per_source_ip: usize,
    pub handshake_timeout: Duration,
    pub connect_timeout: Duration,
    pub idle_timeout: Duration,
    pub tcp_nodelay: bool,
    pub tcp_keepalive: bool,
}

impl Default for PawxyConfig {
    fn default() -> Self {
        Self {
            listen: "127.0.0.1:3218".parse().expect("valid default listen"),
            auth: None,
            max_connections: 256,
            max_per_source_ip: 64,
            handshake_timeout: Duration::from_millis(5000),
            connect_timeout: Duration::from_millis(10000),
            idle_timeout: Duration::from_millis(1_800_000),
            tcp_nodelay: true,
            tcp_keepalive: true,
        }
    }
}

impl PawxyConfig {
    pub fn validate(&self) -> Result<()> {
        if !is_supported_listen_ip(self.listen.ip()) {
            return Err(PawxyError::Config(
                "listen address must be 127.0.0.1 or 0.0.0.0".to_string(),
            ));
        }
        if self.listen.ip().is_unspecified() && self.auth.is_none() {
            return Err(PawxyError::Config(
                "0.0.0.0 listen requires proxy authentication".to_string(),
            ));
        }
        if self.listen.port() == 0 {
            return Err(PawxyError::Config(
                "listen port must be explicit".to_string(),
            ));
        }
        if self.listen.port() < 1024 {
            return Err(PawxyError::Config(
                "listen port must be at least 1024".to_string(),
            ));
        }
        if self.max_connections == 0 {
            return Err(PawxyError::Config(
                "max_connections must be greater than zero".to_string(),
            ));
        }
        if self.max_per_source_ip == 0 {
            return Err(PawxyError::Config(
                "max_per_source_ip must be greater than zero".to_string(),
            ));
        }
        if self.handshake_timeout.is_zero() {
            return Err(PawxyError::Config(
                "handshake_timeout_ms must be greater than zero".to_string(),
            ));
        }
        if self.connect_timeout.is_zero() {
            return Err(PawxyError::Config(
                "connect_timeout_ms must be greater than zero".to_string(),
            ));
        }
        if self.idle_timeout.is_zero() {
            return Err(PawxyError::Config(
                "idle_timeout_ms must be greater than zero".to_string(),
            ));
        }
        if self.max_connections > MAX_CONNECTIONS_LIMIT {
            return Err(PawxyError::Config(format!(
                "max_connections must be at most {MAX_CONNECTIONS_LIMIT}"
            )));
        }
        if self.max_per_source_ip > MAX_PER_SOURCE_IP_LIMIT {
            return Err(PawxyError::Config(format!(
                "max_per_source_ip must be at most {MAX_PER_SOURCE_IP_LIMIT}"
            )));
        }
        if self.handshake_timeout > Duration::from_millis(MAX_HANDSHAKE_TIMEOUT_MS) {
            return Err(PawxyError::Config(format!(
                "handshake_timeout_ms must be at most {MAX_HANDSHAKE_TIMEOUT_MS}"
            )));
        }
        if self.connect_timeout > Duration::from_millis(MAX_CONNECT_TIMEOUT_MS) {
            return Err(PawxyError::Config(format!(
                "connect_timeout_ms must be at most {MAX_CONNECT_TIMEOUT_MS}"
            )));
        }
        if self.idle_timeout > Duration::from_millis(MAX_IDLE_TIMEOUT_MS) {
            return Err(PawxyError::Config(format!(
                "idle_timeout_ms must be at most {MAX_IDLE_TIMEOUT_MS}"
            )));
        }
        Ok(())
    }

    pub fn from_json(json: &str) -> Result<Self> {
        let wire: PawxyConfigJson = serde_json::from_str(json)?;
        wire.into_config()
    }
}

fn is_supported_listen_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(value) => value == Ipv4Addr::LOCALHOST || value == Ipv4Addr::UNSPECIFIED,
        IpAddr::V6(_) => false,
    }
}

#[derive(Debug, Deserialize)]
struct PawxyConfigJson {
    listen: Option<String>,
    auth_enabled: Option<bool>,
    username: Option<String>,
    password: Option<String>,
    max_connections: Option<usize>,
    max_per_source_ip: Option<usize>,
    handshake_timeout_ms: Option<u64>,
    connect_timeout_ms: Option<u64>,
    idle_timeout_ms: Option<u64>,
    tcp_nodelay: Option<bool>,
    tcp_keepalive: Option<bool>,
}

impl PawxyConfigJson {
    fn into_config(self) -> Result<PawxyConfig> {
        let mut config = PawxyConfig::default();
        if let Some(listen) = self.listen {
            config.listen = listen
                .parse()
                .map_err(|_| PawxyError::Config("invalid listen socket address".to_string()))?;
        }
        if self.auth_enabled.unwrap_or(false) {
            let username = self
                .username
                .filter(|value| !value.is_empty())
                .ok_or_else(|| PawxyError::Config("auth username is required".to_string()))?;
            let password = self
                .password
                .filter(|value| !value.is_empty())
                .ok_or_else(|| PawxyError::Config("auth password is required".to_string()))?;
            config.auth = Some(AuthConfig { username, password });
        }
        if let Some(value) = self.max_connections {
            config.max_connections = value;
        }
        if let Some(value) = self.max_per_source_ip {
            config.max_per_source_ip = value;
        }
        if let Some(value) = self.handshake_timeout_ms {
            config.handshake_timeout = Duration::from_millis(value);
        }
        if let Some(value) = self.connect_timeout_ms {
            config.connect_timeout = Duration::from_millis(value);
        }
        if let Some(value) = self.idle_timeout_ms {
            config.idle_timeout = Duration::from_millis(value);
        }
        if let Some(value) = self.tcp_nodelay {
            config.tcp_nodelay = value;
        }
        if let Some(value) = self.tcp_keepalive {
            config.tcp_keepalive = value;
        }
        config.validate()?;
        Ok(config)
    }
}

#[cfg(test)]
mod tests {
    use super::PawxyConfig;

    #[test]
    fn default_listen_avoids_common_mihomo_port() {
        let default_listen = PawxyConfig::default().listen;

        assert_eq!(default_listen.to_string(), "127.0.0.1:3218");
        assert_ne!(default_listen.port(), 7890);
    }

    #[test]
    fn from_json_rejects_zero_limits_and_timeouts() {
        for (field, message) in [
            (
                "max_connections",
                "max_connections must be greater than zero",
            ),
            (
                "max_per_source_ip",
                "max_per_source_ip must be greater than zero",
            ),
            (
                "handshake_timeout_ms",
                "handshake_timeout_ms must be greater than zero",
            ),
            (
                "connect_timeout_ms",
                "connect_timeout_ms must be greater than zero",
            ),
            (
                "idle_timeout_ms",
                "idle_timeout_ms must be greater than zero",
            ),
        ] {
            let json = format!(r#"{{"{field}":0}}"#);
            let error = PawxyConfig::from_json(&json).expect_err("zero config must be rejected");
            assert!(
                error.to_string().contains(message),
                "expected {field} rejection to contain {message:?}, got {error}"
            );
        }
    }

    #[test]
    fn from_json_rejects_unsupported_listen_addresses_and_ports() {
        for (json, message) in [
            (
                r#"{"listen":"192.0.2.1:3218"}"#,
                "listen address must be 127.0.0.1 or 0.0.0.0",
            ),
            (
                r#"{"listen":"127.0.0.2:3218"}"#,
                "listen address must be 127.0.0.1 or 0.0.0.0",
            ),
            (
                r#"{"listen":"[::1]:3218"}"#,
                "listen address must be 127.0.0.1 or 0.0.0.0",
            ),
            (
                r#"{"listen":"[::]:3218","auth_enabled":true,"username":"pawxy","password":"secret"}"#,
                "listen address must be 127.0.0.1 or 0.0.0.0",
            ),
            (
                r#"{"listen":"127.0.0.1:0"}"#,
                "listen port must be explicit",
            ),
            (
                r#"{"listen":"127.0.0.1:80"}"#,
                "listen port must be at least 1024",
            ),
            (
                r#"{"listen":"0.0.0.0:3218","auth_enabled":true,"username":"pawxy","password":"secret"}"#,
                "",
            ),
        ] {
            let result = PawxyConfig::from_json(json);
            if message.is_empty() {
                result.expect("authenticated wildcard listen should remain supported");
            } else {
                let error = result.expect_err("unsupported listen must be rejected");
                assert!(
                    error.to_string().contains(message),
                    "expected listen rejection to contain {message:?}, got {error}"
                );
            }
        }
    }

    #[test]
    fn from_json_rejects_values_above_operational_caps() {
        for (field, value, message) in [
            (
                "max_connections",
                "4097",
                "max_connections must be at most 4096",
            ),
            (
                "max_per_source_ip",
                "1025",
                "max_per_source_ip must be at most 1024",
            ),
            (
                "handshake_timeout_ms",
                "60001",
                "handshake_timeout_ms must be at most 60000",
            ),
            (
                "connect_timeout_ms",
                "60001",
                "connect_timeout_ms must be at most 60000",
            ),
            (
                "idle_timeout_ms",
                "86400001",
                "idle_timeout_ms must be at most 86400000",
            ),
        ] {
            let json = format!(r#"{{"{field}":{value}}}"#);
            let error =
                PawxyConfig::from_json(&json).expect_err("oversized config must be rejected");
            assert!(
                error.to_string().contains(message),
                "expected {field} rejection to contain {message:?}, got {error}"
            );
        }
    }

    #[test]
    fn from_json_rejects_enabled_auth_without_nonempty_credentials() {
        for (json, message) in [
            (r#"{"auth_enabled":true}"#, "auth username is required"),
            (
                r#"{"auth_enabled":true,"username":"","password":"secret"}"#,
                "auth username is required",
            ),
            (
                r#"{"auth_enabled":true,"username":"pawxy","password":""}"#,
                "auth password is required",
            ),
        ] {
            let error =
                PawxyConfig::from_json(json).expect_err("enabled auth requires credentials");
            assert!(
                error.to_string().contains(message),
                "expected auth rejection to contain {message:?}, got {error}"
            );
        }
    }
}
