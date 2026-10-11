import SwiftUI

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vaultManager = VaultManager.shared

    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var selectedCategory: UUID?
    @State private var isFavorite = false
    @State private var showPassword = false
    @State private var totp = ""
    @State private var showingTOTPScanner = false
    @State private var errorMessage: String?

    private let favoritesId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var assignableCategories: [Category] {
        vaultManager.categories.filter { $0.id != favoritesId }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Username or email", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                }
                .listRowBackground(Palette.surface)

                Section {
                    HStack {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(.newPassword)

                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(Palette.textSecondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    }
                    StrengthMeter(password: password)
                    Button {
                        password = CryptoService.shared.generatePassword()
                        showPassword = true
                    } label: {
                        Label("Generate Strong Password", systemImage: "wand.and.stars")
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
                        ForEach(assignableCategories) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                }
                .listRowBackground(Palette.surface)

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 90)
                } header: {
                    Text("Notes")
                }
                .listRowBackground(Palette.surface)

                Section {
                    DisclosureGroup("One-time code (optional)") {
                        TOTPFields(secret: $totp, showingScanner: $showingTOTPScanner)
                    }
                }
                .listRowBackground(Palette.surface)

                if let errorMessage = errorMessage {
                    Section { InlineBanner(kind: .error, message: errorMessage) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tint(Palette.accent)
            .sheet(isPresented: $showingTOTPScanner) {
                QRScannerView { scanned in
                    totp = scanned
                    showingTOTPScanner = false
                }
            }
        }
    }

    private func save() {
        if !totp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && TOTP.parse(totp) == nil {
            errorMessage = "That one-time code key isn't valid. Paste the setup key or the otpauth:// link."
            return
        }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = VaultEntry(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: "", // encrypted by the manager
            url: trimmedURL.isEmpty ? nil : trimmedURL,
            notes: nil,   // encrypted by the manager
            categoryID: selectedCategory,
            totpSecret: nil,
            isFavorite: isFavorite
        )

        do {
            try VaultManager.shared.addEntry(entry, password: password, notes: notes.isEmpty ? nil : notes, totpSecret: totp)
            dismiss()
        } catch {
            errorMessage = "The entry could not be saved. Please unlock the vault and try again."
        }
    }
}
