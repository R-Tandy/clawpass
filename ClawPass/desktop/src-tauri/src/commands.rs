use serde::{Deserialize, Serialize};
use tauri::State;
use std::sync::Mutex;
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Clone)]
pub struct VaultEntry {
    pub id: String,
    pub title: String,
    pub username: String,
    pub encrypted_password: Vec<u8>,
    pub url: Option<String>,
    pub encrypted_notes: Option<Vec<u8>>,
    pub category_id: Option<String>,
    pub totp_secret: Option<String>,
    pub created_at: i64,
    pub modified_at: i64,
    pub is_favorite: bool,
}

#[derive(Serialize)]
pub struct PasswordOptions {
    pub length: u32,
    pub use_uppercase: bool,
    pub use_lowercase: bool,
    pub use_numbers: bool,
    pub use_symbols: bool,
}

// Keeper CSV import structure
#[derive(Debug, Deserialize)]
struct KeeperRecord {
    #[serde(rename = "Folder")]
    folder: String,
    #[serde(rename = "Title")]
    title: String,
    #[serde(rename = "Login")]
    login: String,
    #[serde(rename = "Password")]
    password: String,
    #[serde(rename = "Website Address")]
    website: String,
    #[serde(rename = "Notes")]
    notes: String,
}

pub struct AppState {
    pub vault: Mutex<Option<Vault>>,
}

pub struct Vault {
    pub key: Vec<u8>,
    pub entries: Vec<VaultEntry>,
}

// Vault commands
#[tauri::command]
pub async fn unlock_vault(
    password: String,
    state: State<'_, AppState>
) -> Result<bool, String> {
    // Implementation would check password against stored hash
    // and decrypt the vault key
    let mut vault = state.vault.lock().map_err(|e| e.to_string())?;
    
    // For now, placeholder implementation
    if password.len() >= 8 {
        *vault = Some(Vault {
            key: vec![], // Derived key would go here
            entries: vec![],
        });
        Ok(true)
    } else {
        Ok(false)
    }
}

#[tauri::command]
pub async fn lock_vault(state: State<'_, AppState>) {
    let mut vault = state.vault.lock().unwrap();
    *vault = None;
}

#[tauri::command]
pub async fn create_vault(
    password: String,
    state: State<'_, AppState>
) -> Result<(), String> {
    let mut vault = state.vault.lock().map_err(|e| e.to_string())?;
    
    // Generate salt and derive key
    let salt = generate_salt();
    let key = derive_key(&password, &salt);
    
    // Create encrypted database
    create_database(&key)?;
    
    *vault = Some(Vault {
        key,
        entries: vec![],
    });
    
    Ok(())
}

#[tauri::command]
pub async fn get_entries(
    state: State<'_, AppState>
) -> Result<Vec<VaultEntry>, String> {
    let vault = state.vault.lock().map_err(|e| e.to_string())?;
    
    if let Some(v) = vault.as_ref() {
        Ok(v.entries.clone())
    } else {
        Err("Vault not unlocked".to_string())
    }
}

#[tauri::command]
pub async fn add_entry(
    entry: VaultEntry,
    state: State<'_, AppState>
) -> Result<(), String> {
    let mut vault = state.vault.lock().map_err(|e| e.to_string())?;
    
    if let Some(v) = vault.as_mut() {
        v.entries.push(entry);
        Ok(())
    } else {
        Err("Vault not unlocked".to_string())
    }
}

#[tauri::command]
pub async fn update_entry(
    entry: VaultEntry,
    state: State<'_, AppState>
) -> Result<(), String> {
    let mut vault = state.vault.lock().map_err(|e| e.to_string())?;
    
    if let Some(v) = vault.as_mut() {
        if let Some(idx) = v.entries.iter().position(|e| e.id == entry.id) {
            v.entries[idx] = entry;
        }
        Ok(())
    } else {
        Err("Vault not unlocked".to_string())
    }
}

#[tauri::command]
pub async fn delete_entry(
    id: String,
    state: State<'_, AppState>
) -> Result<(), String> {
    let mut vault = state.vault.lock().map_err(|e| e.to_string())?;
    
    if let Some(v) = vault.as_mut() {
        v.entries.retain(|e| e.id != id);
        Ok(())
    } else {
        Err("Vault not unlocked".to_string())
    }
}

#[tauri::command]
pub async fn decrypt_password(
    encrypted: Vec<u8>,
    state: State<'_, AppState>
) -> Result<String, String> {
    let vault = state.vault.lock().map_err(|e| e.to_string())?;
    
    if let Some(v) = vault.as_ref() {
        decrypt(&v.key, &encrypted)
    } else {
        Err("Vault not unlocked".to_string())
    }
}

#[tauri::command]
pub async fn decrypt_notes(
    encrypted: Vec<u8>,
    state: State<'_, AppState>
) -> Result<String, String> {
    decrypt_password(encrypted, state).await
}

