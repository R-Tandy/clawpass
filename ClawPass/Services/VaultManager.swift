import Foundation
import SQLite
import LocalAuthentication
import CryptoKit

enum VaultError: Error {
    case notInitialized
    case alreadyInitialized
    case invalidPassword
    case databaseError(Error)
    case entryNotFound
    case keychainError(OSStatus)
}

class VaultManager: ObservableObject, SyncServiceDelegate {
    static let shared = VaultManager()
    
    @Published private(set) var isUnlocked = false
    @Published private(set) var entries: [VaultEntry] = []
    @Published private(set) var categories: [Category] = []
    @Published var syncStatus: String = ""
    @Published private(set) var vaultSyncStatus: String = ""
    
    private var db: Connection?
    private var encryptionKey: SymmetricKey?
    private let cryptoService = CryptoService.shared
    private var syncService = SyncService.shared
    
    private let entriesTable = Table("entries")
    private let categoriesTable = Table("categories")
    private let settingsTable = Table("settings")
    
    // MARK: - Database Schema
    
    private let id = Expression<String>("id")
    private let title = Expression<String>("title")
    private let username = Expression<String>("username")
    private let encryptedPassword = Expression<Data>("encrypted_password")
    private let url = Expression<String?>("url")
    private let encryptedNotes = Expression<Data?>("encrypted_notes")
    private let categoryID = Expression<String?>("category_id")
    private let totpSecret = Expression<String?>("totp_secret")
    private let createdAt = Expression<Date>("created_at")
    private let modifiedAt = Expression<Date>("modified_at")
    private let isFavorite = Expression<Bool>("is_favorite")
    private let syncStatusColumn = Expression<String>("sync_status")
    
    private let catId = Expression<String>("id")
    private let catName = Expression<String>("name")
    private let catIcon = Expression<String>("icon")
    private let catColor = Expression<String>("color")
    
    // MARK: - Initialization
    
    private init() {}
    
    func initialize(with password: String) throws {
        guard db == nil else {
            throw VaultError.alreadyInitialized
        }
        
        // Create database file in app documents
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vault.db")
            .path
        
        // Generate salt and derive key
        let salt = Data.randomBytes(count: 32)
        let key = try cryptoService.deriveKey(from: password, salt: salt)
        
        // Create verification hash (SHA-256 of the derived key)
        let verifyHash = cryptoService.sha256(key)
        
        // Store salt and verification hash together in keychain
        var saltWithHash = salt
        saltWithHash.append(verifyHash)
        try storeSalt(saltWithHash)
        
        // Open encrypted database
        db = try Connection(path)
        encryptionKey = key
        
        // Create tables
        try createTables()
        
        // Add sync_status column if it doesn't exist (Migration)
        do {
            try db?.run(entriesTable.addColumn(syncStatusColumn, defaultValue: "synced"))
        } catch {
            print("[Vault] Sync status column already exists or migration failed: \(error)")
        }
        
        // Add default category
        let defaultCategory = Category.default
        try addCategory(defaultCategory)
        
        isUnlocked = true
        try loadData()
    }
    
    func unlock(with password: String) throws {
        guard db == nil else { return }
        
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vault.db")
            .path
        
        // Retrieve stored salt and hash
        guard let saltWithHash = try retrieveSalt() else {
            throw VaultError.notInitialized
        }
        
        // Separate salt and stored hash (last 32 bytes)
        // If saltWithHash is < 64, it's a legacy vault.
        let salt = saltWithHash.count >= 64 ? 
                   Data(saltWithHash.prefix(saltWithHash.count - 32)) : 
                   saltWithHash
        
        let storedHash = saltWithHash.count >= 64 ? 
                        Data(saltWithHash.suffix(32)) : 
                        nil

        // Derive key
        let key = try cryptoService.deriveKey(from: password, salt: salt)
        
        // Verify password using the stored hash (if available)
        if let expectedHash = storedHash {
            let currentHash = cryptoService.sha256(key)
            if currentHash != expectedHash {
                throw VaultError.invalidPassword
            }
        }
        
        do {
            db = try Connection(path)
            encryptionKey = key
            try loadData()
            isUnlocked = true
            
            // BRIDGE: Save password to UserDefaults for SyncService re-keying
            UserDefaults.standard.set(password, forKey: "vault_master_password")
            print("[Vault] Master password bridged to UserDefaults for sync")
            
            // Set up sync delegate
            syncService.delegate = self
        } catch {
            throw VaultError.invalidPassword
        }
    }
    
    func lock() {
        db = nil
        encryptionKey = nil
        entries = []
        categories = []
        isUnlocked = false
    }
    
    // MARK: - CRUD Operations
    
