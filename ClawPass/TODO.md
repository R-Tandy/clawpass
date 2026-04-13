# ClawPass Desktop - Status and TODO

## Current Status (2026-04-13)

### Fixed ✅
1. **Vault persistence path** - Now uses `~/.clawpass/` instead of current directory
2. **Password encryption** - Backend encrypts passwords/notes with AES-GCM
3. **Auto-save on add/update/delete** - Entries save to disk automatically
4. **Master password verification** - Real verification against saved salt/encrypted vault
5. **Nonce generation** - Random 12-byte nonces for vault encryption (not static zeros)
6. **Menu event handlers** - `show_preferences` and `generate_password` now work via App.vue injection
7. **Import/Export** - Implemented with Tauri dialog API
8. **Categories persistence** - Full CRUD commands in Rust backend
9. **Category UI** - Sidebar displays categories with colors and counts
10. **Add Category modal** - Full UI with icon/color picker
11. **Add Entry category selector** - Dropdown to select category when adding entries

### Critical Bug Fixed (2026-04-13)
- **`save_vault_to_disk` was using `VAULT_FILE` constant instead of `get_vault_path()`**
  - This caused saves to write to the wrong directory
  - Fixed to use `fs::write(get_vault_path()?, &encrypted)`

### Fixed (2026-04-13) - Menu Handlers
- App.vue now provides `showPreferences` and `showGenerator` refs to child components
- VaultView.vue injects these and watches for menu-triggered changes
- Import/Export now use `@tauri-apps/api/dialog` for file picking

## Remaining Issues 🔧

### High Priority (Actually Broken)
1. **~~Categories not persisted~~** - ✅ FIXED

### Medium Priority (Stubs)
2. **Sync functionality** - iOS app not built yet, so this is expected
   - `sync.rs` has empty implementations
   - Menu shows alert: "iOS app not yet built"

3. **TOTP support** - Field exists but no logic

### Low Priority
4. **Preferences page** - Menu works but no actual UI
5. **Windows Hello** - Has dependency but no implementation
6. **Unused code warnings** - `VaultManager`, `create_database`, etc.

## Testing Checklist

After the save_vault_to_disk fix:
- [ ] Create vault with master password
- [ ] Add entry with password
- [ ] Verify entry appears in list
- [ ] Close app completely
- [ ] Reopen app
- [ ] Unlock vault
- [ ] Verify entry still exists
- [ ] Edit entry
- [ ] Delete entry
- [ ] Import from Keeper CSV
- [ ] Export vault

## File Locations

- **Vault data**: `C:\Users\Reno\.clawpass\vault.dat`
- **Salt**: `C:\Users\Reno\.clawpass\salt.dat`
- **Source**: `C:\Users\Reno\Documents\password-manager\ClawPass\desktop`
