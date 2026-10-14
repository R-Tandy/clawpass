import SwiftUI

// MARK: - Root

struct ContentView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoLockSeconds") private var autoLockSeconds = 60
    @State private var leftAppAt: Date?
    @State private var coverScreen = false
    @ObservedObject private var syncService = SyncService.shared

    var body: some View {
        ZStack(alignment: .top) {
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

            // Before a vault is open, say whether the computer's beacon has been heard.
            if !vaultManager.isUnlocked && !vaultManager.isFirstPopulationPending {
                ComputerStatusPill(found: !syncService.discoveredDevices.isEmpty)
                    .padding(.top, 8)
            }

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

struct ComputerStatusPill: View {
    let found: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(found ? Palette.success : Palette.textTertiary).frame(width: 8, height: 8)
            Text(found ? "Computer found" : "Looking for your computer…")
                .font(.caption)
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.surface))
        .accessibilityElement(children: .combine)
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

                    Button("Retrieve Vault") {
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
                    Button("Retrieve Vault from PC") { showingRestore = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Palette.accent)
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
    @State private var isSearching = false
    @State private var selectedCategory: Category?
    @State private var selectedIds = Set<UUID>()
    @State private var confirmingDelete = false
    @State private var showSyncedBanner = false
    @FocusState private var searchFocused: Bool

    private let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// A vault created on this phone that the computer has not accepted yet.
    private var notYetSynced: Bool {
        UserDefaults.standard.string(forKey: "pendingRegister_\(syncService.vaultId)") != nil
    }

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
                // The "synced" confirmation is shown for a few seconds; problems and offline stay visible.
                if !syncService.isConnected || vaultManager.lastHandshakeError != nil || showSyncedBanner || notYetSynced {
                    SyncStatusBar(isConnected: syncService.isConnected, error: vaultManager.lastHandshakeError, notSynced: notYetSynced)
                }

                if isSearching {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(Palette.textTertiary)
                        TextField("Search", text: $searchText)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Palette.textTertiary) }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surfaceRaised))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                if !vaultManager.categories.isEmpty {
                    CategoryChips(categories: vaultManager.categories, selected: $selectedCategory)
                }

                if !selectedIds.isEmpty {
                    HStack {
                        Text("\(selectedIds.count) selected").font(.subheadline).foregroundColor(Palette.textSecondary)
                        Spacer()
                        Button("Clear") { selectedIds.removeAll() }
                        Button("Delete Selected", role: .destructive) { confirmingDelete = true }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Palette.surface)
                }

                if filteredEntries.isEmpty {
                    EmptyVaultState(isFiltering: !searchText.isEmpty || selectedCategory != nil,
                                    isSyncing: vaultManager.entries.isEmpty && syncService.isConnected && !syncService.firstSyncComplete,
                                    addAction: { showingAddEntry = true })
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            HStack(spacing: 12) {
                                Button { toggle(entry.id) } label: {
                                    Image(systemName: selectedIds.contains(entry.id) ? "checkmark.square.fill" : "square")
                                        .font(.title3)
                                        .foregroundColor(selectedIds.contains(entry.id) ? Palette.accent : Palette.textTertiary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Select \(entry.title)")
                                NavigationLink(destination: EntryDetailView(entry: entry)) {
                                    EntryRowView(entry: entry)
                                }
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
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        isSearching.toggle()
                        if isSearching { searchFocused = true } else { searchText = "" }
                    } label: { Image(systemName: isSearching ? "xmark" : "magnifyingglass") }
                        .accessibilityLabel(isSearching ? "Close search" : "Search")
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
            .confirmationDialog("Delete \(selectedIds.count) selected?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    selectedIds.forEach { vaultManager.deleteEntry(id: $0) }
                    selectedIds.removeAll()
                }
                Button("Cancel", role: .cancel) { }
            }
            .onChange(of: syncService.isConnected) { connected in
                guard connected else { showSyncedBanner = false; return }
                showSyncedBanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { showSyncedBanner = false }
            }
        }
        .navigationViewStyle(.stack)
        .tint(Palette.accent)
    }

    private func toggle(_ id: UUID) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
}

struct SyncStatusBar: View {
    let isConnected: Bool
    let error: String?
    var notSynced = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isConnected && !notSynced ? "checkmark.icloud" : "icloud.slash")
                .foregroundColor(isConnected && !notSynced ? Palette.success : Palette.textTertiary)
            Text(notSynced
                 ? "Not yet synced to PC"
                 : isConnected
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

/// Renders a category icon that may be an SF Symbol name (iOS-made) or an emoji (desktop-made).
struct CategoryGlyph: View {
    let icon: String

    var body: some View {
        if icon.unicodeScalars.allSatisfy({ $0.isASCII }) {
            Image(systemName: icon)
        } else {
            Text(icon)
        }
    }
}

/// Category filter: one line of text (icon + name) that opens a vertical list to pick from.
struct CategoryChips: View {
    let categories: [Category]
    @Binding var selected: Category?

    var body: some View {
        HStack {
            Menu {
                Button { selected = nil } label: {
                    Label("All Items", systemImage: selected == nil ? "checkmark" : "square.grid.2x2")
                }
                ForEach(categories) { category in
                    Button { selected = category } label: {
                        if selected?.id == category.id {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text("\(glyph(category.icon)) \(category.name)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let category = selected {
                        CategoryGlyph(icon: category.icon).foregroundColor(Color(hex: category.color))
                        Text(category.name)
                    } else {
                        Image(systemName: "square.grid.2x2.fill")
                        Text("All Items")
                    }
                    Image(systemName: "chevron.down").font(.caption)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.surfaceRaised))
            }
            .accessibilityLabel("Category")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Menu rows are plain text, so only emoji icons can sit beside the name.
    private func glyph(_ icon: String) -> String {
        icon.unicodeScalars.allSatisfy({ $0.isASCII }) ? "•" : icon
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
