// MARK: - VERSION_SYNC_2026_06_27_CLEAN_REWRITE_WITH_API
import Foundation
import SQLite3
import LocalAuthentication
import CryptoKit

/// Tells SQLite to copy bound strings/blobs instead of keeping the caller's pointer.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// NULL-safe column read (a NULL column would otherwise crash String(cString:)).
func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
    guard let c = sqlite3_column_text(stmt, index) else { return "" }
    return String(cString: c)
}

enum VaultError: Error {
    case notInitialized
    case alreadyInitialized
    case invalidPassword
    case databaseError(String)
    case entryNotFound
    case keychainError(OSStatus)
    case decryptionFailed
    /// Refused `unlock` for a vault that doesn't exist on disk yet. Caller
    /// should route the user to `setupVault` (the 'Retrieve Vault from
    /// Server' flow) instead.
    case vaultNotFound(String)
    /// The vault database exists but its encryption salt is not on this device.
    case saltMissing
}

extension Notification.Name {
    static let vaultDataChanged = Notification.Name("vaultDataChanged")
}

class VaultManager: ObservableObject, SyncServiceDelegate {
    static let shared = VaultManager()
    
    @Published var vaultName: String = "My Vault"
    @Published private(set) var isUnlocked = false
    @Published private(set) var isReady = false
    @Published var entries: [VaultEntry] = []
    @Published private(set) var categories: [Category] = []
    @Published var syncStatus: String = ""
    @Published private(set) var vaultSyncStatus: String = ""
    @Published var keyStatus: String = "Unknown"
    @Published var debugSaltHex: String = "Unknown"
    @Published var debugKeyHash: String = "Unknown"
    @Published var debugCanaryStatus: String = "Not Checked"
    @Published var saltReady = false
    @Published var isFirstPopulationPending = false
    @Published var lastSyncUpdate: Date = Date()
    @Published var lastHandshakeError: String? = nil

    
    private var db: OpaquePointer?
    private var encryptionKey: SymmetricKey?
    private let cryptoService = CryptoService.shared
    private var syncService = SyncService.shared
    private var pendingSetupPassword: String?
    /// Master password held in memory only while unlocked, so local entries can be
    /// re-keyed if the server's salt differs from the one this device generated.
    private var sessionPassword: String?
    private var retrieveWatchdog: DispatchWorkItem?
    /// Entries sent to the server this session: id -> modified time (ms) at send.
    /// Marked synced once the server answers the follow-up sync request.
    private var inFlight: [String: Int64] = [:]
    /// True while applying server-sent sync responses. Suppresses the
    /// sync-push in saveEntry/deleteEntry so we don't echo back entries
    /// the server just sent us. Set/cleared in the SyncServiceDelegate
    /// handlers below.
    private var isApplyingRemoteUpdate = false
    
    init() {
        SyncService.shared.delegate = self
    }
    
    // MARK: - Database Core
    
    /// Per-vault DB filename. Matches Desktop's `vault_{id}.db` convention.
    /// v3+ never falls back to the un-suffixed `vault.db` (LEGACY-V2, do not
    /// touch). If `vaultId` is empty we return an empty string — every caller
    /// that uses this also gates on `!vaultId.isEmpty`, so the empty string
    /// is a safe "no path" sentinel rather than a fallback to legacy state.
    private func currentVaultDbFilename() -> String {
        let vid = SyncService.shared.vaultId
        if vid.isEmpty {
            return ""
        }
        return "vault_\(vid).db"
    }
    
