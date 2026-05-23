use thiserror::Error;

pub type Result<T> = std::result::Result<T, PawxyError>;

#[derive(Debug, Error)]
pub enum PawxyError {
    #[error("configuration error: {0}")]
    Config(String),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("parse error: {0}")]
    Parse(&'static str),
    #[error("protocol error: {0}")]
    Protocol(&'static str),
    #[error("timeout while {0}")]
    Timeout(&'static str),
    #[error("UTF-8 error: {0}")]
    Utf8(#[from] std::str::Utf8Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}
