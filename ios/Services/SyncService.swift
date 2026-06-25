// SINCED_VERSION_2026_06_06_STABILITY_FIX
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

// MARK: - Sync Message Protocol ( Matches Desktop ) 
enum SyncMessage: Codable {
    case logUpload(logs: String)
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
    case requestTombstones(vaultId: String)
    case tombstonesResponse(deletedIds: [String])
    case deleteVault(vaultId: String)
    
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
        case deleted_ids = "deleted_ids"
        case message
        case logs
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .logUpload(let logs):
            try container.encode("log_upload", forKey: .type)
            try container.encode(logs, forKey: .logs)
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
            try container.encode("salt_response", forKey: .salt)
        case .requestCategories(let vaultId):
            try container.encode("request_categories", forKey: .type)
            try container.encode(vaultId, forKey: .vault_id)
        case .categoriesResponse(let categories):
            try container.encode("categories_response", forKey: .categories)
        case .requestTombstones(let vaultId):
            try container.encode("request_tombstones", forKey: .type)
            try container.encode(vaultId, forKey: .vault_id)
        case .tombstonesResponse(let deletedIds):
            try container.encode("tombstones_response", forKey: .type)
            try container.encode(deletedIds, forKey: .deleted_ids)
        case .deleteVault(let vaultId):
            try container.encode("delete_vault", forKey: .type)
            try container.encode(vaultId, forKey: .vault_id)
        default:
            try container.encode("unknown", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let type: String
        if let decodedType = try? container.decode(String.self, forKey: .type) {
            type = decodedType.lowercased()
        } else {
            if let _ = try? container.decode(String.self, forKey: .entry_id) {
                type = "entry_delete"
            } else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Missing 'type' field")
            }
        }
        
        switch type {
        case "log_upload":
            let logs = try container.decode(String.self, forKey: .logs)
            self = .logUpload(logs: logs)
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
        case "entry_delete", "entrydelete":
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
        case "request_tombstones":
            let vaultId = try container.decode(String.self, forKey: .vault_id)
            self = .requestTombstones(vaultId: vaultId)
        case "tombstones_response":
            let deletedIds = try container.decode([String].self, forKey: .deleted_ids)
            self = .tombstonesResponse(deletedIds: deletedIds)
        case "delete_vault":
            let vaultId = try container.decode(String.self, forKey: .vault_id)
            self = .deleteVault(vaultId: vaultId)
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
        if let notes = notes {
            self.encrypted_notes = Array(notes.utf8)
        } else {
            self.encrypted_notes = nil
        }
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
        if let notes = self.encrypted_notes {
            entry.encryptedNotes = Data(notes)
        } else {
            entry.encryptedNotes = nil
        }
        return entry
    }
}

enum SyncError: Error {
    case invalidEntryId, notConnected, authenticationFailed, encodingFailed, decodingFailed, networkError(Error)
}

protocol SyncServiceDelegate: AnyObject {
    func syncServiceDidConnect(_ service: SyncService)
    func syncServiceDidDisconnect(_ service: SyncService)
    func syncService(_ service: SyncService, didReceiveSyncEntries entries: [SyncVaultEntry], timestamp: Int64)
    func syncService(_ service: SyncService, didEncounterError error: Error)
    func syncService(_ service: SyncService, didDiscoverDevices devices: [SyncDevice])
    func syncServiceDidReceiveSalt(_ service: SyncService, salt: [UInt8])
    func syncService(_ service: SyncService, didReceiveCategories categories: [SyncCategory])
    func syncService(_ service: SyncService, didReceiveTombstones deletedIds: [String])
}

let currentProtocolVersion: UInt32 = 3

struct SyncDevice: Identifiable {
    var id: String { remoteDeviceId }
    let name: String
    let endpoint: NWEndpoint
    let host: String
    let port: UInt16
    let remoteDeviceId: String
}