#[tauri::command]
pub fn generate_password(options: PasswordOptions) -> String {
    use rand::{thread_rng, Rng};
    
    let mut chars = String::new();
    if options.use_lowercase {
        chars.push_str("abcdefghijklmnopqrstuvwxyz");
    }
    if options.use_uppercase {
        chars.push_str("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    }
    if options.use_numbers {
        chars.push_str("0123456789");
    }
    if options.use_symbols {
        chars.push_str("!@#$%^&*()_+-=[]{}|;:,.<>?");
    }
    
    if chars.is_empty() {
        return String::new();
    }
    
    let mut rng = thread_rng();
    let char_vec: Vec<char> = chars.chars().collect();
    
    (0..options.length)
        .map(|_| char_vec[rng.gen_range(0..char_vec.len())])
        .collect()
}

#[tauri::command]
pub async fn import_from_keeper(
    file_path: String,
    state: State<'_, AppState>
) -> Result<usize, String> {
    use std::fs::File;
    use std::io::BufReader;
    
    let file = File::open(&file_path).map_err(|e| e.to_string())?;
    let reader = BufReader::new(file);
    
    let mut csv_reader = csv::Reader::from_reader(reader);
    let mut imported_count = 0;
    
    let mut vault = state.vault.lock().map_err(|e| e.to_string())?;
    let vault_ref = vault.as_mut().ok_or("Vault not unlocked")?;
    
    for result in csv_reader.deserialize() {
        let record: KeeperRecord = result.map_err(|e| e.to_string())?;
        
        // Skip empty records
        if record.title.is_empty() && record.login.is_empty() {
            continue;
        }
        
        // Encrypt password and notes
        let encrypted_password = encrypt(&vault_ref.key, &record.password)?;
        let encrypted_notes = if record.notes.is_empty() {
            None
        } else {
            Some(encrypt(&vault_ref.key, &record.notes)?)
        };
        
        let entry = VaultEntry {
            id: uuid::Uuid::new_v4().to_string(),
            title: record.title,
            username: record.login,
            encrypted_password,
            url: if record.website.is_empty() { None } else { Some(record.website) },
            encrypted_notes,
            category_id: if record.folder.is_empty() { None } else { Some(record.folder) },
            totp_secret: None,
            created_at: chrono::Utc::now().timestamp(),
            modified_at: chrono::Utc::now().timestamp(),
            is_favorite: false,
        };
        
        vault_ref.entries.push(entry);
        imported_count += 1;
    }
    
    Ok(imported_count)
}

#[tauri::command]
pub async fn export_vault(
    file_path: String,
    state: State<'_, AppState>
) -> Result<(), String> {
    use std::fs::File;
    use std::io::Write;
    
    let vault = state.vault.lock().map_err(|e| e.to_string())?;
    let vault_ref = vault.as_ref().ok_or("Vault not unlocked")?;
    
    let export_data = serde_json::to_vec(&vault_ref.entries)
        .map_err(|e| e.to_string())?;
    
    let mut file = File::create(&file_path).map_err(|e| e.to_string())?;
    file.write_all(&export_data).map_err(|e| e.to_string())?;
    
    Ok(())
}

// Sync commands (placeholders)
#[tauri::command]
pub async fn start_sync_listener() -> Result<(), String> {
    Ok(())
}

#[tauri::command]
pub async fn discover_sync_peers() -> Result<Vec<String>, String> {
    Ok(vec![])
}

#[tauri::command]
pub async fn connect_to_peer(address: String) -> Result<(), String> {
    Ok(())
}

// Helper functions
fn generate_salt() -> Vec<u8> {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    (0..32).map(|_| rng.gen()).collect()
}

fn derive_key(password: &str, salt: &[u8]) -> Vec<u8> {
    use pbkdf2::pbkdf2_hmac;
    use sha2::Sha256;
    
    let mut key = vec![0u8; 32];
    pbkdf2_hmac::<Sha256>(password.as_bytes(), salt, 100_000, &mut key);
    key
}

fn create_database(key: &[u8]) -> Result<(), String> {
    // Placeholder - would create SQLCipher database
    Ok(())
}

fn encrypt(key: &[u8], plaintext: &str) -> Result<Vec<u8>, String> {
    use aes_gcm::{
        aead::{Aead, AeadCore, KeyInit},
        Aes256Gcm, Nonce, Key,
    };
    use rand::Rng;
    
    let key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(key);
    
    let nonce = Nonce::from_slice(&[0u8; 12]); // Should use random nonce in production
    let ciphertext = cipher
        .encrypt(nonce, plaintext.as_bytes())
        .map_err(|e| e.to_string())?;
    
    Ok(ciphertext)
}

fn decrypt(key: &[u8], ciphertext: &[u8]) -> Result<String, String> {
    use aes_gcm::{
        aead::{Aead, KeyInit},
        Aes256Gcm, Nonce, Key,
    };
    
    let key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(key);
    
    let nonce = Nonce::from_slice(&[0u8; 12]);
    let plaintext = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| e.to_string())?;
    
    String::from_utf8(plaintext).map_err(|e| e.to_string())
}
