// SINCED_VERSION_2026_05_14_CATEGORIES_SLEDGEHAMMER
import Foundation
import Network
import CryptoKit
import UIKit

// MARK: - Sync Packet (Matches Desktop Wrapper)
struct SyncPacket: Codable {
    let deviceId: String
    let message: SyncMessage
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case message
    }
}

// MARK: - Sync Message Protocol (Matches Desktop)
enum SyncMessage: Codable {
    case handshake(deviceId: String, version: UInt32, vaultId: String)
    case syncRequest(lastTimestamp: Int64)
    case syncResponse(entries: [SyncVaultEntry], timestamp: Int64)
    case entryUpdate(entry: SyncVaultEntry)
    case entryDelete(entryId: String)
    case ack
    case ping
    case pong
    case error(message: String)
    case requestSalt(vaultId: String)
    case saltResponse(salt: [UInt8])
    case requestCategories(vaultId: String)
    case categoriesResponse(categories: [SyncCategory])
    
    enum CodingKeys: String, CodingKey {
        case type
        case device_id = "device_id"
        case version
        case vault_id = "vault_id"
        case last_timestamp = "last_timestamp"
        case entries
        case timestamp
        case entry
        case entry_id = "entry_id"
        case salt
        case categories
        case message
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .handshake(let deviceId, let version, let vaultId):
            try container.encode("handshake", forKey: .type)
            try container.encode(deviceId, forKey: .device_id)
            try container.encode(version, forKey: .version)
            try container.encode(vaultId, forKey: .vault_id)
        case .syncRequest(let lastTimestamp):
            try container.encode("sync_request", forKey: .type)
            try container.encode(lastTimestamp, forKey: .last_timestamp)
        case .syncResponse(let entries, let timestamp):
            try container.encode("sync_response", forKey: .type)
            try container.encode(entries, forKey: .entries)
            try container.encode(timestamp, forKey: .timestamp)
        case .entryUpdate(let entry):
            try container.encode("entry_update", forKey: .type)
            try container.encode(entry, forKey: .entry)
        case .entryDelete(let entryId):
            try container.encode("entry_delete", forKey: .type)
            try container.encode(entryId, forKey: .entry_id)
        case .ack:
            try container.encode("ack", forKey: .type)
        case .ping:
            try container.encode("ping", forKey: .type)
        case .pong:
            try container.encode("pong", forKey: .type)
        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        case .requestSalt(let vaultId):
            try container.encode("request_salt", forKey: .type)
            try container.encode(vaultId, forKey: .vault_id)
        case .saltResponse(let salt):
            try container.encode("salt_response", forKey: .type)
            try container.encode(salt, forKey: .salt)
        case .requestCategories(let vaultId):
            try container.encode("request_categories", forKey: .type)
            try container.encode(vaultId, forKey: .vault_id)
        case .categoriesResponse(let categories):
            try container.encode("categories_response", forKey: .type)
            try container.encode(categories, forKey: .categories)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "handshake":
            let deviceId = try container.decode(String.self, forKey: .device_id)
            let version = try container.decode(UInt32.self, forKey: .version)
            let vaultId = try container.decode(String.self, forKey: .vault_id)
            self = .handshake(deviceId: deviceId, version: version, vaultId: vaultId)
        case "sync_request":
            let lastTimestamp = try container.decode(Int64.self, forKey: .last_timestamp)
            self = .syncRequest(lastTimestamp: lastTimestamp)
        case "sync_response":
            let entries = try container.decode([SyncVaultEntry].self, forKey: .entries)
            let timestamp = try container.decode(Int64.self, forKey: .timestamp)
            self = .syncResponse(entries: entries, timestamp: timestamp)
        case "entry_update":
            let entry = try container.decode(SyncVaultEntry.self, forKey: .entry)
            self = .entryUpdate(entry: entry)
        case "entry_delete":
            let entryId = try container.decode(String.self, forKey: .entry_id)
            self = .entryDelete(entryId: entryId)
        case "ack":
            self = .ack
        case "ping":
            self = .ping
        case "pong":
            self = .pong
        case "error":
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message: message)
        case "request_salt":
            let vaultId = try container.decode(String.self, forKey: .vault_id)
            self = .requestSalt(vaultId: vaultId)
        case "salt_response":
            let salt = try container.decode([UInt8].self, forKey: .salt)
            self = .saltResponse(salt: salt)
        case "request_categories":
            let vaultId = try container.decode(String.self, forKey: .vault_id)
            self = .requestCategories(vaultId: vaultId)
        case "categories_response":
            let categories = try container.decode([SyncCategory].self, forKey: .categories)
            self = .categoriesResponse(categories: categories)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }
}

