import SwiftUI
import Network

/// Vault preferences and connection options. Connection options only manage the link to
/// the desktop app; restoring a vault lives on the welcome screen and nowhere else.
struct SettingsView: View {
    var showsDone = false

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vaultManager = VaultManager.shared
    @ObservedObject private var syncService = SyncService.shared
    @AppStorage("autoLockSeconds") private var autoLockSeconds = 60
    @AppStorage("faceIDUnlock") private var faceIDUnlock = true

    @State private var vaultName = ""
    @State private var ipAddress = ""
    @State private var port = "7878"
    @State private var showingQRScanner = false
    @State private var connectionError: String?
    @State private var confirmingDeleteVault = false

    var body: some View {
        Form {
            if vaultManager.isUnlocked {
                vaultSection
                securitySection
            }
            syncSection
            diagnosticsSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Palette.accent)
        .onAppear {
            vaultName = vaultManager.vaultName
            syncService.startUDPListener()
        }
        .confirmationDialog("Are you sure you want to delete this vault?", isPresented: $confirmingDeleteVault, titleVisibility: .visible) {
            Button("Delete this Vault", role: .destructive) {
                vaultManager.deleteCurrentVault()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Note: this will not delete the vault from your Computer.")
        }
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView { scannedUri in
                showingQRScanner = false
                connectFromQR(scannedUri)
            }
        }
    }

    // MARK: Sections

    private var vaultSection: some View {
        Section {
            HStack {
                Text("Name")
                TextField("My Vault", text: $vaultName)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .onSubmit(saveName)
            }
            NavigationLink("Categories") { CategoriesView() }
            Button("Delete this Vault", role: .destructive) { confirmingDeleteVault = true }
        } header: {
            Text("Vault")
        }
        .listRowBackground(Palette.surface)
        .onDisappear(perform: saveName)
    }

    private var securitySection: some View {
        Section {
            Picker("Auto-lock", selection: $autoLockSeconds) {
                Text("Immediately").tag(0)
                Text("After 1 minute").tag(60)
                Text("After 5 minutes").tag(300)
                Text("Never").tag(-1)
            }
            if CryptoService.shared.biometricsAvailable {
                Toggle("Unlock with Face ID", isOn: $faceIDUnlock)
                    .onChange(of: faceIDUnlock) { enabled in
                        vaultManager.setBiometricUnlock(enabled)
                    }
            }
            Button("Lock Now") {
                dismiss()
                vaultManager.lock()
            }
        } header: {
            Text("Security")
        } footer: {
            Text("The vault locks when the app has been in the background for the chosen time.")
        }
        .listRowBackground(Palette.surface)
    }

    private var syncSection: some View {
        Group {
            Section {
                HStack {
                    Circle()
                        .fill(syncService.isConnected ? Palette.success : Palette.textTertiary)
                        .frame(width: 10, height: 10)
                    Text(syncService.isConnected ? "Connected to your computer" : "Not connected")
                    Spacer()
                }
                .accessibilityElement(children: .combine)

                if let error = vaultManager.lastHandshakeError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(Palette.warning)
                }
                if let connectionError = connectionError {
                    Text(connectionError)
                        .font(.footnote)
                        .foregroundColor(Palette.danger)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Sync happens directly with \(AppBrand.desktopName) on your Wi-Fi network. Nothing is sent to the cloud.")
            }
            .listRowBackground(Palette.surface)

            Section {
                if syncService.discoveredDevices.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching your network…").foregroundColor(Palette.textSecondary)
                    }
                } else {
                    ForEach(syncService.discoveredDevices) { device in
                        Button {
                            syncService.connect(to: device)
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(device.host)
                                Spacer()
                                Text("Connect").foregroundColor(Palette.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("Computers Found")
            }
            .listRowBackground(Palette.surface)

            Section {
                HStack {
                    Text("Address")
                    TextField("192.168.1.20", text: $ipAddress)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                HStack {
                    Text("Port")
                    TextField("7878", text: $port)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                Button("Connect") { connectManually() }
                    .disabled(ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    showingQRScanner = true
                } label: {
                    Label("Scan Connection QR Code", systemImage: "qrcode.viewfinder")
                }
            } header: {
                Text("Manual Connection")
            } footer: {
                Text("Use this if your computer is not found automatically. The QR code is shown in \(AppBrand.desktopName).")
            }
            .listRowBackground(Palette.surface)
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Button("Send logs to PC") { syncService.uploadLogs() }
                .disabled(!syncService.isConnected)
        } header: {
            Text("Diagnostics")
        }
        .listRowBackground(Palette.surface)
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Self.versionString).foregroundColor(Palette.textSecondary)
            }
        } header: {
            Text("About")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Actions

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build)) Beta"
    }