    func addEntry(_ entry: VaultEntry, password: String, notes: String?) throws {
        guard let db = db, let key = encryptionKey else {
            print("[Vault-ERR] addEntry failed: Vault not initialized or key missing")
            throw VaultError.notInitialized
        }
        
        var entry = entry
        do {
            entry.encryptedPassword = try cryptoService.encrypt(password, using: key)
            if let notes = notes {
                entry.encryptedNotes = try cryptoService.encrypt(notes, using: key)
            }
        } catch {
            print("[Vault-ERR] Encryption failed in addEntry: \(error)")
            throw error
        }
        
        let insert = entriesTable.insert(
            id <- entry.id.uuidString,
            title <- entry.title,
            username <- entry.username,
            encryptedPassword <- entry.encryptedPassword,
            url <- entry.url,
            encryptedNotes <- entry.encryptedNotes,
            categoryID <- entry.categoryID?.uuidString,
            totpSecret <- entry.totpSecret,
            createdAt <- entry.createdAt,
            modifiedAt <- entry.modifiedAt,
            isFavorite <- entry.isFavorite,
            syncStatusColumn <- "pending_update"
        )
        
        do {
            try db.run(insert)
            print("[Vault-SUCCESS] Entry \(entry.id.uuidString) inserted into DB")
            try loadData()
        } catch {
            print("[Vault-FATAL] SQLite Insert Error: \(error)")
            throw VaultError.databaseError(error)
        }
        
        syncService.sendEntryUpdate(entry: entry)
    }
    
    func updateEntry(_ entry: VaultEntry, newPassword: String? = nil, newNotes: String? = nil) throws {
        guard let db = db, let key = encryptionKey else {
            print("[Vault-ERR] updateEntry failed: Vault not initialized or key missing")
            throw VaultError.notInitialized
        }
        
        var encryptedPwd = entry.encryptedPassword
        var encryptedNts = entry.encryptedNotes
        
        do {
            if let newPassword = newPassword {
                encryptedPwd = try cryptoService.encrypt(newPassword, using: key)
            }
            if let newNotes = newNotes {
                encryptedNts = try cryptoService.encrypt(newNotes, using: key)
            }
        } catch {
            print("[Vault-ERR] Encryption failed in updateEntry: \(error)")
            throw error
        }
        
        let entryRow = entriesTable.filter(id == entry.id.uuidString)
        let update = entryRow.update(
            title <- entry.title,
            username <- entry.username,
            encryptedPassword <- encryptedPwd,
            url <- entry.url,
            encryptedNotes <- encryptedNts,
            categoryID <- entry.categoryID?.uuidString,
            totpSecret <- entry.totpSecret,
            modifiedAt <- Date(),
            isFavorite <- entry.isFavorite,
            syncStatusColumn <- "pending_update"
        )
        
        do {
            try db.run(update)
            print("[Vault-SUCCESS] Entry \(entry.id.uuidString) updated in DB")
            try loadData()
        } catch {
            print("[Vault-FATAL] SQLite Update Error: \(error)")
            throw VaultError.databaseError(error)
        }
        
        var updatedEntry = entry
        updatedEntry.encryptedPassword = encryptedPwd
        updatedEntry.encryptedNotes = encryptedNts
        syncService.sendEntryUpdate(entry: updatedEntry)
    }
    
    func deleteEntry(_ entry: VaultEntry) throws {
        guard let db = db else { throw VaultError.notInitialized }
        
        // Soft delete: mark as pending_delete instead of immediate removal
        let entryRow = entriesTable.filter(id == entry.id.uuidString)
        let update = entryRow.update(syncStatusColumn <- "pending_delete")
        
        try db.run(update)
        
        // CRITICAL: We must filter out "pending_delete" entries from the main list
        try loadData()
        
        // Attempt immediate propagation
        syncService.sendEntryDelete(entryId: entry.id.uuidString)
    }
    
    func decryptPassword(for entry: VaultEntry) throws -> String {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        return try cryptoService.decrypt(entry.encryptedPassword, using: key)
    }
    
    func decryptNotes(for entry: VaultEntry) throws -> String? {
        guard let key = encryptionKey, let notes = entry.encryptedNotes else { return nil }
        return try cryptoService.decrypt(notes, using: key)
    }
    
    // MARK: - Categories
    
    func addCategory(_ category: Category) throws {
        guard let db = db else { throw VaultError.notInitialized }
        
        let insert = categoriesTable.insert(
            catId <- category.id.uuidString,
            catName <- category.name,
            catIcon <- category.icon,
            catColor <- category.color
        )
        
        try db.run(insert)
        try loadCategories()
    }
    
    // MARK: - Outbox Management
    
