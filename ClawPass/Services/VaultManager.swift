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
    case decryptionFailed
}

extension Notification.Name {
    static let vaultDataChanged = Notification.Name("vaultDataChanged")
}

class VaultManager: ObservableObject, SyncServiceDelegate {
    static let shared = VaultManager()
    
    @Published private(set) var isUnlocked = false
    @Published var entries: [VaultEntry] = []
    @Published private(set) var categories: [Category] = []
    @Published var syncStatus: String = ""
    @Published private(set) var vaultSyncStatus: String = ""
    @Published var keyStatus: String = "Unknown"
    
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
    
    private init() {}
    
    func initialize(with password: String) throws {
        guard db == nil else { throw VaultError.alreadyInitialized }
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("vault.db").path
        let salt = Data.randomBytes(count: 32)
        let key = try cryptoService.deriveKey(from: password, salt: salt)
        let verifyHash = cryptoService.sha256(key)
        var saltWithHash = salt
        saltWithHash.append(verifyHash)
        try storeSalt(saltWithHash)
        db = try Connection(path)
        encryptionKey = key
        try createTables()
        do {
            try db?.run(entriesTable.addColumn(syncStatusColumn, defaultValue: "synced"))
        } catch {
            print("[Vault] Sync status column exists")
        }
        try addCategory(Category.default)
        isUnlocked = true
        try loadData()
    }
    
