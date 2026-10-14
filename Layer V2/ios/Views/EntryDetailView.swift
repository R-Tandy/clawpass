import SwiftUI
import UniformTypeIdentifiers

struct EntryDetailView: View {
    let entry: VaultEntry
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vaultManager = VaultManager.shared

    @State private var title: String
    @State private var username: String
    @State private var password = ""
    @State private var url: String
    @State private var notes = ""
    @State private var selectedCategory: UUID?
    @State private var isFavorite: Bool

    @State private var passwordLoaded = false
    @State private var totp = ""
    @State private var totpLoaded = true
    @State private var showTOTPFields = false
    @State private var showingTOTPScanner = false
    @State private var showingPassword = false
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var toast: String?

    private let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    init(entry: VaultEntry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        _username = State(initialValue: entry.username)
        _url = State(initialValue: entry.url ?? "")
        _selectedCategory = State(initialValue: entry.categoryID)
        _isFavorite = State(initialValue: entry.isFavorite)
    }

    var body: some View {
        Form {
            if isEditing { editSections } else { readSections }

            if let errorMessage = errorMessage {
                Section { InlineBanner(kind: .error, message: errorMessage) }
                    .listRowBackground(Color.clear)
            }

            if !isEditing {
                Section {
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label("Delete Entry", systemImage: "trash")
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(isEditing ? "Edit Entry" : title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelEditing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveChanges)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Palette.surfaceRaised))
                    .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .tint(Palette.accent)
        .onAppear {
            loadPassword()
            loadNotes()
            loadTOTP()
        }
        .onDisappear {
            showingPassword = false
            password = ""
            notes = ""
            totp = ""
        }
        .onChange(of: vaultManager.isUnlocked) { unlocked in
            if !unlocked { password = ""; notes = ""; totp = "" }
        }
        .sheet(isPresented: $showingTOTPScanner) {
            QRScannerView { scanned in
                totp = scanned
                showingTOTPScanner = false
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                VaultManager.shared.deleteEntry(id: entry.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will also be removed from your computer the next time they sync. This cannot be undone.")
        }
    }

    // MARK: Read-only

    @ViewBuilder
    private var readSections: some View {
        Section {
            if !username.isEmpty {
                detailRow("Username", value: username) { copy(username, label: "Username") }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Password").font(.footnote).foregroundColor(Palette.textSecondary)
                    Text(passwordDisplay)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Button { showingPassword.toggle() } label: {
                    Image(systemName: showingPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showingPassword ? "Hide password" : "Show password")
                Button { copy(password, label: "Password") } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy password")
                .disabled(!passwordLoaded || password.isEmpty)
            }
        }
        .listRowBackground(Palette.surface)

        if let config = TOTP.parse(totp) {
            Section {
                TOTPRow(config: config) { code in copy(code, label: "Code") }
            }
            .listRowBackground(Palette.surface)
        }

        if let link = websiteURL {
            Section {
                Link(destination: link) {
                    HStack {
                        Text(url).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("Website")
            }
            .listRowBackground(Palette.surface)
        } else if !url.isEmpty {
            Section {
                Text(url).foregroundColor(Palette.textSecondary)
            } header: {
                Text("Website")
            }
            .listRowBackground(Palette.surface)
        }

        if !notes.isEmpty {
            Section {
                Text(notes).textSelection(.enabled)
            } header: {
                Text("Notes")
            }
            .listRowBackground(Palette.surface)
        }
    }

    // MARK: Editing

    @ViewBuilder
    private var editSections: some View {
        Section {
            TextField("Title", text: $title)
            TextField("Username or email", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .listRowBackground(Palette.surface)

        Section {
            if passwordLoaded {
                HStack {
                    Group {
                        if showingPassword {
                            TextField("Password", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    Button { showingPassword.toggle() } label: {
                        Image(systemName: showingPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showingPassword ? "Hide password" : "Show password")
                }
                StrengthMeter(password: password)
                Button {
                    password = CryptoService.shared.generatePassword()
                    showingPassword = true
                } label: {
                    Label("Generate Strong Password", systemImage: "wand.and.stars")
                }
            } else {
                Text("The saved password could not be decrypted, so it cannot be edited here. Other fields can still be changed.")
                    .font(.footnote)
                    .foregroundColor(Palette.warning)
            }
        } header: {
            Text("Password")
        }
        .listRowBackground(Palette.surface)

        Section {
            TextField("Website", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Category", selection: $selectedCategory) {
                Text("None").tag(UUID?.none)
                ForEach(vaultManager.categories.filter { $0.id != favoritesId }) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
            }
            Toggle("Favorite", isOn: $isFavorite)
        }
        .listRowBackground(Palette.surface)

        Section {
            TextEditor(text: $notes).frame(minHeight: 90)
        } header: {
            Text("Notes")
        }
        .listRowBackground(Palette.surface)

        if totpLoaded {
            Section {
                DisclosureGroup("One-time code", isExpanded: $showTOTPFields) {
                    TOTPFields(secret: $totp, showingScanner: $showingTOTPScanner)
                }
            }
            .listRowBackground(Palette.surface)
        }
    }

    // MARK: Helpers

    private var passwordDisplay: String {
        guard passwordLoaded else { return "Unavailable" }
        if password.isEmpty { return "None saved" }
        return showingPassword ? password : String(repeating: "•", count: min(password.count, 16))
    }

    private var websiteURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let parsed = URL(string: candidate), let host = parsed.host, host.contains(".") else { return nil }
        return parsed
    }

    private func detailRow(_ label: String, value: String, copyAction: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.footnote).foregroundColor(Palette.textSecondary)
                Text(value).foregroundColor(Palette.textPrimary).lineLimit(1)
            }
            Spacer()
            Button(action: copyAction) { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy \(label.lowercased())")
        }
    }

    private func loadPassword() {
        do {
            password = try VaultManager.shared.decryptPassword(for: entry)
            passwordLoaded = true
        } catch {
            password = ""
            passwordLoaded = false
        }
    }

    private func loadNotes() {
        notes = (try? VaultManager.shared.decryptNotes(for: entry)) ?? ""
    }

    private func loadTOTP() {
        do {
            totp = try VaultManager.shared.decryptTOTP(for: entry)
            totpLoaded = true
            showTOTPFields = !totp.isEmpty
        } catch {
            totp = ""
            totpLoaded = false
        }
    }

    private func cancelEditing() {
        title = entry.title
        username = entry.username
        url = entry.url ?? ""
        selectedCategory = entry.categoryID
        isFavorite = entry.isFavorite
        errorMessage = nil
        loadPassword()
        loadNotes()
        loadTOTP()
        isEditing = false
    }

    private func saveChanges() {
        if totpLoaded && !totp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && TOTP.parse(totp) == nil {
            errorMessage = "That one-time code key isn't valid. Paste the setup key or the otpauth:// link."
            return
        }
        var updated = vaultManager.entries.first(where: { $0.id == entry.id }) ?? entry
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = trimmedURL.isEmpty ? nil : trimmedURL
        updated.categoryID = selectedCategory
        updated.isFavorite = isFavorite

        do {
            // Only touch the stored password when it was successfully decrypted for editing.
            try VaultManager.shared.updateEntry(updated,
                                                newPassword: passwordLoaded ? password : nil,
                                                newNotes: notes,
                                                newTotp: totpLoaded ? totp : nil)
            errorMessage = nil
            isEditing = false
        } catch {
            errorMessage = "Your changes could not be saved. Please try again."
        }
    }

    /// Copies to the clipboard for this device only, and lets iOS clear it after 30 seconds
    /// (works even if the app is closed, unlike a timer).
    private func copy(_ text: String, label: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)]
        )
        toast = "\(label) copied. Clears in 30 seconds."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toast = nil }
    }
}

// MARK: - One-time code views

/// Single field (plus QR scan) for entering a setup key; kept inside a collapsed group so forms stay short.
struct TOTPFields: View {
    @Binding var secret: String
    @Binding var showingScanner: Bool

    var body: some View {
        TextField("Setup key or otpauth:// link", text: $secret)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        Button {
            showingScanner = true
        } label: {
            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
        }
    }
}

/// Live 6-digit code with a countdown to the next one.
struct TOTPRow: View {
    let config: TOTP.Config
    let onCopy: (String) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince1970)
            let remaining = config.period - seconds % config.period
            let code = TOTP.code(config, at: context.date)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("One-time code").font(.footnote).foregroundColor(Palette.textSecondary)
                    Text(spaced(code))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(Palette.textPrimary)
                }
                Spacer()
                Text("\(remaining)s")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(remaining <= 5 ? Palette.warning : Palette.textSecondary)
                Button { onCopy(code) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy one-time code")
            }
        }
    }

    private func spaced(_ code: String) -> String {
        let half = code.count / 2
        return String(code.prefix(half)) + " " + String(code.dropFirst(half))
    }
}