struct SyncCategory: Codable {
    let id: String
    let name: String
    let icon: String
    let color: String
}

struct SyncVaultEntry: Codable {
    let id: String
    let title: String
    let username: String
    let encrypted_password: [UInt8]
    let url: String?
    let encrypted_notes: [UInt8]?
    let category_id: String?
    let totp_secret: String?
    let created_at: Int64
    let modified_at: Int64
    let is_favorite: Bool
    
    init(id: String, title: String, username: String, password: String, url: String?, notes: String?, categoryId: String?, totpSecret: String?, createdAt: Int64, modifiedAt: Int64, isFavorite: Bool) {
        self.id = id
        self.title = title
        self.username = username
        self.encrypted_password = Array(password.utf8)
        self.url = url
        self.encrypted_notes = notes.map { Array($0.utf8) }
        self.category_id = categoryId
        self.totp_secret = totpSecret
        self.created_at = createdAt
        self.modified_at = modifiedAt
        self.is_favorite = isFavorite
    }
    
    init(from entry: VaultEntry, vaultKey: SymmetricKey) throws {
        self.id = entry.id.uuidString
        self.title = entry.title
        self.username = entry.username
        self.encrypted_password = entry.encryptedPassword.map { UInt8($0) }
        self.url = entry.url
        self.encrypted_notes = entry.encryptedNotes?.map { UInt8($0) }
        self.category_id = entry.categoryID?.uuidString
        self.totp_secret = entry.totpSecret
        self.created_at = Int64(entry.createdAt.timeIntervalSince1970)
        self.modified_at = Int64(entry.modifiedAt.timeIntervalSince1970)
        self.is_favorite = entry.isFavorite
    }
    
    func toVaultEntry() throws -> VaultEntry {
        guard let uuid = UUID(uuidString: self.id) else { throw SyncError.invalidEntryId }
        let categoryUUID = self.category_id.flatMap { UUID(uuidString: $0) }
        var entry = VaultEntry(
            id: uuid, title: self.title, username: self.username, password: "",
            url: self.url, notes: nil, categoryID: categoryUUID, totpSecret: self.totp_secret, isFavorite: self.is_favorite
        )
        entry.encryptedPassword = Data(self.encrypted_password)
        entry.encryptedNotes = self.encrypted_notes.map { Data($0) }
        return entry
    }
}

enum SyncError: Error {
    case invalidEntryId, notConnected, authenticationFailed, encodingFailed, decodingFailed, networkError(Error)
}

protocol SyncServiceDelegate: AnyObject {
    func syncServiceDidConnect(_ service: SyncService)
    func syncServiceDidDisconnect(_ service: SyncService)
    func syncService(_ service: SyncService, didReceiveEntries entries: [VaultEntry])
    func syncService(_ service: SyncService, didEncounterError error: Error)
    func syncService(_ service: SyncService, didDiscoverDevices devices: [SyncDevice])
}

let currentProtocolVersion: UInt32 = 2

struct SyncDevice: Identifiable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint
    let host: String
    let port: UInt16
}

// Global diagnostic buffer to bypass instance shadowing
var GLOBAL_SYNC_DIAGNOSTIC: String = "No data yet"

class SyncService: ObservableObject {
    static let shared = SyncService()
    @Published var isConnected = false
    @Published var isDiscovering = false
    @Published var discoveredDevices: [SyncDevice] = []
    @Published var lastSyncTimestamp: Int64 = 0
    @Published var syncStatus: String = "Idle"
    private var handshakeCompleted = false
    weak var delegate: SyncServiceDelegate?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let syncQueue = DispatchQueue(label: "com.clawpass.sync", qos: .userInitiated)
    private var deviceId: String { UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString }
    private let serviceType = "_clawpass._tcp"
    
    init() {
        let savedHost = UserDefaults.standard.string(forKey: "last_sync_host") ?? ""
        let savedPort = UserDefaults.standard.string(forKey: "last_sync_port") ?? "7878"
        print("[SINCED] Loaded last connection: \(savedHost):\(savedPort)")
    }
    
