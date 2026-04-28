import Foundation
import Network
import CryptoKit
import UIKit

// MARK: - Sync Message Protocol (Matches Desktop)
enum SyncMessage: Codable {
    case handshake(deviceId: String, version: UInt32)
    case syncRequest(lastTimestamp: Int64)
    case syncResponse(entries: [SyncVaultEntry], timestamp: Int64)
    case entryUpdate(entry: SyncVaultEntry)
    case entryDelete(entryId: String)
    case ping
    case pong
    
    enum CodingKeys: String, CodingKey {
        case type
        case device_id = "device_id"
        case version
        case last_timestamp = "last_timestamp"
        case entries
        case timestamp
        case entry
        case entry_id = "entry_id"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .handshake(let deviceId, let version):
            try container.encode("handshake", forKey: .type)
            try container.encode(deviceId, forKey: .device_id)
            try container.encode(version, forKey: .version)
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
        case .ping:
            try container.encode("ping", forKey: .type)
        case .pong:
            try container.encode("pong", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "handshake":
            let deviceId = try container.decode(String.self, forKey: .device_id)
            let version = try container.decode(UInt32.self, forKey: .version)
            self = .handshake(deviceId: deviceId, version: version)
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
        case "ping":
            self = .ping
        case "pong":
            self = .pong
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }
}

// MARK: - Sync Vault Entry (Matches Desktop Structure)
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
    
    // TEST MODE: Plain text constructor (no encryption)
    init(id: String, title: String, username: String, password: String, url: String?, notes: String?, categoryId: String?, totpSecret: String?, createdAt: Int64, modifiedAt: Int64, isFavorite: Bool) {
        self.id = id
        self.title = title
        self.username = username
        // For testing, store plaintext as UTF-8 bytes
        self.encrypted_password = Array(password.utf8)
        self.url = url
        self.encrypted_notes = notes.map { Array($0.utf8) }
        self.category_id = categoryId
        self.totp_secret = totpSecret
        self.created_at = createdAt
        self.modified_at = modifiedAt
        self.is_favorite = isFavorite
    }
    
    // Convert from local VaultEntry
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
    
    // Convert to local VaultEntry (test mode - assumes plaintext)
    func toVaultEntry() throws -> VaultEntry {
        guard let uuid = UUID(uuidString: self.id) else {
            throw SyncError.invalidEntryId
        }
        
        let categoryUUID = self.category_id.flatMap { UUID(uuidString: $0) }
        
        // Create entry with placeholder encrypted data
        // In test mode, the "encrypted" data is actually plaintext UTF-8
        let entry = VaultEntry(
            id: uuid,
            title: self.title,
            username: self.username,
            encryptedPassword: Data(self.encrypted_password),
            url: self.url,
            encryptedNotes: self.encrypted_notes.map { Data($0) },
            categoryID: categoryUUID,
            totpSecret: self.totp_secret,
            createdAt: Date(timeIntervalSince1970: TimeInterval(self.created_at)),
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(self.modified_at)),
            isFavorite: self.is_favorite
        )
        
        return entry
    }
}

enum SyncError: Error {
    case invalidEntryId
    case notConnected
    case authenticationFailed
    case encodingFailed
    case decodingFailed
    case networkError(Error)
}

// MARK: - Sync Service
protocol SyncServiceDelegate: AnyObject {
    func syncServiceDidConnect(_ service: SyncService)
    func syncServiceDidDisconnect(_ service: SyncService)
    func syncService(_ service: SyncService, didReceiveEntries entries: [VaultEntry])
    func syncService(_ service: SyncService, didDeleteEntry entryId: String)
    func syncService(_ service: SyncService, didEncounterError error: Error)
    func syncService(_ service: SyncService, didDiscoverDevices devices: [SyncDevice])
}

struct SyncDevice: Identifiable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint
    let host: String
    let port: UInt16
}

class SyncService: ObservableObject {
    static let shared = SyncService()
    
    @Published var isConnected = false
    @Published var isDiscovering = false
    @Published var discoveredDevices: [SyncDevice] = []
    @Published var lastSyncTimestamp: Int64 = 0
    
