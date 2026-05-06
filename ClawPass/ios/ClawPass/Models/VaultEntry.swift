import Foundation
import CryptoKit

struct VaultEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var username: String
    var encryptedPassword: Data
    var url: String?
    var encryptedNotes: Data?
    var categoryID: UUID?
    var totpSecret: String?
    var createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    
    init(id: UUID = UUID(),
         title: String,
         username: String,
         password: String,
         url: String? = nil,
         notes: String? = nil,
         categoryID: UUID? = nil,
         totpSecret: String? = nil,
         isFavorite: Bool = false) {
        self.id = id
        self.title = title
        self.username = username
        self.url = url
        self.categoryID = categoryID
        self.totpSecret = totpSecret
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFavorite = isFavorite
        
        // These will be encrypted by the VaultManager
        self.encryptedPassword = Data()
        self.encryptedNotes = nil
    }
}

struct Category: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String // SF Symbol name
    var color: String // Hex color
    
    static let `default` = Category(
        id: UUID(),
        name: "All Items",
        icon: "key.fill",
        color: "#007AFF"
    )
}

struct VaultSettings: Codable {
    var autoLockTimeout: TimeInterval = 300 // 5 minutes
    var clearClipboardDelay: TimeInterval = 30 // 30 seconds
    var defaultPasswordLength: Int = 16
    var useSymbols: Bool = true
    var useNumbers: Bool = true
    var useUppercase: Bool = true
}
