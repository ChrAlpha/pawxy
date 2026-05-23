use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, Mutex};

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::time::timeout;
use tracing::{debug, warn};

use crate::config::PawxyConfig;
use crate::error::{PawxyError, Result};
use crate::http_proxy::{
    is_supported_http_method, parse_connect_target as parse_http_connect_target,
    parse_request_head, proxy_auth_allowed, response_400, response_407, response_502,
    rewrite_absolute_form_request,
};
use crate::metrics::Metrics;
use crate::sniff::{classify_prefix, Protocol};
use crate::socks5::{
    choose_auth_method, parse_connect_target as parse_socks_connect_target,
    username_password_matches, METHOD_NO_ACCEPTABLE,
};
use crate::tunnel::tunnel;

#[derive(Clone)]
pub struct ShutdownHandle {
    sender: watch::Sender<bool>,
}

pub struct ShutdownSignal {
    receiver: watch::Receiver<bool>,
}

impl ShutdownSignal {
    pub fn new() -> (ShutdownHandle, Self) {
        let (sender, receiver) = watch::channel(false);
        (ShutdownHandle { sender }, Self { receiver })
    }
}

impl ShutdownHandle {
    pub fn shutdown(&self) {
        let _ = self.sender.send(true);
    }
}

pub struct PawxyServer;

impl PawxyServer {
    pub async fn run(config: PawxyConfig, shutdown: ShutdownSignal) -> Result<()> {
        let metrics = Arc::new(Metrics::new(&config));
        Self::run_with_metrics(config, shutdown, metrics).await
    }

    pub async fn run_with_metrics(
        config: PawxyConfig,
        mut shutdown: ShutdownSignal,
        metrics: Arc<Metrics>,
    ) -> Result<()> {
        config.validate()?;
        let listener = TcpListener::bind(config.listen).await?;
        let local_addr = listener.local_addr()?;
        metrics.mark_started(local_addr.to_string(), &config);

        let config = Arc::new(config);
        let per_source = Arc::new(Mutex::new(HashMap::<IpAddr, u64>::new()));

        loop {
            tokio::select! {
                changed = shutdown.receiver.changed() => {
                    if changed.is_ok() && *shutdown.receiver.borrow() {
                        break;
                    }
                    if changed.is_err() {
                        break;
                    }
                }
                accepted = listener.accept() => {
                    let (stream, peer_addr) = accepted?;
                    if config.tcp_nodelay {
                        let _ = stream.set_nodelay(true);
                    }
                    if config.tcp_keepalive {
                        let socket_ref = socket2::SockRef::from(&stream);
                        let _ = socket_ref.set_keepalive(true);
                    }

                    let source_ip = peer_addr.ip();
                    if metrics.active_connections() >= config.max_connections as u64 {
                        debug!("rejecting connection over global limit");
                        continue;
                    }
                    if !try_acquire_source(&per_source, source_ip, config.max_per_source_ip) {
                        debug!("rejecting connection over per-source limit");
                        continue;
                    }

                    metrics.connection_started();
                    let config = config.clone();
                    let metrics = metrics.clone();
                    let per_source = per_source.clone();
                    tokio::spawn(async move {
                        let result = handle_connection(stream, config, metrics.clone()).await;
                        if let Err(error) = result {
                            warn!(%error, "connection ended with error");
                            metrics.set_last_error(Some(error.to_string()));
                        }
                        metrics.connection_finished();
                        release_source(&per_source, source_ip);
                    });
                }
            }
        }

        metrics.mark_stopped();
        Ok(())
    }
}

fn try_acquire_source(
    per_source: &Mutex<HashMap<IpAddr, u64>>,
    source_ip: IpAddr,
    max_per_source_ip: usize,
) -> bool {
    let mut counts = per_source.lock().expect("per-source lock");
    let count = counts.entry(source_ip).or_insert(0);
    if *count >= max_per_source_ip as u64 {
        return false;
    }
    *count += 1;
    true
}

fn release_source(per_source: &Mutex<HashMap<IpAddr, u64>>, source_ip: IpAddr) {
    let mut counts = per_source.lock().expect("per-source lock");
    if let Some(count) = counts.get_mut(&source_ip) {
        *count = count.saturating_sub(1);
        if *count == 0 {
            counts.remove(&source_ip);
        }
    }
}

async fn handle_connection(
    mut stream: TcpStream,
    config: Arc<PawxyConfig>,
    metrics: Arc<Metrics>,
) -> Result<()> {
    let mut initial = [0_u8; 512];
    let read = timeout(config.handshake_timeout, stream.read(&mut initial))
        .await
        .map_err(|_| PawxyError::Timeout("reading initial proxy bytes"))??;
    if read == 0 {
        return Ok(());
    }
    let protocol = classify_prefix(&initial[..read])
        .ok_or(PawxyError::Protocol("unknown proxy protocol prefix"))?;
    let client = BufferedTcp::new(stream, initial[..read].to_vec());
    match protocol {
        Protocol::Http => handle_http(client, config, metrics).await,
        Protocol::Socks5 => handle_socks5(client, config, metrics).await,
    }
}

