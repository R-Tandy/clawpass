// VERSION_SINCED_2026_06_22_SETTINGS
import SwiftUI
import Network
import AVFoundation

struct SettingsView: View {

    @StateObject private var vaultManager = VaultManager.shared
    @StateObject private var syncService = SyncService.shared
    @State private var ipAddress = ""
    @State private var port = "7878"
    @State private var showingConnectionError = false
    @State private var errorMessage = ""
    @State private var showingQRScanner = false
    
    var body: some View {
        ZStack {
            Color(hex: "0B0C10").ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("VAULT SETTINGS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "C5A059"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top)
                    
                    // Vault Identity Plate
                    IdentityPlate(vaultManager: vaultManager)
                    
                    // Key Status Plate
                    KeyStatusPlate(vaultManager: vaultManager)
                    
                    Divider()
                        .background(Color(hex: "2D2E35"))
                        .padding(.vertical, 8)
                    
                    Text("SERVER LINK")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "C5A059"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    StatusPlate(isConnected: syncService.isConnected, status: syncService.syncStatus)
                    
                    BeaconPlate(devices: syncService.discoveredDevices) { device in
                        syncService.connect(to: device)
                    }
                    
                    ConnectionPlate(ip: $ipAddress, port: $port, onConnect: {
                        let host = NWEndpoint.Host(ipAddress)
                        let portNum = UInt16(port) ?? 7878
                        let endpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(integerLiteral: portNum))
                        
                        let device = SyncDevice(
                            name: "Manual Connection",
                            endpoint: endpoint,
                            host: ipAddress,
                            port: portNum,
                            remoteDeviceId: "manual"
                        )
                        syncService.connect(to: device)
                    })
                    
                    // QR Scanner Trigger
                    Button(action: {
                        showingQRScanner = true
                    }) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(Color(hex: "C5A059"))
                            Text("SCAN CONNECTION QR")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "0B0C10"))
                                .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(Color(hex: "C5A059"))
                        .cornerRadius(4)
                        .shadow(color: Color(hex: "8B6B32"), radius: 2, x: 0, y: 2)
                    }
                    .padding(.top, 12)
                    
                    LogPlate(logs: syncService.logs)
                }
                .padding()
            }
        }
        .onAppear {
            syncService.startUDPListener()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: "1B1C21"), for: .navigationBar)
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView { scannedUri in
                if scannedUri.hasPrefix("clawpass://") {
                    let stripped = scannedUri.replacingOccurrences(of: "clawpass://", with: "")
                    let components = stripped.split(separator: ":")
                    if components.count == 2 {
                        let host = String(components[0])
                        let port = UInt16(components[1]) ?? 7878
                        
                        let endpoint = NWEndpoint.hostPort(
                            host: NWEndpoint.Host(host), 
                            port: NWEndpoint.Port(integerLiteral: port)
                        )
                        
                        let device = SyncDevice(
                            name: "QR Scanned Device",
                            endpoint: endpoint,
                            host: host,
                            port: port,
                            remoteDeviceId: "qr_scanned"
                        )
                        syncService.connect(to: device)
                    }
                }
            }
        }
        .alert("Connection Error", isPresented: $showingConnectionError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}

struct IdentityPlate: View {
    @ObservedObject var vaultManager: VaultManager
    
    var body: some View {
        VStack(spacing: 12) {
            Text("VAULT IDENTITY")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "94a3b8"))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Text("NAME:")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "94a3b8"))
                
                TextField("Enter vault name...", text: Binding(
                    get: {
                        return vaultManager.vaultName
                    },
                    set: { newValue in
                        // Don't use `try?` here — the failure mode is
                        // "vault is locked" (db == nil), in which case
                        // the user has typed a name into the settings
                        // field and silently lost it. The Binding set
                        // closure can't throw, so we capture the error
                        // in a do/catch and log. The user sees no
                        // visible error in the field, but the next time
                        // they open the app the field will reflect the
                        // last successfully-persisted value.
                        do {
                            try vaultManager.updateVaultName(newValue)
                        } catch {
                            print("[IdentityPlate] updateVaultName failed: \(error)")
                        }
                    }
                ))
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(Color(hex: "C5A059"))
                .padding(8)
                .background(Color(hex: "0B0C10"))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
            }
        }
        .padding()
        .background(Color(hex: "1B1C21"))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
    }
}

