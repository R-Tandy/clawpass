import SwiftUI

struct SyncView: View {
    @ObservedObject var syncService = SyncService.shared
    @State private var manualHost: String = UserDefaults.standard.string(forKey: "last_sync_host") ?? ""
    @State private var manualPort: String = UserDefaults.standard.string(forKey: "last_sync_port") ?? "7878"
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(syncService.isConnected ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    
                    Text(syncService.isConnected ? "Connected" : "Disconnected")
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Text(syncService.syncStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding(.top, 20)
            
            Divider()
            
            // Device List
            List(syncService.discoveredDevices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name).fontWeight(.medium)
                        Text(device.host).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Connect") {
                        syncService.connect(to: device)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }
            .listStyle(.plain)
            
            // Manual Connection
            VStack(spacing: 12) {
                HStack {
                    TextField("Host (e.g. 192.168.1.5)", text: $manualHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", text: $manualPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                Button("Manual Connect") {
                    if let port = UInt16(manualPort) {
                        syncService.connectManual(host: manualHost, port: port)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding()
            
            HStack {
                Button("Start Discovery") {
                    syncService.startDiscovery()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Stop") {
                    syncService.stopDiscovery()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 30)
        }
        .padding()
        .navigationTitle("Sync")
    }

    private func getRawBlobLeak() -> String {
        guard let firstEntry = VaultManager.shared.entries.first else {
            return "No entries in vault"
        }
        let data = firstEntry.encryptedPassword
        if data.isEmpty {
            return "Encrypted password is empty"
        }
        return data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

struct SyncView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SyncView()
        }
    }
}
