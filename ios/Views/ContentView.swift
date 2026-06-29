// VERSION_SINCED_2026_05_28_FINAL
import SwiftUI
import LocalAuthentication
import UIKit

struct ContentView: View {
    @StateObject private var vaultManager = VaultManager.shared
    @State private var showingSetup = false
    
    var body: some View {
        ZStack {
            if vaultManager.isUnlocked {
                VaultView()
            } else if vaultManager.isFirstPopulationPending {
                // While we are waiting for the server to respond to our identity request
                IdentificationView()
            } else if !vaultManager.hasAnyVault() {
                // If no DB exists and we aren't currently identifying, go to Setup
                SetupView(onComplete: {
                    // Transition handled by vaultManager.isUnlocked
                })
            } else {
                // DB exists, we need a password to derive identity and unlock
                UnlockView()
            }
            
            // State Monitor Removed for Production
        }
        .onAppear {
            checkVaultStatus()
            SyncService.shared.startUDPListener()
            SyncService.shared.startDiscovery()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SaltReady"))) { _ in
            print("[UI] SaltReady notification received. Triggering refresh...")
            vaultManager.objectWillChange.send()
        }
    }
    
    private func checkVaultStatus() {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vault.db")
        
        print("[UI] Checking vault path: \(path.path)")
        if !FileManager.default.fileExists(atPath: path.path) {
            print("[UI] Vault database NOT found. Flagging for setup.")
        } else {
            print("[UI] Vault database exists.")
        }
    }
}

struct IdentificationView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @ObservedObject private var syncService = SyncService.shared
    
    var body: some View {
        ZStack {
            Color(hex: "0B0C10")
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "network")
                    .font(.system(size: 80))
                    .foregroundColor(Color(hex: "C5A059"))
                
                Text("Identifying Vault")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "C5A059"))
                
                VStack(spacing: 20) {
                    Text("Connecting to your server to retrieve vault identity...")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "94a3b8"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    ScrollView(.vertical) {
                        Text(syncService.logs)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "39FF14"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(hex: "0B0C10"))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                    }
                    .frame(height: 120)
                    .padding(.horizontal)
                }
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "C5A059")))
                    .padding()
            }
        }
    }
}

struct UnlockView: View {
    @State private var password = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var useBiometric = false
    @ObservedObject private var syncService = SyncService.shared
    