    private func saveName() {
        let trimmed = vaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard vaultManager.isUnlocked, !trimmed.isEmpty, trimmed != vaultManager.vaultName else { return }
        try? vaultManager.updateVaultName(trimmed)
    }

    private func connectManually() {
        connectionError = nil
        let host = ipAddress.trimmingCharacters(in: .whitespaces)
        guard let portNumber = UInt16(port.trimmingCharacters(in: .whitespaces)), portNumber > 0 else {
            connectionError = "Enter a valid port number (usually 7878)."
            return
        }
        connect(host: host, port: portNumber, name: "Manual Connection", id: "manual")
    }

    private func connectFromQR(_ uri: String) {
        connectionError = nil
        // The desktop app encodes its address as layer://<ip>:<port>
        guard let range = uri.range(of: "://") else {
            connectionError = "That QR code is not a \(AppBrand.name) connection code."
            return
        }
        let parts = uri[range.upperBound...].split(separator: ":")
        guard parts.count == 2, let portNumber = UInt16(parts[1]) else {
            connectionError = "That QR code is not a \(AppBrand.name) connection code."
            return
        }
        connect(host: String(parts[0]), port: portNumber, name: "QR Scanned Device", id: "qr_scanned")
    }

    private func connect(host: String, port: UInt16, name: String, id: String) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let device = SyncDevice(name: name, endpoint: endpoint, host: host, port: port, remoteDeviceId: id)
        syncService.connect(to: device)
    }
}

// MARK: - Categories

struct CategoriesView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var editing: Category?
    @State private var showingNew = false

    private let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private var custom: [Category] { vaultManager.categories.filter { $0.id != favoritesID } }

    var body: some View {
        List {
            if custom.isEmpty {
                Text("No categories yet. Add one to group your entries.")
                    .foregroundColor(Palette.textSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(custom) { category in
                Button { editing = category } label: {
                    HStack(spacing: 12) {
                        CategoryGlyph(icon: category.icon)
                            .foregroundColor(Color(hex: category.color))
                            .frame(width: 28)
                        Text(category.name).foregroundColor(Palette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(Palette.textTertiary)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { custom[$0] }.forEach { vaultManager.deleteCategory(id: $0.id) }
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add category")
            }
        }
        .sheet(item: $editing) { CategoryEditor(category: $0) }
        .sheet(isPresented: $showingNew) { CategoryEditor(category: nil) }
        .tint(Palette.accent)
    }
}

struct CategoryEditor: View {
    let category: Category?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var color: String

    private static let icons = ["folder.fill", "briefcase.fill", "creditcard.fill", "cart.fill", "house.fill", "gamecontroller.fill",
                                "envelope.fill", "heart.fill", "graduationcap.fill", "airplane", "wrench.and.screwdriver.fill", "globe"]
    private static let colors = ["#C5A059", "#5AC8FA", "#34C759", "#FF9F0A", "#FF453A", "#BF5AF2", "#64D2FF", "#8E8E93"]

    init(category: Category?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _icon = State(initialValue: category?.icon ?? "folder.fill")
        _color = State(initialValue: category?.color ?? "#C5A059")
    }

    private var iconChoices: [String] { Self.icons.contains(icon) ? Self.icons : [icon] + Self.icons }
    private var colorChoices: [String] { Self.colors.contains { $0.caseInsensitiveCompare(color) == .orderedSame } ? Self.colors : [color] + Self.colors }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                .listRowBackground(Palette.surface)

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(iconChoices, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                CategoryGlyph(icon: symbol)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(icon == symbol ? Palette.onAccent : Palette.textPrimary)
                                    .background(Circle().fill(icon == symbol ? Palette.accent : Palette.surfaceRaised))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Icon")
                }
                .listRowBackground(Palette.surface)

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 14) {
                        ForEach(colorChoices, id: \.self) { hex in
                            Button { color = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Palette.textPrimary, lineWidth: color.caseInsensitiveCompare(hex) == .orderedSame ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Color")
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        VaultManager.shared.saveCategory(Category(id: category?.id ?? UUID(), name: trimmed, icon: icon, color: color))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tint(Palette.accent)
        }
    }
}
