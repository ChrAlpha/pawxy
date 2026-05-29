use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use pawxy_core::{AuthConfig, Metrics, PawxyConfig, PawxyServer, ShutdownSignal};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::oneshot;

fn free_addr() -> SocketAddr {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("reserve port");
    let addr = listener.local_addr().expect("local addr");
    drop(listener);
    addr
}

async fn start_echo_server() -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("echo bind");
    let addr = listener.local_addr().expect("echo addr");
    tokio::spawn(async move {
        loop {
            let Ok((mut stream, _)) = listener.accept().await else {
                break;
            };
            tokio::spawn(async move {
                let mut buf = [0_u8; 1024];
                while let Ok(n) = stream.read(&mut buf).await {
                    if n == 0 {
                        break;
                    }
                    if stream.write_all(&buf[..n]).await.is_err() {
                        break;
                    }
                }
            });
        }
    });
    addr
}

async fn start_http_server() -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("http bind");
    let addr = listener.local_addr().expect("http addr");
    tokio::spawn(async move {
        loop {
            let Ok((mut stream, _)) = listener.accept().await else {
                break;
            };
            tokio::spawn(async move {
                let mut bytes = Vec::new();
                let mut buf = [0_u8; 256];
                loop {
                    let Ok(n) = stream.read(&mut buf).await else {
                        return;
                    };
                    if n == 0 {
                        return;
                    }
                    bytes.extend_from_slice(&buf[..n]);
                    if bytes.windows(4).any(|w| w == b"\r\n\r\n") {
                        break;
                    }
                }
                let request = String::from_utf8_lossy(&bytes);
                let body = if request.starts_with("GET /through-pawxy?ok=1 HTTP/1.1\r\n")
                    && !request
                        .to_ascii_lowercase()
                        .contains("\r\nproxy-authorization:")
                {
                    "absolute-ok"
                } else {
                    "unexpected-request"
                };
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                let _ = stream.write_all(response.as_bytes()).await;
            });
        }
    });
    addr
}

async fn start_http_body_server() -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("http bind");
    let addr = listener.local_addr().expect("http addr");
    tokio::spawn(async move {
        loop {
            let Ok((mut stream, _)) = listener.accept().await else {
                break;
            };
            tokio::spawn(async move {
                let mut bytes = Vec::new();
                let mut buf = [0_u8; 256];
                loop {
                    let Ok(n) = stream.read(&mut buf).await else {
                        return;
                    };
                    if n == 0 {
                        return;
                    }
                    bytes.extend_from_slice(&buf[..n]);
                    if bytes.windows(4).any(|w| w == b"\r\n\r\n")
                        && bytes.ends_with(b"\r\n\r\ndata")
                    {
                        break;
                    }
                }
                let request = String::from_utf8_lossy(&bytes);
                let body = if request.starts_with("POST /submit HTTP/1.1\r\n")
                    && request.ends_with("data")
                {
                    "body-ok"
                } else {
                    "unexpected-request"
                };
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                let _ = stream.write_all(response.as_bytes()).await;
            });
        }
    });
    addr
}

async fn start_half_close_observer() -> (SocketAddr, oneshot::Receiver<Vec<u8>>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("half-close bind");
    let addr = listener.local_addr().expect("half-close addr");
    let (seen_tx, seen_rx) = oneshot::channel();
    tokio::spawn(async move {
        let Ok((mut stream, _)) = listener.accept().await else {
            return;
        };
        let mut received = Vec::new();
        if stream.read_to_end(&mut received).await.is_err() {
            return;
        }
        let _ = seen_tx.send(received);
        let _ = stream.write_all(b"after-eof").await;
        let _ = stream.shutdown().await;
    });
    (addr, seen_rx)
}

async fn start_pawxy(mut config: PawxyConfig) -> (SocketAddr, pawxy_core::ShutdownHandle) {
    let listen = free_addr();
    config.listen = listen;
    config.handshake_timeout = Duration::from_millis(1000);
    config.connect_timeout = Duration::from_millis(1000);
    config.idle_timeout = Duration::from_millis(1000);
    let (shutdown, signal) = ShutdownSignal::new();
    tokio::spawn(async move {
        PawxyServer::run(config, signal)
            .await
            .expect("pawxy server");
    });
    tokio::time::sleep(Duration::from_millis(50)).await;
    (listen, shutdown)
}

