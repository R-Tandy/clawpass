import SwiftUI

// MARK: - Root

struct ContentView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoLockSeconds") private var autoLockSeconds = 60
    @State private var leftAppAt: Date?
    @State private var coverScreen = false

    var body: some View {
        ZStack {
            Group {
                if vaultManager.isUnlocked {
                    VaultView()
                } else if vaultManager.isFirstPopulationPending {
                    ConnectingView()
                } else if !vaultManager.hasAnyVault() {
                    WelcomeView()
                } else {
                    UnlockView()
                }
            }
            .transition(.opacity)

            // Hides vault contents in the app switcher snapshot.
            if coverScreen {
                PrivacyCover()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vaultManager.isUnlocked)
        .animation(.easeInOut(duration: 0.2), value: vaultManager.isFirstPopulationPending)
        .screenBackground()
        .onAppear { SyncService.shared.startUDPListener() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                coverScreen = false
                if let left = leftAppAt, vaultManager.isUnlocked,
                   autoLockSeconds >= 0, Date().timeIntervalSince(left) >= Double(autoLockSeconds) {
                    vaultManager.lock()
                }
                leftAppAt = nil
            case .inactive:
                coverScreen = vaultManager.isUnlocked
            case .background:
                coverScreen = vaultManager.isUnlocked
                if leftAppAt == nil { leftAppAt = Date() }
            @unknown default:
                break
            }
        }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            BrandMark(size: 96)
        }
    }
}

// MARK: - Welcome (no vault on this device)

private enum WelcomeSheet: String, Identifiable {
    case create, restore, connection
    var id: String { rawValue }
}

struct WelcomeView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @ObservedObject private var syncService = SyncService.shared
    @State private var sheet: WelcomeSheet?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    BrandMark(size: 96)
                    Text(AppBrand.name)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(Palette.textPrimary)
                    Text(AppBrand.tagline)
                        .font(.title3)
                        .foregroundColor(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 56)

                if let error = vaultManager.lastHandshakeError {
                    InlineBanner(kind: .error, message: error)
                        .onTapGesture { vaultManager.lastHandshakeError = nil }
                }

                VStack(spacing: 12) {
                    Button { sheet = .create } label: {
                        Label("Create a New Vault", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button { sheet = .restore } label: {
                        Label("Restore from My Computer", systemImage: "desktopcomputer")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(syncService.isConnected ? Palette.success : Palette.textTertiary)
                            .frame(width: 8, height: 8)
                        Text(syncService.isConnected
                             ? "Computer found on your network"
                             : "Looking for your computer…")
                            .font(.footnote)
                            .foregroundColor(Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)

                    Button("Connection options") { sheet = .connection }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Palette.accent)
                }

                Text("Everything is encrypted on this device. Syncing happens directly between your phone and your own computer. There is no cloud account.")
                    .font(.caption)
                    .foregroundColor(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .create: CreateVaultView()
            case .restore: RestoreVaultView()
            case .connection: NavigationView { SettingsView(showsDone: true) }
            }
        }
    }
}

// MARK: - Create vault

struct CreateVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var errorMessage: String?
    @State private var working = false

    private var mismatch: Bool { !confirm.isEmpty && password != confirm }
    private var canCreate: Bool { password.count >= 8 && password == confirm && !working }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose a master password")
                        .font(.title2.weight(.bold))
                        .foregroundColor(Palette.textPrimary)
                    Text("It unlocks everything in your vault and cannot be recovered if you forget it, so pick something you will remember.")
                        .font(.subheadline)
                        .foregroundColor(Palette.textSecondary)

                    FieldRow(title: "Master password", text: $password, secure: true, contentType: .newPassword)
                    StrengthMeter(password: password)
                    FieldRow(title: "Confirm password", text: $confirm, secure: true, contentType: .newPassword)

                    if password.count > 0 && password.count < 8 {
                        InlineBanner(kind: .info, message: "Use at least 8 characters.")
                    } else if mismatch {
                        InlineBanner(kind: .error, message: "The passwords do not match.")
                    }
                    if let errorMessage = errorMessage {
                        InlineBanner(kind: .error, message: errorMessage)
                    }

                    Button(action: create) {
                        if working { ProgressView().tint(Palette.onAccent) } else { Text("Create Vault") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canCreate)
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .screenBackground()
            .navigationTitle("New Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func create() {
        working = true
        errorMessage = nil
        // Key derivation takes a moment; let the spinner render first.
        DispatchQueue.main.async {
            do {
                try VaultManager.shared.createVault(password: password)
                dismiss()
            } catch VaultError.alreadyInitialized {
                errorMessage = "A vault with this password already exists on this device. Go back and unlock it instead."
            } catch {
                errorMessage = "The vault could not be created. Please try again."
            }
            working = false
        }
    }
}