    func unlock(with password: String) throws {
        guard db == nil else { return }
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("vault.db").path
        guard let saltWithHash = try retrieveSalt() else { throw VaultError.notInitialized }
        let salt = saltWithHash.count >= 64 ? Data(saltWithHash.prefix(saltWithHash.count - 32)) : saltWithHash
        let storedHash = saltWithHash.count >= 64 ? Data(saltWithHash.suffix(32)) : nil
        let key = try cryptoService.deriveKey(from: password, salt: salt)
        if let expectedHash = storedHash {
            if cryptoService.sha256(key) != expectedHash { throw VaultError.invalidPassword }
        }
        do {
            db = try Connection(path)
            encryptionKey = key
            try loadData()
            isUnlocked = true
            UserDefaults.standard.set(password, forKey: "vault_master_password")
            syncService.delegate = self
            
            // Verify key immediately
            verifyCurrentKey()
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
    
    // MARK: - Key Validation
    func verifyCurrentKey() {
        guard let db = db, let key = encryptionKey else { 
            DispatchQueue.main.async { self.keyStatus = "No Key" }
            return 
        }
        
        do {
            if let firstEntry = try db.pluck(entriesTable.filter(syncStatusColumn != "pending_delete")) {
                let encryptedPwd = firstEntry[encryptedPassword]
                _ = try cryptoService.decrypt(encryptedPwd, using: key)
                DispatchQueue.main.async { self.keyStatus = "Key Valid" }
            } else {
                DispatchQueue.main.async { self.keyStatus = "Empty Vault" }
            }
        } catch {
            print("[Vault] Key Validation Failed: \(error)")
            DispatchQueue.main.async { self.keyStatus = "Key Mismatch" }
        }
    }
    
    // MARK: - CRUD
    func addEntry(_ entry: VaultEntry, password: String, notes: String?) throws {
        guard let db = db, let key = encryptionKey else { throw VaultError.notInitialized }
        var entry = entry
        entry.encryptedPassword = try cryptoService.encrypt(password, using: key)
        if let notes = notes { entry.encryptedNotes = try cryptoService.encrypt(notes, using: key) }
        
        try db.run(entriesTable.insert(
            id <- entry.id.uuidString, title <- entry.title, username <- entry.username,
            encryptedPassword <- entry.encryptedPassword, url <- entry.url,
            encryptedNotes <- entry.encryptedNotes, categoryID <- entry.categoryID?.uuidString,
            totpSecret <- entry.totpSecret, createdAt <- entry.createdAt,
            modifiedAt <- entry.modifiedAt, isFavorite <- entry.isFavorite,
            syncStatusColumn <- "pending_update"
        ))
        refreshUI()
        syncService.sendEntryUpdate(entry: entry)
    }
    
    func updateEntry(_ entry: VaultEntry, newPassword: String? = nil, newNotes: String? = nil) throws {
        guard let db = db, let key = encryptionKey else { throw VaultError.notInitialized }
        var encryptedPwd = entry.encryptedPassword
        var encryptedNts = entry.encryptedNotes
        if let p = newPassword { encryptedPwd = try cryptoService.encrypt(p, using: key) }
        if let n = newNotes { encryptedNts = try cryptoService.encrypt(n, using: key) }
        
        try db.run(entriesTable.filter(id == entry.id.uuidString).update(
            title <- entry.title, username <- entry.username, encryptedPassword <- encryptedPwd,
            url <- entry.url, encryptedNotes <- encryptedNts, categoryID <- entry.categoryID?.uuidString,
            totpSecret <- entry.totpSecret, modifiedAt <- Date(), isFavorite <- entry.isFavorite,
            syncStatusColumn <- "pending_update"
        ))
        refreshUI()
        var updated = entry
        updated.encryptedPassword = encryptedPwd
        updated.encryptedNotes = encryptedNts
        syncService.sendEntryUpdate(entry: updated)
    }
    
    func deleteEntry(_ entry: VaultEntry) throws {
        guard let db = db else { throw VaultError.notInitialized }
        try db.run(entriesTable.filter(id == entry.id.uuidString).update(syncStatusColumn <- "pending_delete"))
        refreshUI()
        syncService.sendEntryDelete(entryId: entry.id.uuidString)
    }
    
    func decryptPassword(for entry: VaultEntry) throws -> String {
        guard let key = encryptionKey else { 
            print("[Vault] Decrypt failed: No key")
            throw VaultError.notInitialized 
        }
        do {
            return try cryptoService.decrypt(entry.encryptedPassword, using: key)
        } catch {
            print("[Vault] Decryption failed for entry \(entry.id)")
            throw VaultError.decryptionFailed
        }
    }
    
    func decryptNotes(for entry: VaultEntry) throws -> String? {
        guard let key = encryptionKey, let notes = entry.encryptedNotes else { return nil }
        return try cryptoService.decrypt(notes, using: key)
    }
    
    func addCategory(_ category: Category) throws {
        guard let db = db else { throw VaultError.notInitialized }
        try db.run(categoriesTable.insert(catId <- category.id.uuidString, catName <- category.name, catIcon <- category.icon, catColor <- category.color))
        refreshUI()
    }
    
    // MARK: - Outbox
    func getPendingEntries(completion: @escaping ([VaultEntry], [String]) -> Void) {
        guard let db = db else { completion([], []); return }
        do {
            var updates: [VaultEntry] = []
            var deletes: [String] = []
            for row in try db.prepare(entriesTable.filter(syncStatusColumn == "pending_update")) {
                let entry = VaultEntry(id: UUID(uuidString: row[id])!, title: row[title], username: row[username], password: "", url: row[url], notes: nil, categoryID: row[categoryID].flatMap { UUID(uuidString: $0) }, totpSecret: row[totpSecret], isFavorite: row[isFavorite])
                var mutable = entry
                mutable.encryptedPassword = row[encryptedPassword]
                mutable.encryptedNotes = row[encryptedNotes]
                mutable.createdAt = row[createdAt]; mutable.modifiedAt = row[modifiedAt]
                updates.append(mutable)
            }
            for row in try db.prepare(entriesTable.filter(syncStatusColumn == "pending_delete")) { deletes.append(row[id]) }
            completion(updates, deletes)
        } catch { completion([], []) }
    }
    
    func markAsSynced(entryId: String) {
        guard let db = db else { return }
        try? db.run(entriesTable.filter(id == entryId).update(syncStatusColumn <- "synced"))
    }
    
    func finalizeDelete(entryId: String) {
        guard let db = db else { return }
        try? db.run(entriesTable.filter(id == entryId).delete())
        refreshUI()
    }
    
    func updateSaltAndReKey(salt: [UInt8]) {
        guard let password = UserDefaults.standard.string(forKey: "vault_master_password") else { return }
        do {
            let saltData = Data(salt)
            let key = try cryptoService.deriveKey(from: password, salt: saltData)
            let verifyHash = cryptoService.sha256(key)
            
            var saltWithHash = saltData
            saltWithHash.append(verifyHash)
            
            // CRITICAL: Persist the updated salt to keychain so it survives restarts
            try storeSalt(saltWithHash)
            
            self.encryptionKey = key
            print("[Vault] Key re-derived and salt persisted via sync salt")
            verifyCurrentKey()
            refreshUI()
        } catch { print("[Vault] Re-key failed: \(error)") }
    }
    
    func syncCategories(_ categories: [SyncCategory]) {
        guard let db = db else { return }
        do {
            try db.transaction {
                for cat in categories {
                    let query = categoriesTable.filter(catId == cat.id)
                    if try db.pluck(query) != nil {
                        try db.run(query.update(catName <- cat.name, catIcon <- cat.icon, catColor <- cat.color))
                    } else {
                        try db.run(categoriesTable.insert(catId <- cat.id, catName <- cat.name, catIcon <- cat.icon, catColor <- cat.color))
                    }
                }
                refreshUI()
            }
        } catch { print("[Vault] Cat sync failed: \(error)") }
    }
    
    private func createTables() throws {
        guard let db = db else { return }
        try db.run(entriesTable.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true); t.column(title); t.column(username); t.column(encryptedPassword); t.column(url); t.column(encryptedNotes); t.column(categoryID); t.column(totpSecret); t.column(createdAt); t.column(modifiedAt); t.column(isFavorite); t.column(syncStatusColumn)
        })
        try db.run(categoriesTable.create(ifNotExists: true) { t in
            t.column(catId, primaryKey: true); t.column(catName); t.column(catIcon); t.column(catColor)
        })
    }
    
