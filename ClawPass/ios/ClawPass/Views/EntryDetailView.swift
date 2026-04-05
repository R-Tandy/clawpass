import SwiftUI

struct EntryDetailView: View {
    let entry: VaultEntry
    @StateObject private var vaultManager = VaultManager.shared
    
    @State private var decryptedPassword = ""
    @State private var decryptedNotes = ""
    @State private var showingPassword = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditView = false
    @State private var clipboardTimer: Timer?
    
    var body: some View {
        List {
            Section("Credentials") {
                CredentialRow(
                    label: "Username",
                    value: entry.username,
                    isSecure: false
                )
                
                CredentialRow(
                    label: "Password",
                    value: decryptedPassword,
                    isSecure: !showingPassword
                )
                
                Button(showingPassword ? "Hide Password" : "Show Password") {
                    if showingPassword {
                        showingPassword = false
                    } else {
                        loadPassword()
                    }
                }
            }
            
            if let url = entry.url, !url.isEmpty {
                Section("Website") {
                    Link(destination: URL(string: url)!) {
                        HStack {
                            Text(url)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            }
            
            if !decryptedNotes.isEmpty {
                Section("Notes") {
                    Text(decryptedNotes)
                }
            }
            
            Section {
                Button("Copy Username") {
                    copyToClipboard(entry.username)
                }
                
                Button("Copy Password") {
                    copyToClipboard(decryptedPassword)
                }
            }
            
            Section {
                Button("Edit Entry") {
                    showingEditView = true
                }
                
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete Entry")
                }
            }
        }
        .navigationTitle(entry.title)
        .onAppear {
            loadPassword()
            loadNotes()
        }
        .onDisappear {
            clipboardTimer?.invalidate()
            showingPassword = false
            decryptedPassword = ""
            decryptedNotes = ""
        }
        .confirmationDialog("Delete Entry?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingEditView) {
            EditEntryView(entry: entry)
        }
    }
    
    private func loadPassword() {
        do {
            decryptedPassword = try vaultManager.decryptPassword(for: entry)
            showingPassword = true
        } catch {
            print("Failed to decrypt password: \(error)")
        }
    }
    
    private func loadNotes() {
        do {
            decryptedNotes = try vaultManager.decryptNotes(for: entry) ?? ""
        } catch {
            print("Failed to decrypt notes: \(error)")
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        
        // Clear clipboard after 30 seconds
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            if UIPasteboard.general.string == text {
                UIPasteboard.general.string = ""
            }
        }
    }
    
    private func deleteEntry() {
        do {
            try vaultManager.deleteEntry(entry)
        } catch {
            print("Failed to delete entry: \(error)")
        }
    }
}

struct CredentialRow: View {
    let label: String
    let value: String
    let isSecure: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            
            if isSecure {
                SecureField("", text: .constant(value))
                    .disabled(true)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(value)
                    .lineLimit(1)
            }
        }
    }
}

struct EditEntryView: View {
    let entry: VaultEntry
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var username: String
    @State private var password: String
    @State private var url: String
    @State private var notes: String
    @State private var isFavorite: Bool
    
    init(entry: VaultEntry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        _username = State(initialValue: entry.username)
        _password = State(initialValue: "") // Will load decrypted
        _url = State(initialValue: entry.url ?? "")
        _notes = State(initialValue: "") // Will load decrypted
        _isFavorite = State(initialValue: entry.isFavorite)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Entry Details") {
                    TextField("Title", text: $title)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    SecureField("Password (leave blank to keep current)", text: $password)
                        .textContentType(.password)
                    TextField("Website URL", text: $url)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Toggle("Favorite", isOn: $isFavorite)
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
            }
        }
    }
    
    private func saveChanges() {
        var updatedEntry = entry
        updatedEntry.title = title
        updatedEntry.username = username
        updatedEntry.url = url.isEmpty ? nil : url
        updatedEntry.isFavorite = isFavorite
        
        do {
            try VaultManager.shared.updateEntry(
                updatedEntry,
                newPassword: password.isEmpty ? nil : password,
                newNotes: notes.isEmpty ? nil : notes
            )
            dismiss()
        } catch {
            print("Failed to update entry: \(error)")
        }
    }
}