async fn handle_http(
    mut client: BufferedTcp,
    config: Arc<PawxyConfig>,
    metrics: Arc<Metrics>,
) -> Result<()> {
    let header = match client
        .read_until_double_crlf(16 * 1024, config.handshake_timeout)
        .await
    {
        Ok(header) => header,
        Err(error) => {
            let _ = client.stream.write_all(response_400()).await;
            return Err(error);
        }
    };
    let head = match parse_request_head(&header) {
        Ok(head) if is_supported_http_method(&head.method) => head,
        _ => {
            client.stream.write_all(response_400()).await?;
            return Ok(());
        }
    };

    if !proxy_auth_allowed(&head.headers, config.auth.as_ref()) {
        client.stream.write_all(response_407()).await?;
        return Ok(());
    }

    if head.method == "CONNECT" {
        let target = match parse_http_connect_target(&head.target) {
            Ok(target) => target,
            Err(_) => {
                client.stream.write_all(response_400()).await?;
                return Ok(());
            }
        };
        let target_stream =
            match connect_target(&target.host, target.port, config.connect_timeout).await {
                Ok(stream) => stream,
                Err(error) => {
                    client.stream.write_all(response_502()).await?;
                    return Err(error);
                }
            };
        client
            .stream
            .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            .await?;
        let pending = client.take_pending();
        tunnel(
            client.into_inner(),
            target_stream,
            pending,
            config.idle_timeout,
            metrics,
        )
        .await
    } else {
        let (target, mut rewritten) = match rewrite_absolute_form_request(&head) {
            Ok(value) => value,
            Err(_) => {
                client.stream.write_all(response_400()).await?;
                return Ok(());
            }
        };
        let target_stream =
            match connect_target(&target.host, target.port, config.connect_timeout).await {
                Ok(stream) => stream,
                Err(error) => {
                    client.stream.write_all(response_502()).await?;
                    return Err(error);
                }
            };
        rewritten.extend_from_slice(&client.take_pending());
        tunnel(
            client.into_inner(),
            target_stream,
            rewritten,
            config.idle_timeout,
            metrics,
        )
        .await
    }
}

