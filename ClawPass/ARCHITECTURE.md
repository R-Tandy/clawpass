# ClawPass Architecture

## Overview
Cross-platform password manager with local WiFi sync. iPhone primary, Windows secondary.

## Security Model
- **Master Password** → PBKDF2 key derivation (100k iterations)
- **Database Key** → Derived from master + salt, stored in iOS Keychain / Windows DPAPI
- **Database** → SQLCipher (AES-256)
- **Biometric** → Face ID / Touch ID / Windows Hello unlocks keychain, not the database directly
- **Sync** → WebSocket with pre-shared key authentication

## Platforms

### iOS (Primary)
- **Language:** Swift
- **Framework:** SwiftUI
- **Database:** SQLite + SQLCipher
- **Biometric:** LocalAuthentication framework
- **Clipboard:** UIPasteboard with auto-clear timer

### Windows (Secondary)
- **Language:** Rust
- **Framework:** Tauri (Rust + Web frontend)
- **Database:** SQLite + SQLCipher (rusqlite bundled)
- **Biometric:** Windows Hello via WebAuthn/WinRT

## Sync Protocol
1. **Discovery:** mDNS/Bonjour broadcast on local network
2. **Pairing:** QR code exchange of public keys (one-time)
3. **Connection:** WebSocket on port 7373 (or ephemeral)
4. **Authentication:** Challenge-response with pre-shared key
5. **Sync:** Bidirectional merge with conflict resolution

## Data Model
```
Vault
├── entries: [Entry]
├── categories: [Category]
└── settings: Settings

Entry
├── id: UUID
├── title: String
├── username: String
├── password: EncryptedString
├── url: String?
├── notes: EncryptedString?
├── category: Category?
├── totp: TOTP?
├── created: Date
├── modified: Date
└── favorite: Bool

Category
├── id: UUID
├── name: String
├── icon: String
└── color: String
```

## Features (MVP)
- [ ] Master password + biometric unlock
- [ ] Add/edit/delete entries
- [ ] Password generator (configurable length, symbols)
- [ ] Categories with icons/colors
- [ ] Copy username/password to clipboard (auto-clear)
- [ ] Search/filter entries
- [ ] TOTP generation
- [ ] Secure notes
- [ ] Backup/restore encrypted vault
- [ ] Keeper CSV import

## Features (Post-MVP)
- [ ] Windows desktop app
- [ ] Local WiFi sync
- [ ] Safari extension (iOS)
- [ ] Share sheet integration
- [ ] Password breach checking (Have I Been Pwned API)
- [ ] Attachments (encrypted files)

## Project Structure
```
ClawPass/
├── ios/                    # Swift/SwiftUI app
│   ├── ClawPass/
│   │   ├── Views/
│   │   ├── Models/
│   │   ├── Services/
│   │   └── Utils/
│   └── ClawPass.xcodeproj
├── desktop/                # Tauri app
│   ├── src-tauri/
│   └── src/
├── shared/                 # Shared logic (Rust library)
│   └── src/
└── docs/
```