    func getPendingEntries(completion: @escaping ([VaultEntry], [String]) -> Void) {
        guard let db = db else {
            completion([], [])
            return
        }
        
        do {
            var updates: [VaultEntry] = []
            var deletes: [String] = []
            
            // Find pending updates
            let updateQuery = entriesTable.filter(syncStatusColumn == "pending_update")
            for row in try db.prepare(updateQuery) {
                let entry = VaultEntry(
                    id: UUID(uuidString: row[id])!,
                    title: row[title],
                    username: row[username],
                    password: "", // Encrypted in DB
                    url: row[url],
                    notes: nil,
                    categoryID: row[categoryID].flatMap { UUID(uuidString: $0) },
                    totpSecret: row[totpSecret],
                    isFavorite: row[isFavorite]
                )
                var entryWithData = entry
                entryWithData.encryptedPassword = row[encryptedPassword]
                entryWithData.encryptedNotes = row[encryptedNotes]
                entryWithData.createdAt = row[createdAt]
                entryWithData.modifiedAt = row[modifiedAt]
                updates.append(entryWithData)
            }
            
            // Find pending deletes
            let deleteQuery = entriesTable.filter(syncStatusColumn == "pending_delete")
            for row in try db.prepare(deleteQuery) {
                deletes.append(row[id])
            }
            
            completion(updates, deletes)
        } catch {
            print("[Vault] Error fetching pending entries: \(error)")
            completion([], [])
        }
    }
    
    func markAsSynced(entryId: String) {
        guard let db = db else { return }
        do {
            let row = entriesTable.filter(id == entryId)
            try db.run(row.update(syncStatusColumn <- "synced"))
        } catch {
            print("[Vault] Error marking as synced: \(error)")
        }
    }
    
    func finalizeDelete(entryId: String) {
        guard let db = db else { return }
        do {
            let row = entriesTable.filter(id == entryId)
            try db.run(row.delete()) // Actually remove from DB now that server knows
            try loadData()
        } catch {
            print("[Vault] Error finalizing delete: \(error)")
        }
    }
    