// MARK: - Restore from computer

struct RestoreVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var syncService = SyncService.shared
    @State private var password = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Restore your vault")
                        .font(.title2.weight(.bold))
                        .foregroundColor(Palette.textPrimary)
                    Text("Make sure \(AppBrand.desktopName) is open on a computer connected to the same Wi-Fi network, then enter the master password for your vault.")
                        .font(.subheadline)
                        .foregroundColor(Palette.textSecondary)

                    FieldRow(title: "Master password", text: $password, secure: true, contentType: .password)

                    Button("Restore Vault") {
                        VaultManager.shared.retrieveVault(password: password)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(password.isEmpty)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(syncService.isConnected ? Palette.success : Palette.textTertiary)
                            .frame(width: 8, height: 8)
                        Text(syncService.isConnected ? "Computer found" : "No computer found yet. It will connect automatically.")
                            .font(.footnote)
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                .padding(24)
            }
            .screenBackground()
            .navigationTitle("Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Connecting (restore in progress)

struct ConnectingView: View {
    @ObservedObject private var syncService = SyncService.shared
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Palette.accent))
                .scaleEffect(1.6)
                .padding(.bottom, 8)
            Text(syncService.isConnected ? "Verifying your vault…" : "Looking for your computer…")
                .font(.title2.weight(.bold))
                .foregroundColor(Palette.textPrimary)
            Text("Keep \(AppBrand.desktopName) open on the same Wi-Fi network. This usually takes a few seconds.")
                .font(.subheadline)
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            DisclosureGroup("Details", isExpanded: $showDetails) {
                ScrollView {
                    Text(syncService.logs)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
            }
            .font(.footnote)
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 32)

            Spacer()

            Button("Cancel") { VaultManager.shared.cancelRetrieve() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
    }
}

// MARK: - Unlock

