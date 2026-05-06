# MEMORY.md - Long-term Memory

## About Reno
- Building ClawPass - a password manager with Tauri (desktop) and Swift (iOS)
- Learning Japanese
- Appreciates dark adult humor
- Token-conscious with Ollama API usage
- Has Nvidia developer account for potential fallback AI service
- Located in Waco, TX (America/Chicago timezone)

## ClawPass Architecture
- **Desktop**: Tauri (Rust backend + Vue frontend) at `C:\Users\Reno\Documents\password-manager\ClawPass\desktop`
  - sync_tcp.rs: TCP sync server on port 7878, length-prefixed JSON protocol
  - Vault storage: `~/.clawpass/vault.dat`, `~/.clawpass/salt.dat`, `~/.clawpass/categories.dat`
- **iOS**: Swift app at `C:\Users\Reno\Documents\password-manager\ClawPass\` (NOT in ios/ subfolder)
  - ios/ folder only contains `.build` artifacts from Tuist
  - Actual source: `ClawPass/*.swift`, `ClawPass/Views/*.swift`, `ClawPass/Services/*.swift`
- **Sync**: Local TCP sync between desktop/iOS (port 7878)
  - Protocol: length-prefixed JSON (4-byte BE length + JSON)
  - Messages: Ping, SyncRequest, SyncResponse, EntryUpdate, EntryDelete
  - Desktop TCP listener running on port 7878 (pid 55924, clawpass-tauri)
  - iOS uses Network framework for TCP + Bonjour discovery

### Key Backend Details
- Backend expects plaintext passwords/notes (encrypts internally with AES-GCM)
- Categories stored as JSON in `categories.dat`
- Vault uses `NewVaultEntryInput` struct for add/update operations

## Project Status (2026-04-22)
### Desktop App - Mostly Working
- ✅ Master password verification
- ✅ Vault creation/unlock
- ✅ Add/view entries
- ✅ Categories (user-managed)
- ✅ Favorites filtering
- ✅ Password generator
- ⚠️ Edit entry - needs testing
- ⚠️ Delete entry - needs testing
- ⚠️ Import/Export - UI exists but not functional

### iOS App
- Pushed to GitHub, GitHub Actions building
- Synced with desktop via local TCP

### Technical Debt
- Many unused imports/variables (Rust warnings)
- `create_database` function unused
- Sync UI not fully connected

## Skills & Tools
- VS Code for Rust/Vue work
- GitHub for iOS CI/CD
- vite + tauri dev server for desktop development

## Session Patterns
- Webchat via openclaw-control-ui for daily work
- tui via openclaw-tui for quick tests
- MiniMax-M2.7:cloud model works well for this work - efficient and effective