struct KeyStatusPlate: View {
    @ObservedObject var vaultManager: VaultManager
    
    var body: some View {
        let keyStatus = vaultManager.verifyCurrentKey()
        VStack(spacing: 12) {
            HStack {
                Text("CRYPTOGRAPHIC STATE:")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "94a3b8"))
                Spacer()
                
                HStack {
                    Circle()
                        .fill(keyStatus == "Key Valid" ? Color(hex: "39FF14") : Color(hex: "C5A059"))
                        .frame(width: 8, height: 8)
                    
                    Text(keyStatus.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(keyStatus == "Key Valid" ? Color(hex: "39FF14") : Color(hex: "C5A059"))
                }
            }
        }
        .padding()
        .background(Color(hex: "1B1C21"))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
    }
}

struct StatusPlate: View {
    let isConnected: Bool
    let status: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("SATELLITE LINK:")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "94a3b8"))
                Spacer()
                
                HStack {
                    Circle()
                        .fill(isConnected ? Color(hex: "39FF14") : Color(hex: "5C5E66"))
                        .frame(width: 8, height: 8)
                        .shadow(color: isConnected ? Color(hex: "39FF14") : Color.clear, radius: 4)
                    
                    Text(isConnected ? "ESTABLISHED" : "DISCONNECTED")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(isConnected ? Color(hex: "39FF14") : Color(hex: "C5A059"))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("SYNC STATUS:")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "94a3b8"))
                
                Text(status)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(hex: "C5A059"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(hex: "1B1C21"))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
    }
}

struct BeaconPlate: View {
    let devices: [SyncDevice]
    var onConnect: (SyncDevice) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(Color(hex: "C5A059"))
                Text("DETECTED BEACONS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "C5A059"))
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if devices.isEmpty {
                Text("Scanning for signals...")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: "5C5E66"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(devices) { device in
                        Button(action: { onConnect(device) }) {
                            HStack {
                                Text("SIGNAL: \(device.host)")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Color(hex: "C5A059"))
                                Spacer()
                                Text("CONNECT")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "C5A059"))
                                    .foregroundColor(Color(hex: "0B0C10"))
                                    .cornerRadius(2)
                            }
                            .padding()
                            .background(Color(hex: "1B1C21"))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(hex: "1B1C21"))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
    }
}

struct ConnectionPlate: View {
    @Binding var ip: String
    @Binding var port: String
    var onConnect: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("MANUAL CONNECTION")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "C5A059"))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP ADDRESS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "94a3b8"))
                    TextField("192.168.1.x", text: $ip)
                        .padding()
                        .background(Color(hex: "0B0C10"))
                        .foregroundColor(Color(hex: "C5A059"))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                        .font(.system(.body, design: .monospaced))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("PORT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "94a3b8"))
                    TextField("7878", text: $port)
                        .padding()
                        .background(Color(hex: "0B0C10"))
                        .foregroundColor(Color(hex: "C5A059"))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                        .font(.system(.body, design: .monospaced))
                }
            }
            
            Button(action: onConnect) {
                Text("INITIATE HANDSHAKE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "0B0C10"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "C5A059"))
                    .cornerRadius(4)
                    .shadow(color: Color(hex: "8B6B32"), radius: 2, x: 0, y: 2)
            }
        }
        .padding()
        .background(Color(hex: "1B1C21"))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
    }
}

struct LogPlate: View {
    let logs: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SYSTEM LOGS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "C5A059"))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                Text(logs)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "39FF14"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(hex: "0B0C10"))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
            }
            .frame(height: 200)
            
            Button(action: {
                SyncService.shared.uploadLogs()
            }) {
                Text("DUMP LOGS TO SERVER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "0B0C10"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "C5A059"))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
            }
        }
    }
}
