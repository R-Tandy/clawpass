// MARK: - VERSION_SINCED_2026_06_27_CLEAN_REWRITE_WITH_API
import Foundation
import SQLite3
import LocalAuthentication
import CryptoKit

enum VaultError: Error {
    case notInitialized
    case alreadyInitialized
    case invalidPassword
    case databaseError(String)
    case entryNotFound
    case keychainError(OSStatus)
    case decryptionFailed
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
    
    private var db: OpaquePointer?
    private var encryptionKey: SymmetricKey?
    private let cryptoService = CryptoService.shared
    private var syncService = SyncService.shared
    private var pendingUnlockPassword: String?
    private var pendingSetupPassword: String?
    
    init() {
        SyncService.shared.delegate = self
    }
    
    // MARK: - Database Core
    
    /// Per-vault DB filename. Matches Desktop's `vault_{id}.db` convention when a
    /// `vaultId` is set, and falls back to the legacy `vault.db` for the default
    /// ("vault_1") or unset cases — keeping existing single-vault installs working.
    private func currentVaultDbFilename() -> String {
        let vid = SyncService.shared.vaultId
        if vid.isEmpty || vid == "vault_1" {
            return "vault.db"
        }
        return "vault_\(vid).db"
    }
    
    /// Absolute path to the DB file that *should* currently be open, given the
    /// SyncService vaultId. Callers use this to open/initialize against the
    /// correct per-vault file.
    private func currentVaultDbPath() -> String {
        let vaultDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("ClawPass")
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        return vaultDir.appendingPathComponent(currentVaultDbFilename()).path
    }
    
