# ClawPass Desktop - TODO (2026-07-07)

This is the **active** TODO for the Desktop (Tauri + Vue) side.

---

## ✅ Done 2026-07-07: Preferences persistence
- `Prefs` struct + `get_prefs` / `set_prefs` Tauri commands.
- `prefs.json` in `~/.clawpass/` (global, not per-vault).
- Vue store: `prefs` ref + `loadPrefs()` + `savePrefs()`.
- `PreferencesModal.vue`: loads on mount, deep-watches and saves on
  every change.
- `VaultView.vue`:
  - `copyToClipboard` respects `prefs.clear_clipboard` and
    `prefs.clipboard_timeout_seconds` (was hard-coded 30s).
  - Auto-lock timer: 5 activity events (mousemove/keydown/click/
    scroll/touchstart) reset a `setTimeout(prefs.auto_lock_minutes *
    60_000)`. Fires `lock()` on expiry. `0` = never.
  - `watch(prefs.auto_lock_minutes)` re-arms the timer on setting
    change.
  - `onUnmounted` cleans up listeners and clears the pending timer
    (critical for vault-switching within the same window session).
- `App.vue` `onMounted`: `vault.loadPrefs()` once at app start.
- `cargo check` clean. `npm run build` (vue-tsc + vite) clean.
- ⚠ **Desktop is gitignored — this work is local-only. Reno must
  `cargo build && cargo run` to apply.**

---

## Menu structure (current vs. desired)

### ClawPass menu (top-left application menu)
| Item | Status | Notes |
|------|--------|-------|
| About ClawPass | Working (native) | Could move About info (version, tagline) from the Preferences modal here instead. |
| Preferences... | Opens PreferencesModal | Modal exists; **the security settings don't persist yet** (autoLock, clipboard timeout) — see "Preferences" section below. |
| Quit | Working (native) | |

### Edit menu

✅ **DONE 2026-07-07** (local — `desktop/` is gitignored; Reno must rebuild):
- Added `Select All` (Ctrl+A) — selects every entry in the current filter.
- Added `Delete Selected` (Del) — bulk delete via the existing per-row `delete_entry` path; one tombstone per entry, one `EntryDelete` per entry on the wire to keep iOS in sync.
- Added `Lock Now` (Ctrl+L) — quick way to lock from the menu.
- Kept `Generate Password` (Ctrl+G) at the bottom under a separator.
- `Move Selected to Vault...` still deferred — cross-vault moves are a design problem and not in the way of anything else. The `list_all_vaults` Tauri command is already registered when we get to it.
- No Undo/Redo/Cut/Copy/Paste were ever added to the menu (Tauri menus only contain items you explicitly add; the OS-provided Edit menu for text inputs only shows up inside an open EntryEdit modal if we add it there). So there's nothing to remove.

### Sync menu

✅ **DONE 2026-07-07** (local — same caveat as Edit):
- Added `Sync Now` (Ctrl+R) — emits a `sync_now` event; the Vue side calls `trigger_remote_sync` via `invoke`. **Known limitation:** `trigger_remote_sync` is a stub that returns "Remote sync trigger requires active session handle integration". The error surfaces via the existing `sync-status` event channel, so the menu item exists and the error is visible in the header indicator. Wiring the actual server requires storing the `SyncServer` handle in `AppState` — small refactor, deferred to the QR/Scanner work since they're the same family of "surface server state to UI" work.
- `Start Listening` and `Discover Devices` were never in the menu (see note in Edit menu about Tauri not providing a default Edit menu). So nothing to remove here either.
- `Device List` and `Pull Logs from <device>` still deferred — both require the same `SyncServer`-in-AppState refactor.

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

## Preferences modal

✅ **DONE 2026-07-07** — see "Done 2026-07-07" at the top. Settings now
persist to `prefs.json` and auto-lock + clipboard-clear work as configured.
Open question for next session: surface a small "Vault auto-locked" toast
when the timer fires? Currently the user just sees the lock screen. Defer.

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
