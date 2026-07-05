# ClawPass Desktop - TODO (2026-06-30)

This is the **active** TODO for the Desktop (Tauri + Vue) side. The previous
copy was an old backup that had been overwritten by various "good-intentioned"
fixes and is no longer useful — it was deleted.

---

## Menu structure (current vs. desired)

### ClawPass menu (top-left application menu)
| Item | Status | Notes |
|------|--------|-------|
| About ClawPass | Working (native) | Could move About info (version, tagline) from the Preferences modal here instead. |
| Preferences... | Opens PreferencesModal | Modal exists; **the security settings don't persist yet** (autoLock, clipboard timeout) — see "Preferences" section below. |
| Quit | Working (native) | |

### Edit menu
| Item | Current state | Desired |
|------|---------------|---------|
| Undo / Redo / Cut / Copy / Paste | Native, **dead-weight** in this app | **Remove**. Mouseup outside the entry-edit window closes it, so these commands have nothing to operate on. |
| Generate Password | Fixed 2026-06-30 — was broken because the modal was mounted in VaultView instead of App.vue, so the menu's `generate_password` event had nothing to bind to. Now mounted globally in App.vue like PreferencesModal. The toolbar button (which always worked) now drives the same modal via `inject('showGenerator')`. | Keep. |
| **Select All** | Doesn't exist | Add. Selects all visible entries in the current category/search filter. |
| **Delete Selected** | Doesn't exist | Add. Bulk-deletes selected entries; prompts once for confirmation. Should respect the existing tombstone + iOS-sync pipeline (one EntryDelete per entry on the wire). |
| **Move Selected to Vault...** | Doesn't exist | Add. Opens a small picker listing `vault_<id>.db` files (uses `list_all_vaults` Tauri command already registered in `main.rs`); on confirm, moves each selected entry's row to the chosen vault's DB. Cross-vault moves are tricky — defer until core per-vault storage and the move-target are both in place. |

### Sync menu
| Item | Current state | Desired |
|------|---------------|---------|
| Start Listening | Wired 2026-06-30 to `start_sync_listener` (used to emit a freeform text string and broke the Connected indicator). | **Remove** — was never useful in production and is now redundant with the auto-start of the sync server in `main.rs setup`. |
| Discover Devices | Wired 2026-06-30 to `discover_sync_peers`. iOS already does this on its own and pushes entries directly. | **Remove** for the same reason. |
| **Device List** | Doesn't exist | Add. Shows the iPhone(s) currently connected to the desktop sync server (peer list from `sync_tcp::SyncServer` — needs to be exposed to the menu/UI; the data is already in the server's in-memory `connections` map). |
| **Pull Logs from <device>** | Doesn't exist | Add. Per-device submenu: triggers a `request_logs` message on the wire to that iOS device and surfaces them in a viewer modal. The wire message does not exist yet; would need a new `SyncMessage::RequestLogs` and `SyncMessage::LogBatch` variant. |

### Window Sync button (bottom-left of sidebar in `VaultView.vue`)
- Currently calls `startSync` which sets a status indicator and tries to invoke `start_sync_listener`.
- The sync server is already running (started in `main.rs` setup), so this button has nothing useful to do.
- **Possible replacements** (ideas — Reno wants to keep "something there" for the look):
  1. **Reveal in Sync menu** — open the new Sync > Device List submenu from this button.
  2. **Quick reconnect** — if the user thinks they lost a device, click this to trigger a re-broadcast of the desktop's announcement and re-scan peer list.
  3. **Sync stats** — show entry counts, last sync timestamp, etc. (mostly informational).

---

## iOS <-> Desktop sync wiring (already done in code)

- Desktop is a Tauri sync server (`src-tauri/src/sync_tcp.rs`), started at app launch.
- iOS discovers Desktop via mDNS and connects over TCP.
- Wire protocol covers salt exchange, request_sync / sync_response, EntryUpdate, EntryDelete, RequestTombstones / TombstoneList.
- Last sync timestamp is persisted per-vault on iOS (`lastSyncTimestamp_<vaultId>` UserDefaults key).
- Per-vault path convention: `vault_<id>.db`, `salt_<id>.dat`, `tombstones_<id>.dat`, `categories_<id>.dat`. Legacy un-suffixed `vault.db` is preserved and not touched by v3+ code paths.
- Discriminated by `vault_id` on every EntryUpdate / EntryDelete so a vault-A update can't pollute vault-B's in-memory list.

---

## Preferences modal (open, needs settings persistence)

Reactive settings exist in `PreferencesModal.vue`:
- `autoLockMinutes` (1 / 5 / 15 / 30 / 0=Never) — **does not actually lock the vault** after the chosen interval.
- `clearClipboard` + `clipboardTimeoutSeconds` — VaultView hard-codes 30s in its `copyToClipboard` timeout; the modal setting is ignored.
- The "Start Sync" button works (calls `start_sync_listener`).

To make these real:
1. Add a `prefs` table to the per-vault DB (or a global `~/.clawpass/prefs.json`).
2. Tauri commands: `get_prefs()`, `set_prefs(autolock_minutes, clipboard_timeout_seconds)`.
3. Wire `VaultView.copyToClipboard` to use the `clipboardTimeoutSeconds` from the store.
4. Add an inactivity timer in `VaultView` (or a service) that calls `lock()` after `autoLockMinutes` of no input — gated on `autoLockMinutes > 0`.

---

## TOTP

Field exists on `VaultEntry` and the iOS app, but no logic to:
- Generate the current code from a stored secret.
- Render the rolling countdown UI.
- Copy code to clipboard with auto-clear.

Defer until core sync is rock-solid.

---

## Build & run reminders

- Desktop `src-tauri/` is **gitignored** — local file changes don't get committed; Reno must `cargo build` after edits.
- iOS code IS in git. Always `git status` and `git log` before pushing to make sure the iOS-side commits are clean.
- Sync menu wiring fix: commit `286d572` (iOS v2 cleanup) is on `origin/main`. Desktop fix is local-only and needs a rebuild.

---

## Quick reference: things that DON'T need work

- Lock button UX (fixed 2026-06-30): `await vault.lock()` before `router.push('/')`.
- Vault switch empty-state (fixed 2026-06-30): `selectedCategory` and `searchQuery` reset in `lock()`.
- Duplicate `vault-updated` listener (fixed 2026-06-30): `setupSyncListener` tears down previous unlisten before re-registering.
- Generate Password menu (fixed 2026-06-30): modal now mounted globally in App.vue, VaultView uses `inject('showGenerator')`.
- Sync > Start Listening / Discover Devices (fixed 2026-06-30): menu now invokes real Tauri commands instead of emitting text strings.
- iOS v2 file references (fixed commit `286d572`): zero references to `vault.db` / `salt.dat` / `tombstones.dat` / `categories.dat` / `salt_.dat` as strings in iOS code. `nuclearReset()` only wipes `vault_<id>.db`.