    /// Absolute path to the DB file that *should* currently be open, given the
    /// SyncService vaultId. Callers use this to open/initialize against the
    /// correct per-vault file.
    /// Documents/Vaultinator. A pre-rename Documents/Layer folder is moved over once so existing vaults keep working.
    static var vaultDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let new = docs.appendingPathComponent("Vaultinator")
        let old = docs.appendingPathComponent("Layer")
        let fm = FileManager.default
        if !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) {
            do { try fm.moveItem(at: old, to: new) } catch { return old }
        }
        return new
    }

    private func currentVaultDbPath() -> String {
        let vaultDir = VaultManager.vaultDirectory
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        return vaultDir.appendingPathComponent(currentVaultDbFilename()).path
    }
    
    private func closeDatabase() {
        if let handle = db { sqlite3_close(handle) }
        db = nil
    }

    private func openDatabase(path: String) -> Bool {
        closeDatabase()
        if sqlite3_open(path, &db) != SQLITE_OK {
            let err = db == nil ? "Unknown error" : String(cString: sqlite3_errmsg(db))
            print("[SQLite3] Error opening database: \(err)")
            return false
        }
        return true
    }
    
    private func createTables() {
        guard let db = db else { return }

        let createEntries = "CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, title TEXT, username TEXT, encrypted_password BLOB, url TEXT, encrypted_notes BLOB, category_id TEXT, totp_secret TEXT, created_at REAL, modified_at REAL, is_favorite INTEGER, sync_status TEXT);"
        let createCategories = "CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT, icon TEXT, color TEXT);"
        let createSettings = "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);"
        // Offline-delete outbox. Each row is an entry id that the user
        // deleted locally but that the server hasn't acknowledged yet
        // (because we were offline, or the handshake hadn't completed,
        // or we crashed between send and ACK). flushOutbox() reads this
        // table, sends an EntryDelete per row, then removes the row
        // optimistically. didReceiveTombstones() also removes a row if
        // the server happens to echo the id back (covers the case where
        // the same entry was deleted on both sides). The table lives
        // in the same per-vault .db file as entries. deleteLocalVault() removes
        // every per-vault `vault_<id>.db` in the ClawPass directory (NOT
        // the un-suffixed legacy `vault.db`), which wipes the outbox table
        // automatically with no extra code.
        let createTombstones = "CREATE TABLE IF NOT EXISTS pending_tombstones (id TEXT PRIMARY KEY, created_at REAL);"

        let tables = [createEntries, createCategories, createSettings, createTombstones]
        for tableSql in tables {
            var errMsg: UnsafeMutablePointer<Int8>? = nil
            if sqlite3_exec(db, tableSql, nil, nil, &errMsg) != SQLITE_OK {
                let error = errMsg == nil ? "Unknown error" : String(cString: errMsg!)
                print("[SQLite3] Error creating table: \(error)")
                sqlite3_free(errMsg)
            }
        }
    }
    
    private func loadData() {
        guard let db = db else { return }
        var loadedEntries: [VaultEntry] = []
        
        let query = "SELECT id, title, username, encrypted_password, url, encrypted_notes, category_id, totp_secret, created_at, modified_at, is_favorite FROM entries;"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idStr = columnText(stmt, 0)
                let title = columnText(stmt, 1)
                let username = columnText(stmt, 2)
                
                var entry = VaultEntry(id: UUID(uuidString: idStr) ?? UUID(), title: title, username: username, password: "", url: nil, notes: nil, categoryID: nil, totpSecret: nil, isFavorite: false)
                
                if let data = sqlite3_column_blob(stmt, 3) {
                    let len = sqlite3_column_bytes(stmt, 3)
                    entry.encryptedPassword = Data(bytes: data, count: Int(len))
                }
                
                if let urlPtr = sqlite3_column_text(stmt, 4) {
                    entry.url = String(cString: urlPtr)
                }
                
                if let data = sqlite3_column_blob(stmt, 5) {
                    let len = sqlite3_column_bytes(stmt, 5)
                    entry.encryptedNotes = Data(bytes: data, count: Int(len))
                }
                
                if let catPtr = sqlite3_column_text(stmt, 6) {
                    entry.categoryID = UUID(uuidString: String(cString: catPtr))
                }
                
                if let totpPtr = sqlite3_column_text(stmt, 7) {
                    entry.totpSecret = String(cString: totpPtr)
                }
                
                let createdTs = sqlite3_column_double(stmt, 8)
                let modifiedTs = sqlite3_column_double(stmt, 9)
                if createdTs > 0 { entry.createdAt = Date(timeIntervalSince1970: createdTs) }
                if modifiedTs > 0 { entry.modifiedAt = Date(timeIntervalSince1970: modifiedTs) }
                entry.isFavorite = sqlite3_column_int(stmt, 10) != 0
                loadedEntries.append(entry)
            }
        }
        sqlite3_finalize(stmt)
        
        var loadedCats: [Category] = []
        let catQuery = "SELECT id, name, icon, color FROM categories;"
        var catStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, catQuery, -1, &catStmt, nil) == SQLITE_OK {
            while sqlite3_step(catStmt) == SQLITE_ROW {
                let idStr = columnText(catStmt, 0)
                let name = columnText(catStmt, 1)
                let icon = columnText(catStmt, 2)
                let color = columnText(catStmt, 3)
                loadedCats.append(Category(id: UUID(uuidString: idStr) ?? UUID(), name: name, icon: icon, color: color))
            }
        }
        sqlite3_finalize(catStmt)

        let favId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        if !loadedCats.contains(where: { $0.id == favId }) {
            loadedCats.append(Category(id: favId, name: "Favorites", icon: "star.fill", color: "#FFD700"))
        }
        
        DispatchQueue.main.async {
            self.entries = loadedEntries
            self.categories = loadedCats
            self.isFirstPopulationPending = false
            if self.isUnlocked { self.isReady = true }
            self.lastSyncUpdate = Date()
            self.objectWillChange.send()
        }
    }
    
    /// Persists an entry. Local edits (`fromRemote == false`) are stamped with the
    /// current time and flagged `pending` until pushed to the server. Entries applied
    /// from the server keep the sender's timestamps and are flagged `synced`, so
    /// "newest wins" holds in both directions.
    func saveEntry(_ source: VaultEntry, fromRemote: Bool = false, keepTimestamp: Bool = false) {
        guard let db = db else { return }
        var entry = source
        if !fromRemote && !keepTimestamp { entry.modifiedAt = Date() }
        
        let insert = "INSERT OR REPLACE INTO entries (id, title, username, encrypted_password, url, encrypted_notes, category_id, totp_secret, created_at, modified_at, is_favorite, sync_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, entry.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, entry.username, -1, SQLITE_TRANSIENT)
            
            if !entry.encryptedPassword.isEmpty {
                _ = entry.encryptedPassword.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, 4, bytes.baseAddress, Int32(entry.encryptedPassword.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            
            if let url = entry.url {
                sqlite3_bind_text(stmt, 5, url, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            
            if let notes = entry.encryptedNotes, !notes.isEmpty {
                _ = notes.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, 6, bytes.baseAddress, Int32(notes.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            
            if let catID = entry.categoryID {
                sqlite3_bind_text(stmt, 7, catID.uuidString, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            
            if let totp = entry.totpSecret {
                sqlite3_bind_text(stmt, 8, totp, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            
            sqlite3_bind_double(stmt, 9, entry.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 10, entry.modifiedAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 11, entry.isFavorite ? 1 : 0)
            sqlite3_bind_text(stmt, 12, (fromRemote ? "synced" : "pending"), -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[SQLite3] Failed to save entry: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(stmt)
        // Update the in-memory array so the UI sees the change immediately.
        // Without this, views stay on stale data until the next loadData() call.
        DispatchQueue.main.async {
            if let idx = self.entries.firstIndex(where: { $0.id == entry.id }) {
                self.entries[idx] = entry
            } else {
                self.entries.append(entry)
            }
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .vaultDataChanged, object: nil)
        }
        // Push the change to the Desktop sync server. Suppressed while we're
        // applying a server-sent sync response (the echo-back would be a loop).
        // Also no-op while the handshake hasn't completed (sendEntryUpdate
        // itself guards on that and logs a notice).
        if !fromRemote && !isApplyingRemoteUpdate {
            SyncService.shared.sendEntryUpdate(entry: entry)
        }
    }

    /// Called by SyncService when an entry update was written to the socket.
    func noteEntrySent(_ entry: VaultEntry) {
        let ms = Int64(entry.modifiedAt.timeIntervalSince1970 * 1000)
        DispatchQueue.main.async { self.inFlight[entry.id.uuidString.uppercased()] = ms }
    }

    /// The server answered a sync request, so everything sent before it was processed
    /// (TCP preserves order). Flip those entries from pending to synced unless they
    /// were edited again after being sent.
    func syncServiceDidCompleteSync(_ service: SyncService) {
        DispatchQueue.main.async {
            guard let db = self.db, !self.inFlight.isEmpty else { return }
            var stmt: OpaquePointer?
            let sql = "UPDATE entries SET sync_status = 'synced' WHERE upper(id) = ? AND CAST(modified_at * 1000 AS INTEGER) <= ?;"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for (id, ms) in self.inFlight {
                    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(stmt, 2, ms + 1)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
            sqlite3_finalize(stmt)
            self.inFlight.removeAll()
        }
    }

    /// Flags entries as delivered to the server so they are not re-sent on reconnect.
    func markEntriesSynced(ids: [String]) {
        guard let db = db, !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "UPDATE entries SET sync_status = 'synced' WHERE id IN (\(placeholders));"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (i, id) in ids.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), id, -1, SQLITE_TRANSIENT)
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// When (ms since epoch) a pending local delete was made, or nil if not in the outbox.
    func tombstoneMillis(id: String) -> Int64? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        var result: Int64? = nil
        if sqlite3_prepare_v2(db, "SELECT created_at FROM pending_tombstones WHERE lower(id) = lower(?);", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = Int64(sqlite3_column_double(stmt, 0) * 1000)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    /// Modified time (ms since epoch) of the local copy of an entry, or nil if absent.
    private func localModifiedMillis(id: String) -> Int64? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        var result: Int64? = nil
        if sqlite3_prepare_v2(db, "SELECT modified_at FROM entries WHERE lower(id) = lower(?);", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = Int64(sqlite3_column_double(stmt, 0) * 1000)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    private func isPendingTombstone(_ id: String) -> Bool {
        guard let db = db else { return false }
        var stmt: OpaquePointer?
        var found = false
        if sqlite3_prepare_v2(db, "SELECT 1 FROM pending_tombstones WHERE lower(id) = lower(?);", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            found = sqlite3_step(stmt) == SQLITE_ROW
        }
        sqlite3_finalize(stmt)
        return found
    }

    func deleteEntry(id: UUID) {
        guard let db = db else { return }
        // Case-insensitive match: iOS sends/receives ids via the wire
        // in iOS's canonical UUID().uuidString (always uppercase), but
        // legacy rows may have been persisted in different cases by
        // older code paths. Comparing lower(id) = lower(?) catches
        // both forms without false negatives.
        let del = "DELETE FROM entries WHERE lower(id) = lower(?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, del, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[SQLite3] Failed to delete entry: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(stmt)
        // Same reasoning as saveEntry: update the array on the main thread.
        let idString = id.uuidString
        DispatchQueue.main.async {
            self.entries.removeAll { $0.id == id }
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .vaultDataChanged, object: nil)
        }
        // Always write the tombstone to the durable outbox BEFORE
        // attempting the network send. This is the offline-DELETE fix:
        // sendEntryDelete used to be fire-and-forget and silently
        // dropped the packet when handshakeCompleted was false (the
        // user was offline, or the iOS-side handshake hadn't finished
        // yet). On reconnect, flushOutbox() would read this table and
        // re-send. The row stays in the outbox until either
        // markTombstonesSent() runs (online-send path) or
        // didReceiveTombstones() sees the id come back from the server
        // (dedup path). Idempotent INSERT OR IGNORE means re-deleting
        // the same entry (e.g. from a tombstone echo) is a no-op.
        recordTombstone(id: idString)
        // Push the deletion to the Desktop sync server. Suppressed while
        // we're applying a server-sent sync response (tombstone echo-back
        // would be a loop). Tombstones themselves arrive via raw SQL in
        // didReceiveTombstones, not through this function, so the guard
        // is belt-and-braces.
        if !isApplyingRemoteUpdate {
            SyncService.shared.sendEntryDelete(entryId: idString)
        }
    }
    
    // MARK: - Vault Logic
    
    func getEncryptionKey() -> SymmetricKey? {
        return encryptionKey
    }
    
    /// Creates a brand-new vault entirely on this device. No server is needed; sync
    /// links up later if a desktop vault with the same master password exists.
    func createVault(password: String) throws {
        let derivedVaultId = cryptoService.deriveVaultId(password: password)
        if vaultFileExists(forVaultId: derivedVaultId) { throw VaultError.alreadyInitialized }
        SyncService.shared.setVaultId(derivedVaultId)
        let salt = Data.randomBytes(count: 32)
        try storeSalt(salt, for: derivedVaultId)
        try initializeWithSalt(password: password, salt: salt)
        // Remember to register this new vault with the computer on the first connection.
        if let key = encryptionKey {
            let verify = cryptoService.sha256(key.withUnsafeBytes { Data($0) })
            UserDefaults.standard.set(WireCrypto.hex(verify), forKey: "pendingRegister_\(derivedVaultId)")
        }
        sessionPassword = password
        saveBiometricPasswordIfEnabled(password)
        lastHandshakeError = nil
        beginBackgroundSync()
    }

    /// Recovers an existing vault from the desktop. Shows the "connecting" screen until
    /// the salt arrives, the server refuses, the user cancels, or the watchdog expires.
    func retrieveVault(password: String) {
        let derivedVaultId = cryptoService.deriveVaultId(password: password)
        SyncService.shared.disconnect()
        SyncService.shared.setVaultId(derivedVaultId)
        SyncService.shared.startUDPListener()

        lastHandshakeError = nil
        isFirstPopulationPending = true
        pendingSetupPassword = password
        SyncService.shared.triggerHandshake()

        retrieveWatchdog?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self = self, self.isFirstPopulationPending else { return }
            self.failRetrieve("Could not reach your computer. Open the desktop app on the same Wi-Fi network, or connect manually from Settings.")
        }
        retrieveWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: watchdog)
    }

    /// Abandons an in-progress retrieve (Cancel button, timeout, or server refusal).
    func cancelRetrieve() { failRetrieve(nil) }

    private func failRetrieve(_ message: String?) {
        retrieveWatchdog?.cancel()
        retrieveWatchdog = nil
        pendingSetupPassword = nil
        isFirstPopulationPending = false
        if let message = message { lastHandshakeError = message }
        SyncService.shared.disconnect()
    }

    /// Connects (best effort) and runs the sync pipeline for an unlocked vault.
    private func beginBackgroundSync() {
        SyncService.shared.disconnect()
        SyncService.shared.startUDPListener()
        SyncService.shared.startDiscovery()
        SyncService.shared.triggerHandshake()
    }
    
    func initializeWithSalt(password: String, salt: Data) throws {
        let dbPath = currentVaultDbPath()
        
        guard openDatabase(path: dbPath) else {
            throw VaultError.databaseError("Could not open database at \(dbPath)")
        }
        createTables()
        
        self.encryptionKey = try cryptoService.deriveKey(from: password, salt: salt)
        self.isUnlocked = true
        self.isReady = true
        loadData()
        // Pull the vault name from the per-vault settings table so the
        // name persists across app restarts and vault switches. Without
        // this call, `vaultName` stays at the in-memory default ("My Vault"
        // or whatever was set during a previous session) and the
        // navigation title in VaultView is wrong until the user manually
        // edits the name through SettingsView.
        // ensureVaultNamePersisted (not loadVaultName) so a fresh vault
        // with no persisted name gets a derived default written to disk
        // on first init. See the method for the rationale.
        ensureVaultNamePersisted()
    }
    
    func unlock(with password: String, saltOverride: Data? = nil, skipHandshake: Bool = false, forceLock: Bool = false) throws {
        // Always derive the vaultId from the password before deciding which
        // .db file to open. Without this, an unlock after app restart (or
        // after switching to a different vault password) opens the
        // SyncService.vaultId-nominated file, NOT the file that corresponds
        // to the password we just typed. Result: we load the previous
        // session's entries instead of the vault the user asked for.
        let derivedVaultId = cryptoService.deriveVaultId(password: password)
        SyncService.shared.setVaultId(derivedVaultId)

        // Refuse to "unlock" a vault that doesn't exist on this device yet.
        // The previous behavior silently created an empty vault_<id>.db,
        // derived a key from an empty salt (no keychain entry existed),
        // showed the user a vault view with zero entries, and then the
        // async handshake raced the entry read. Resulting trace showed
        // iOS requesting B's vault_id mid-stream on a connection that
        // was still active for A, with the server forcibly closing the
        // socket (os error 10054) and iOS reporting an absurd packet
        // length (~2 GB) on the next sync attempt.
        //
        // The right UX is to refuse here, surface a clear error to the
        // caller (UnlockView), and tell the user to tap
        // 'Retrieve Vault from Server' which goes through the full
        // Handshake -> Ack -> Salt -> Sync pipeline.
        if !vaultFileExists(forVaultId: derivedVaultId) {
            print("[VaultManager] unlock rejected: no vault_<id>.db for derived id \(derivedVaultId.prefix(12))...")
            throw VaultError.vaultNotFound(derivedVaultId)
        }

        let saltData = saltOverride ?? Data()
        // When the caller didn't supply a salt (first unlock with no prior
        // server contact), use what we already have in the keychain for this
        // vaultId, falling back to empty salt only if none exists.
        let effectiveSalt: Data
        if saltOverride != nil {
            effectiveSalt = saltData
        } else if let stored = try? retrieveSalt(for: derivedVaultId) {
            effectiveSalt = stored
        } else {
            // The vault file exists but its salt is gone (e.g. keychain reset). Opening it
            // with an empty salt would silently produce a useless key, so ask the caller to
            // restore the vault from the desktop instead, which re-adopts the real salt.
            throw VaultError.saltMissing
        }
        try initializeWithSalt(password: password, salt: effectiveSalt)
        sessionPassword = password
        saveBiometricPasswordIfEnabled(password)
        print("[VaultManager] unlock: init OK, entries.count=\(entries.count), db!=nil=\(db != nil)")

        // Clear the key-status banner. Previously only the salt-receive
        // path (syncServiceDidReceiveSalt) cleared this, so users
        // unlocking from a local DB while the server was offline kept
        // seeing the "Key Status: Unknown" banner even though their key
        // was valid and entries had loaded fine.
        DispatchQueue.main.async { self.keyStatus = "" }

        // After a fresh unlock, kick off the sync pipeline so the
        // 'Syncing your vault...' overlay clears. Previously only
        // syncServiceDidReceiveSalt did this, leaving unlock-the-existing-
        // vault flows stuck on the overlay until the user manually opened
        // SyncView and pressed 'Sync now'.
        //
        // Order matters: triggerHandshake() is the *only* way the connection
        // reaches handshakeCompleted=true; without it the pipeline's
        // requestTombstones/Categories/Sync calls silently bail, the
        // syncResponse never arrives, firstSyncComplete stays false, and the
        // overlay shows forever.
        if !skipHandshake {
            // Tear down any live connection from a previous vault BEFORE
            // starting a new handshake. The connection model is hub-and-spoke:
            // a connection carries exactly one vaultId for its lifetime
            // (the server's `active_vault_id` is set at handshake and only
            // changes when a new handshake is processed). Reusing a
            // connection that was last bound to vault A for a new vault-B
            // handshake means the server only switches active_vault_id
            // when the new handshake packet is processed, but in the
            // meantime any in-flight or already-queued A-bound packets
            // (e.g. an A-targeted syncResponse that arrived just before
            // the unlock was tapped) can still be routed to vault B's
            // UI. disconnect() resets handshakeCompleted and isConnected;
            // it's idempotent and safe to call when no connection is
            // active (just resets flags). After disconnect(),
            // triggerHandshake() will see isConnected=false and start a
            // fresh NWConnection on the same discovered peer.
            SyncService.shared.disconnect()
            SyncService.shared.startUDPListener()
            SyncService.shared.startDiscovery()
            SyncService.shared.triggerHandshake()
        }
        if db != nil {
            // Pipeline will fire after handshake completes (because each
            // request is guarded by handshakeCompleted). If syncServiceDidReceiveSalt
            // also fires it, the !isSyncing guard in startFullSyncPipeline dedupes.
            SyncService.shared.startFullSyncPipeline()
        }
    }
    
    func lock() {
        print("[VaultManager] lock: previous dbPath=\(currentVaultDbPath())")
        // Tear down any in-flight TCP connection so the next unlock or
        // setupVault builds a clean one. Without this, a leftover
        // connection from a previous session keeps isConnected=true,
        // triggerHandshake() calls startHandshake() directly which
        // sendPacket's into a stale NWConnection that the OS has long
        // since reset, so awaitingHandshakeAck never flips, so the
        // pipeline's requestSalt/RequestCategories/Sync calls all bail
        // silently on handshakeCompleted=false. The user is then stuck
        // on the 'Identifying Vault' page forever.
        SyncService.shared.disconnect()
        self.encryptionKey = nil
        self.sessionPassword = nil
        self.inFlight.removeAll()
        self.isUnlocked = false
        self.isReady = false
        self.closeDatabase()
        self.entries = []
        // Reset vaultName so a vault switch doesn't briefly show the
        // previous vault's name. The new value is loaded (or derived as
        // a default) in `initializeWithSalt` -> `ensureVaultNamePersisted`
        // on the next unlock. We reset to "My Vault" here as a
        // neutral placeholder; the in-memory value is overwritten before
        // the next render so the user never sees it for long.
        self.vaultName = "My Vault"
        self.objectWillChange.send()
    }
    
    func updateVaultName(_ name: String) throws {
        guard let db = db else { throw VaultError.notInitialized }
        self.vaultName = name
        
        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES ('vault_name', ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        self.objectWillChange.send()
    }
    
    /// Ensures the `settings` table has a `vault_name` row. If the row is
    /// missing (fresh vault, never explicitly named by the user), this
    /// writes a derived default so the nav-bar title shows something more
    /// useful than the in-memory literal "My Vault". The default uses
    /// the first 6 chars of the current vaultId (uppercased hex) so each
    /// vault gets a unique placeholder name — useful for multi-vault
    /// users who can tell at a glance which vault they're in. The user
    /// can still rename the vault in Settings at any time.
    private func ensureVaultNamePersisted() {
        guard let db = db else { return }
        let query = "SELECT value FROM settings WHERE key = 'vault_name';"
        var stmt: OpaquePointer?
        var existing: String? = nil
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let text = sqlite3_column_text(stmt, 0) {
                    existing = String(cString: text)
                }
            }
        }
        sqlite3_finalize(stmt)
        // If a name is already persisted, just mirror it to the
        // @Published field and stop. The user has explicitly named
        // this vault; don't overwrite.
        if let name = existing, !name.isEmpty {
            self.vaultName = name
            return
        }
        // Derive a default from the vaultId. The SyncService exposes
        // the id as a hex string; first 6 chars gives a short, stable
        // identifier. Prefixed with "Vault \u{2022} " so the bullet
        // visually flags it as a generated default the user can
        // rename in Settings.
        let vid = SyncService.shared.vaultId
        let prefix = vid.isEmpty ? "UNNAMED" : String(vid.prefix(6)).uppercased()
        let defaultName = "Vault \u{2022} \(prefix)"
        do {
            try updateVaultName(defaultName)
        } catch {
            // updateVaultName throws on db == nil; we've already
            // guarded on that, so this should never fire. If it
            // does (e.g. disk full), fall through and let the
            // in-memory default stand.
            print("[VaultManager] ensureVaultNamePersisted failed: \(error)")
        }
    }
    
    func refreshUI() {
        DispatchQueue.main.async {
            self.lastSyncUpdate = Date()
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .vaultDataChanged, object: nil)
        }
    }
    
    /// Names of every `vault_<id>.db` currently on disk (no other extensions,
    /// no un-suffixed `vault.db`). Used by ContentView to list available
    /// vaults when `vaultId` is unset. The bare `vault.db` is LEGACY-V2 and
    /// deliberately excluded from v3 enumeration.
    func availableVaultFilenames() -> [String] {
        let vaultDir = VaultManager.vaultDirectory
        guard FileManager.default.fileExists(atPath: vaultDir.path) else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: vaultDir.path)) ?? []
        return items.filter { $0.hasSuffix(".db") && $0.hasPrefix("vault_") && $0 != "vault.db" }.sorted()
    }

    /// True if a `vault_<id>.db` file already exists for this vaultId. false
    /// means the user is trying to *unlock* a vault that hasn't been set up
    /// on this device yet — they should be routed to the 'Retrieve Vault
    /// from Server' flow instead of silently creating an empty vault.
    /// v3+ never falls back to the un-suffixed legacy `vault.db`.
    func vaultFileExists(forVaultId vaultId: String) -> Bool {
        guard !vaultId.isEmpty else { return false }
        let filename = "vault_\(vaultId).db"
        let dbPath = VaultManager.vaultDirectory
            .appendingPathComponent(filename)
            .path
        return FileManager.default.fileExists(atPath: dbPath)
    }

    // MARK: - Keychain Salt Management
    
    func localSalt(for vaultId: String) throws -> Data? { try retrieveSalt(for: vaultId) }

    func storeSalt(_ salt: Data, for vaultId: String) throws {
        let account = "vault_salt_\(vaultId)"
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecValueData: salt] as [String: Any]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw VaultError.keychainError(status)
        }
        UserDefaults.standard.set(salt, forKey: "vault_salt_fallback_\(vaultId)")
        UserDefaults.standard.synchronize()
    }
    
    private func retrieveSalt(for vaultId: String) throws -> Data? {
        let account = "vault_salt_\(vaultId)"
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as [String: Any]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return data }
        if let fallback = UserDefaults.standard.data(forKey: "vault_salt_fallback_\(vaultId)") { return fallback }
        return nil
    }
    
    // MARK: - Compatibility / Legacy API for Views & Sync
    
    func hasAnyVault() -> Bool {
        // True if any per-vault `vault_<id>.db` exists. Matches Desktop's
        // expectation that 'any present vault' gates Unlock vs Setup.
        // v3+ explicitly excludes the un-suffixed legacy `vault.db`.
        let vaultDir = VaultManager.vaultDirectory
        guard FileManager.default.fileExists(atPath: vaultDir.path) else { return false }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: vaultDir.path)) ?? []
        return items.contains { $0.hasSuffix(".db") && $0.hasPrefix("vault_") && $0 != "vault.db" }
    }

    func getDebugInfo(password: String) {
        let combined = Data(password.utf8) + cryptoService.systemIdentitySalt
        self.debugKeyHash = cryptoService.sha256(combined).map { String(format: "%02x", $0) }.joined().prefix(12) + "..."
        self.debugCanaryStatus = "Checked"
        self.objectWillChange.send()
    }

    func verifyCurrentKey() -> String {
        if isUnlocked && encryptionKey != nil {
            return "Key Valid"
        }
        return "Key Invalid"
    }

    /// Deletes ONE vault from this device only: the vault the given password opens.
    /// The vault on the computer is never touched. Returns false when no such vault exists here.
    @discardableResult
    func deleteLocalVault(password: String) -> Bool {
        deleteLocalVault(id: cryptoService.deriveVaultId(password: password))
    }

    /// Deletes the currently open vault from this device only.
    @discardableResult
    func deleteCurrentVault() -> Bool { deleteLocalVault(id: SyncService.shared.vaultId) }

    @discardableResult
    private func deleteLocalVault(id: String) -> Bool {
        guard vaultFileExists(forVaultId: id) else { return false }
        let vaultDir = VaultManager.vaultDirectory
        if let items = try? FileManager.default.contentsOfDirectory(atPath: vaultDir.path) {
            for name in items where name.contains(id) {
                try? FileManager.default.removeItem(atPath: vaultDir.appendingPathComponent(name).path)
            }
        }
        let saltQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrAccount as String: "vault_salt_\(id)"]
        SecItemDelete(saltQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "vault_salt_fallback_\(id)")
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp_\(id)")
        UserDefaults.standard.removeObject(forKey: "categoriesDirty_\(id)")
        UserDefaults.standard.removeObject(forKey: "pendingRegister_\(id)")
        lock()
        isFirstPopulationPending = false
        objectWillChange.send()
        return true
    }

    func addEntry(_ entry: VaultEntry, password: String, notes: String?, totpSecret: String? = nil) throws {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        
        var newEntry = entry
        newEntry.totpSecret = try encryptTOTP(totpSecret ?? "")
        if !password.isEmpty {
            newEntry.encryptedPassword = try cryptoService.encrypt(password, using: key)
        }
        if let notes = notes, !notes.isEmpty {
            let encryptedNotesData = try cryptoService.encrypt(notes, using: key)
            newEntry.encryptedNotes = encryptedNotesData
        }
        saveEntry(newEntry)
    }
    
    func decryptPassword(for entry: VaultEntry) throws -> String {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        guard !entry.encryptedPassword.isEmpty else { return "" }
        return try cryptoService.decrypt(entry.encryptedPassword, using: key)
    }
    
    /// One-time-code secrets are encrypted like passwords and stored as "enc1:<base64>".
    func encryptTOTP(_ secret: String) throws -> String? {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        return "enc1:" + (try cryptoService.encrypt(trimmed, using: key)).base64EncodedString()
    }

    func decryptTOTP(for entry: VaultEntry) throws -> String {
        guard let stored = entry.totpSecret, !stored.isEmpty else { return "" }
        guard stored.hasPrefix("enc1:") else { return stored } // older plaintext value
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        guard let data = Data(base64Encoded: String(stored.dropFirst(5))) else { throw VaultError.decryptionFailed }
        return try cryptoService.decrypt(data, using: key)
    }

    func decryptNotes(for entry: VaultEntry) throws -> String? {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        guard let enc = entry.encryptedNotes, !enc.isEmpty else { return nil }
        return try cryptoService.decrypt(enc, using: key)
    }
    
    /// `newPassword == nil` leaves the stored password untouched; an empty `newNotes`
    /// clears the notes.
    func updateEntry(_ entry: VaultEntry, newPassword: String?, newNotes: String, newTotp: String? = nil) throws {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        
        var updated = entry
        if let newTotp = newTotp { updated.totpSecret = try encryptTOTP(newTotp) }
        if let newPassword = newPassword {
            updated.encryptedPassword = newPassword.isEmpty ? Data() : try cryptoService.encrypt(newPassword, using: key)
        }
        updated.encryptedNotes = newNotes.isEmpty ? nil : try cryptoService.encrypt(newNotes, using: key)
        saveEntry(updated)
    }

    // MARK: - Categories

    private static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// True while local category edits have not yet been sent to the computer.
    private var categoriesDirtyKey: String { "categoriesDirty_\(SyncService.shared.vaultId)" }
    var categoriesDirty: Bool {
        get { UserDefaults.standard.bool(forKey: categoriesDirtyKey) }
        set { UserDefaults.standard.set(newValue, forKey: categoriesDirtyKey) }
    }

    func saveCategory(_ category: Category) {
        guard let db = db, category.id != Self.favoritesID else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO categories (id, name, icon, color) VALUES (?, ?, ?, ?);", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, category.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, category.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category.icon, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, category.color, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        loadData()
        categoriesChanged()
    }

    /// Deleting a category keeps its entries; they simply become uncategorized.
    func deleteCategory(id: UUID) {
        guard let db = db, id != Self.favoritesID else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM categories WHERE lower(id) = lower(?);", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        if sqlite3_prepare_v2(db, "UPDATE entries SET category_id = NULL, modified_at = ?, sync_status = 'pending' WHERE lower(category_id) = lower(?);", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        loadData()
        categoriesChanged()
    }

    private func categoriesChanged() {
        categoriesDirty = true
        SyncService.shared.startFullSyncPipeline()
    }

    /// Custom categories as stored on disk (the virtual Favorites list is never synced).
    func localCategoriesForSync() -> [SyncCategory] {
        guard let db = db else { return [] }
        var result: [SyncCategory] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, name, icon, color FROM categories;", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = columnText(stmt, 0)
                if id.lowercased() == Self.favoritesID.uuidString.lowercased() { continue }
                result.append(SyncCategory(id: id.lowercased(), name: columnText(stmt, 1), icon: columnText(stmt, 2), color: columnText(stmt, 3)))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    // MARK: - Face ID

    private var faceIDEnabled: Bool {
        UserDefaults.standard.object(forKey: "faceIDUnlock") as? Bool ?? true
    }

    /// Stores the session password for biometric unlock, if the user has not opted out.
    func saveBiometricPasswordIfEnabled(_ password: String) {
        guard faceIDEnabled, cryptoService.biometricsAvailable else { return }
        try? cryptoService.saveMasterPasswordToKeychain(password)
    }

    func setBiometricUnlock(_ enabled: Bool) {
        if enabled, let password = sessionPassword {
            saveBiometricPasswordIfEnabled(password)
        } else if !enabled {
            cryptoService.deleteMasterPasswordFromKeychain()
        }
    }
    
    func getPendingEntries(completion: @escaping ([VaultEntry], [String]) -> Void) {
        // Return the raw VaultEntry list (already holds encrypted data)
        // Sync layer will convert to SyncVaultEntry using the proper init
        // completion(entries, [])

        // Offline-DELETE outbox: read pending_tombstones. Each row is
        // an entry id that the user deleted locally but the server
        // hasn't acknowledged yet. flushOutbox() will call
        // sendEntryDelete per id and then call markTombstonesSent()
        // to drop them from the outbox. didReceiveTombstones() also
        // drops rows as a dedup (in case the server sends the same id
        // back as part of its tombstone list).
        guard let db = db else {
            completion([], [])
            return
        }
        var pendingIds = Set<String>()
        var pendingStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id FROM entries WHERE sync_status = 'pending';", -1, &pendingStmt, nil) == SQLITE_OK {
            while sqlite3_step(pendingStmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(pendingStmt, 0) { pendingIds.insert(String(cString: c).uppercased()) }
            }
        }
        sqlite3_finalize(pendingStmt)
        let pendingEntries = entries.filter { pendingIds.contains($0.id.uuidString.uppercased()) }
        let query = "SELECT id FROM pending_tombstones;"
        var stmt: OpaquePointer?
        var ids: [String] = []
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    ids.append(String(cString: cString))
                }
            }
        }
        sqlite3_finalize(stmt)
        completion(pendingEntries, ids)
    }

    /// Insert an entry id into the durable offline-delete outbox.
    /// Called from deleteEntry() before any network send. Idempotent:
    /// re-inserting the same id is a no-op (PRIMARY KEY).
    func recordTombstone(id: String) {
        guard let db = db else { return }
        let sql = "INSERT OR IGNORE INTO pending_tombstones (id, created_at) VALUES (?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[SQLite3] Failed to record tombstone: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(stmt)
    }

    /// Remove a list of tombstone ids from the outbox after they've
    /// been sent on the wire. Called by flushOutbox() once the
    /// EntryDelete packet has been handed to sendPacket(). Optimistic:
    /// we don't wait for the server's Ack because the iOS-side
    /// handleIncomingPacket treats every .ack as a handshake ack and
    /// doesn't carry a per-id correlation. The TCP connection is
    /// reliable within a session; if the server crashes mid-handle,
    /// the worst case is the entry reappearing until the user deletes
    /// again on the next session. (The persistent outbox IS the
    /// durability guarantee for the crash-between-intent-and-send
    /// case; the crash-between-send-and-handle case is rare enough
    /// to accept the simpler model.)
    func markTombstonesSent(ids: [String]) {
        guard let db = db, !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "DELETE FROM pending_tombstones WHERE id IN (\(placeholders));"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (i, id) in ids.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), id, -1, SQLITE_TRANSIENT)
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[SQLite3] Failed to clear sent tombstones: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(stmt)
    }

    /// Remove a single id from the outbox. Called from
    /// didReceiveTombstones() to dedup: if the server's tombstone
    /// list happens to include an id we deleted locally and
    /// recorded in the outbox, we drop our outbox row so we don't
    /// re-send a delete the server has already processed.
    func clearTombstone(id: String) {
        guard let db = db else { return }
        let sql = "DELETE FROM pending_tombstones WHERE lower(id) = lower(?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    // MARK: - SyncServiceDelegate
    
    func syncServiceDidConnect(_ service: SyncService) {
        DispatchQueue.main.async { self.syncStatus = "Connected" }
    }
    
    func syncServiceDidDisconnect(_ service: SyncService) {
        DispatchQueue.main.async { self.syncStatus = "Disconnected" }
    }
    
    func syncService(_ service: SyncService, didReceiveSyncEntries incoming: [SyncVaultEntry], timestamp: Int64) {
        guard let db = db, let key = encryptionKey else { return }

        // Re-entrancy guard: saveEntry() would otherwise push each of these
        // entries back to the server in an echo loop. The guard is cleared
        // in defer so any thrown error path also resets state.
        isApplyingRemoteUpdate = true
        defer { isApplyingRemoteUpdate = false }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        for syncEntry in incoming {
            do {
                // Entries saved without a password legitimately carry no ciphertext.
                if !syncEntry.encrypted_password.isEmpty {
                    _ = try cryptoService.decrypt(Data(syncEntry.encrypted_password), using: key)
                }

                // A delete the user made offline wins until the server has seen it.
                if isPendingTombstone(syncEntry.id) { continue }
                // Newest wins: keep the local copy when it is at least as new.
                if let localMs = localModifiedMillis(id: syncEntry.id), localMs >= syncEntry.modified_at { continue }

                let entry = try syncEntry.toVaultEntry()
                saveEntry(entry, fromRemote: true)
            } catch {
                print("[Sync] Skipping entry \(syncEntry.id) due to decryption failure")
            }
        }
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        
        loadData()
        DispatchQueue.main.async {
            self.vaultSyncStatus = "Last sync: \(Date().formatted(date: .abbreviated, time: .shortened))"
            self.objectWillChange.send()
        }
    }
    
    func syncService(_ service: SyncService, didReceiveCategories categories: [SyncCategory]) {
        guard let db = db else { return }

        // Edits made here that the computer has not seen yet win; send them instead of overwriting.
        // An empty list from the computer never wipes categories that only exist on this phone.
        if categoriesDirty || (categories.isEmpty && !localCategoriesForSync().isEmpty) {
            SyncService.shared.pushCategories()
            return
        }
        
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        
        let insertCat = "INSERT OR REPLACE INTO categories (id, name, icon, color) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, insertCat, -1, &stmt, nil) == SQLITE_OK {
            for cat in categories {
                sqlite3_bind_text(stmt, 1, cat.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, cat.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, cat.icon, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, cat.color, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
        }
        sqlite3_finalize(stmt)

        // The computer's list is the truth: drop categories it no longer has.
        let keep = Set(categories.map { $0.id.lowercased() })
        for local in localCategoriesForSync() where !keep.contains(local.id) {
            var del: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM categories WHERE lower(id) = ?;", -1, &del, nil) == SQLITE_OK {
                sqlite3_bind_text(del, 1, local.id, -1, SQLITE_TRANSIENT)
                sqlite3_step(del)
            }
            sqlite3_finalize(del)
        }
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        loadData()
    }
    
    func syncService(_ service: SyncService, didReceiveTombstones deletedIds: [String], deletedAt: [String: Int64]) {
        guard let db = db else { return }

        // Re-entrancy guard for symmetry with didReceiveSyncEntries. The
        // current tombstones path uses raw SQL (not deleteEntry), so the
        // flag isn't strictly required, but it documents the intent and
        // keeps a future refactor that switches to deleteEntry() safe.
        isApplyingRemoteUpdate = true
        defer { isApplyingRemoteUpdate = false }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        // Case-insensitive DELETE: Desktop normalizes stored ids to
        // UPPERCASE, but tombstone files still contain mixed-case
        // ghosts from pre-fix sync paths. A plain `WHERE id = ?`
        // would silently miss rows that differ in case from the
        // tombstone ID. Compare via `lower(id) = lower(?)`.
        let del = "DELETE FROM entries WHERE lower(id) = lower(?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, del, -1, &stmt, nil) == SQLITE_OK {
            for id in deletedIds {
                // Newest wins: keep a local copy that was edited after the other side deleted it.
                if let deletedMs = deletedAt[id.lowercased()], let localMs = localModifiedMillis(id: id), localMs > deletedMs {
                    continue
                }
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                // Offline-DELETE outbox dedup: if the server's tombstone
                // list includes an id we recorded locally as a pending
                // tombstone (e.g. user deleted on both sides, or the
                // server already processed our offline delete and is
                // echoing it back), drop the outbox row so flushOutbox()
                // doesn't re-send a delete the server has already
                // acknowledged. clearTombstone is a no-op if the id
                // isn't in the outbox.
                clearTombstone(id: id)
            }
        }
        sqlite3_finalize(stmt)
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        loadData()
    }
    
    func syncServiceDidReceiveSalt(_ service: SyncService, salt: [UInt8]) {
        DispatchQueue.main.async {
            self.keyStatus = ""
            let serverSalt = Data(salt)
            let vaultId = SyncService.shared.vaultId
            self.debugSaltHex = serverSalt.map { String(format: "%02x", $0) }.joined()

            if let password = self.pendingSetupPassword {
                // Retrieve flow: adopt the server's salt and open the vault with it.
                do {
                    try self.storeSalt(serverSalt, for: vaultId)
                    try self.initializeWithSalt(password: password, salt: serverSalt)
                    self.sessionPassword = password
                    self.saveBiometricPasswordIfEnabled(password)
                    self.retrieveWatchdog?.cancel()
                    self.pendingSetupPassword = nil
                    self.isFirstPopulationPending = false
                    self.lastHandshakeError = nil
                    SyncService.shared.startFullSyncPipeline()
                } catch {
                    self.failRetrieve("Could not open the vault. Please try again.")
                }
            } else if self.isUnlocked {
                // Reconnect (or first link of a vault created on this phone).
                let localSalt = try? self.retrieveSalt(for: vaultId)
                if let local = localSalt, local != serverSalt {
                    // The desktop's vault has its own salt: re-encrypt local entries
                    // with the key derived from it, then adopt it.
                    do { try self.rekeyLocalEntries(toSalt: serverSalt, vaultId: vaultId) }
                    catch {
                        self.keyStatus = "Key mismatch with desktop"
                        self.lastHandshakeError = "This vault's key does not match the desktop vault. Sync paused."
                        self.saltReady = true
                        return
                    }
                }
                SyncService.shared.startFullSyncPipeline()
            }
            self.saltReady = true
            self.objectWillChange.send()
            NotificationCenter.default.post(name: Notification.Name("SaltReady"), object: nil)
        }
    }

    /// Re-encrypts every local entry from the current key to the key derived from
    /// `salt`, keeping modification times so "newest wins" is unaffected. All entries
    /// are decrypted first; nothing is written if any one fails.
    private func rekeyLocalEntries(toSalt salt: Data, vaultId: String) throws {
        guard let oldKey = encryptionKey, let password = sessionPassword else { throw VaultError.notInitialized }
        let newKey = try cryptoService.deriveKey(from: password, salt: salt)
        var rekeyed: [VaultEntry] = []
        for var entry in entries {
            if !entry.encryptedPassword.isEmpty {
                let plain = try cryptoService.decrypt(entry.encryptedPassword, using: oldKey)
                entry.encryptedPassword = try cryptoService.encrypt(plain, using: newKey)
            }
            if let notes = entry.encryptedNotes, !notes.isEmpty {
                let plain = try cryptoService.decrypt(notes, using: oldKey)
                entry.encryptedNotes = try cryptoService.encrypt(plain, using: newKey)
            }
            rekeyed.append(entry)
        }
        try storeSalt(salt, for: vaultId)
        encryptionKey = newKey
        for entry in rekeyed { saveEntry(entry, fromRemote: false, keepTimestamp: true) }
        print("[VaultManager] Re-keyed \(rekeyed.count) entries to the desktop salt")
    }

    func syncService(_ service: SyncService, didEncounterHandshakeError message: String) {
        DispatchQueue.main.async {
            if self.isFirstPopulationPending {
                self.failRetrieve(message)
            } else {
                self.lastHandshakeError = message
            }
        }
    }
    
    func syncService(_ service: SyncService, didEncounterError error: Error) { }
    func syncService(_ service: SyncService, didDiscoverDevices devices: [SyncDevice]) { }
}

extension Data {
    static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
}