struct UnlockView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var working = false
    @State private var showingEraseConfirm = false
    @State private var canUseBiometrics = false
    @State private var showingRestore = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    BrandMark(size: 84)
                    Text(AppBrand.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(Palette.textPrimary)
                }
                .padding(.top, 72)

                VStack(spacing: 14) {
                    FieldRow(title: "Master password", text: $password, secure: true, contentType: .password)

                    if let errorMessage = errorMessage {
                        InlineBanner(kind: .error, message: errorMessage)
                    }

                    Button(action: unlock) {
                        if working { ProgressView().tint(Palette.onAccent) } else { Text("Unlock") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(password.isEmpty || working)

                    if canUseBiometrics {
                        Button(action: unlockWithBiometrics) {
                            Label("Unlock with Face ID", systemImage: "faceid")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                VStack(spacing: 14) {
                    Button("Restore a vault from my computer") { showingRestore = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Palette.accent)
                    Button("Erase this device's vaults…", role: .destructive) { showingEraseConfirm = true }
                        .font(.footnote)
                        .foregroundColor(Palette.danger)
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            canUseBiometrics = CryptoService.shared.biometricsAvailable && CryptoService.shared.hasSavedMasterPassword()
        }
        .sheet(isPresented: $showingRestore) { RestoreVaultView() }
        .confirmationDialog("Erase every vault stored on this device?", isPresented: $showingEraseConfirm, titleVisibility: .visible) {
            Button("Erase Vaults", role: .destructive) { vaultManager.nuclearReset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Vaults on your computer are not affected. You can restore them afterwards. This cannot be undone.")
        }
    }

    private func unlock() {
        errorMessage = nil
        working = true
        let attempt = password
        DispatchQueue.main.async {
            defer { working = false }
            do {
                try VaultManager.shared.unlock(with: attempt)
                password = ""
            } catch VaultError.vaultNotFound {
                errorMessage = "That password does not match any vault on this device. Check it and try again, or restore your vault from your computer."
            } catch VaultError.saltMissing {
                errorMessage = "This vault's key material is missing from this device. Restore it from your computer below."
            } catch {
                errorMessage = "The vault could not be opened. Please try again."
            }
        }
    }

    private func unlockWithBiometrics() {
        errorMessage = nil
        Task.detached {
            let saved = try? CryptoService.shared.retrieveMasterPasswordFromKeychain(reason: "Unlock \(AppBrand.name)")
            await MainActor.run {
                guard let saved = saved else {
                    errorMessage = "Face ID did not unlock the vault. Enter your master password."
                    return
                }
                do {
                    try VaultManager.shared.unlock(with: saved)
                } catch {
                    errorMessage = "The saved password no longer matches. Enter your master password."
                }
            }
        }
    }
}

// MARK: - Vault list

struct VaultView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @ObservedObject private var syncService = SyncService.shared
    @State private var showingAddEntry = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var selectedCategory: Category?

    private let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var filteredEntries: [VaultEntry] {
        var entries = vaultManager.entries
        if let category = selectedCategory {
            entries = category.id == favoritesId
                ? entries.filter { $0.isFavorite }
                : entries.filter { $0.categoryID == category.id }
        }
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                ($0.url ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return entries.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SyncStatusBar(isConnected: syncService.isConnected, error: vaultManager.lastHandshakeError)

                if !vaultManager.categories.isEmpty {
                    CategoryChips(categories: vaultManager.categories, selected: $selectedCategory)
                }

                if filteredEntries.isEmpty {
                    EmptyVaultState(isFiltering: !searchText.isEmpty || selectedCategory != nil,
                                    isSyncing: vaultManager.entries.isEmpty && syncService.isConnected && !syncService.firstSyncComplete,
                                    addAction: { showingAddEntry = true })
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            NavigationLink(destination: EntryDetailView(entry: entry)) {
                                EntryRowView(entry: entry)
                            }
                            .listRowBackground(Palette.background)
                            .listRowSeparatorTint(Palette.stroke)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .screenBackground()
            .navigationTitle(vaultManager.vaultName)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { vaultManager.lock() } label: { Image(systemName: "lock.fill") }
                        .accessibilityLabel("Lock vault")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                    Button { showingAddEntry = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add entry")
                }
            }
            .tint(Palette.accent)
            .sheet(isPresented: $showingAddEntry) { AddEntryView() }
            .sheet(isPresented: $showingSettings) {
                NavigationView { SettingsView(showsDone: true) }
            }
        }
        .navigationViewStyle(.stack)
        .tint(Palette.accent)
    }
}

struct SyncStatusBar: View {
    let isConnected: Bool
    let error: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isConnected ? "checkmark.icloud" : "icloud.slash")
                .foregroundColor(isConnected ? Palette.success : Palette.textTertiary)
            Text(isConnected
                 ? "Synced with your computer"
                 : (error ?? "Offline. Changes sync when your computer is reachable."))
                .font(.caption)
                .foregroundColor(Palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.surface)
        .accessibilityElement(children: .combine)
    }
}

struct CategoryChips: View {
    let categories: [Category]
    @Binding var selected: Category?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isOn: selected == nil) { selected = nil }
                ForEach(categories) { category in
                    chip(category.name, isOn: selected?.id == category.id) { selected = category }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundColor(isOn ? Palette.onAccent : Palette.textPrimary)
                .background(Capsule().fill(isOn ? Palette.accent : Palette.surfaceRaised))
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct EmptyVaultState: View {
    let isFiltering: Bool
    let isSyncing: Bool
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            if isSyncing {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Palette.accent))
                Text("Syncing your vault…")
                    .font(.headline).foregroundColor(Palette.textPrimary)
            } else if isFiltering {
                Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundColor(Palette.textTertiary)
                Text("No matches").font(.headline).foregroundColor(Palette.textPrimary)
            } else {
                Image(systemName: "key.viewfinder").font(.system(size: 44)).foregroundColor(Palette.accent)
                Text("Your vault is empty").font(.title3.weight(.semibold)).foregroundColor(Palette.textPrimary)
                Text("Add your first password to get started.")
                    .font(.subheadline).foregroundColor(Palette.textSecondary)
                Button("Add Password", action: addAction)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 240)
                    .padding(.top, 6)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct EntryRowView: View {
    let entry: VaultEntry

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surfaceRaised)
                Text(String(entry.title.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(Palette.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Palette.textPrimary)
                if !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.subheadline)
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(Palette.warning)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, 4)
    }
}