    weak var delegate: SyncServiceDelegate?
    
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let syncQueue = DispatchQueue(label: "com.clawpass.sync", qos: .userInitiated)
    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    // Service type for Bonjour discovery
    private let serviceType = "_clawpass._tcp"
    
    // MARK: - Device Discovery
    
    func startDiscovery() {
        isDiscovering = true
        discoveredDevices.removeAll()
        
        let parameters = NWParameters.tcp
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("[Sync] Browser ready")
                case .failed(let error):
                    print("[Sync] Browser failed: \(error)")
                    self?.delegate?.syncService(self!, didEncounterError: error)
                default:
                    break
                }
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            var devices: [SyncDevice] = []
            
            for result in results {
                let endpoint = result.endpoint
                
                // Extract host and port from endpoint
                if case .service(let name, let type, let domain, let interface) = endpoint {
                    // Resolve the service to get IP address
                    self?.resolveService(name: name, type: type, domain: domain, interface: interface) { host, port in
                        if let host = host, let port = port {
                            let device = SyncDevice(
                                name: name,
                                endpoint: endpoint,
                                host: host,
                                port: port
                            )
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
                if let path = connection.currentPath,
                   let endpoint = path.remoteEndpoint,
                   case .hostPort(let host, let port) = endpoint {
                    completion(host.debugDescription, port.rawValue)
                }
                connection.cancel()
            case .failed, .cancelled:
                completion(nil, nil)
            default:
                break
            }
        }
        
        connection.start(queue: syncQueue)
    }
    
    // MARK: - Connection
    
    func connect(to device: SyncDevice) {
        // Cancel any existing connection
        disconnect()
        
        // Create TCP connection
        let host = NWEndpoint.Host(device.host)
        guard let port = NWEndpoint.Port(rawValue: device.port) else {
            delegate?.syncService(self, didEncounterError: SyncError.networkError(NSError(domain: "Invalid endpoint", code: -1)))
            return
        }
        
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let parameters = NWParameters.tcp
        connection = NWConnection(to: endpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("[Sync] Connected to \(device.name)")
                    self?.isConnected = true
                    self?.delegate?.syncServiceDidConnect(self!)
                    self?.sendHandshake()
                case .failed(let error):
                    print("[Sync] Connection failed: \(error)")
                    self?.isConnected = false
                    self?.delegate?.syncService(self!, didEncounterError: error)
                case .cancelled:
                    print("[Sync] Connection cancelled")
                    self?.isConnected = false
                    self?.delegate?.syncServiceDidDisconnect(self!)
                default:
                    break
                }
            }
        }
        
