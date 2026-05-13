// SINCED_VERSION_2026_05_12_SENSORY_FINAL
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
    case handshake(deviceId: String, version: UInt32)
    case syncRequest(lastTimestamp: Int64)
    case syncResponse(entries: [SyncVaultEntry], timestamp: Int64)
    case entryUpdate(entry: SyncVaultEntry)
    case entryDelete(entryId: String)
    case ack
    case ping
    case pong
    case error(message: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case device_id = "device_id"
        case version
        case last_timestamp = "last_timestamp"
        case entries
        case timestamp
        case entry
        case entry_id = "entry_id"
        case message
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
        case .ack:
            try container.encode("ack", forKey: .type)
        case .ping:
            try container.encode("ping", forKey: .type)
        case .pong:
            try container.encode("pong", forKey: .type)
        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
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
        case "ack":
            self = .ack
        case "ping":
            self = .ping
        case "pong":
            self = .pong
        case "error":
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message: message)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }
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

let currentProtocolVersion: UInt32 = 1

struct SyncDevice: Identifiable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint
    let host: String
    let port: UInt16
}

class SINCED_SyncService_V100: ObservableObject {
    static let shared = SINCED_SyncService_V100()
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
        // Load last connection
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
        DispatchQueue.main.async { self.syncStatus = "🚀 SINCED-V100-DEBUG-RAW: Connecting to \(device.name)..." }
        let parameters = NWParameters.tcp
        connection = NWConnection(to: device.endpoint, using: parameters)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("[Sync] Connection ready")
                    self?.isConnected = true
                    self?.syncStatus = "Connected. Waiting for data..."
                    self?.receiveNextMessage()
                case .waiting(let error):
                    print("[Sync] Connection waiting: \(error)")
                    self?.syncStatus = "Waiting: \(error.localizedDescription)"
                case .failed(let error):
                    print("[Sync] Connection failed: \(error)")
                    self?.isConnected = false
                    self?.syncStatus = "Failed: \(error.localizedDescription)"
                    self?.delegate?.syncService(self!, didEncounterError: error)
                case .cancelled:
                    print("[Sync] Connection cancelled")
                    self?.isConnected = false
                    self?.syncStatus = "Disconnected"
                default: break
                }
            }
        }
        connection?.start(queue: syncQueue)
        receiveNextMessage()
        sendHandshake()
    }

    func connectManual(host: String, port: UInt16) {
        print("[SYNC] Manual connect triggered")
        DispatchQueue.main.async { self.syncStatus = "Connecting to \(host):\(port)..." }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let parameters = NWParameters.tcp
        connection = NWConnection(to: endpoint, using: parameters)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("[Sync] Connection ready")
                    self?.isConnected = true
                    self?.syncStatus = "Connected. Waiting for data..."
                    self?.receiveNextMessage()
                case .waiting(let error):
                    print("[Sync] Connection waiting: \(error)")
                    self?.syncStatus = "Waiting: \(error.localizedDescription)"
                case .failed(let error):
                    print("[Sync] Connection failed: \(error)")
                    self?.isConnected = false
                    self?.syncStatus = "Failed: \(error.localizedDescription)"
                    self?.delegate?.syncService(self!, didEncounterError: error)
                case .cancelled:
                    print("[Sync] Connection cancelled")
                    self?.isConnected = false
                    self?.syncStatus = "Disconnected"
                default: break
                }
            }
        }
        connection?.start(queue: syncQueue)
        receiveNextMessage()
        sendHandshake()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        DispatchQueue.main.async { self.syncStatus = "Disconnected" }
    }
    
    private func sendHandshake() {
        let handshake = SyncMessage.handshake(deviceId: deviceId, version: currentProtocolVersion)
        sendPacket(message: handshake)
    }
    
    func requestSync() {
        let request = SyncMessage.syncRequest(lastTimestamp: lastSyncTimestamp)
        sendPacket(message: request)
    }
    
    private func sendPacket(message: SyncMessage) {
        guard let connection = connection else { return }
        let packet = SyncPacket(deviceId: deviceId, message: message)
        do {
            let data = try JSONEncoder().encode(packet)
            var finalData = Data()
            var length = UInt32(data.count).bigEndian
            finalData.append(UnsafeBufferPointer(start: &length, count: 1))
            finalData.append(data)
            connection.send(content: finalData, completion: .contentProcessed({ error in
                if let error = error { print("[SYNC] Send error: \(error)") }
            }))
        } catch {
            print("[SYNC] Encoding error: \(error)")
        }
    }
    
    func receiveNextMessage() {
        guard let connection = connection else { return }
        
        DispatchQueue.main.async { self.syncStatus = "Listening for length (4b)..." }
        
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[SYNC] Receive length error: \(error)")
                DispatchQueue.main.async { self.syncStatus = "Len Error: \(error.localizedDescription)" }
                return
            }
            
            guard let data = data, data.count == 4 else {
                if isComplete {
                    print("[SYNC] Connection closed by server")
                    DispatchQueue.main.async { self.isConnected = false; self.syncStatus = "Disconnected" }
                } else {
                    print("[SYNC] Length read incomplete: \(data?.count ?? 0) bytes")
                }
                return
            }
            
            // RAW BYTE DUMP for "The 2GB Ghost" debug
            let hexBytes = data.map { String(format: "%02x", $0) }.joined(separator: " ")
            DispatchQueue.main.async { 
                self.syncStatus = "BYTES: [ \(hexBytes) ]" 
            }
            print("[SYNC] 🔍 RAW LENGTH BYTES: [ \(hexBytes) ]")
            
            // ATOMIC ENDIAN FIX: Use the most explicit method possible
            let rawValue = data.withUnsafeBytes { $0.load(as: UInt32.self) }
            let length = UInt32(bigEndian: rawValue)
            
            print("[SYNC] Length received: \(length) bytes. Now fetching body...")
            DispatchQueue.main.async { self.syncStatus = "Recv 4b ➔ Fetching \(length)b..." }
            
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, isComplete, error in
                if let error = error {
                    print("[SYNC] Receive body error: \(error)")
                    DispatchQueue.main.async { self.syncStatus = "Body Error: \(error.localizedDescription)" }
                    return
                }
                
                guard let data = data, data.count == Int(length) else {
                    print("[SYNC] Body read incomplete: \(data?.count ?? 0) of \(length) bytes")
                    return
                }
                
                let jsonString = String(data: data, encoding: .utf8) ?? "invalid"
                print("[SYNC] Body received. Length: \(data.count). Raw: \(jsonString)")
                
                do {
                    DispatchQueue.main.async { self.syncStatus = "Recv \(data.count)b. Decoding..." }
                    let packet = try JSONDecoder().decode(SyncPacket.self, from: data)
                    print("[SYNC] Successfully decoded SyncPacket from \(packet.deviceId): \(packet.message)")
                    DispatchQueue.main.async { self.syncStatus = "Decoded: \(packet.message)" }
                    self.handleMessage(packet.message)
                } catch {
                    print("[SYNC] Decoding error: \(error)")
                    print("[SYNC] Raw data that failed: \(jsonString)")
                    DispatchQueue.main.async {
                        self.syncStatus = "Decoding Error! (See logs)"
                        self.delegate?.syncService(self, didEncounterError: SyncError.decodingFailed)
                    }
                    self.receiveNextMessage()
                }
            }
        }
    }
    
    private func handleMessage(_ message: SyncMessage) {
        switch message {
        case .ack:
            print("[Sync] Handshake ACK received")
            DispatchQueue.main.async { self.syncStatus = "ACK Received ➔ Requesting Sync..." }
            self.handshakeCompleted = true
            self.requestSync()
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
            print("[Sync] Received entry update")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.syncStatus = "Entry Update Received"
                if let vaultEntry = try? entry.toVaultEntry() {
                    self.delegate?.syncService(self, didReceiveEntries: [vaultEntry])
                }
            }
        case .entryDelete(let entryId):
            print("[Sync] Received entry delete: \(entryId)")
            DispatchQueue.main.async { self.syncStatus = "Entry Delete Received" }
        case .handshake(let id, let version):
            print("[Sync] Server handshake: \(id) v\(version)")
            DispatchQueue.main.async { self.syncStatus = "Server Handshake OK" }
            self.handshakeCompleted = true
            self.requestSync()
        case .syncRequest:
            print("[Sync] Desktop requested sync")
            DispatchQueue.main.async { self.syncStatus = "Desktop requested sync" }
        case .error(let msg):
            print("[Sync] Server error: \(msg)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.syncStatus = "Error: \(msg)"
                self.delegate?.syncService(self, didEncounterError: SyncError.networkError(NSError(domain: "SyncError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
            }
        default:
            print("[Sync] Unhandled message type")
        }
        receiveNextMessage()
    }
}