async fn start_pawxy_with_metrics(
    mut config: PawxyConfig,
) -> (SocketAddr, pawxy_core::ShutdownHandle, Arc<Metrics>) {
    let listen = free_addr();
    config.listen = listen;
    config.handshake_timeout = Duration::from_millis(1000);
    config.connect_timeout = Duration::from_millis(1000);
    config.idle_timeout = Duration::from_millis(1000);
    let metrics = Arc::new(Metrics::new(&config));
    let (shutdown, signal) = ShutdownSignal::new();
    let runtime_metrics = metrics.clone();
    tokio::spawn(async move {
        PawxyServer::run_with_metrics(config, signal, runtime_metrics)
            .await
            .expect("pawxy server");
    });
    tokio::time::sleep(Duration::from_millis(50)).await;
    (listen, shutdown, metrics)
}

async fn assert_last_error_contains(metrics: &Metrics, expected: &str) {
    for _ in 0..20 {
        if let Some(error) = metrics.snapshot().last_error {
            if error.contains(expected) {
                return;
            }
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!(
        "last_error did not contain {expected:?}: {:?}",
        metrics.snapshot().last_error
    );
}

async fn assert_tunnel_metrics(metrics: &Metrics, bytes: u64) {
    for _ in 0..20 {
        let status = metrics.snapshot();
        if status.total_connections >= 1
            && status.active_connections >= 1
            && status.bytes_in >= bytes
            && status.bytes_out >= bytes
        {
            return;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    let status = metrics.snapshot();
    panic!(
        "metrics did not record active bidirectional tunnel traffic: active={} total={} bytes_in={} bytes_out={}",
        status.active_connections, status.total_connections, status.bytes_in, status.bytes_out
    );
}

async fn assert_active_connections_drain(metrics: &Metrics) {
    for _ in 0..20 {
        let status = metrics.snapshot();
        if status.active_connections == 0 {
            return;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!(
        "active connections did not drain: {}",
        metrics.snapshot().active_connections
    );
}

async fn read_until_double_crlf(stream: &mut TcpStream) -> Vec<u8> {
    let mut bytes = Vec::new();
    let mut buf = [0_u8; 64];
    loop {
        let n = tokio::time::timeout(Duration::from_secs(1), stream.read(&mut buf))
            .await
            .expect("read should not hang")
            .expect("read response");
        assert_ne!(n, 0, "connection closed before response header");
        bytes.extend_from_slice(&buf[..n]);
        if bytes.windows(4).any(|w| w == b"\r\n\r\n") {
            return bytes;
        }
    }
}

async fn open_connect_tunnel(proxy: SocketAddr, target: SocketAddr) -> TcpStream {
    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(format!("CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n\r\n").as_bytes())
        .await
        .expect("write connect");
    let response = read_until_double_crlf(&mut stream).await;
    assert!(String::from_utf8_lossy(&response).starts_with("HTTP/1.1 200"));
    stream
}

async fn assert_proxy_closes_without_tunnel(proxy: SocketAddr, target: SocketAddr) {
    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    let _ = stream
        .write_all(format!("CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n\r\n").as_bytes())
        .await;
    let mut response = [0_u8; 64];
    let read = tokio::time::timeout(Duration::from_secs(1), stream.read(&mut response))
        .await
        .expect("limit rejection should not hang");
    match read {
        Ok(0) => {}
        Ok(n) => {
            let text = String::from_utf8_lossy(&response[..n]);
            assert!(
                !text.starts_with("HTTP/1.1 200"),
                "limited connection unexpectedly opened a tunnel: {text}"
            );
        }
        Err(error) if error.kind() == std::io::ErrorKind::ConnectionReset => {}
        Err(error) => panic!("unexpected limited connection read error: {error}"),
    }
}

#[tokio::test]
async fn http_connect_tunnels_to_echo_server() {
    let echo = start_echo_server().await;
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(format!("CONNECT {echo} HTTP/1.1\r\nHost: {echo}\r\n\r\n").as_bytes())
        .await
        .expect("write connect");

    let mut response = [0_u8; 64];
    let n = stream
        .read(&mut response)
        .await
        .expect("read connect response");
    assert!(String::from_utf8_lossy(&response[..n]).starts_with("HTTP/1.1 200"));

    stream.write_all(b"ping").await.expect("write tunnel");
    let mut echoed = [0_u8; 4];
    stream.read_exact(&mut echoed).await.expect("read echo");
    assert_eq!(&echoed, b"ping");
    shutdown.shutdown();
}

#[tokio::test]
async fn http_connect_updates_bidirectional_metrics() {
    let echo = start_echo_server().await;
    let (proxy, shutdown, metrics) = start_pawxy_with_metrics(PawxyConfig::default()).await;

    let mut stream = open_connect_tunnel(proxy, echo).await;
    stream.write_all(b"metrics").await.expect("write tunnel");
    let mut echoed = [0_u8; 7];
    stream.read_exact(&mut echoed).await.expect("read echo");
    assert_eq!(&echoed, b"metrics");

    assert_tunnel_metrics(&metrics, 7).await;
    drop(stream);
    assert_active_connections_drain(&metrics).await;
    shutdown.shutdown();
}

#[tokio::test]
async fn max_connections_closes_excess_clients() {
    let echo = start_echo_server().await;
    let config = PawxyConfig {
        max_connections: 1,
        max_per_source_ip: 8,
        ..PawxyConfig::default()
    };
    let (proxy, shutdown, metrics) = start_pawxy_with_metrics(config).await;
    let _held = open_connect_tunnel(proxy, echo).await;

    assert_proxy_closes_without_tunnel(proxy, echo).await;
    assert_last_error_contains(&metrics, "max_connections limit reached").await;

    shutdown.shutdown();
}

#[tokio::test]
async fn max_per_source_ip_closes_excess_clients() {
    let echo = start_echo_server().await;
    let config = PawxyConfig {
        max_connections: 8,
        max_per_source_ip: 1,
        ..PawxyConfig::default()
    };
    let (proxy, shutdown, metrics) = start_pawxy_with_metrics(config).await;
    let _held = open_connect_tunnel(proxy, echo).await;

    assert_proxy_closes_without_tunnel(proxy, echo).await;
    assert_last_error_contains(&metrics, "max_per_source_ip limit reached").await;

    shutdown.shutdown();
}

#[tokio::test]
async fn http_connect_preserves_payload_sent_with_request_head() {
    let echo = start_echo_server().await;
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(format!("CONNECT {echo} HTTP/1.1\r\nHost: {echo}\r\n\r\nearly").as_bytes())
        .await
        .expect("write pipelined connect");

    let response = read_until_double_crlf(&mut stream).await;
    assert!(String::from_utf8_lossy(&response).starts_with("HTTP/1.1 200"));

    let mut echoed = [0_u8; 5];
    stream
        .read_exact(&mut echoed)
        .await
        .expect("read early echo");
    assert_eq!(&echoed, b"early");
    shutdown.shutdown();
}

#[tokio::test]
async fn http_connect_preserves_target_to_client_after_client_half_close() {
    let (target, seen_rx) = start_half_close_observer().await;
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = open_connect_tunnel(proxy, target).await;
    stream
        .write_all(b"client-done")
        .await
        .expect("write tunnel");
    stream.shutdown().await.expect("half-close client writer");

    let mut response = [0_u8; 9];
    stream
        .read_exact(&mut response)
        .await
        .expect("read after target observed client EOF");
    assert_eq!(&response, b"after-eof");

    let seen = seen_rx.await.expect("target should report received bytes");
    assert_eq!(seen, b"client-done");
    shutdown.shutdown();
}

#[tokio::test]
async fn socks5_connect_tunnels_to_echo_server() {
    let echo = start_echo_server().await;
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(&[0x05, 0x01, 0x00])
        .await
        .expect("greeting");
    let mut method = [0_u8; 2];
    stream.read_exact(&mut method).await.expect("method");
    assert_eq!(method, [0x05, 0x00]);

    let octets = match echo.ip() {
        std::net::IpAddr::V4(ip) => ip.octets(),
        std::net::IpAddr::V6(_) => unreachable!("echo uses ipv4"),
    };
    let port = echo.port().to_be_bytes();
    stream
        .write_all(&[
            0x05, 0x01, 0x00, 0x01, octets[0], octets[1], octets[2], octets[3], port[0], port[1],
        ])
        .await
        .expect("connect request");
    let mut reply = [0_u8; 10];
    stream.read_exact(&mut reply).await.expect("connect reply");
    assert_eq!(reply[1], 0x00);

    stream.write_all(b"pong").await.expect("write tunnel");
    let mut echoed = [0_u8; 4];
    stream.read_exact(&mut echoed).await.expect("read echo");
    assert_eq!(&echoed, b"pong");
    shutdown.shutdown();
}

#[tokio::test]
async fn socks5_connect_preserves_payload_sent_with_handshake() {
    let echo = start_echo_server().await;
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let octets = match echo.ip() {
        std::net::IpAddr::V4(ip) => ip.octets(),
        std::net::IpAddr::V6(_) => unreachable!("echo uses ipv4"),
    };
    let port = echo.port().to_be_bytes();
    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(&[
            0x05, 0x01, 0x00, 0x05, 0x01, 0x00, 0x01, octets[0], octets[1], octets[2], octets[3],
            port[0], port[1], b'e', b'a', b'r', b'l', b'y',
        ])
        .await
        .expect("write pipelined socks request");

    let mut method = [0_u8; 2];
    stream.read_exact(&mut method).await.expect("method");
    assert_eq!(method, [0x05, 0x00]);

    let mut reply = [0_u8; 10];
    stream.read_exact(&mut reply).await.expect("connect reply");
    assert_eq!(reply[1], 0x00);

    let mut echoed = [0_u8; 5];
    stream
        .read_exact(&mut echoed)
        .await
        .expect("read early echo");
    assert_eq!(&echoed, b"early");
    shutdown.shutdown();
}

#[tokio::test]
async fn socks5_username_password_auth_rejects_wrong_and_tunnels_correct_auth() {
    let echo = start_echo_server().await;
    let config = PawxyConfig {
        auth: Some(AuthConfig {
            username: "pawxy".to_string(),
            password: "pass".to_string(),
        }),
        ..PawxyConfig::default()
    };
    let (proxy, shutdown) = start_pawxy(config).await;

    let mut wrong = TcpStream::connect(proxy).await.expect("connect proxy");
    wrong
        .write_all(&[0x05, 0x01, 0x02])
        .await
        .expect("wrong greeting");
    let mut method = [0_u8; 2];
    wrong.read_exact(&mut method).await.expect("method");
    assert_eq!(method, [0x05, 0x02]);
    wrong
        .write_all(&[0x01, 0x05, b'p', b'a', b'w', b'x', b'y', 0x02, b'n', b'o'])
        .await
        .expect("wrong auth");
    let mut auth_reply = [0_u8; 2];
    wrong.read_exact(&mut auth_reply).await.expect("auth reply");
    assert_eq!(auth_reply, [0x01, 0x01]);

    let mut right = TcpStream::connect(proxy).await.expect("connect proxy");
    right
        .write_all(&[0x05, 0x01, 0x02])
        .await
        .expect("right greeting");
    right.read_exact(&mut method).await.expect("method");
    assert_eq!(method, [0x05, 0x02]);
    right
        .write_all(&[
            0x01, 0x05, b'p', b'a', b'w', b'x', b'y', 0x04, b'p', b'a', b's', b's',
        ])
        .await
        .expect("right auth");
    right.read_exact(&mut auth_reply).await.expect("auth reply");
    assert_eq!(auth_reply, [0x01, 0x00]);

    let octets = match echo.ip() {
        std::net::IpAddr::V4(ip) => ip.octets(),
        std::net::IpAddr::V6(_) => unreachable!("echo uses ipv4"),
    };
    let port = echo.port().to_be_bytes();
    right
        .write_all(&[
            0x05, 0x01, 0x00, 0x01, octets[0], octets[1], octets[2], octets[3], port[0], port[1],
        ])
        .await
        .expect("connect request");
    let mut reply = [0_u8; 10];
    right.read_exact(&mut reply).await.expect("connect reply");
    assert_eq!(reply[1], 0x00);

    right.write_all(b"auth").await.expect("write tunnel");
    let mut echoed = [0_u8; 4];
    right.read_exact(&mut echoed).await.expect("read echo");
    assert_eq!(&echoed, b"auth");
    shutdown.shutdown();
}

#[tokio::test]
async fn absolute_form_http_request_is_forwarded_origin_form() {
    let http = start_http_server().await;
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(
            format!(
                "GET http://{http}/through-pawxy?ok=1 HTTP/1.1\r\nHost: {http}\r\nConnection: close\r\n\r\n"
            )
            .as_bytes(),
        )
        .await
        .expect("write request");

    let mut response = Vec::new();
    stream
        .read_to_end(&mut response)
        .await
        .expect("read response");
    assert!(String::from_utf8_lossy(&response).contains("absolute-ok"));
    shutdown.shutdown();
}

#[tokio::test]
async fn absolute_form_http_post_preserves_body_bytes() {
    let http = start_http_body_server().await;
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(
            format!(
                "POST http://{http}/submit HTTP/1.1\r\nHost: {http}\r\nContent-Length: 4\r\nConnection: close\r\n\r\ndata"
            )
            .as_bytes(),
        )
        .await
        .expect("write request");

    let mut response = Vec::new();
    stream
        .read_to_end(&mut response)
        .await
        .expect("read response");
    assert!(String::from_utf8_lossy(&response).contains("body-ok"));
    shutdown.shutdown();
}

#[tokio::test]
async fn auth_required_rejects_wrong_auth_and_accepts_correct_auth() {
    let echo = start_echo_server().await;
    let config = PawxyConfig {
        auth: Some(AuthConfig {
            username: "pawxy".to_string(),
            password: "pass".to_string(),
        }),
        ..PawxyConfig::default()
    };
    let (proxy, shutdown) = start_pawxy(config).await;

    let mut wrong = TcpStream::connect(proxy).await.expect("connect proxy");
    wrong
        .write_all(format!("CONNECT {echo} HTTP/1.1\r\nHost: {echo}\r\nProxy-Authorization: Basic cGF3eHk6bm8=\r\n\r\n").as_bytes())
        .await
        .expect("write wrong auth");
    let mut response = [0_u8; 128];
    let n = wrong
        .read(&mut response)
        .await
        .expect("read wrong auth response");
    assert!(String::from_utf8_lossy(&response[..n]).starts_with("HTTP/1.1 407"));

    let mut right = TcpStream::connect(proxy).await.expect("connect proxy");
    right
        .write_all(format!("CONNECT {echo} HTTP/1.1\r\nHost: {echo}\r\nProxy-Authorization: Basic cGF3eHk6cGFzcw==\r\n\r\n").as_bytes())
        .await
        .expect("write correct auth");
    let mut ok = [0_u8; 64];
    let n = right
        .read(&mut ok)
        .await
        .expect("read correct auth response");
    assert!(String::from_utf8_lossy(&ok[..n]).starts_with("HTTP/1.1 200"));
    shutdown.shutdown();
}

#[tokio::test]
async fn auth_required_absolute_form_http_rejects_missing_auth_and_strips_correct_auth() {
    let http = start_http_server().await;
    let config = PawxyConfig {
        auth: Some(AuthConfig {
            username: "pawxy".to_string(),
            password: "pass".to_string(),
        }),
        ..PawxyConfig::default()
    };
    let (proxy, shutdown) = start_pawxy(config).await;

    let mut missing = TcpStream::connect(proxy).await.expect("connect proxy");
    missing
        .write_all(
            format!("GET http://{http}/through-pawxy?ok=1 HTTP/1.1\r\nHost: {http}\r\n\r\n")
                .as_bytes(),
        )
        .await
        .expect("write missing auth");
    let mut response = [0_u8; 128];
    let n = missing
        .read(&mut response)
        .await
        .expect("read missing auth response");
    assert!(String::from_utf8_lossy(&response[..n]).starts_with("HTTP/1.1 407"));

    let mut right = TcpStream::connect(proxy).await.expect("connect proxy");
    right
        .write_all(
            format!(
                "GET http://{http}/through-pawxy?ok=1 HTTP/1.1\r\nHost: {http}\r\nProxy-Authorization: Basic cGF3eHk6cGFzcw==\r\nConnection: close\r\n\r\n"
            )
            .as_bytes(),
        )
        .await
        .expect("write correct auth");
    let mut ok = Vec::new();
    right.read_to_end(&mut ok).await.expect("read response");
    let text = String::from_utf8_lossy(&ok);
    assert!(text.contains("absolute-ok"), "unexpected response: {text}");
    assert!(!text.contains("unexpected-request"));
    shutdown.shutdown();
}

#[tokio::test]
async fn invalid_protocol_prefix_is_rejected() {
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    stream
        .write_all(b"NOPE")
        .await
        .expect("write invalid prefix");
    let mut buf = [0_u8; 8];
    let read = tokio::time::timeout(Duration::from_secs(1), stream.read(&mut buf))
        .await
        .expect("read should not hang")
        .expect("read close");
    assert_eq!(read, 0);
    shutdown.shutdown();
}

#[tokio::test]
async fn oversized_http_headers_are_rejected() {
    let (proxy, shutdown) = start_pawxy(PawxyConfig::default()).await;

    let mut stream = TcpStream::connect(proxy).await.expect("connect proxy");
    let oversized = format!(
        "GET http://example.com/ HTTP/1.1\r\nHost: example.com\r\nX-Fill: {}\r\n\r\n",
        "a".repeat(17 * 1024)
    );
    stream
        .write_all(oversized.as_bytes())
        .await
        .expect("write oversized request");
    let mut buf = [0_u8; 128];
    let read = tokio::time::timeout(Duration::from_secs(1), stream.read(&mut buf))
        .await
        .expect("read should not hang")
        .expect("read rejection response");
    assert!(String::from_utf8_lossy(&buf[..read]).starts_with("HTTP/1.1 400"));
    shutdown.shutdown();
}

#[test]
fn lan_listen_without_auth_is_rejected_by_config_validation() {
    let config = PawxyConfig {
        listen: "0.0.0.0:3218".parse().expect("listen"),
        ..PawxyConfig::default()
    };

    let error = config.validate().expect_err("must reject unsafe LAN mode");

    assert!(error.to_string().contains("requires proxy authentication"));
}
