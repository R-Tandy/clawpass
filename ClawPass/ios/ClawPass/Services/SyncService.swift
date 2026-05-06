import Foundation
import Network
import CryptoKit

protocol SyncServiceDelegate: AnyObject {
    func syncServiceDidConnect(_ service: SyncService)
    func syncServiceDidDisconnect(_ service: SyncService)
    func syncService(_ service: SyncService, didReceiveEntries entries: [VaultEntry])
    func syncService(_ service: SyncService, didEncounterError error: Error)
}

class SyncService: ObservableObject {
    static let shared = SyncService()
    
    @Published var isConnected = false
    @Published var isDiscovering = false
    @Published var discoveredPeers: [NWEndpoint] = []
    
    weak var delegate: SyncServiceDelegate?
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private let syncQueue = DispatchQueue(label: "com.clawpass.sync")
    
    // Service type for Bonjour discovery
    private let serviceType = "_clawpass._tcp"
    private let servicePort: NWEndpoint.Port = 7373
    
    // MARK: - Service Discovery
    
    func startDiscovery() {
        isDiscovering = true
        discoveredPeers.removeAll()
        
        let parameters = NWParameters.tcp
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("Browser ready")
                case .failed(let error):
                    self?.delegate?.syncService(self!, didEncounterError: error)
                default:
                    break
                }
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredPeers = results.map { $0.endpoint }
            }
        }
        
        browser?.start(queue: syncQueue)
    }
    
    func stopDiscovery() {
        isDiscovering = false
        browser?.cancel()
        browser = nil
    }
    
    // MARK: - Server Mode
    
    func startListening() {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: servicePort)
            
            listener?.service = NWListener.Service(name: "ClawPass", type: serviceType)
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        print("Listener ready on port \(self?.servicePort ?? 0)")
                    case .failed(let error):
                        self?.delegate?.syncService(self!, didEncounterError: error)
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: syncQueue)
            
        } catch {
            delegate?.syncService(self, didEncounterError: error)
        }
    }
    
    func stopListening() {
        listener?.cancel()
        listener = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        isConnected = false
    }
    
    // MARK: - Client Connection
    
    func connect(to endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)
        
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.delegate?.syncServiceDidConnect(self!)
                    self?.authenticate(connection: connection)
                case .failed(let error):
                    self?.delegate?.syncService(self!, didEncounterError: error)
                case .cancelled:
                    self?.isConnected = false
                    self?.delegate?.syncServiceDidDisconnect(self!)
                default:
                    break
                }
            }
        }
        
        connection.start(queue: syncQueue)
        connections.append(connection)
    }
    
    // MARK: - Private Methods
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.delegate?.syncServiceDidConnect(self!)
                    self?.waitForAuthentication(connection: connection)
                case .failed(let error):
                    self?.delegate?.syncService(self!, didEncounterError: error)
                case .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }
        
        connection.start(queue: syncQueue)
        connections.append(connection)
    }
    
    private func authenticate(connection: NWConnection) {
        // Send authentication challenge
        let challenge = Data.randomBytes(count: 32)
        let message = SyncMessage.authenticate(challenge: challenge)
        send(message, via: connection)
    }
    
    private func waitForAuthentication(connection: NWConnection) {
        receive(from: connection) { [weak self] message in
            guard case .authenticate(let challenge) = message else {
                connection.cancel()
                return
            }
            
            // Verify challenge and respond
            // In production, this would use the pre-shared key from vault setup
            let response = self?.createAuthResponse(for: challenge) ?? Data()
            self?.send(.authResponse(response: response), via: connection)
        }
    }
    
    private func createAuthResponse(for challenge: Data) -> Data {
        // This would use the vault's encryption key to sign the challenge
        // Placeholder implementation
        return challenge
    }
    
    private func send(_ message: SyncMessage, via connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(message)
            let length = UInt32(data.count).bigEndian
            var packet = Data()
            packet.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
            packet.append(data)
            
            connection.send(content: packet, completion: .contentProcessed({ _ in }))
        } catch {
            print("Failed to encode message: \(error)")
        }
    }
    
    private func receive(from connection: NWConnection, handler: @escaping (SyncMessage) -> Void) {
        // First receive 4 bytes (length prefix)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let data = data, data.count == 4 else {
                if let error = error {
                    self?.delegate?.syncService(self!, didEncounterError: error)
                }
                return
            }
            
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // Then receive the actual message
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, error in
                guard let data = data else {
                    if let error = error {
                        self?.delegate?.syncService(self!, didEncounterError: error)
                    }
                    return
                }
                
                do {
                    let message = try JSONDecoder().decode(SyncMessage.self, from: data)
                    handler(message)
                } catch {
                    print("Failed to decode message: \(error)")
                }
            }
        }
    }
    
    // MARK: - Public Sync Methods
    
    func syncEntries(_ entries: [VaultEntry]) {
        // Send entries to all connected peers
        for connection in connections where connection.state == .ready {
            let message = SyncMessage.syncEntries(entries: entries)
            send(message, via: connection)
        }
    }
}

// MARK: - Sync Messages

enum SyncMessage: Codable {
    case authenticate(challenge: Data)
    case authResponse(response: Data)
    case syncEntries(entries: [VaultEntry])
    case requestEntries
    case disconnect
    
    // Manual Codable conformance for associated values
    enum CodingKeys: String, CodingKey {
        case type, challenge, response, entries
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .authenticate(let challenge):
            try container.encode("authenticate", forKey: .type)
            try container.encode(challenge, forKey: .challenge)
        case .authResponse(let response):
            try container.encode("authResponse", forKey: .type)
            try container.encode(response, forKey: .response)
        case .syncEntries(let entries):
            try container.encode("syncEntries", forKey: .type)
            try container.encode(entries, forKey: .entries)
        case .requestEntries:
            try container.encode("requestEntries", forKey: .type)
        case .disconnect:
            try container.encode("disconnect", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "authenticate":
            let challenge = try container.decode(Data.self, forKey: .challenge)
            self = .authenticate(challenge: challenge)
        case "authResponse":
            let response = try container.decode(Data.self, forKey: .response)
            self = .authResponse(response: response)
        case "syncEntries":
            let entries = try container.decode([VaultEntry].self, forKey: .entries)
            self = .syncEntries(entries: entries)
        case "requestEntries":
            self = .requestEntries
        case "disconnect":
            self = .disconnect
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type")
        }
    }
}
