import Foundation
import CryptoKit
import CommonCrypto
import LocalAuthentication

enum CryptoError: Error {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case biometricFailed
    case keychainError(OSStatus)
}

class CryptoService {
    static let shared = CryptoService()
    
    let systemIdentitySalt = "CLAWPASS_SYSTEM_SALT_2026".data(using: .utf8)!
    
    private let keychainService = "com.clawpass.databasekey"

    private let keychainAccount = "masterKey"
    
    // MARK: - Key Derivation
    
    func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        var derivedKeyData = Data(count: 32)
        
        let passwordData = Data(password.utf8)
        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(100000), // 100k iterations
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedKeyData)
    }
    
    // MARK: - Encryption
    
    func encrypt(_ plaintext: String, using key: SymmetricKey) throws -> Data {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }
        
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }
    
    func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }
        
        return plaintext
    }
    
    func sha256(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
    
    func deriveVaultId(password: String) -> String {
        let combined = Data(password.utf8) + systemIdentitySalt
        let digest = SHA256.hash(data: combined)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    
    // MARK: - Biometric Authentication

    /// True when this device can evaluate Face ID / Touch ID right now.
    var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    // MARK: - Keychain Master Password Storage
    //
    // The master password is kept only so Face ID can unlock the vault. The item is
    // bound to this device, only readable while the phone is unlocked, and protected by
    // the current biometric enrolment, so reading it prompts for Face ID / Touch ID and
    // is invalidated if fingerprints/faces are added.

    private let masterPasswordAccount = "vault_master_password"

    func saveMasterPasswordToKeychain(_ password: String) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil
        ) else {
            throw CryptoError.keychainError(errSecParam)
        }
        deleteMasterPasswordFromKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: masterPasswordAccount,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(password.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw CryptoError.keychainError(status)
        }
    }

    /// Whether a master password is stored for biometric unlock (never prompts).
    func hasSavedMasterPassword() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: masterPasswordAccount,
            kSecUseAuthenticationContext as String: context,
            kSecReturnAttributes as String: true
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Reads the stored master password. The Keychain itself shows the Face ID prompt
    /// using `reason`. Blocking; call off the main thread.
    func retrieveMasterPasswordFromKeychain(reason: String) throws -> String? {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: masterPasswordAccount,
            kSecUseAuthenticationContext as String: context,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        if status == errSecUserCanceled || status == errSecAuthFailed { throw CryptoError.biometricFailed }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CryptoError.keychainError(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteMasterPasswordFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: masterPasswordAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    /// Random password using the system CSPRNG, with at least one character from every
    /// selected class.
    func generatePassword(length: Int = 20,
                         useUppercase: Bool = true,
                         useLowercase: Bool = true,
                         useNumbers: Bool = true,
                         useSymbols: Bool = true) -> String {
        var pools: [[Character]] = []
        if useLowercase { pools.append(Array("abcdefghijkmnopqrstuvwxyz")) }
        if useUppercase { pools.append(Array("ABCDEFGHJKLMNPQRSTUVWXYZ")) }
        if useNumbers { pools.append(Array("23456789")) }
        if useSymbols { pools.append(Array("!@#$%^&*-_=+?")) }
        guard !pools.isEmpty else { return "" }

        let all = pools.flatMap { $0 }
        var rng = SystemRandomNumberGenerator()
        var chars: [Character] = pools.compactMap { $0.randomElement(using: &rng) }
        while chars.count < max(length, pools.count) {
            chars.append(all.randomElement(using: &rng)!)
        }
        chars.shuffle(using: &rng)
        return String(chars)
    }
}

// MARK: - One-time codes (TOTP, RFC 6238)

enum TOTP {
    struct Config {
        let secret: Data
        let digits: Int
        let period: Int
        let algorithm: String
    }

    /// Accepts a bare base32 setup key or an `otpauth://totp/...` link.
    static func parse(_ input: String) -> Config? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var secretText = trimmed
        var digits = 6
        var period = 30
        var algorithm = "SHA1"

        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let items = URLComponents(string: trimmed)?.queryItems else { return nil }
            func value(_ name: String) -> String? { items.first { $0.name.lowercased() == name }?.value }
            guard let secret = value("secret") else { return nil }
            secretText = secret
            if let d = value("digits").flatMap({ Int($0) }), (6...8).contains(d) { digits = d }
            if let p = value("period").flatMap({ Int($0) }), p > 0 { period = p }
            if let a = value("algorithm") { algorithm = a.uppercased() }
        }

        guard let secret = base32Decode(secretText), !secret.isEmpty else { return nil }
        return Config(secret: secret, digits: digits, period: period, algorithm: algorithm)
    }

    static func base32Decode(_ text: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer = 0
        var bits = 0
        var output = Data()
        for ch in text.uppercased() where ch != " " && ch != "-" && ch != "=" {
            guard let index = alphabet.firstIndex(of: ch) else { return nil }
            buffer = (buffer << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
                buffer &= (1 << bits) - 1
            }
        }
        return output
    }

    static func code(_ config: Config, at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(config.period)
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let key = SymmetricKey(data: config.secret)
        let mac: [UInt8]
        switch config.algorithm {
        case "SHA256": mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case "SHA512": mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        default: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        }
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<config.digits { modulus *= 10 }
        let number = Int(binary % modulus)
        return String(format: "%0\(config.digits)d", number)
    }
}
