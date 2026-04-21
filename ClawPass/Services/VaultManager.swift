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
        
        // Store salt in keychain
        try storeSalt(salt)
        
        // Open encrypted database
        db = try Connection(path)
        encryptionKey = key
        
        // Create tables
        try createTables()
        
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
        
        // Retrieve stored salt
        guard let salt = try retrieveSalt() else {
            throw VaultError.notInitialized
        }
        
        // Derive key and try to open database
        let key = try cryptoService.deriveKey(from: password, salt: salt)
        
        do {
            db = try Connection(path)
            encryptionKey = key
            try loadData()
            isUnlocked = true
            
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
            throw VaultError.notInitialized
        }
        
        var entry = entry
        entry.encryptedPassword = try cryptoService.encrypt(password, using: key)
        if let notes = notes {
            entry.encryptedNotes = try cryptoService.encrypt(notes, using: key)
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
            isFavorite <- entry.isFavorite
        )
        
        try db.run(insert)
        try loadData()
    }
    
    func updateEntry(_ entry: VaultEntry, newPassword: String? = nil, newNotes: String? = nil) throws {
        guard let db = db, let key = encryptionKey else {
            throw VaultError.notInitialized
        }
        
        var encryptedPwd = entry.encryptedPassword
        var encryptedNts = entry.encryptedNotes
        
        if let newPassword = newPassword {
            encryptedPwd = try cryptoService.encrypt(newPassword, using: key)
        }
        if let newNotes = newNotes {
            encryptedNts = try cryptoService.encrypt(newNotes, using: key)
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
            isFavorite <- entry.isFavorite
        )
        
        try db.run(update)
        try loadData()
    }
    
    func deleteEntry(_ entry: VaultEntry) throws {
        guard let db = db else { throw VaultError.notInitialized }
        
        let entryRow = entriesTable.filter(id == entry.id.uuidString)
        try db.run(entryRow.delete())
        try loadData()
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
    
    // MARK: - Private Methods
    
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
        
        for row in try db.prepare(entriesTable) {
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
    
    func syncService(_ service: SyncService, didReceiveEntries entries: [VaultEntry]) {
        // Merge incoming entries with local entries
        // For now, just log it
        syncStatus = "Received \(entries.count) entries from desktop"
        
        // TODO: Implement proper merge logic
        // - Check timestamps to determine which entry is newer
        // - Add new entries, update existing ones
        // - Handle conflicts (same ID, different content)
    }
    
    func syncService(_ service: SyncService, didEncounterError error: Error) {
        syncStatus = "Sync error: \(error.localizedDescription)"
    }
    
    func syncService(_ service: SyncService, didDiscoverDevices devices: [SyncDevice]) {
        // Discovery handled in UI
    }
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
