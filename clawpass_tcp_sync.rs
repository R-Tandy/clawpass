// Add this to desktop/src-tauri/src/sync.rs or as sync_tcp.rs
// Mirrors iOS raw TCP protocol for compatibility

use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Debug, Clone)]
pub enum SyncMessage {
    Handshake { device_id: String, version: u32 },
    SyncRequest { last_timestamp: u64 },
    SyncResponse { entries: Vec<VaultEntry>, timestamp: u64 },
    EntryUpdate { entry: VaultEntry },
    EntryDelete { entry_id: String },
    Ping,
    Pong,
}

impl SyncMessage {
    fn to_bytes(&self) -> Vec<u8> {
        let json = serde_json::to_string(self).unwrap();
        let len = json.len() as u32;
        let mut buf = Vec::with_capacity(4 + json.len());
        buf.extend_from_slice(&len.to_be_bytes());
        buf.extend_from_slice(json.as_bytes());
        buf
    }
    
    fn from_bytes(buf: &[u8]) -> Option<Self> {
        if buf.len() < 4 { return None; }
        let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;
        if buf.len() < 4 + len { return None; }
        serde_json::from_slice(&buf[4..4+len]).ok()
    }
}

pub struct TcpSyncServer {
    vault: Arc<RwLock<Vault>>,
    port: u16,
}

impl TcpSyncServer {
    pub async fn start(vault: Arc<RwLock<Vault>>, port: u16) -> Result<Self, String> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port))
            .await
            .map_err(|e| format!("Failed to bind: {}", e))?;
        
        let server = Self { vault, port };
        
        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, addr)) => {
                        log::info!("Sync connection from: {}", addr);
                        // Handle connection
                    }
                    Err(e) => {
                        log::error!("Accept error: {}", e);
                    }
                }
            }
        });
        
        Ok(server)
    }
    
    async fn handle_client(&self, mut stream: TcpStream) {
        let mut buf = vec![0u8; 8192];
        
        loop {
            match stream.read(&mut buf).await {
                Ok(0) => break, // Connection closed
                Ok(n) => {
                    if let Some(msg) = SyncMessage::from_bytes(&buf[..n]) {
                        match msg {
                            SyncMessage::Ping => {
                                let pong = SyncMessage::Pong.to_bytes();
                                let _ = stream.write_all(&pong).await;
                            }
                            SyncMessage::SyncRequest { last_timestamp } => {
                                let vault = self.vault.read().await;
                                let entries: Vec<VaultEntry> = vault.entries
                                    .iter()
                                    .filter(|e| e.updated_at > last_timestamp)
                                    .cloned()
                                    .collect();
                                
                                let response = SyncMessage::SyncResponse {
                                    entries,
                                    timestamp: now(),
                                };
                                let _ = stream.write_all(&response.to_bytes()).await;
                            }
                            _ => {}
                        }
                    }
                }
                Err(_) => break,
            }
        }
    }
}

fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

// In main.rs, add alongside websocket:
// let tcp_sync = TcpSyncServer::start(vault.clone(), 7878).await?;
