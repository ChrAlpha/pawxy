use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpStream;
use tokio::time::timeout;

use crate::error::Result;
use crate::metrics::Metrics;

pub async fn tunnel(
    client: TcpStream,
    target: TcpStream,
    client_pending: Vec<u8>,
    idle_timeout: Duration,
    metrics: Arc<Metrics>,
) -> Result<()> {
    let (client_read, client_write) = client.into_split();
    let (target_read, target_write) = target.into_split();
    let client_to_target = copy_direction(
        client_read,
        target_write,
        client_pending,
        idle_timeout,
        Direction::ClientToTarget,
        metrics.clone(),
    );
    let target_to_client = copy_direction(
        target_read,
        client_write,
        Vec::new(),
        idle_timeout,
        Direction::TargetToClient,
        metrics,
    );
    let (first, second) = tokio::join!(client_to_target, target_to_client);
    first?;
    second?;
    Ok(())
}

#[derive(Clone, Copy)]
enum Direction {
    ClientToTarget,
    TargetToClient,
}

async fn copy_direction(
    mut reader: OwnedReadHalf,
    mut writer: OwnedWriteHalf,
    initial: Vec<u8>,
    idle_timeout: Duration,
    direction: Direction,
    metrics: Arc<Metrics>,
) -> std::io::Result<()> {
    if !initial.is_empty() {
        writer.write_all(&initial).await?;
        count(&metrics, direction, initial.len() as u64);
    }

    let mut buffer = vec![0_u8; 32 * 1024];
    loop {
        let read = match timeout(idle_timeout, reader.read(&mut buffer)).await {
            Ok(read) => read?,
            Err(_) => break,
        };
        if read == 0 {
            break;
        }
        writer.write_all(&buffer[..read]).await?;
        count(&metrics, direction, read as u64);
    }
    let _ = writer.shutdown().await;
    Ok(())
}

fn count(metrics: &Metrics, direction: Direction, amount: u64) {
    match direction {
        Direction::ClientToTarget => metrics.add_bytes_in(amount),
        Direction::TargetToClient => metrics.add_bytes_out(amount),
    }
}
