use std::net::SocketAddr;
use std::process::ExitCode;

use pawxy_core::{AuthConfig, PawxyConfig, PawxyServer, ShutdownSignal};

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("pawxy-cli: {error}");
            ExitCode::from(1)
        }
    }
}

async fn run() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("serve") => serve(args.collect()).await,
        _ => {
            Err("usage: pawxy-cli serve --listen 127.0.0.1:3218 [--auth username:password]".into())
        }
    }
}

async fn serve(args: Vec<String>) -> Result<(), String> {
    let mut listen: SocketAddr = "127.0.0.1:3218"
        .parse()
        .expect("valid built-in listen address");
    let mut auth = None;
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--listen" => {
                index += 1;
                let value = args
                    .get(index)
                    .ok_or_else(|| "--listen requires an address".to_string())?;
                listen = value
                    .parse()
                    .map_err(|_| format!("invalid listen address: {value}"))?;
            }
            "--auth" => {
                index += 1;
                let value = args
                    .get(index)
                    .ok_or_else(|| "--auth requires username:password".to_string())?;
                let (username, password) = value
                    .split_once(':')
                    .ok_or_else(|| "--auth requires username:password".to_string())?;
                if username.is_empty() || password.is_empty() {
                    return Err("--auth username and password must be non-empty".to_string());
                }
                auth = Some(AuthConfig {
                    username: username.to_string(),
                    password: password.to_string(),
                });
            }
            other => return Err(format!("unknown argument: {other}")),
        }
        index += 1;
    }

    let config = PawxyConfig {
        listen,
        auth,
        ..PawxyConfig::default()
    };
    config.validate().map_err(|error| error.to_string())?;

    let (shutdown, signal) = ShutdownSignal::new();
    let shutdown_on_signal = shutdown.clone();
    tokio::spawn(async move {
        if tokio::signal::ctrl_c().await.is_ok() {
            shutdown_on_signal.shutdown();
        }
    });

    eprintln!(
        "pawxy-cli: serving mixed HTTP + SOCKS5 on {}",
        config.listen
    );
    PawxyServer::run(config, signal)
        .await
        .map_err(|error| error.to_string())
}
