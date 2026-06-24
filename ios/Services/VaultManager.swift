// MARK: - VERSION_SINCED_2026_06_23_FINAL_RECOVERY
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

    private var db: Connection?
    private var encryptionKey: SymmetricKey?
    private let cryptoService = CryptoService.shared
    private var syncService = SyncService.shared

    // Database Tables
    private let entriesTable = Table("entries")
    private let categoriesTable = Table("categories")
    private let tombstonesTable = Table("tombstones")
    private let settingsTable = Table("settings")

    // Entry Columns
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

    // Category Columns
    private let catId = Expression<String>("id")
    private let catName = Expression<String>("name")
    private let catIcon = Expression<String>("icon")
    private let catColor = Expression<String>("color")

    // Settings Columns
    private let settingId = Expression<String>("id")
    private let settingValue = Expression<Data>("value")

    // Tombstone Columns
    private let tombstoneId = Expression<String>("id")
    private let tombstoneTimestamp = Expression<Date>("timestamp")

    private var pendingSetupPassword: String?
    private var pendingUnlockPassword: String?

    init() {
        SyncService.shared.delegate = self
    }

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

    func initializeWithSalt(password: String, salt: [UInt8]) throws {
        guard db == nil else { throw VaultError.alreadyInitialized }
        let derivedVaultId = cryptoService.deriveVaultId(password: password)
        let fileManager = FileManager.default
        let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docDir.appendingPathComponent("vault_\(derivedVaultId).db")
        let path = fileURL.path

        if !fileManager.fileExists(atPath: docDir.path) {
            try fileManager.createDirectory(at: docDir, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: path) {
            let success = fileManager.createFile(atPath: path, contents: nil, attributes: nil)
            if !success {
                throw VaultError.databaseError(NSError(domain: "VaultError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create vault_\(derivedVaultId).db file"]))
            }
        }

        let saltData = Data(salt)
        let key = try cryptoService.deriveKey(from: password, salt: saltData)
        try storeSalt(saltData, for: derivedVaultId)

        do {
            db = try Connection(path)
            encryptionKey = key
            try createTables()

            let canary = "CLAWPASS_CANARY"
            let encryptedCanary = try cryptoService.encrypt(canary, using: key)
            try db?.run(settingsTable.insert(settingId <- "canary", settingValue <- encryptedCanary))
            try addCategory(Category.default)
            do { try db?.run(entriesTable.addColumn(syncStatusColumn, defaultValue: "synced")) } catch { }
            try loadData()
            verifyCurrentKey()
            SyncService.shared.setVaultId(derivedVaultId)
            DispatchQueue.main.async {
                self.saltReady = true
                self.objectWillChange.send()
            }
        } catch {
            db = nil
            encryptionKey = nil
            throw VaultError.databaseError(error)
        }
    }

    func unlock(with password: String, saltOverride: Data? = nil, skipHandshake: Bool = false, forceLock: Bool = true) throws {
        if forceLock { lock(silent: true) }
        let derivedVaultId = cryptoService.deriveVaultId(password: password)
        SyncService.shared.setVaultId(derivedVaultId)
        
        let salt = saltOverride ?? (try? retrieveSalt(for: derivedVaultId))
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("vault_\(derivedVaultId).db").path

        if !FileManager.default.fileExists(atPath: path) {
            throw VaultError.notInitialized
        }
        
        guard let salt = salt else {
            throw VaultError.notInitialized
        }

        let key = try cryptoService.deriveKey(from: password, salt: salt)
        do {
            let currentDb = try Connection(path)
            if let canaryRow = try currentDb.pluck(settingsTable.filter(settingId == "canary")) {
                let decrypted = try cryptoService.decrypt(canaryRow[settingValue], using: key)
                if decrypted == "CLAWPASS_CANARY" {
                    db = currentDb
                    encryptionKey = key
                    try loadData()
                    loadVaultName()
                    DispatchQueue.main.async {
                        self.isUnlocked = true
                        self.isFirstPopulationPending = true
                        self.isReady = true
                        self.keyStatus = ""
                        self.objectWillChange.send()
                    }
                    UserDefaults.standard.set(password, forKey: "vault_master_password")
                    syncService.delegate = self
                    if !skipHandshake { syncService.triggerHandshake() }
                    return
                } else {
                    throw VaultError.invalidPassword
                }
            } else {
                throw VaultError.notInitialized
            }
        } catch {
            throw error
        }
    }

    func getDebugInfo(password: String) {
        let derivedVaultId = cryptoService.deriveVaultId(password: password)
        guard let storedSalt = try? retrieveSalt(for: derivedVaultId) else {
            self.debugSaltHex = "NONE"; self.debugKeyHash = "NONE"; return
        }
        let key = try? cryptoService.deriveKey(from: password, salt: storedSalt)
        self.debugSaltHex = storedSalt.map { String(format: "%02x", $0) }.joined()
        if let k = key {
            let keyData = k.withUnsafeBytes { Data($0) }
            self.debugKeyHash = cryptoService.sha256(keyData).map { String(format: "%02x", $0) }.joined()
        } else {
            self.debugKeyHash = "DERIVATION_FAILED"
        }
    }

    func lock(silent: Bool = false) {
        syncService.disconnect()
        db = nil
        encryptionKey = nil
        entries = []
        categories = []
        if !silent {
            isUnlocked = false
            isReady = false
            isFirstPopulationPending = false
            keyStatus = "Unknown"
        }
    }

    func nuclearReset() {
        lock()
        do {
            let fileManager = FileManager.default
            let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let files = try fileManager.contentsOfDirectory(atPath: docDir.path)
            for file in files {
                if file.hasPrefix("vault_") && file.hasSuffix(".db") {
                    try fileManager.removeItem(atPath: docDir.appendingPathComponent(file).path)
                }
            }
            let query = [kSecClass: kSecClassGenericPassword] as [String: Any]
            SecItemDelete(query as CFDictionary)
            UserDefaults.standard.dictionaryRepresentation().keys.forEach { key in
                if key.hasPrefix("vault_salt_fallback_") {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            DispatchQueue.main.async {
                self.saltReady = false; self.isUnlocked = false; self.entries = []; self.categories = []; self.keyStatus = "Unknown"; self.objectWillChange.send()
            }
        } catch { print("[Vault] Nuclear Reset failed: \(error)") }
    }

    func verifyCurrentKey() -> String {
        guard let db = db, let key = encryptionKey else { return "No Key" }
        do {
            if let firstEntry = try db.pluck(entriesTable.filter(syncStatusColumn != "pending_delete")) {
                _ = try cryptoService.decrypt(firstEntry[encryptedPassword], using: key)
                return "Key Valid"
            } else {
                return "Empty Vault"
            }
        } catch { return "Key Mismatch" }
    }

    func addEntry(_ entry: VaultEntry, password: String, notes: String?) throws {
        guard let db = db, let key = encryptionKey else { throw VaultError.notInitialized }
        var entry = entry
        entry.encryptedPassword = try cryptoService.encrypt(password, using: key)
        if let notes = notes { entry.encryptedNotes = try cryptoService.encrypt(notes, using: key) }
        try db.run(entriesTable.insert(
            id <- entry.id.uuidString.lowercased(), title <- entry.title, username <- entry.username,
            encryptedPassword <- entry.encryptedPassword, url <- entry.url,
            encryptedNotes <- entry.encryptedNotes, categoryID <- entry.categoryID?.uuidString.lowercased(),
            totpSecret <- entry.totpSecret, createdAt <- entry.createdAt,
            modifiedAt <- entry.modifiedAt, isFavorite <- entry.isFavorite,
            syncStatusColumn <- "pending_update"
        ))
        try loadData(); refreshUI()
        syncService.sendEntryUpdate(entry: entry); syncService.flushOutbox()
    }

    func updateEntry(_ entry: VaultEntry, newPassword: String? = nil, newNotes: String? = nil) throws {
        guard let db = db, let key = encryptionKey else { throw VaultError.notInitialized }
        var encryptedPwd = entry.encryptedPassword
        var encryptedNts = entry.encryptedNotes
        if let p = newPassword { encryptedPwd = try cryptoService.encrypt(p, using: key) }
        if let n = newNotes { encryptedNts = try cryptoService.encrypt(n, using: key) }
        try db.run(entriesTable.filter(id == entry.id.uuidString.lowercased()).update(
            title <- entry.title, username <- entry.username, encryptedPassword <- encryptedPwd,
            url <- entry.url, encryptedNotes <- encryptedNts, categoryID <- entry.categoryID?.uuidString.lowercased(),
            totpSecret <- entry.totpSecret, modifiedAt <- Date(), isFavorite <- entry.isFavorite,
            syncStatusColumn <- "pending_update"
        ))
        try loadData(); refreshUI()
        var updated = entry
        updated.encryptedPassword = encryptedPwd
        updated.encryptedNotes = encryptedNts
        syncService.sendEntryUpdate(entry: updated); syncService.flushOutbox()
    }

    func deleteEntry(_ entry: VaultEntry) throws {
        guard let db = db else { throw VaultError.notInitialized }
        let entryIdLower = entry.id.uuidString.lowercased()
        let entryIdUpper = entry.id.uuidString.uppercased()
        try db.transaction {
            try db.run(entriesTable.filter(id == entryIdLower).delete())
            try db.run(entriesTable.filter(id == entryIdUpper).delete())
            try db.run(tombstonesTable.insert(tombstoneId <- entryIdLower, tombstoneTimestamp <- Date()))
        }
        try loadData(); refreshUI()
        syncService.sendEntryDelete(entryId: entryIdLower)
    }

    func decryptPassword(for entry: VaultEntry) throws -> String {
        guard let key = encryptionKey else { throw VaultError.notInitialized }
        return try cryptoService.decrypt(entry.encryptedPassword, using: key)
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

    func getPendingEntries(completion: @escaping ([VaultEntry], [String]) -> Void) {
        guard let db = db else { completion([], []); return }
        do {
            var updates: [VaultEntry] = []; var deletes: [String] = []
            for row in try db.prepare(entriesTable.filter(syncStatusColumn == "pending_update")) {
                let idS = row[id]
                if let uuid = UUID(uuidString: idS) {
                    let entry = VaultEntry(id: uuid, title: row[title], username: row[username], password: "", url: row[url], notes: nil, categoryID: row[categoryID].flatMap { UUID(uuidString: $0) }, totpSecret: row[totpSecret], isFavorite: row[isFavorite])
                    var mutable = entry
                    mutable.encryptedPassword = row[encryptedPassword]; mutable.encryptedNotes = row[encryptedNotes]; mutable.createdAt = row[createdAt]; mutable.modifiedAt = row[modifiedAt]
                    updates.append(mutable)
                }
            }
            for row in try db.prepare(tombstonesTable) { deletes.append(row[tombstoneId]) }
            completion(updates, deletes)
        } catch { completion([], []) }
    }

    private func createTables() throws {
        try db?.run(entriesTable.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true); t.column(title); t.column(username); t.column(encryptedPassword); t.column(url); t.column(encryptedNotes); t.column(categoryID); t.column(totpSecret); t.column(createdAt); t.column(modifiedAt); t.column(isFavorite); t.column(syncStatusColumn)
        })
        try db?.run(categoriesTable.create(ifNotExists: true) { t in
            t.column(catId, primaryKey: true); t.column(catName); t.column(catIcon); t.column(catColor)
        })
        try db?.run(settingsTable.create(ifNotExists: true) { t in
            t.column(settingId, primaryKey: true); t.column(settingValue)
        })
        try db?.run(tombstonesTable.create(ifNotExists: true) { t in
            t.column(tombstoneId, primaryKey: true); t.column(tombstoneTimestamp)
        })
    }

    private func loadDataInternal() throws -> [VaultEntry] {
        guard let db = db else { return [] }
        var loadedEntries: [VaultEntry] = []
        do {
            let rows = try db.prepare(entriesTable.filter(syncStatusColumn != "pending_delete"))
            for row in rows {
                let idString = row[id].lowercased()
                if let uuid = UUID(uuidString: idString) {
                    let entry = VaultEntry(id: uuid, title: row[title], username: row[username], password: "", url: row[url], notes: nil, categoryID: row[categoryID].flatMap { $0.lowercased() }.flatMap { UUID(uuidString: $0) }, totpSecret: row[totpSecret], isFavorite: row[isFavorite])
                    var mutable = entry
                    mutable.encryptedPassword = row[encryptedPassword]; mutable.encryptedNotes = row[encryptedNotes]; mutable.createdAt = row[createdAt]; mutable.modifiedAt = row[modifiedAt]
                    loadedEntries.append(mutable)
                }
            }
        } catch { throw error }
        return loadedEntries
    }

    func updateVaultName(_ name: String) throws {
        guard let db = db else { throw VaultError.notInitialized }
        try db.run(settingsTable.insert(or: .replace, settingId <- "vault_name", settingValue <- Data(name.utf8)))
        self.vaultName = name
        self.objectWillChange.send()
    }

    private func loadVaultName() {
        guard let db = db else { return }
        if let row = try? db.pluck(settingsTable.filter(settingId == "vault_name")) {
            let data = row[settingValue]
            if let name = String(data: data, encoding: .utf8) {
                self.vaultName = name
            }
        }
    }

    private func loadData() throws {
        guard let db = db else { return }
        var loadedEntries: [VaultEntry] = []
        do {
            let rows = try db.prepare(entriesTable.filter(syncStatusColumn != "pending_delete"))
            for row in rows {
                let idString = row[id].lowercased()
                if let uuid = UUID(uuidString: idString) {
                    let entry = VaultEntry(id: uuid, title: row[title], username: row[username], password: "", url: row[url], notes: nil, categoryID: row[categoryID].flatMap { $0.lowercased() }.flatMap { UUID(uuidString: $0) }, totpSecret: row[totpSecret], isFavorite: row[isFavorite])
                    var mutable = entry
                    mutable.encryptedPassword = row[encryptedPassword]; mutable.encryptedNotes = row[encryptedNotes]; mutable.createdAt = row[createdAt]; mutable.modifiedAt = row[modifiedAt]
                    loadedEntries.append(mutable)
                }
            }
        } catch { throw error }
        var loadedCats: [Category] = []
        let favoritesCat = Category(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "Favorites", icon: "star.fill", color: "#FFD700")
        loadedCats.append(favoritesCat)
        for row in try db.prepare(categoriesTable) {
            let catIdStr = row[catId].lowercased()
            if let uuid = UUID(uuidString: catIdStr) {
                loadedCats.append(Category(id: uuid, name: row[catName], icon: row[catIcon], color: row[catColor]))
            }
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

    @Published var lastSyncUpdate: Date = Date()

    func refreshUI() {
        DispatchQueue.main.async {
            self.lastSyncUpdate = Date()
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .vaultDataChanged, object: nil)
        }
    }

    func storeSalt(_ salt: Data, for vaultId: String) throws {
        let account = "vault_salt_\(vaultId)"
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecValueData: salt] as [String: Any]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
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

    func syncServiceDidConnect(_ service: SyncService) { DispatchQueue.main.async { self.syncStatus = "Connected" } }
    func syncServiceDidDisconnect(_ service: SyncService) { DispatchQueue.main.async { self.syncStatus = "Disconnected" } }

    func syncService(_ service: SyncService, didReceiveSyncEntries incoming: [SyncVaultEntry], timestamp: Int64) {
        guard let db = db, let key = encryptionKey else { return }
        do {
            try db.transaction {
                for syncEntry in incoming {
                    do {
                        _ = try cryptoService.decrypt(Data(syncEntry.encrypted_password), using: key)
                        try self.applySyncUpdate(entry: syncEntry)
                    } catch { }
                }
            }
            let updatedEntries = try loadDataInternal()
            DispatchQueue.main.async {
                self.entries = updatedEntries
                self.isFirstPopulationPending = false
                self.vaultSyncStatus = "Last sync: \(timestamp)"
                self.objectWillChange.send()
            }
        } catch { }
    }

    func syncService(_ service: SyncService, didReceiveCategories categories: [SyncCategory]) {
        guard let db = db else { return }
        do {
            try db.transaction {
                for cat in categories {
                    let existing = try db.pluck(categoriesTable.filter(catId == cat.id))
                    if existing == nil { try db.run(categoriesTable.insert(catId <- cat.id, catName <- cat.name, catIcon <- cat.icon, catColor <- cat.color)) }
                    else if (existing![catName] != cat.name || existing![catIcon] != cat.icon || existing![catColor] != cat.color) {
                        try db.run(categoriesTable.filter(catId == cat.id).update(catName <- cat.name, catIcon <- cat.icon, catColor <- cat.color))
                    }
                }
            }
            refreshUI()
        } catch { }
    }

    func syncService(_ service: SyncService, didReceiveTombstones deletedIds: [String]) {
        guard let db = db else { return }
        do {
            try db.transaction {
                for entryId in deletedIds { try db.run(entriesTable.filter(id == entryId.lowercased()).delete()) }
            }
            try loadData()
            refreshUI()
        } catch { }
    }

    func syncServiceDidReceiveSalt(_ service: SyncService, salt: [UInt8]) {
        DispatchQueue.main.async {
            self.keyStatus = ""
            let serverSaltData = Data(salt)
            do {
                let currentVaultId = SyncService.shared.vaultId
                if let localSalt = try self.retrieveSalt(for: currentVaultId) {
                    if localSalt != serverSaltData { try self.storeSalt(serverSaltData, for: currentVaultId) }
                } else { try self.storeSalt(serverSaltData, for: currentVaultId) }
                self.debugSaltHex = serverSaltData.map { String(format: "%02x", $0) }.joined()
                if let password = self.pendingSetupPassword {
                    do {
                        try self.initializeWithSalt(password: password, salt: salt)
                        try self.unlock(with: password, skipHandshake: true, forceLock: false)
                        self.pendingSetupPassword = nil
                        self.isFirstPopulationPending = false
                        DispatchQueue.main.async { self.isUnlocked = true; self.objectWillChange.send() }
                        if self.db != nil { SyncService.shared.startFullSyncPipeline() }
                    } catch { self.isFirstPopulationPending = false }
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
    
    private func applySyncUpdate(entry: SyncVaultEntry) throws {
        guard let db = db else { throw VaultError.notInitialized }
        let entryIdLower = entry.id.lowercased()
        if try db.scalar(entriesTable.filter(id == entryIdLower).count) > 0 {
            try db.run(entriesTable.filter(id == entryIdLower).update(
                title <- entry.title, username <- entry.username,
                encryptedPassword <- Data(entry.encrypted_password), url <- entry.url,
                encryptedNotes <- entry.encrypted_notes.map { Data($0) },
                categoryID <- entry.category_id, totpSecret <- entry.totp_secret,
                createdAt <- Date(timeIntervalSince1970: TimeInterval(entry.created_at)),
                modifiedAt <- Date(timeIntervalSince1970: TimeInterval(entry.modified_at)),
                isFavorite <- entry.is_favorite, syncStatusColumn <- "synced"
            ))
        } else {
            try db.run(entriesTable.insert(
                id <- entryIdLower, title <- entry.title, username <- entry.username,
                encryptedPassword <- Data(entry.encrypted_password), url <- entry.url,
                encryptedNotes <- entry.encrypted_notes.map { Data($0) },
                categoryID <- entry.category_id, totpSecret <- entry.totp_secret,
                createdAt <- Date(timeIntervalSince1970: TimeInterval(entry.created_at)),
                modifiedAt <- Date(timeIntervalSince1970: TimeInterval(entry.modified_at)),
                isFavorite <- entry.is_favorite, syncStatusColumn <- "synced"
            ))
        }
    }
}

extension Data {
    static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
}