        connection?.start(queue: syncQueue)
    }
    
    func connectManual(host: String, port: UInt16) {
        let device = SyncDevice(name: "Manual Entry", endpoint: .hostPort(host: .name(host, nil), port: .init(integerLiteral: port)), host: host, port: port)
        connect(to: device)
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    // MARK: - Protocol Messages
    
    private func sendHandshake() {
        let message = SyncMessage.handshake(deviceId: deviceId, version: 1)
        send(message)
        
        // After handshake, request sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.requestSync()
        }
    }
    
    func requestSync() {
        let message = SyncMessage.syncRequest(lastTimestamp: lastSyncTimestamp)
        send(message)
    }
    
    func sendEntryUpdate(_ entry: VaultEntry, vaultKey: SymmetricKey) {
        guard isConnected else {
            delegate?.syncService(self, didEncounterError: SyncError.notConnected)
            return
        }
        
        do {
            let syncEntry = try SyncVaultEntry(from: entry, vaultKey: vaultKey)
            let message = SyncMessage.entryUpdate(entry: syncEntry)
            send(message)
        } catch {
            delegate?.syncService(self, didEncounterError: error)
        }
    }
    
    func sendEntryDelete(entryId: String) {
        guard isConnected else {
            delegate?.syncService(self, didEncounterError: SyncError.notConnected)
            return
        }
        
        let message = SyncMessage.entryDelete(entryId: entryId)
        send(message)
    }
    
    // MARK: - Send/Receive
    
    private func send(_ message: SyncMessage) {
        do {
            let data = try JSONEncoder().encode(message)
            let jsonString = String(data: data, encoding: .utf8) ?? "invalid"
            print("[SYNC] Sending message: \(jsonString)")
            
            let length = UInt32(data.count).bigEndian
            var packet = Data()
            packet.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
            packet.append(data)
            
            print("[SYNC] Packet size: \(packet.count) bytes (length prefix: \(length), data: \(data.count))")
            
            connection?.send(content: packet, completion: .contentProcessed { error in
                if let error = error {
                    print("[SYNC] Send error: \(error)")
                    DispatchQueue.main.async {
                        self.delegate?.syncService(self, didEncounterError: error)
                    }
                } else {
                    print("[SYNC] Message sent successfully")
                }
            })
            
            // Wait for response
            receiveNextMessage()
        } catch {
            print("[SYNC] Encoding error: \(error)")
            delegate?.syncService(self, didEncounterError: SyncError.encodingFailed)
        }
    }
    
    private func receiveNextMessage() {
        print("[SYNC] Waiting to receive...")
        
        // First receive 4 bytes (length prefix)
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[SYNC] Receive length error: \(error)")
                DispatchQueue.main.async {
                    self.delegate?.syncService(self, didEncounterError: error)
                }
                return
            }
            
            guard let data = data, data.count == 4 else {
                print("[SYNC] Invalid length data: \(data?.count ?? 0) bytes")
                return
            }
            
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            print("[SYNC] Expected message length: \(length)")
            
            // Then receive the actual message
            self.connection?.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] data, _, _, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[SYNC] Receive data error: \(error)")
                    DispatchQueue.main.async {
                        self.delegate?.syncService(self, didEncounterError: error)
                    }
                    return
                }
                
                guard let data = data else {
                    print("[SYNC] No data received")
                    return
                }
                
                let jsonString = String(data: data, encoding: .utf8) ?? "invalid"
                print("[SYNC] Received raw data: \(jsonString)")
                
                do {
                    let message = try JSONDecoder().decode(SyncMessage.self, from: data)
                    print("[SYNC] Decoded message: \(message)")
                    self.handleMessage(message)
                } catch {
                    print("[SYNC] Decoding error: \(error)")
                    DispatchQueue.main.async {
                        self.delegate?.syncService(self, didEncounterError: SyncError.decodingFailed)
                    }
                }
            }
        }
    }
    
    private func handleMessage(_ message: SyncMessage) {
        switch message {
        case .pong:
            print("[Sync] Received pong")
            
        case .syncResponse(let entries, let timestamp):
            print("[Sync] Received \(entries.count) entries")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Convert entries
                var vaultEntries: [VaultEntry] = []
                var failedEntries: Int = 0
                for entry in entries {
                    do {
                        let vaultEntry = try entry.toVaultEntry()
                        vaultEntries.append(vaultEntry)
                    } catch {
                        print("[Sync] Failed to convert entry '\(entry.title)': \(error)")
                        failedEntries += 1
                    }
                }
                
                let convertedCount = vaultEntries.count
                let totalCount = entries.count
                print("[Sync] Converted \(convertedCount)/\(totalCount) entries (\(failedEntries) failed)")
                self.lastSyncTimestamp = timestamp
                self.delegate?.syncService(self, didReceiveEntries: vaultEntries)
            }
            
        case .entryUpdate(let entry):
            print("[Sync] Received entry update")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let vaultEntry = try? entry.toVaultEntry() {
                    self.delegate?.syncService(self, didReceiveEntries: [vaultEntry])
                }
            }
            
        case .entryDelete(let entryId):
            print("[Sync] Received entry delete: \(entryId)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.syncService(self, didDeleteEntry: entryId)
            }
            
        default:
            print("[Sync] Unhandled message type")
        }
    }
}

// MARK: - Extensions

extension VaultEntry {
    // Convenience initializer for sync conversion
    init(id: UUID, title: String, username: String, encryptedPassword: Data, url: String?, encryptedNotes: Data?, categoryID: UUID?, totpSecret: String?, createdAt: Date, modifiedAt: Date, isFavorite: Bool) {
        self.id = id
        self.title = title
        self.username = username
        self.encryptedPassword = encryptedPassword
        self.url = url
        self.encryptedNotes = encryptedNotes
        self.categoryID = categoryID
        self.totpSecret = totpSecret
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isFavorite = isFavorite
    }
}
