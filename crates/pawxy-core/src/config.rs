use std::net::SocketAddr;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::error::{PawxyError, Result};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuthConfig {
    pub username: String,
    pub password: String,
}

#[derive(Clone, Debug)]
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
        if self.listen.ip().is_unspecified() && self.auth.is_none() {
            return Err(PawxyError::Config(
                "0.0.0.0/:: listen requires proxy authentication".to_string(),
            ));
        }
        Ok(())
    }

    pub fn from_json(json: &str) -> Result<Self> {
        let wire: PawxyConfigJson = serde_json::from_str(json)?;
        wire.into_config()
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
}