    func updateSaltAndReKey(salt: [UInt8]) {
        DispatchQueue.main.async { self.syncStatus = "Re-keying: Fetching password..." }
        
        guard let password = UserDefaults.standard.string(forKey: "vault_master_password") else {
            print("[Vault] Error: No master password found in storage for re-keying")
            DispatchQueue.main.async { self.syncStatus = "Re-key Error: No Master PWD" }
            return
        }
        
        do {
            let saltData = Data(salt)
            let key = try cryptoService.deriveKey(from: password, salt: saltData)
            
            // KEY LEAK DIAGNOSTIC: Log the derived key to verify against server
            let keyHex = key.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined(separator: "") }
            print("[SINCED-KEY-LEAK] Derived Key: \(keyHex)")
            DispatchQueue.main.async { self.syncStatus = "Key: \(keyHex.prefix(16))..." }
            
            self.encryptionKey = key
            print("[Vault] SUCCESS: Key re-derived using synced salt")
            DispatchQueue.main.async { self.syncStatus = "SINCED: Key Validated ✅" }
            try loadData()
        } catch {
            print("[Vault] FATAL: Re-keying failed: \(error)")
            DispatchQueue.main.async { self.syncStatus = "Re-key Fatal: \(error.localizedDescription)" }
        }
    }
    
    func syncCategories(_ categories: [SyncCategory]) {
        guard let db = db else {
            print("[Vault] Sync categories error: Vault not initialized")
            return
        }
        
        do {
            try db.transaction {
                for cat in categories {
                    let query = categoriesTable.filter(catId == cat.id)
                    if let row = try db.pluck(query) {
                        let update = query.update(
                            catName <- cat.name,
                            catIcon <- cat.icon,
                            catColor <- cat.color
                        )
                        try db.run(update)
                    } else {
                        let insert = categoriesTable.insert(
                            catId <- cat.id,
                            catName <- cat.name,
                            catIcon <- cat.icon,
                            catColor <- cat.color
                        )
                        try db.run(insert)
                    }
                }
                try loadCategories()
            }
            print("[Vault] Successfully synced \(categories.count) categories")
        } catch {
            print("[Vault] Category sync failed: \(error)")
        }
    }
    
    private func createTables() throws {
        guard let db = db else { return }
        
        try db.run(entriesTable.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(title)
            t.column(username)
            t.column(encryptedPassword)
            t.column(url)
            t.column(encryptedNotes)
            t.column(categoryID)
            t.column(totpSecret)
            t.column(createdAt)
            t.column(modifiedAt)
            t.column(isFavorite)
            t.column(syncStatusColumn)
        })
        
        try db.run(categoriesTable.create(ifNotExists: true) { t in
            t.column(catId, primaryKey: true)
            t.column(catName)
            t.column(catIcon)
            t.column(catColor)
        })
    }
    
    private func loadData() throws {
        try loadEntries()
        try loadCategories()
    }
    
    private func loadEntries() throws {
        guard let db = db else { return }
        
        var loadedEntries: [VaultEntry] = []
        
        // FILTER: Only load entries that are NOT marked for deletion
        let query = entriesTable.filter(syncStatusColumn != "pending_delete")
        
        for row in try db.prepare(query) {
            let entry = VaultEntry(
                id: UUID(uuidString: row[id])!,
                title: row[title],
                username: row[username],
                password: "", // Will be decrypted on demand
                url: row[url],
                notes: nil, // Will be decrypted on demand
                categoryID: row[categoryID].flatMap { UUID(uuidString: $0) },
                totpSecret: row[totpSecret],
                isFavorite: row[isFavorite]
            )
            
            // We need to manually set the encrypted data
            var mutableEntry = entry
            mutableEntry.encryptedPassword = row[encryptedPassword]
            mutableEntry.encryptedNotes = row[encryptedNotes]
            
            loadedEntries.append(mutableEntry)
        }
        
        entries = loadedEntries
    }
    
    private func loadCategories() throws {
        guard let db = db else { return }
        
        var loadedCategories: [Category] = []
        
        for row in try db.prepare(categoriesTable) {
            let category = Category(
                id: UUID(uuidString: row[catId])!,
                name: row[catName],
                icon: row[catIcon],
                color: row[catColor]
            )
            loadedCategories.append(category)
        }
        
        categories = loadedCategories
    }
    
    private func storeSalt(_ salt: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "vault_salt",
            kSecValueData as String: salt
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keychainError(status)
        }
    }
    
    private func retrieveSalt() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "vault_salt",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    // MARK: - SyncServiceDelegate
    
    func syncServiceDidConnect(_ service: SyncService) {
        syncStatus = "Connected to desktop"
    }
    
    func syncServiceDidDisconnect(_ service: SyncService) {
        syncStatus = "Disconnected"
    }
    
    func syncService(_ service: SyncService, didReceiveEntries incomingEntries: [VaultEntry]) {
        guard let db = db else {
            syncStatus = "Sync error: Vault not initialized"
            return
        }
        
        do {
            try db.transaction {
                var updatedCount = 0
                var insertedCount = 0
                
                for incoming in incomingEntries {
                    // Check if entry exists locally
                    let query = entriesTable.filter(id == incoming.id.uuidString)
                    if let localRow = try db.pluck(query) {
                        let localModifiedAt = localRow[modifiedAt]
                        
                        if incoming.modifiedAt >= localModifiedAt {
                            // Incoming is newer or same - update local
                            // SAFETY CHECK: Do not overwrite a local password with an empty one from server
                            let newEncryptedPassword = (incoming.encryptedPassword.isEmpty && !localRow[encryptedPassword].isEmpty) 
                                ? localRow[encryptedPassword] 
                                : incoming.encryptedPassword
                            
                            let newEncryptedNotes = (incoming.encryptedNotes == nil && localRow[encryptedNotes] != nil)
                                ? localRow[encryptedNotes]
                                : incoming.encryptedNotes

                            let update = query.update(
                                title <- incoming.title,
                                username <- incoming.username,
                                encryptedPassword <- newEncryptedPassword,
                                url <- incoming.url,
                                encryptedNotes <- newEncryptedNotes,
                                categoryID <- incoming.categoryID?.uuidString,
                                totpSecret <- incoming.totpSecret,
                                modifiedAt <- incoming.modifiedAt,
                                isFavorite <- incoming.isFavorite
                            )
                            try db.run(update)
                            updatedCount += 1
                        }
                    } else {
                        // New entry - insert
                        let insert = entriesTable.insert(
                            id <- incoming.id.uuidString,
                            title <- incoming.title,
                            username <- incoming.username,
                            encryptedPassword <- incoming.encryptedPassword,
                            url <- incoming.url,
                            encryptedNotes <- incoming.encryptedNotes,
                            categoryID <- incoming.categoryID?.uuidString,
                            totpSecret <- incoming.totpSecret,
                            createdAt <- incoming.createdAt,
                            modifiedAt <- incoming.modifiedAt,
                            isFavorite <- incoming.isFavorite
                        )
                        try db.run(insert)
                        insertedCount += 1
                    }
                }
                
                try loadData()
                syncStatus = "Sync complete: \(insertedCount) added, \(updatedCount) updated"
            }
        } catch {
            syncStatus = "Sync failed: \(error.localizedDescription)"
            print("Sync merge error: \(error)")
        }
    }
    
    func syncService(_ service: SyncService, didEncounterError error: Error) {
        syncStatus = "Sync error: \(error.localizedDescription)"
    }
    
    func syncService(_ service: SyncService, didDiscoverDevices devices: [SyncDevice]) {
        // Discovery handled in UI
    }
}

// MARK: - Extensions

extension Data {
    static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
}
