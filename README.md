# ClawPass iOS

Secure password manager for iOS with local WiFi sync.

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Dependencies

- SQLCipher (encrypted SQLite)
- CryptoKit (Apple's crypto library)
- LocalAuthentication (Face ID / Touch ID)

## Setup

1. Install SQLCipher:
   ```bash
   brew install sqlcipher
   ```

2. Open `ClawPass.xcodeproj` in Xcode

3. Build and run on device or simulator

## Features

- AES-256 encrypted vault (SQLCipher)
- Master password + Face ID / Touch ID unlock
- Password generator with customizable rules
- Categories with icons and colors
- Copy-to-clipboard with auto-clear (30 sec)
- Secure notes
- Local WiFi sync between devices
- Import from Keeper CSV

## Security

- PBKDF2 key derivation (100k iterations)
- Database encrypted with AES-256
- Keys stored in iOS Secure Enclave (Keychain)
- Biometric unlock via LocalAuthentication
- Auto-clear clipboard after 30 seconds

## Sync Protocol

- mDNS/Bonjour discovery on local network
- WebSocket connection with pre-shared key auth
- Bidirectional merge with conflict resolution
- Port 7373 (configurable)

## Project Structure

```
ClawPass/
├── ClawPassApp.swift       # App entry point
├── Models/
│   └── VaultEntry.swift    # Data models
├── Views/
│   ├── ContentView.swift   # Main view
│   ├── UnlockView.swift    # Authentication
│   ├── VaultView.swift     # Password list
│   ├── AddEntryView.swift  # New entry form
│   └── EntryDetailView.swift # Entry details
└── Services/
    ├── CryptoService.swift # Encryption/decryption
    ├── VaultManager.swift  # Database operations
    └── SyncService.swift   # WiFi sync
```

## License

MIT