class SyncService: ObservableObject {
    static let shared = SyncService()
    @Published var isConnected = false
    @Published var isDiscovering = false
    @Published var discoveredDevices: [SyncDevice] = []
    @Published var lastSyncTimestamp: Int64 = 0
    @Published var syncStatus: String = "Idle"
    @Published var logs: String = "System initialized. Awaiting connection...\n"
    @Published private(set) var vaultSyncStatus: String = ""
    @Published var keyStatus: String = "Unknown"
    @Published var saltReady = false
    @Published var firstSyncComplete = false
    private var isSyncing = false
    
    private var handshakeCompleted = false
    private var pendingHandshake = false
    weak var delegate: SyncServiceDelegate?
    private var connection: NWConnection?
    private var beaconListener: NWListener? 
    private let beaconPort: NWEndpoint.Port = 7879
    private let syncQueue = DispatchQueue(label: "com.clawpass.sync", qos: .userInitiated)
    private var deviceId: String { UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString }
    
    var vaultId: String = "vault_1"


    init() {
        log("SINCED_VERSION_V3_BETA: Initial initializing SyncService")
        let savedHost = UserDefaults.standard.string(forKey: "last_sync_host") ?? ""
        let savedPort = UserDefaults.standard.string(forKey: "last_sync_port") ?? "7878"
        print("[SINCED] Loaded last connection: \(savedHost):\(savedPort)")
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs += "\(message)\n"
        }
    }
    
    func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while let current = ptr {
                let interface = current.pointee
                let addrFamily = interface.ifa_addr?.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                    }
                }
                ptr = interface.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    func setVaultId(_ id: String) {
        self.vaultId = id
        log("SINCED: Vault Identity set to \(id)")
    }

    private var isHandshaking = false
    private var awaitingHandshakeAck = false

    func triggerHandshake() {
        guard !isHandshaking else {
            log("SINCED: Handshake already in progress. Ignoring request.")
            return
        }
        
        guard isConnected else {
            log("SINCED: Not connected. Attempting proactive connection...")
            pendingHandshake = true
            
            if let targetDevice = discoveredDevices.first {
                log("SINCED: Proactively connecting to discovered device: \(targetDevice.host)")
                connect(to: targetDevice)
            } else {
                log("SINCED: No discovered devices available to connect to.")
            }
            return
        }
        startHandshake()
    }


    func connect(to device: SyncDevice) {
        // 1. Prevent connection storms: If we are already ready or attempting, stop.
        if let existing = connection {
            switch existing.state {
            case .ready, .preparing, .setup:
                log("SINCED: Connection already active or preparing for \(device.host). Skipping.")
                return
            default:
                break
            }
        }
        
        log("SINCED: Initiating clean connection to \(device.name) (\(device.host):\(device.port))...")
        
        // 2. Total teardown of any lingering state
        disconnect() 
        
        // Small delay to allow the OS to release the port and clear the socket buffer
        syncQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let host = NWEndpoint.Host(device.host)
            let port = NWEndpoint.Port(integerLiteral: device.port)
            self.connection = NWConnection(host: host, port: port, using: .tcp)
            
            self.connection?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.log("SINCED: Connection established to \(device.host)")
                    DispatchQueue.main.async {
                        self.isConnected = true
                        self.syncStatus = "Connected"
                        self.delegate?.syncServiceDidConnect(self)
                    }
                    
                    self.isHandshaking = false
                    self.awaitingHandshakeAck = false
                    self.handshakeCompleted = false

                    if self.pendingHandshake {
                        self.log("SINCED: Executing pending handshake...")
                        self.startHandshake()
                        self.pendingHandshake = false
                    } else {
                        self.startHandshake()
                    }
                case .failed(let error):
                    self.log("SINCED: Connection failed: \(error)")
                    self.handleDisconnect()
                case .cancelled:
                    self.handleDisconnect()
                default:
                    break
                }
            }
            self.connection?.start(queue: self.syncQueue)
        }
    }

    func startUDPListener() {
        do {
            beaconListener = try NWListener(using: .udp, on: beaconPort)
            beaconListener?.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                connection.start(queue: self.syncQueue)
                
                connection.receiveMessage { (data, _, isComplete, error) in
                    if let data = data, let msg = String(data: data, encoding: .utf8), msg.hasPrefix("CLAWPASS_BEACON:") {
                        let remoteId = String(msg.dropFirst("CLAWPASS_BEACON:".count))
                        
                        self.syncQueue.async {
                            if let host = self.extractHost(from: connection.endpoint) {
                                let device = SyncDevice(name: "Vault Server", endpoint: connection.endpoint, host: host, port: 7878, remoteDeviceId: remoteId)
                                
                                DispatchQueue.main.async {
                                    if let index = self.discoveredDevices.firstIndex(where: { $0.remoteDeviceId == remoteId }) {
                                        self.discoveredDevices[index] = device
                                        self.log("SINCED: Updated existing device \(remoteId) in list.")
                                    } else {
                                        self.discoveredDevices.append(device)
                                        self.log("SINCED: Discovered new device \(remoteId) and added to list.")
                                    }
                                }
                                
                                if (VaultManager.shared.isUnlocked || self.pendingHandshake) && !self.isConnected {
                                    self.connect(to: device)
                                }
                            }
                        }
                    }
                }
            }
            beaconListener?.start(queue: syncQueue)
            log("SINCED: UDP Beacon Listener started on port \(beaconPort)")
        } catch {
            log("SINCED: Failed to start UDP listener: \(error)")
        }
    }

    private func extractHost(from endpoint: NWEndpoint) -> String? {
        if case let .hostPort(host, _) = endpoint {
            return host.debugDescription.components(separatedBy: " ").last
        }
        return nil
    }

    func startDiscovery() {
        // Discovery handled by UDP Beacons
    }

    func sendPacket(_ packet: SyncPacket) {
        do {
            let jsonData = try JSONEncoder().encode(packet)
            var length = UInt32(jsonData.count).bigEndian
            let lengthData = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            let finalPacket = lengthData + jsonData
            connection?.send(content: finalPacket, completion: .contentProcessed({ error in
                if let error = error { print("[SINCED] Outbound packet error: \(error)") }
            }))
        } catch { print("[SINCED] Outbound encoding failed: \(error)") }
    }

    func sendEntryUpdate(entry: VaultEntry) {
        do {
            guard handshakeCompleted else {
                log("SINCED: Blocked EntryUpdate - Handshake not completed. Entry will be sent during next flush.")
                return
            }
            guard let key = VaultManager.shared.getEncryptionKey() else {
                log("Error: Vault not unlocked, cannot encrypt entry update.")
                return
            }
            let syncEntry = try SyncVaultEntry(from: entry, vaultKey: key)
            let updateMsg = SyncMessage.entryUpdate(entry: syncEntry)
            let packet = SyncPacket(deviceId: deviceId, message: updateMsg)
            sendPacket(packet)
        } catch { print("[SINCED] Failed to prepare entry update: \(error)") }
    }

    func sendEntryDelete(entryId: String) {
        guard handshakeCompleted else {
            log("SINCED: Blocked EntryDelete - Handshake not completed. Entry will be sent during next flush.")
            return
        }
        let deleteMsg = SyncMessage.entryDelete(entryId: entryId.lowercased())
        let packet = SyncPacket(deviceId: deviceId, message: deleteMsg)
        sendPacket(packet)
    }

    func deleteVault() {
        guard isConnected && handshakeCompleted else {
            log("SINCED: Cannot delete vault - not connected or handshake not completed.")
            return
        }
        log("SINCED: Requesting nuclear wipe of vault \(vaultId)...")
        let request = SyncMessage.deleteVault(vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        sendPacket(packet)
    }

    func requestTombstones() {
        guard handshakeCompleted else { return }
        let request = SyncMessage.requestTombstones(vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        sendPacket(packet)
    }

    func startFullSyncPipeline() {
        guard !isSyncing else {
            log("SINCED: Sync pipeline already active. Skipping redundant trigger.")
            return
        }

        isSyncing = true
        log("SINCED: Starting automated sync pipeline...")

        syncQueue.async { [weak self] in
            guard let self = self else { return }
            self.flushOutbox()
            self.requestTombstones()
            self.requestCategories()
            self.requestSync()

            // Strict deterministic flow — no timers.
            // Caller (VaultManager after salt/unlock) is responsible for sequencing.
            DispatchQueue.main.async {
                self.isSyncing = false
                self.log("SINCED: Sync pipeline cycle complete.")
            }
        }
    }

    func requestCategories() {
        guard handshakeCompleted else { return }
        let request = SyncMessage.requestCategories(vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        sendPacket(packet)
    }

    func requestSync() {
        guard handshakeCompleted else { return }
        let request = SyncMessage.syncRequest(lastTimestamp: self.lastSyncTimestamp)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        sendPacket(packet)
    }

    func requestSalt() {
        guard handshakeCompleted else { 
            log("SINCED: Cannot request salt - Handshake not completed.")
            return 
        }
        log("SINCED-TX: Sending requestSalt for Vault ID: \(vaultId)")
        let request = SyncMessage.requestSalt(vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: request)
        sendPacket(packet)
    }

    func flushOutbox() {
        guard isConnected && handshakeCompleted else { return }
        VaultManager.shared.getPendingEntries { [weak self] (updates, deletes) in
            guard let self = self else { return }
            for entry in updates {
                self.sendEntryUpdate(entry: entry)
            }
            for entryId in deletes {
                self.sendEntryDelete(entryId: entryId)
            }
        }
    }

    func uploadLogs() {
        guard isConnected else {
            log("SINCED: Cannot upload logs - not connected.")
            return
        }
        log("SINCED-TX: Uploading current logs to server...")
        let uploadMsg = SyncMessage.logUpload(logs: self.logs)
        let packet = SyncPacket(deviceId: deviceId, message: uploadMsg)
        sendPacket(packet)
    }

    func disconnect() {
        // 1. STRIP HANDLERS FIRST
        // This is critical: preventing the .cancelled or .failed state from 
        // triggering handleDisconnect() during a manual teardown.
        connection?.stateUpdateHandler = nil
        
        // 2. Cancel the connection
        connection?.cancel()
        connection = nil
        
        // 3. Hard reset all session flags
        isConnected = false
        syncStatus = "Disconnected"
        handshakeCompleted = false
        isHandshaking = false
        awaitingHandshakeAck = false
        pendingHandshake = false
        
        delegate?.syncServiceDidDisconnect(self)
        log("SINCED: Connection fully torn down and state reset.")
    }

    private func handleDisconnect() {
        // Only trigger a full reset if the connection is actually gone
        // and not currently being replaced by a new one.
        if connection == nil {
            log("SINCED: No active connection to reset.")
            return
        }
        
        log("SINCED: Handling connection loss... initiating hard reset.")
        disconnect()
    }


    private func startHandshake() {
        if vaultId == "vault_1" {
            log("SINCED: Blocked handshake - vault identity not yet derived (still vault_1).")
            return
        }
        
        isHandshaking = true
        awaitingHandshakeAck = true
        log("SINCED: Starting handshake sequence for vault \(vaultId)...")
        let handshake = SyncMessage.handshake(deviceId: deviceId, version: currentProtocolVersion, vaultId: vaultId)
        let packet = SyncPacket(deviceId: deviceId, message: handshake)
        sendPacket(packet)
        self.receiveLoop()
    }


    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }
            
            if let data = data, data.count == 4 {
                // Explicitly construct UInt32 from big-endian bytes to avoid endianness bugs
                let length = UInt32(data[0]) << 24 | 
                             UInt32(data[1]) << 16 | 
                             UInt32(data[2]) << 8  | 
                             UInt32(data[3])
                
                // Safety valve: prevent attempting to read gargantuan packets (e.g. > 1MB)
                if length > 1024 * 1024 {
                    self.log("SINCED: Received absurd packet length (\(length)). Forcing disconnect.")
                    self.handleDisconnect()
                    return
                }
                
                self.readPacket(length: Int(length))
            } else if let error = error {
                self.log("Connection receive error: \(error)")
                self.handleDisconnect()
            } else if isComplete {
                self.handleDisconnect()
            }
        }
    }

    private func readPacket(length: Int) {
        connection?.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }
            
            if let data = data, data.count == length {
                do {
                    let packet = try JSONDecoder().decode(SyncPacket.self, from: data)
                    self.handleIncomingPacket(packet)
                } catch {
                    let shortError = "\(error)".components(separatedBy: "\n").first ?? "Unknown decode error"
                    self.log("SINCED: Packet decode error: \(shortError)")
                }
                self.receiveLoop()
            } else if let error = error {
                self.log("Payload receive error: \(error)")
                self.handleDisconnect()
            } else if isComplete {
                self.handleDisconnect()
            }
        }
    }

    private func handleIncomingPacket(_ packet: SyncPacket) {
        switch packet.message {
        case .handshake(let deviceId, let version, let vaultId):
            self.log("SINCED: Handshake received from \(deviceId).")
            
        case .ack:
            if awaitingHandshakeAck {
                self.log("SINCED: Handshake ACK received.")
                self.isHandshaking = false
                self.awaitingHandshakeAck = false
                self.handshakeCompleted = true
                self.log("SINCED: Connection established and verified.")
                
                // Crucial: Request salt immediately after handshake to proceed with setup or unlock
                self.requestSalt()
                log("SINCED: Automatically requesting vault salt...")
                
                // REMOVED: automatic startFullSyncPipeline() call. 
                // The VaultManager must trigger this once the DB is actually open.
            } else {
                self.log("SINCED: Received generic ACK.")
            }

            
        case .saltResponse(let salt):
            self.log("SINCED: Salt response received.")
            self.delegate?.syncServiceDidReceiveSalt(self, salt: salt)
            
        case .syncResponse(let entries, let timestamp):
            self.log("SINCED: Sync response received (\(entries.count) entries).")
            DispatchQueue.main.async {
                self.firstSyncComplete = true
            }
            self.delegate?.syncService(self, didReceiveSyncEntries: entries, timestamp: timestamp)
            
        case .categoriesResponse(let categories):
            self.log("SINCED: Categories response received (\(categories.count) categories).")
            self.delegate?.syncService(self, didReceiveCategories: categories)
            
        case .tombstonesResponse(let deletedIds):
            self.log("SINCED: Tombstones response received (\(deletedIds.count) IDs).")
            self.delegate?.syncService(self, didReceiveTombstones: deletedIds)
            
        case .entryUpdate(let entry):
            self.log("SINCED: Individual entry update received: \(entry.title)")
            self.delegate?.syncService(self, didReceiveSyncEntries: [entry], timestamp: Int64(Date().timeIntervalSince1970))
            
        case .entryDelete(let entryId):
            self.log("SINCED: Individual entry deletion received: \(entryId)")
            self.delegate?.syncService(self, didReceiveTombstones: [entryId])
            
        case .error(let message):
            self.log("SINCED SERVER ERROR: \(message)")
            
        case .ping:
            self.log("SINCED: Ping received.")
            self.sendPacket(SyncPacket(deviceId: deviceId, message: .pong))
            
        case .pong:
            self.log("SINCED: Pong received.")
            
        case .deleteVault:
            self.log("SINCED: Server-initiated vault deletion? (Unexpected)")
        case .logUpload:
            self.log("SINCED: Server requested log upload? (Unexpected)")
        case .syncRequest, .requestSalt, .requestCategories, .requestTombstones:
            self.log("SINCED: Received request message from server (usually client-initiated).")
        }
    }
}