    private func openDatabase(path: String) -> Bool {
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

        let tables = [createEntries, createCategories, createSettings]
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
                let idStr = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let username = String(cString: sqlite3_column_text(stmt, 2))
                
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
                let idStr = String(cString: sqlite3_column_text(catStmt, 0))
                let name = String(cString: sqlite3_column_text(catStmt, 1))
                let icon = String(cString: sqlite3_column_text(catStmt, 2))
                let color = String(cString: sqlite3_column_text(catStmt, 3))
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
    
    func saveEntry(_ entry: VaultEntry) {
        guard let db = db else { return }
        
        let insert = "INSERT OR REPLACE INTO entries (id, title, username, encrypted_password, url, encrypted_notes, category_id, totp_secret, created_at, modified_at, is_favorite, sync_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (entry.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (entry.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (entry.username as NSString).utf8String, -1, nil)
            
            if !entry.encryptedPassword.isEmpty {
                _ = entry.encryptedPassword.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, 4, bytes.baseAddress, Int32(entry.encryptedPassword.count), nil)
                }
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            
            if let url = entry.url {
                sqlite3_bind_text(stmt, 5, (url as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            
            if let notes = entry.encryptedNotes, !notes.isEmpty {
                _ = notes.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(stmt, 6, bytes.baseAddress, Int32(notes.count), nil)
                }
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            
            if let catID = entry.categoryID {
                sqlite3_bind_text(stmt, 7, (catID.uuidString as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            
            if let totp = entry.totpSecret {
                sqlite3_bind_text(stmt, 8, (totp as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            
            let now = Date().timeIntervalSince1970
            sqlite3_bind_double(stmt, 9, now)
            sqlite3_bind_double(stmt, 10, now)
            sqlite3_bind_int(stmt, 11, entry.isFavorite ? 1 : 0)
            sqlite3_bind_text(stmt, 12, "synced", -1, nil)
            
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
    }

    func deleteEntry(id: UUID) {
        guard let db = db else { return }
        let del = "DELETE FROM entries WHERE id = ?;"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, del, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[SQLite3] Failed to delete entry: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(stmt)
        // Same reasoning as saveEntry: update the array on the main thread.
        DispatchQueue.main.async {
            self.entries.removeAll { $0.id == id }
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .vaultDataChanged, object: nil)
        }
    }
    
    // MARK: - Vault Logic
    
    func getEncryptionKey() -> SymmetricKey? {
        return encryptionKey
    }
    
    func setupVault(password: String) {
        let derivedVaultId = cryptoService.deriveVaultId(password: password)
        SyncService.shared.setVaultId(derivedVaultId)
        SyncService.shared.startUDPListener()
        SyncService.shared.triggerHandshake()
        self.isFirstPopulationPending = true
        self.pendingSetupPassword = password
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
            effectiveSalt = Data()
        }
        try initializeWithSalt(password: password, salt: effectiveSalt)

        // After a fresh unlock, kick off the sync pipeline so the
        // 'Syncing your vault...' overlay clears. Previously only
        // syncServiceDidReceiveSalt did this, leaving unlock-the-existing-
        // vault flows stuck on the overlay until the user manually opened
        // SyncView and pressed 'Sync now'.
        if !skipHandshake {
            SyncService.shared.startUDPListener()
            SyncService.shared.startDiscovery()
        }
        if db != nil {
            SyncService.shared.startFullSyncPipeline()
        }
    }
    
    func lock() {
        self.encryptionKey = nil
        self.isUnlocked = false
        self.isReady = false
        self.db = nil
        self.entries = []
        self.objectWillChange.send()
    }
    
    func updateVaultName(_ name: String) throws {
        guard let db = db else { throw VaultError.notInitialized }
        self.vaultName = name
        
        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES ('vault_name', ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        self.objectWillChange.send()
    }
    
    private func loadVaultName() {
        guard let db = db else { return }
        let query = "SELECT value FROM settings WHERE key = 'vault_name';"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let text = sqlite3_column_text(stmt, 0) {
                    self.vaultName = String(cString: text)
                }
            }
        }
        sqlite3_finalize(stmt)
    }
    
    func refreshUI() {
        DispatchQueue.main.async {
            self.lastSyncUpdate = Date()
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .vaultDataChanged, object: nil)
        }
    }
    
    // MARK: - Keychain Salt Management
    
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
        // True if any vault_<id>.db exists OR the legacy vault.db. Matches
        // Desktop's expectation that 'any present vault' gates Unlock vs Setup.
        let vaultDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("ClawPass")
        guard FileManager.default.fileExists(atPath: vaultDir.path) else { return false }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: vaultDir.path)) ?? []
        return items.contains { $0.hasSuffix(".db") && ($0 == "vault.db" || $0.hasPrefix("vault_")) }
    }

    /// Names of every vault_<id>.db / vault.db currently on disk. Used by
    /// ContentView to list available vaults when `vaultId` is unset.
    func availableVaultFilenames() -> [String] {
        let vaultDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("ClawPass")
        guard FileManager.default.fileExists(atPath: vaultDir.path) else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(atPath: vaultDir.path)) ?? []
        return items.filter { $0.hasSuffix(".db") && ($0 == "vault.db" || $0.hasPrefix("vault_")) }.sorted()
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

    func nuclearReset() {
        let vaultDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("ClawPass")
        // Wipe all vault_*.db and the legacy vault.db. Matches Desktop's
        // "wipe everything" semantics from PROJECT_STATUS.md Phase 3.
        if let items = try? FileManager.default.contentsOfDirectory(atPath: vaultDir.path) {
            for name in items where name.hasSuffix(".db") {
                try? FileManager.default.removeItem(atPath: vaultDir.appendingPathComponent(name).path)
            }
        }
        
        // Wipe every vault_salt_* keychain item (single-class delete matches
        // a deletion-by-service query; we then re-add nothing, leaving Keychain
        // clean for the next init).
        let allKeychain: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        SecItemDelete(allKeychain as CFDictionary)
        // Belt-and-braces: also wipe the UserDefaults fallback salts.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("vault_salt_fallback_") {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        
        self.lock()
        self.isFirstPopulationPending = false
        self.objectWillChange.send()
        print("[VaultManager] Nuclear reset completed")
    }
    
    func addEntry(_ entry: VaultEntry, password: String, notes: String?) throws {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        
        var newEntry = entry
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
    
    func decryptNotes(for entry: VaultEntry) throws -> String? {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        guard let enc = entry.encryptedNotes, !enc.isEmpty else { return nil }
        return try cryptoService.decrypt(enc, using: key)
    }
    
    func updateEntry(_ entry: VaultEntry, newPassword: String, newNotes: String) throws {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        
        var updated = entry
        if !newPassword.isEmpty {
            updated.encryptedPassword = try cryptoService.encrypt(newPassword, using: key)
        }
        if !newNotes.isEmpty {
            let enc = try cryptoService.encrypt(newNotes, using: key)
            updated.encryptedNotes = enc
        }
        saveEntry(updated)
    }
    
    func getPendingEntries(completion: @escaping ([VaultEntry], [String]) -> Void) {
        // Return the raw VaultEntry list (already holds encrypted data)
        // Sync layer will convert to SyncVaultEntry using the proper init
        completion(entries, [])
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
        
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        
        for syncEntry in incoming {
            do {
                _ = try cryptoService.decrypt(Data(syncEntry.encrypted_password), using: key)
                
                var entry = VaultEntry(
                    id: UUID(uuidString: syncEntry.id) ?? UUID(),
                    title: syncEntry.title,
                    username: syncEntry.username,
                    password: "",
                    url: syncEntry.url,
                    notes: nil,
                    categoryID: syncEntry.category_id.flatMap { UUID(uuidString: $0) },
                    totpSecret: syncEntry.totp_secret,
                    isFavorite: syncEntry.is_favorite
                )
                entry.encryptedPassword = Data(syncEntry.encrypted_password)
                entry.encryptedNotes = syncEntry.encrypted_notes.map { Data($0) }
                
                saveEntry(entry)
            } catch {
                print("[Sync] Skipping entry \(syncEntry.id) due to decryption failure")
            }
        }
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        
        loadData()
        DispatchQueue.main.async {
            self.vaultSyncStatus = "Last sync: \(timestamp)"
            self.objectWillChange.send()
        }
    }
    
    func syncService(_ service: SyncService, didReceiveCategories categories: [SyncCategory]) {
        guard let db = db else { return }
        
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        
        let insertCat = "INSERT OR REPLACE INTO categories (id, name, icon, color) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, insertCat, -1, &stmt, nil) == SQLITE_OK {
            for cat in categories {
                sqlite3_bind_text(stmt, 1, (cat.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (cat.name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (cat.icon as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (cat.color as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
        }
        sqlite3_finalize(stmt)
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        loadData()
    }
    
    func syncService(_ service: SyncService, didReceiveTombstones deletedIds: [String]) {
        guard let db = db else { return }
        
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        
        let del = "DELETE FROM entries WHERE id = ?;"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, del, -1, &stmt, nil) == SQLITE_OK {
            for id in deletedIds {
                sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
        }
        sqlite3_finalize(stmt)
        
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        loadData()
    }
    
    func syncServiceDidReceiveSalt(_ service: SyncService, salt: [UInt8]) {
        DispatchQueue.main.async {
            self.keyStatus = ""
            let serverSaltData = Data(salt)
            do {
                let currentVaultId = SyncService.shared.vaultId
                if let localSalt = try self.retrieveSalt(for: currentVaultId) {
                    if localSalt != serverSaltData {
                        try self.storeSalt(serverSaltData, for: currentVaultId)
                    }
                } else {
                    try self.storeSalt(serverSaltData, for: currentVaultId)
                }
                self.debugSaltHex = serverSaltData.map { String(format: "%02x", $0) }.joined()
                print("[VaultManager] Salt received from server: \(self.debugSaltHex.prefix(16))...; current vaultId=\(currentVaultId)")
                
                if let password = self.pendingSetupPassword {
                    do {
                        // Single-pass init with the server salt — no second unlock call.
                        // The previous code re-derived the key with saltOverride==nil
                        // (i.e. empty salt) immediately after, producing a key that
                        // didn't match what entries were encrypted with. That left
                        // entries un-decryptable, showing zero entries in the UI.
                        try self.initializeWithSalt(password: password, salt: serverSaltData)
                        let resolvedPath = self.currentVaultDbPath()
                        print("[VaultManager] init OK; DB=\(resolvedPath); key=\(self.encryptionKey != nil ? "valid" : "INVALID")")
                        self.pendingSetupPassword = nil
                        self.isFirstPopulationPending = false
                        DispatchQueue.main.async { self.isUnlocked = true; self.objectWillChange.send() }
                        if self.db != nil { SyncService.shared.startFullSyncPipeline() }
                    } catch {
                        print("[VaultManager] setup init failed: \(error)")
                        self.isFirstPopulationPending = false
                    }
                } else if let password = self.pendingUnlockPassword {
                    do {
                        try self.unlock(with: password, saltOverride: serverSaltData, skipHandshake: true, forceLock: true)
                        self.pendingUnlockPassword = nil
                        DispatchQueue.main.async { self.isUnlocked = true; self.objectWillChange.send() }
                        if self.db != nil { SyncService.shared.startFullSyncPipeline() }
                    } catch { }
                }
            } catch { self.keyStatus = "Salt Store Error" }
            self.saltReady = true
            self.objectWillChange.send()
            NotificationCenter.default.post(name: Notification.Name("SaltReady"), object: nil)
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
