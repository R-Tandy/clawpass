# Full Desktop Sync Fix - TCP Server for iOS Compatibility

## Files to Create/Modify in ClawPass/desktop/src-tauri/

---

## 1. NEW FILE: src/sync_tcp.rs

```rust
use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use std::sync::Arc;
use tokio::sync::RwLock;
use crate::vault::{Vault, VaultEntry};
use serde::{Serialize, Deserialize};
use log;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum SyncMessage {
    #[serde(rename = "handshake")]
    Handshake { device_id: String, version: u32 },
    #[serde(rename = "sync_request")]
    SyncRequest { last_timestamp: u64 },
    #[serde(rename = "sync_response")]
    SyncResponse { entries: Vec<VaultEntry>, timestamp: u64 },
    #[serde(rename = "entry_update")]
    EntryUpdate { entry: VaultEntry },
    #[serde(rename = "entry_delete")]
    EntryDelete { entry_id: String },
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "pong")]
    Pong,
}

impl SyncMessage {
    pub fn to_bytes(&self) -> Vec<u8> {
        let json = serde_json::to_string(self).unwrap_or_default();
        let len = json.len() as u32;
        let mut buf = Vec::with_capacity(4 + json.len());
        buf.extend_from_slice(&len.to_be_bytes());
        buf.extend_from_slice(json.as_bytes());
        buf
    }
    
    pub fn from_bytes(buf: &[u8]) -> Option<Self> {
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
        
        log::info!("TCP Sync server listening on port {}", port);
        
        let server = Self { vault, port };
        let vault_clone = server.vault.clone();
        
        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, addr)) => {
                        log::info!("Sync client connected: {}", addr);
                        let vault = vault_clone.clone();
                        tokio::spawn(async move {
                            Self::handle_client(vault, stream).await;
                        });
                    }
                    Err(e) => {
                        log::error!("Accept error: {}", e);
                    }
                }
            }
        });
        
        Ok(server)
    }
    
    async fn handle_client(vault: Arc<RwLock<Vault>>, mut stream: TcpStream) {
        let mut buf = vec![0u8; 65536];
        let mut cursor = 0usize;
        
        loop {
            match stream.read(&mut buf[cursor..]).await {
                Ok(0) => {
                    log::info!("Client disconnected");
                    break;
                }
                Ok(n) => {
                    cursor += n;
                    
                    // Try to parse messages
                    while cursor >= 4 {
                        let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;
                        if cursor < 4 + len { break; }
                        
                        if let Some(msg) = SyncMessage::from_bytes(&buf[..4+len]) {
                            let response = Self::process_message(&vault, msg).await;
                            if let Some(resp) = response {
                                let resp_bytes = resp.to_bytes();
                                if stream.write_all(&resp_bytes).await.is_err() {
                                    break;
                                }
                            }
                        }
                        
                        buf.copy_within(4+len..cursor, 0);
                        cursor -= 4 + len;
                    }
                }
                Err(e) => {
                    log::error!("Read error: {}", e);
                    break;
                }
            }
        }
    }
    
    async fn process_message(vault: &Arc<RwLock<Vault>>, msg: SyncMessage) -> Option<SyncMessage> {
        match msg {
            SyncMessage::Ping => {
                log::debug!("Received ping, sending pong");
                Some(SyncMessage::Pong)
            }
            SyncMessage::SyncRequest { last_timestamp } => {
                log::info!("Sync request from timestamp: {}", last_timestamp);
                let vault = vault.read().await;
                let entries: Vec<VaultEntry> = vault.entries()
                    .into_iter()
                    .filter(|e| e.updated_at > last_timestamp)
                    .collect();
                
                Some(SyncMessage::SyncResponse {
                    entries,
                    timestamp: now(),
                })
            }
            SyncMessage::EntryUpdate { entry } => {
                log::info!("Received entry update: {}", entry.id);
                let mut vault = vault.write().await;
                let _ = vault.add_or_update_entry(entry);
                None
            }
            SyncMessage::EntryDelete { entry_id } => {
                log::info!("Received entry delete: {}", entry_id);
                let mut vault = vault.write().await;
                let _ = vault.delete_entry(&entry_id);
                None
            }
            _ => {
                log::warn!("Unhandled message type");
                None
            }
        }
    }
}

fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
```

---

## 2. MODIFY: Cargo.toml

Add under `[dependencies]`:
```toml
tokio = { version = "1.35", features = ["rt-multi-thread", "macros", "net", "io-util"] }
```

---

## 3. MODIFY: src/main.rs

Add at the top with other mods:
```rust
mod sync_tcp;
```

In your `main()` function, start the TCP server alongside existing services:
```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use crate::vault::Vault;

fn main() {
    // ... existing setup ...
    
    tauri::Builder::default()
        .setup(|app| {
            // Initialize vault
            let vault = Arc::new(RwLock::new(Vault::new()));
            
            // Start TCP sync server on port 7878
            let vault_clone = vault.clone();
            tauri::async_runtime::spawn(async move {
                match sync_tcp::TcpSyncServer::start(vault_clone, 7878).await {
                    Ok(_) => log::info!("TCP sync server started on port 7878"),
                    Err(e) => log::error!("Failed to start TCP sync: {}", e),
                }
            });
            
            // ... existing setup ...
            Ok(())
        })
        // ... rest of builder ...
}
```

---

## 4. MODIFY: src/vault.rs

Ensure `VaultEntry` derives Serialize/Deserialize:
```rust
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct VaultEntry {
    pub id: String,
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    pub category_id: Option<String>,
    pub created_at: u64,
    pub updated_at: u64,
}

impl Vault {
    pub fn entries(&self) -> Vec<VaultEntry> {
        self.entries.clone()
    }
    
    pub fn add_or_update_entry(&mut self, entry: VaultEntry) -> Result<(), String> {
        // Remove existing if present
        self.entries.retain(|e| e.id != entry.id);
        self.entries.push(entry);
        self.save()  // Auto-save
    }
    
    pub fn delete_entry(&mut self, id: &str) -> Result<(), String> {
        self.entries.retain(|e| e.id != id);
        self.save()
    }
}
```

---

## 5. iOS Side (Swift)

Update iOS `SyncService.swift` to connect to desktop:

```swift
class SyncService: ObservableObject {
    private var connection: NWConnection?
    private let host = "192.168.1.XXX" // Desktop IP - or use Bonjour/mDNS
    private let port = 7878
    
    func connect() {
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.init(string: host)!),
            port: .init(integer: port)
        )
        
        connection = NWConnection(to: endpoint, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.sendHandshake()
                case .failed(let error):
                    self?.errorMessage = error.localizedDescription
                default:
                    break
                }
            }
        }
        connection?.start(queue: .global())
    }
    
    func sync() {
        let request: [String: Any] = [
            "type": "sync_request",
            "data": ["last_timestamp": UserDefaults.standard.integer(forKey: "lastSync")]
        ]
        send(data: request)
    }
}
```

---

## Summary

This adds a **TCP server on port 7878** to the desktop app that mirrors the iOS protocol:
- Same length-prefixed JSON format
- Same message types (handshake, sync_request, sync_response, entry_update, entry_delete, ping/pong)
- Desktop accepts connections from iOS devices on the same network

**To use:**
1. Desktop starts TCP server on startup
2. iOS discovers desktop via mDNS or manual IP entry
3. iOS connects to `desktop-ip:7878`
4. Bidirectional sync via the protocol

Build and push - iOS app should now sync with desktop!
