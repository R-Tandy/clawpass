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
    
    // MARK: - Biometric Authentication
    
    func authenticateWithBiometric(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            throw CryptoError.biometricFailed
        }
    }
    
    // MARK: - Password Generation
    
    func generatePassword(length: Int = 16,
                         useUppercase: Bool = true,
                         useLowercase: Bool = true,
                         useNumbers: Bool = true,
                         useSymbols: Bool = true) -> String {
        var characters = ""
        
        if useLowercase { characters += "abcdefghijklmnopqrstuvwxyz" }
        if useUppercase { characters += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        if useNumbers { characters += "0123456789" }
        if useSymbols { characters += "!@#$%^&*()_+-=[]{}|;:,.<>?" }
        
        guard !characters.isEmpty else { return "" }
        
        var password = ""
        var rng = SystemRandomNumberGenerator()
        
        for _ in 0..<length {
            let randomIndex = Int.random(in: 0..<characters.count, using: &rng)
            let index = characters.index(characters.startIndex, offsetBy: randomIndex)
            password.append(characters[index])
        }
        
        return password
    }
}
