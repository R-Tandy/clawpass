# ClawPass Desktop

Secure password manager for Windows (and cross-platform via Tauri).

## Features

- AES-256 encryption via SQLCipher
- Master password + Windows Hello (biometric) unlock
- Password generator with customizable rules
- Categories and favorites
- Auto-clear clipboard after 30 seconds
- Import from Keeper CSV
- Local WiFi sync with iOS app
- Dark theme

## Prerequisites

- Rust (latest stable)
- Node.js 18+
- npm or yarn

## Setup

```bash
# Install Tauri CLI
npm install -g @tauri-apps/cli

# Install dependencies
npm install

# Run in dev mode
npm run tauri dev

# Build for production
npm run tauri build
```

## Import from Keeper

1. Export your Keeper passwords to CSV
2. In ClawPass, click Import button
3. Select the CSV file
4. Entries will be imported with encrypted passwords

## Sync with iOS

1. On iOS: Go to Sync section, enable "Sync Server"
2. On Desktop: Click "Discover Devices" in Sync menu
3. Select your iOS device
4. Authenticate with your vault password
5. Changes sync bidirectionally

## Security

- PBKDF2 key derivation (100k iterations)
- AES-256-GCM encryption
- Keys never stored in plaintext
- Biometric unlock via Windows Hello
- Clipboard auto-clear
- No cloud storage - local only

## Project Structure

```
desktop/
├── src/                    # Vue frontend
│   ├── components/         # UI components
│   ├── views/              # Page views
│   ├── stores/             # Pinia stores
│   └── router/             # Vue Router
├── src-tauri/              # Rust backend
│   └── src/
│       ├── main.rs         # Entry point
│       ├── commands.rs     # Tauri commands
│       ├── vault.rs        # Vault operations
│       └── sync.rs         # WiFi sync
└── package.json
```

## License

MIT