    private func refreshUI() {
        DispatchQueue.main.async {
            do {
                try self.loadData()
                self.objectWillChange.send()
                NotificationCenter.default.post(name: .vaultDataChanged, object: nil)
            } catch { print("[Vault] refreshUI failed: \(error)") }
        }
    }
    
    private func loadData() throws {
        try loadEntries()
        try loadCategories()
    }
    
    private func loadEntries() throws {
        guard let db = db else { return }
        var loaded: [VaultEntry] = []
        let query = entriesTable.filter(syncStatusColumn != "pending_delete")
        for row in try db.prepare(query) {
            var entry = VaultEntry(id: UUID(uuidString: row[id])!, title: row[title], username: row[username], password: "", url: row[url], notes: nil, categoryID: row[categoryID].flatMap { UUID(uuidString: $0) }, totpSecret: row[totpSecret], isFavorite: row[isFavorite])
            entry.encryptedPassword = row[encryptedPassword]
            entry.encryptedNotes = row[encryptedNotes]
            entry.createdAt = row[createdAt]; entry.modifiedAt = row[modifiedAt]
            loaded.append(entry)
        }
        self.entries = loaded
    }
    
    private func loadCategories() throws {
        guard let db = db else { return }
        var loaded: [Category] = []
        for row in try db.prepare(categoriesTable) {
            loaded.append(Category(id: UUID(uuidString: row[catId])!, name: row[catName], icon: row[catIcon], color: row[catColor]))
        }
        self.categories = loaded
    }
    
    private func storeSalt(_ salt: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "vault_salt", kSecValueData as String: salt]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { throw VaultError.keychainError(status) }
    }
    
    private func retrieveSalt() throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "vault_salt", kSecReturnData as String: true]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }
    
    func syncServiceDidConnect(_ service: SyncService) { DispatchQueue.main.async { self.syncStatus = "Connected" } }
    func syncServiceDidDisconnect(_ service: SyncService) { DispatchQueue.main.async { self.syncStatus = "Disconnected" } }
    
    func syncService(_ service: SyncService, didReceiveEntries incoming: [VaultEntry]) {
        guard let db = db else { return }
        do {
            try db.transaction {
                for entry in incoming {
                    let query = entriesTable.filter(id == entry.id.uuidString)
                    if let local = try db.pluck(query) {
                        if entry.modifiedAt >= local[modifiedAt] && local[syncStatusColumn] != "pending_delete" {
                            try db.run(query.update(title <- entry.title, username <- entry.username, encryptedPassword <- entry.encryptedPassword, url <- entry.url, encryptedNotes <- entry.encryptedNotes, categoryID <- entry.categoryID?.uuidString, totpSecret <- entry.totpSecret, modifiedAt <- entry.modifiedAt, isFavorite <- entry.isFavorite, syncStatusColumn <- "synced"))
                        }
                    } else if try db.pluck(query) == nil {
                        try db.run(entriesTable.insert(id <- entry.id.uuidString, title <- entry.title, username <- entry.username, encryptedPassword <- entry.encryptedPassword, url <- entry.url, encryptedNotes <- entry.encryptedNotes, categoryID <- entry.categoryID?.uuidString, totpSecret <- entry.totpSecret, createdAt <- entry.createdAt, modifiedAt <- entry.modifiedAt, isFavorite <- entry.isFavorite, syncStatusColumn <- "synced"))
                    }
                }
                refreshUI()
            }
            DispatchQueue.main.async { self.syncStatus = "Sync Complete" }
        } catch {
            print("[Vault] Sync Merge Error: \(error)")
        }
    }
    
    func syncService(_ service: SyncService, didEncounterError error: Error) { DispatchQueue.main.async { self.syncStatus = "Error: \(error.localizedDescription)" } }
    func syncService(_ service: SyncService, didDiscoverDevices devices: [SyncDevice]) { }
}

extension Data {
    static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
}
