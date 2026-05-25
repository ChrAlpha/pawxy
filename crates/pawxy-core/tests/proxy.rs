use std::net::SocketAddr;
use std::time::Duration;

use pawxy_core::{AuthConfig, PawxyConfig, PawxyServer, ShutdownSignal};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

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
                let body = if request.starts_with("GET /through-pawxy?ok=1 HTTP/1.1\r\n") {
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
