import SwiftUI

struct SyncView: View {
    @StateObject private var syncService = SyncService.shared
    @State private var manualHost = ""
    @State private var manualPort = "7878"
    @State private var showManualEntry = false
    @State private var isSyncing = false
    @State private var lastSyncMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Status
                connectionStatusCard
                
                // Auto-discovered devices
                discoveredDevicesSection
                
                // Manual connection
                manualConnectionSection
                
                // Sync button
                if syncService.isConnected {
                    syncButton
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Sync with Desktop")
            .navigationBarItems(
                trailing: Button(action: {
                    if syncService.isDiscovering {
                        syncService.stopDiscovery()
                    } else {
                        syncService.startDiscovery()
                    }
                }) {
                    Image(systemName: syncService.isDiscovering ? "stop.circle" : "arrow.clockwise.circle")
                        .font(.title2)
                }
            )
            .onAppear {
                syncService.startDiscovery()
            }
            .onDisappear {
                syncService.stopDiscovery()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var connectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(syncService.isConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(syncService.isConnected ? "Connected" : "Not Connected")
                    .font(.headline)
                
                Spacer()
                
                if syncService.isConnected {
                    Button("Disconnect") {
                        syncService.disconnect()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            
            if !lastSyncMessage.isEmpty {
                Text(lastSyncMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var discoveredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovered Devices")
                    .font(.headline)
                
                Spacer()
                
                if syncService.isDiscovering {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if syncService.discoveredDevices.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "desktopcomputer.and.arrow.down")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No devices found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Make sure ClawPass Desktop is running on the same network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .padding(.vertical, 40)
            } else {
                ForEach(syncService.discoveredDevices) { device in
                    DeviceRow(
                        device: device,
                        isConnected: syncService.isConnected && syncService.discoveredDevices.firstIndex(where: { $0.id == device.id }) != nil
                    )
                    .onTapGesture {
                        if !syncService.isConnected {
                            connect(to: device)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var manualConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manual Connection")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showManualEntry.toggle()
                }) {
                    Image(systemName: showManualEntry ? "chevron.up" : "chevron.down")
                }
            }
            
            if showManualEntry {
                VStack(spacing: 12) {
                    TextField("IP Address (e.g., 192.168.1.100)", text: $manualHost)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                    
                    TextField("Port", text: $manualPort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                    
                    Button("Connect") {
                        connectManual()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(manualHost.isEmpty || manualPort.isEmpty)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var syncButton: some View {
        Button(action: {
            performSync()
        }) {
            HStack {
                if isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                Text(isSyncing ? "Syncing..." : "Sync Now")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSyncing ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isSyncing)
    }
    
    // MARK: - Actions
    
    private func connect(to device: SyncDevice) {
        syncService.connect(to: device)
        lastSyncMessage = "Connecting to \(device.name)..."
    }
    
    private func connectManual() {
        guard let port = UInt16(manualPort) else {
            lastSyncMessage = "Invalid port number"
            return
        }
        
        syncService.connectManual(host: manualHost, port: port)
        lastSyncMessage = "Connecting to \(manualHost):\(port)..."
    }
    
    private func performSync() {
        isSyncing = true
        lastSyncMessage = "Requesting sync..."
        
        syncService.requestSync()
        
        // Simulate sync completion (in real implementation, this would wait for delegate callback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isSyncing = false
            lastSyncMessage = "Sync completed"
        }
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: SyncDevice
    let isConnected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text("\(device.host):\(device.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isConnected ? Color.green : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Button Style

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(configuration.isPressed ? Color.blue.opacity(0.8) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
    }
}

// MARK: - Preview

struct SyncView_Previews: PreviewProvider {
    static var previews: some View {
        SyncView()
    }
}