    func startDiscovery() {
        isDiscovering = true
        discoveredDevices.removeAll()
        let parameters = NWParameters.tcp
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready: print("[Sync] Browser ready")
                case .failed(let error):
                    print("[Sync] Browser failed: \(error)")
                    self?.delegate?.syncService(self!, didEncounterError: error)
                default: break
                }
            }
        }
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            var devices: [SyncDevice] = []
            for result in results {
                let endpoint = result.endpoint
                if case .service(let name, let type, let domain, let interface) = endpoint {
                    self?.resolveService(name: name, type: type, domain: domain, interface: interface) { host, port in
                        if let host = host, let port = port {
                            let device = SyncDevice(name: name, endpoint: endpoint, host: host, port: port)
                            devices.append(device)
                            DispatchQueue.main.async {
                                self?.discoveredDevices = devices
                                self?.delegate?.syncService(self!, didDiscoverDevices: devices)
                            }
                        }
                    }
                }
            }
        }
        browser?.start(queue: syncQueue)
    }
    
    func stopDiscovery() {
        isDiscovering = false
        browser?.cancel()
        browser = nil
    }
    
    private func resolveService(name: String, type: String, domain: String, interface: NWInterface?, completion: @escaping (String?, UInt16?) -> Void) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: interface)
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let path = connection.currentPath, let endpoint = path.remoteEndpoint, case .hostPort(let host, let port) = endpoint {
                    completion(host.debugDescription, port.rawValue)
                }
                connection.cancel()
            case .failed, .cancelled: completion(nil, nil)
            default: break
            }
        }
        connection.start(queue: syncQueue)
    }
    
    func connect(to device: SyncDevice) {
        print("[SYNC] 🚨 CONNECT METHOD TRIGGERED")
        DispatchQueue.main.async { self.syncStatus = "🚀 SINCED-V100-SLEDGE: Connecting to \(device.name)..." }
        let parameters = NWParameters.tcp
        connection = NWConnection(to: device.endpoint, using: parameters)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("[Sync] Connection ready")
                    self?.isConnected = true
                    self?.syncStatus = "Connected. Sending Handshake..."
                    self?.sendHandshake()
                    self?.receiveNextMessage()
                    // Trigger Outbox Flush when connection is established
                    self?.flushOutbox()
                case .waiting(let error):
                    print("[Sync] Connection waiting: \(error)")
                    self?.isConnected = false
                    self?.syncStatus = "Waiting: \(error.localizedDescription)"
                case .failed(let error):
                    print("[Sync] Connection failed: \(error)")
                    self?.isConnected = false
                    self?.syncStatus = "Failed: \(error.localizedDescription)"
                case .cancelled:
                    print("[Sync] Connection cancelled")
                    self?.isConnected = false
                    self?.syncStatus = "Disconnected"
                default: break
                }
            }
        }
        connection?.start(queue: syncQueue)
    }
    
    func connectManual(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let device = SyncDevice(name: "Manual Device", endpoint: endpoint, host: host, port: port)
        connect(to: device)
    }
    
    private func receiveNextMessage() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] (data, _, isComplete, error) in
            guard let strongSelf = self else { return }
            
            if let error = error {
                print("[Sync] Length read error: \(error)")
                DispatchQueue.main.async { strongSelf.syncStatus = "Len Error: \(error.localizedDescription)" }
                return
            }
            
            guard let data = data, data.count == 4 else {
                if isComplete {
                    print("[Sync] Connection closed by server")
                    DispatchQueue.main.async { strongSelf.isConnected = false; strongSelf.syncStatus = "Disconnected" }
                } else {
                    strongSelf.receiveNextMessage()
                }
                return
            }
            
            let hexBytes = data.map { String(format: "%02x", $0) }.joined(separator: " ")
            GLOBAL_SYNC_DIAGNOSTIC = "LEN: [ \(hexBytes) ]"
            DispatchQueue.main.async { strongSelf.syncStatus = "SINCED-V100: \(GLOBAL_SYNC_DIAGNOSTIC)" }
            
            let length = UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
            
            if length == 0 {
                strongSelf.receiveNextMessage()
                return
            }
            
            if length > 10 * 1024 * 1024 {
                print("[Sync] Length too large: \(length)")
                DispatchQueue.main.async { strongSelf.syncStatus = "SINCED-V100: Payload too large (\(length))" }
                return
            }
            
            strongSelf.connection?.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { (bodyData, _, _, bodyError) in
                guard let strongSelf = self else { return }
                
                if let bodyError = bodyError {
                    print("[Sync] Body read error: \(bodyError)")
                    DispatchQueue.main.async { strongSelf.syncStatus = "Body Error: \(bodyError.localizedDescription)" }
                    strongSelf.receiveNextMessage()
                    return
                }
                
                guard let bodyData = bodyData, bodyData.count == Int(length) else {
                    print("[Sync] Body read incomplete")
                    DispatchQueue.main.async { strongSelf.syncStatus = "Body Read Incomplete" }
                    strongSelf.receiveNextMessage()
                    return
                }
                
                do {
                    let packet = try JSONDecoder().decode(SyncPacket.self, from: bodyData)
                    DispatchQueue.main.async { strongSelf.syncStatus = "Decoded: \(packet.message)" }
                    strongSelf.handleMessage(packet.message)
                } catch {
                    print("[Sync] Decoding error: \(error)")
                    let errorMsg = "\(error)".prefix(30)
                    DispatchQueue.main.async { strongSelf.syncStatus = "Decode Err: \(errorMsg)" }
                    strongSelf.receiveNextMessage()
                }
            }
        }
    }
    
    private func handleMessage(_ message: SyncMessage) {
        switch message {
        case .ack:
            print("[Sync] Handshake ACK received")
            DispatchQueue.main.async { self.syncStatus = "SINCED: ACK Received ➔ Requesting Salt..." }
            self.handshakeCompleted = true
            self.requestSalt()
        case .saltResponse(let salt):
            print("[SINCED] Salt received (\(salt.count) bytes)")
            DispatchQueue.main.async { self.syncStatus = "SINCED: Salt Received ➔ Re-Keying..." }
            VaultManager.shared.updateSaltAndReKey(salt: salt)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                print("[SINCED] Slow-mo delay finished, requesting categories...")
                self.requestCategories()
            }
        case .categoriesResponse(let categories):
            print("[SINCED] Categories received (\(categories.count) items)")
            DispatchQueue.main.async { self.syncStatus = "Categories Received ➔ Requesting Sync..." }
            VaultManager.shared.syncCategories(categories)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.requestSync()
            }
        case .pong:
            print("[Sync] Received pong")
            DispatchQueue.main.async { self.syncStatus = "Pong received" }
        case .syncResponse(let entries, let timestamp):
            print("[Sync] Received \(entries.count) entries")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.syncStatus = "SINCED-V2: Sync Response Received (\(entries.count) entries)"
                var vaultEntries: [VaultEntry] = []
                for entry in entries {
                    if let vaultEntry = try? entry.toVaultEntry() { vaultEntries.append(vaultEntry) }
                }
                self.lastSyncTimestamp = timestamp
                self.delegate?.syncService(self, didReceiveEntries: vaultEntries)
            }
        case .entryUpdate(let entry):
            print("[SINCED-V2] Entry Update Received")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.syncStatus = "Entry Update Received"
                if let vaultEntry = try? entry.toVaultEntry() {
                    self.delegate?.syncService(self, didReceiveEntries: [vaultEntry])
                }
            }
        case .entryDelete(let entryId):
            print("[SINCED-V2] Entry Delete Received")
            DispatchQueue.main.async { self.syncStatus = "Entry Delete Received" }
        case .handshake(let id, let version, let vaultId):
            print("[SINCED-V2] Server handshake: \(id) v\(version) Vault:\(vaultId)")
            DispatchQueue.main.async { self.syncStatus = "Server Handshake OK" }
            self.handshakeCompleted = true
            self.requestSync()
        case .syncRequest:
            print("[SINCED-V2] Desktop requested sync")
            DispatchQueue.main.async { self.syncStatus = "Desktop requested sync" }
        case .requestSalt:
            print("[SINCED-V2] Server requested salt")
            DispatchQueue.main.async { self.syncStatus = "Server requested salt" }
        case .error(let msg):
            print("[SINCED-V2] Server error: \(msg)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.syncStatus = "Error: \(msg)"
                self.delegate?.syncService(self, didEncounterError: SyncError.networkError(NSError(domain: "SyncError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
            }
        default:
            print("[SINCED-V2] Unhandled message type")
        }
        receiveNextMessage()
    }
    
    func sendHandshake() {
        let vaultId = "default-vault"
        let handshake = SyncMessage.handshake(deviceId: deviceId, version: currentProtocolVersion, vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: handshake)
        
        do {
            let jsonData = try JSONEncoder().encode(packet)
            var length = UInt32(jsonData.count).bigEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            let finalPacket = lengthData + jsonData
            
            connection?.send(content: finalPacket, completion: .contentProcessed({ error in
                if let error = error {
                    print("[SINCED] Failed to send handshake: \(error)")
                } else {
                    print("[SINCED] Handshake delivered with length prefix (\(finalPacket.count) bytes)")
                }
            }))
        } catch {
            print("[SINCED] Handshake encoding failed: \(error)")
        }
    }
    
    func requestSalt() {
        let vaultId = "default-vault"
        let request = SyncMessage.requestSalt(vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        
        do {
            let jsonData = try JSONEncoder().encode(packet)
            var length = UInt32(jsonData.count).bigEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            let finalPacket = lengthData + jsonData
            
            connection?.send(content: finalPacket, completion: .contentProcessed({ error in
                if let error = error {
                    print("[SINCED] Failed to request salt: \(error)")
                } else {
                    print("[SINCED] Salt request delivered with length prefix (\(finalPacket.count) bytes)")
                }
            }))
        } catch {
            print("[SINCED] Salt encoding failed: \(error)")
        }
    }
    
    func requestCategories() {
        let vaultId = "default-vault"
        let request = SyncMessage.requestCategories(vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        
        do {
            let jsonData = try JSONEncoder().encode(packet)
            var length = UInt32(jsonData.count).bigEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            let finalPacket = lengthData + jsonData
            
            connection?.send(content: finalPacket, completion: .contentProcessed({ error in
                if let error = error {
                    print("[SINCED] Failed to request categories: \(error)")
                } else {
                    print("[SINCED] Category request delivered with length prefix (\(finalPacket.count) bytes)")
                }
            }))
        } catch {
            print("[SINCED] Category encoding failed: \(error)")
        }
    }
    
    func requestSync() {
        let request = SyncMessage.syncRequest(lastTimestamp: lastSyncTimestamp)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        
        do {
            let jsonData = try JSONEncoder().encode(packet)
            var length = UInt32(jsonData.count).bigEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            let finalPacket = lengthData + jsonData
            
            connection?.send(content: finalPacket, completion: .contentProcessed({ error in
                if let error = error {
                    print("[SINCED] Failed to send sync request: \(error)")
                } else {
                    print("[SINCED] Sync request delivered with length prefix (\(finalPacket.count) bytes)")
                }
            }))
        } catch {
            print("[SINCED] Encoding failed: \(error)")
        }
    }

    func sendEntryUpdate(entry: VaultEntry) {
        // Use a dummy key for the SyncVaultEntry init as we only need the data for transport
        do {
            let syncEntry = try SyncVaultEntry(from: entry, vaultKey: SymmetricKey(data: Data(repeating: 0, count: 32)))
            let updateMsg = SyncMessage.entryUpdate(entry: syncEntry)
            let packet = SyncPacket(deviceId: deviceId, message: updateMsg)
            sendPacket(packet)
        } catch {
            print("[SINCED] Failed to prepare entry update: \(error)")
        }
    }

    func sendEntryDelete(entryId: String) {
        let deleteMsg = SyncMessage.entryDelete(entryId: entryId)
        let packet = SyncPacket(deviceId: deviceId, message: deleteMsg)
        sendPacket(packet)
    }

    func flushOutbox() {
        guard isConnected else {
            print("[Sync] Outbox flush skipped: Not connected")
            return
        }
        
        print("[Sync] 📦 Flushing Offline Outbox...")
        
        VaultManager.shared.getPendingEntries { [weak self] (updates, deletes) in
            guard let self = self else { return }
            
            var processedCount = 0
            
            for entry in updates {
                self.sendEntryUpdate(entry: entry)
                VaultManager.shared.markAsSynced(entryId: entry.id.uuidString)
                processedCount += 1
            }
            
            for entryId in deletes {
                self.sendEntryDelete(entryId: entryId)
                VaultManager.shared.finalizeDelete(entryId: entryId)
                processedCount += 1
            }
            
            print("[Sync] 📦 Outbox flush complete. Processed \(processedCount) changes.")
            DispatchQueue.main.async {
                self.syncStatus = "Outbox Flushed (\(processedCount) items)"
            }
        }
    }

    private func sendPacket(_ packet: SyncPacket) {
        do {
            let jsonData = try JSONEncoder().encode(packet)
            var length = UInt32(jsonData.count).bigEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            let finalPacket = lengthData + jsonData
            
            connection?.send(content: finalPacket, completion: .contentProcessed({ error in
                if let error = error {
                    print("[SINCED] Outbound packet error: \(error)")
                } else {
                    print("[SINCED] Outbound packet delivered (\(finalPacket.count) bytes)")
                }
            }))
        } catch {
            print("[SINCED] Outbound encoding failed: \(error)")
        }
    }
}