    var body: some View {
        ZStack {
            Color(hex: "0B0C10")
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Color(hex: "C5A059"))
                
                Text("ClawPass")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "C5A059"))
                
                SecureField("Master Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color(hex: "1B1C21"))
                    .foregroundColor(Color(hex: "C5A059"))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                    .frame(maxWidth: 300)
                    .onSubmit { unlock() }
                
                Button(action: unlock) {
                    Text("Unlock")
                        .font(.headline)
                        .frame(maxWidth: 280)
                        .padding()
                        .background(Color(hex: "C5A059"))
                        .foregroundColor(Color(hex: "0B0C10"))
                        .cornerRadius(4)
                        .shadow(color: Color(hex: "8B6B32"), radius: 2, x: 0, y: 2)
                }
                .disabled(password.isEmpty)
                
                Button(action: recoverVault) {
                    Text("Retrieve Vault from Server")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color(hex: "C5A059"))
                        .padding(.vertical, 8)
                        .frame(maxWidth: 280)
                        .background(Color(hex: "1B1C21"))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                }
                .disabled(password.isEmpty)
                
                Button(action: unlockWithBiometric) {
                    HStack {
                        Image(systemName: "faceid")
                        Text("Use Face ID")
                    }
                    .foregroundColor(Color(hex: "C5A059"))
                }
                .disabled(!LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))

                Button(action: nuclearReset) {
                    Text("Nuclear Reset")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 20)
                }
            }
            .padding()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .overlay(
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("SINCED DEBUG")
                        .font(.system(size: 9, weight: .bold))
                    Spacer()
                }
                Text("Salt: \(VaultManager.shared.debugSaltHex)")
                Text("Hash: \(VaultManager.shared.debugKeyHash)")
                Text("Canary: \(VaultManager.shared.debugCanaryStatus)")
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(.green)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
            .padding()
            .frame(maxHeight: 80)
            .offset(y: 100), // Push it below the primary UI fold
            alignment: .bottom
        )
    }
    
    private func unlock() {
        VaultManager.shared.getDebugInfo(password: password)
        do {
            try VaultManager.shared.unlock(with: password)
        } catch let err as VaultError {
            switch err {
            case .vaultNotFound:
                errorMessage = "No vault exists for that password on this device. Tap 'Retrieve Vault from Server' to set it up."
            default:
                errorMessage = "Invalid password"
            }
            showingError = true
        } catch {
            errorMessage = "Invalid password"
            showingError = true
        }
    }
    
    private func recoverVault() {
        VaultManager.shared.getDebugInfo(password: password)
        VaultManager.shared.setupVault(password: password)
    }
    
    private func nuclearReset() {
        VaultManager.shared.nuclearReset()
    }
    
    private func unlockWithBiometric() {
        Task {
            do {
                let success = try await CryptoService.shared.authenticateWithBiometric(
                    reason: "Unlock ClawPass"
                )
                if success {
                    // Retrieve master password from UserDefaults for biometric unlock
                    if let savedPassword = UserDefaults.standard.string(forKey: "vault_master_password") {
                        await MainActor.run {
                            do {
                                try VaultManager.shared.unlock(with: savedPassword)
                            } catch {
                                errorMessage = "Biometric unlock failed: Invalid password stored"
                                showingError = true
                            }
                        }
                    } else {
                        await MainActor.run {
                            errorMessage = "Master password not saved. Please unlock manually first."
                            showingError = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Biometric authentication failed"
                    showingError = true
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4) * 17, (int) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct VaultView: View {
    @StateObject private var vaultManager = VaultManager.shared
    @ObservedObject private var syncService = SyncService.shared
    @State private var showingAddEntry = false
    @State private var showingSync = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @FocusState private var isSearchFieldFocused: Bool
    
    var filteredEntries: [VaultEntry] {
        var entries = vaultManager.entries
        
        if let category = selectedCategory {
            if category.id == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
                entries = entries.filter { $0.isFavorite }
            } else {
                entries = entries.filter { $0.categoryID == category.id }
            }
        }
        
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Primary sort: Favorites first, then Alphabetical by title
        return entries.sorted {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
    
    var body: some View {
        let currentTitle = vaultManager.vaultName
        NavigationView {
            ZStack {
                Color(hex: "0B0C10").ignoresSafeArea()
                
                VStack {
                    // Key Status Banner
                    if !vaultManager.keyStatus.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Key Status: \(vaultManager.keyStatus)")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.8))
                    }
                    
                    // Category Filter Menu
                    HStack {
                        Text("Filter by Category:")
                            .font(.caption)
                            .foregroundColor(Color(hex: "C5A059"))
                        
                        Menu {
                            Button("All Items") {
                                selectedCategory = nil
                            }
                            
                            Divider()
                            
                            ForEach(vaultManager.categories) { category in
                                Button(category.name) {
                                    selectedCategory = category
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedCategory?.name ?? "All Items")
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(hex: "1B1C21"))
                            .foregroundColor(Color(hex: "C5A059"))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if isSearching {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Color(hex: "94a3b8"))
                            TextField("Search passwords...", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.white)
                                .focused($isSearchFieldFocused)
                            
                            Button(action: { 
                                isSearching = false 
                                isSearchFieldFocused = false
                            }) {
                                Text("Cancel")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(hex: "C5A059"))
                            }
                        }
                        .padding(10)
                        .padding(.horizontal)
                        .background(Color(hex: "1B1C21"))
                        .foregroundColor(Color(hex: "C5A059"))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    List {
                        ForEach(filteredEntries) { entry in
                            NavigationLink(destination: EntryDetailView(entry: entry)) {
                                EntryRowView(entry: entry)
                            }
                            .listRowBackground(Color(hex: "0B0C10"))
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                if (vaultManager.isFirstPopulationPending || !syncService.firstSyncComplete) && vaultManager.entries.isEmpty {
                    ZStack {
                        Color(hex: "0B0C10").opacity(0.9)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "C5A059")))
                            
                            Text("Syncing your vault...")
                                .font(.headline)
                                .foregroundColor(Color(hex: "C5A059"))
                            
                            Text("Retrieving your secure entries from the server")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "94a3b8"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "1B1C21"), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Button(action: { 
                            isSearching.toggle()
                            isSearchFieldFocused = isSearching
                        }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(isSearching ? Color.white : Color(hex: "C5A059"))
                        }
                        
                        Button(action: { vaultManager.lock() }) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(Color(hex: "C5A059"))
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showingSync = true }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(vaultManager.syncStatus.contains("Connected") ? Color(hex: "39FF14") : Color(hex: "C5A059"))
                        }
                        
                        Button(action: { showingAddEntry = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(Color(hex: "C5A059"))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                AddEntryView()
            }
            .sheet(isPresented: $showingSync) {
                SettingsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultDataChanged)) { _ in
                print("[UI] VaultView received vaultDataChanged notification. Refreshing...")
                vaultManager.objectWillChange.send()
            }
        }
    }
}

struct EntryRowView: View {
    let entry: VaultEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .foregroundColor(Color(hex: "C5A059"))
                Text(entry.username)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(Color(hex: "94a3b8"))
            }
            
            Spacer()
            
            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(Color(hex: "FFD700"))
            }
        }
        .padding()
        .background(Color(hex: "1B1C21"))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
        .padding(.vertical, 4)
    }
}

// MARK: - Setup View

struct SetupView: View {
    let onComplete: () -> Void
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)
                
                Text("Welcome to ClawPass")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Create your master password to secure your vault.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 15) {
                    SecureField("Master Password", text: $password)
                        .textContentType(.newPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 300)
                    
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 300)
                }
                
                Button(action: createVault) {
                    Text("Create Vault")
                        .font(.headline)
                        .frame(maxWidth: 280)
                        .padding()
                        .background(password.isEmpty || password != confirmPassword ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(password.isEmpty || password != confirmPassword)
                
                if !password.isEmpty && password != confirmPassword {
                    Text("Passwords do not match")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, -10)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createVault() {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            showingError = true
            return
        }
        
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            showingError = true
            return
        }
        
        // Start the new "Identity-First" setup flow
        VaultManager.shared.setupVault(password: password)
    }
}