async fn handle_socks5(
    mut client: BufferedTcp,
    config: Arc<PawxyConfig>,
    metrics: Arc<Metrics>,
) -> Result<()> {
    let greeting = client.read_exact_vec(2, config.handshake_timeout).await?;
    if greeting[0] != 0x05 {
        return Err(PawxyError::Protocol("invalid SOCKS5 version"));
    }
    let methods = client
        .read_exact_vec(greeting[1] as usize, config.handshake_timeout)
        .await?;
    let Some(method) = choose_auth_method(&methods, config.auth.is_some()) else {
        client
            .stream
            .write_all(&[0x05, METHOD_NO_ACCEPTABLE])
            .await?;
        return Ok(());
    };
    client.stream.write_all(&[0x05, method]).await?;

    if let Some(auth) = &config.auth {
        let mut payload = client.read_exact_vec(2, config.handshake_timeout).await?;
        let username_len = payload[1] as usize;
        payload.extend(
            client
                .read_exact_vec(username_len, config.handshake_timeout)
                .await?,
        );
        let password_len = client.read_exact_vec(1, config.handshake_timeout).await?;
        let password_len_value = password_len[0] as usize;
        payload.extend(password_len);
        payload.extend(
            client
                .read_exact_vec(password_len_value, config.handshake_timeout)
                .await?,
        );
        if !username_password_matches(&payload, &auth.username, &auth.password)? {
            client.stream.write_all(&[0x01, 0x01]).await?;
            return Ok(());
        }
        client.stream.write_all(&[0x01, 0x00]).await?;
    }

    let mut request = client.read_exact_vec(4, config.handshake_timeout).await?;
    let address_bytes = match request[3] {
        0x01 => 4,
        0x04 => 16,
        0x03 => {
            let len = client.read_exact_vec(1, config.handshake_timeout).await?;
            let domain_len = len[0] as usize;
            request.extend(len);
            domain_len
        }
        _ => {
            write_socks_failure(&mut client.stream, 0x08).await?;
            return Ok(());
        }
    };
    request.extend(
        client
            .read_exact_vec(address_bytes + 2, config.handshake_timeout)
            .await?,
    );

    let target = match parse_socks_connect_target(&request) {
        Ok(target) => target,
        Err(_) => {
            write_socks_failure(&mut client.stream, 0x07).await?;
            return Ok(());
        }
    };
    let target_stream = match connect_socks_target(&target, config.connect_timeout).await {
        Ok(stream) => stream,
        Err(error) => {
            write_socks_failure(&mut client.stream, 0x05).await?;
            return Err(error);
        }
    };
    client
        .stream
        .write_all(&[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
        .await?;
    let pending = client.take_pending();
    tunnel(
        client.into_inner(),
        target_stream,
        pending,
        config.idle_timeout,
        metrics,
    )
    .await
}

async fn write_socks_failure(stream: &mut TcpStream, code: u8) -> Result<()> {
    stream
        .write_all(&[0x05, code, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
        .await?;
    Ok(())
}

async fn connect_socks_target(
    target: &crate::socks5::SocksTarget,
    connect_timeout: std::time::Duration,
) -> Result<TcpStream> {
    match &target.addr {
        crate::socks5::SocksAddr::Ip(ip) => {
            connect_target(&ip.to_string(), target.port, connect_timeout).await
        }
        crate::socks5::SocksAddr::Domain(domain) => {
            connect_target(domain, target.port, connect_timeout).await
        }
    }
}

async fn connect_target(
    host: &str,
    port: u16,
    connect_timeout: std::time::Duration,
) -> Result<TcpStream> {
    timeout(connect_timeout, TcpStream::connect((host, port)))
        .await
        .map_err(|_| PawxyError::Timeout("connecting to target"))?
        .map_err(PawxyError::Io)
}

struct BufferedTcp {
    stream: TcpStream,
    buffer: Vec<u8>,
    offset: usize,
}

impl BufferedTcp {
    fn new(stream: TcpStream, buffer: Vec<u8>) -> Self {
        Self {
            stream,
            buffer,
            offset: 0,
        }
    }

    async fn read_exact_vec(
        &mut self,
        len: usize,
        read_timeout: std::time::Duration,
    ) -> Result<Vec<u8>> {
        self.ensure_available(len, Some(read_timeout), usize::MAX)
            .await?;
        let start = self.offset;
        let end = start + len;
        self.offset = end;
        Ok(self.buffer[start..end].to_vec())
    }

    async fn read_until_double_crlf(
        &mut self,
        max_len: usize,
        read_timeout: std::time::Duration,
    ) -> Result<Vec<u8>> {
        loop {
            if let Some(relative) = find_double_crlf(&self.buffer[self.offset..]) {
                let start = self.offset;
                let end = self.offset + relative + 4;
                self.offset = end;
                return Ok(self.buffer[start..end].to_vec());
            }
            if self.buffer.len().saturating_sub(self.offset) >= max_len {
                return Err(PawxyError::Parse("HTTP header exceeds 16 KiB"));
            }
            self.read_more(Some(read_timeout), max_len).await?;
        }
    }

    fn take_pending(&mut self) -> Vec<u8> {
        let pending = self.buffer[self.offset..].to_vec();
        self.buffer.clear();
        self.offset = 0;
        pending
    }

    fn into_inner(self) -> TcpStream {
        self.stream
    }

    async fn ensure_available(
        &mut self,
        len: usize,
        read_timeout: Option<std::time::Duration>,
        max_len: usize,
    ) -> Result<()> {
        while self.buffer.len().saturating_sub(self.offset) < len {
            self.read_more(read_timeout, max_len).await?;
        }
        Ok(())
    }

    async fn read_more(
        &mut self,
        read_timeout: Option<std::time::Duration>,
        max_len: usize,
    ) -> Result<()> {
        if self.offset > 0 && self.offset >= self.buffer.len() / 2 {
            self.buffer.drain(..self.offset);
            self.offset = 0;
        }
        if self.buffer.len().saturating_sub(self.offset) > max_len {
            return Err(PawxyError::Parse("buffer exceeds maximum length"));
        }
        let mut chunk = [0_u8; 4096];
        let read = if let Some(read_timeout) = read_timeout {
            timeout(read_timeout, self.stream.read(&mut chunk))
                .await
                .map_err(|_| PawxyError::Timeout("reading proxy handshake"))??
        } else {
            self.stream.read(&mut chunk).await?
        };
        if read == 0 {
            return Err(PawxyError::Parse("unexpected EOF"));
        }
        self.buffer.extend_from_slice(&chunk[..read]);
        if self.buffer.len().saturating_sub(self.offset) > max_len {
            return Err(PawxyError::Parse("buffer exceeds maximum length"));
        }
        Ok(())
    }
}

fn find_double_crlf(bytes: &[u8]) -> Option<usize> {
    memchr::memmem::find(bytes, b"\r\n\r\n")
}
