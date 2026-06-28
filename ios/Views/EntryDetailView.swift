// VERSION_SINCED_2026_05_28_FINAL
import SwiftUI

struct EntryDetailView: View {
    let entry: VaultEntry
    @State private var title: String
    @State private var username: String
    @State private var password = ""
    @State private var url: String
    @State private var notes = ""
    @State private var selectedCategory: UUID?
    @State private var isFavorite: Bool
    
    @State private var showingPassword = false
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var clipboardTimer: Timer?
    @Environment(\.dismiss) var dismiss
    
    init(entry: VaultEntry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        _username = State(initialValue: entry.username)
        _url = State(initialValue: entry.url ?? "")
        _selectedCategory = State(initialValue: entry.categoryID)
        _isFavorite = State(initialValue: entry.isFavorite)
    }
    
    var body: some View {
        ZStack {
            Color(hex: "0B0C10").ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Credentials Plate
                    VStack(spacing: 15) {
                        Text("CREDENTIALS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "C5A059"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if isEditing {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("TITLE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "94a3b8"))
                                    Spacer()
                                    TextField("", text: $title)
                                        .padding(6)
                                        .background(Color(hex: "0B0C10"))
                                        .foregroundColor(Color(hex: "C5A059"))
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 200)
                                }
                                
                                HStack {
                                    Text("USER").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "94a3b8"))
                                    Spacer()
                                    TextField("", text: $username)
                                        .padding(6)
                                        .background(Color(hex: "0B0C10"))
                                        .foregroundColor(Color(hex: "C5A059"))
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 200)
                                }
                                
                                HStack {
                                    Text("CAT").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "94a3b8"))
                                    Spacer()
                                    Text(VaultManager.shared.categories.first(where: { $0.id == selectedCategory })?.name ?? "None")
                                        .padding(6)
                                        .background(Color(hex: "0B0C10"))
                                        .foregroundColor(Color(hex: "C5A059"))
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 200)
                                    
                                    Button(action: {
                                        // Temporary: In a full impl, this would open a category picker
                                        // For now, we toggle through existing categories as a shortcut
                                        if let currentIdx = VaultManager.shared.categories.firstIndex(where: { $0.id == selectedCategory }) {
                                            let nextIdx = (currentIdx + 1) % VaultManager.shared.categories.count
                                            selectedCategory = VaultManager.shared.categories[nextIdx].id
                                        } else if !VaultManager.shared.categories.isEmpty {
                                            selectedCategory = VaultManager.shared.categories[0].id
                                        }
                                    }) {
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(Color(hex: "C5A059"))
                                            .padding(6)
                                    }
                                }
                                
                                HStack {
                                    Text("PASS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "94a3b8"))
                                    Spacer()
                                    SecureField("", text: $password)
                                        .padding(6)
                                        .background(Color(hex: "0B0C10"))
                                        .foregroundColor(Color(hex: "C5A059"))
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 200)
                                }
                            }
                        } else {
                            CredentialRow(label: "Username", value: username, isSecure: false)
                            CredentialRow(label: "Password", value: password, isSecure: !showingPassword)
                            
                            Button(action: {
                                if showingPassword { showingPassword = false } else { loadPassword() }
                            }) {
                                Text(showingPassword ? "HIDE PASSWORD" : "SHOW PASSWORD")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "C5A059"))
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(hex: "1B1C21"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "1B1C21"))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                    
                    if !url.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("WEBSITE")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "C5A059"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if isEditing {
                                TextField("", text: $url)
                                    .padding()
                                    .background(Color(hex: "0B0C10"))
                                    .foregroundColor(Color(hex: "C5A059"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                Link(destination: URL(string: url)!) {
                                    HStack {
                                        Text(url).foregroundColor(Color(hex: "C5A059")).font(.system(.body, design: .monospaced)).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square").foregroundColor(Color(hex: "C5A059"))
                                    }
                                    .padding()
                                    .background(Color(hex: "1B1C21"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                }
                            }
                        }
                    }
                    
                    if !notes.isEmpty || isEditing {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("NOTES")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "C5A059"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if isEditing {
                                TextEditor(text: $notes)
                                    .frame(height: 100)
                                    .padding(4)
                                    .background(Color(hex: "0B0C10"))
                                    .foregroundColor(Color(hex: "C5A059"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                Text(notes)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(Color(hex: "94a3b8"))
                                    .padding()
                                    .background(Color(hex: "1B1C21"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                            }
                        }
                    }
                    
                    // Action Plate
                    VStack(spacing: 12) {
                        if isEditing {
                            HStack(spacing: 12) {
                                Button("CANCEL") {
                                    isEditing = false
                                    resetFields()
                                }
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "C5A059"))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "1B1C21"))
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                                
                                Button("SAVE") {
                                    saveChanges()
                                    isEditing = false
                                }
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "0B0C10"))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "C5A059"))
                                .cornerRadius(4)
                                .shadow(color: Color(hex: "8B6B32"), radius: 2, x: 0, y: 2)
                            }
                        } else {
                            Button(action: { copyToClipboard(username) }) {
                                Label("Copy Username", systemImage: "doc.on.doc")
                                    .foregroundColor(Color(hex: "C5A059"))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(hex: "1B1C21"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                            }
                            
                            Button(action: { copyToClipboard(password) }) {
                                Label("Copy Password", systemImage: "doc.on.doc")
                                    .foregroundColor(Color(hex: "C5A059"))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(hex: "1B1C21"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                            }
                            
                            Divider().background(Color(hex: "2D2E35"))
                            
                            Button(action: { isEditing = true }) {
                                Label("Edit Entry", systemImage: "pencil")
                                    .foregroundColor(.white)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(hex: "2D2E35"))
                                    .cornerRadius(4)
                            }
                            
                            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                Label("Delete Entry", systemImage: "trash")
                                    .foregroundColor(.white)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(hex: "B22222"))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "1B1C21"))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                }
                .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: "1B1C21"), for: .navigationBar)
        .onAppear {
            loadPassword()
            loadNotes()
        }
        .onDisappear {
            clipboardTimer?.invalidate()
            showingPassword = false
            password = ""
            notes = ""
        }
        .confirmationDialog("Delete Entry?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                do {
                    VaultManager.shared.deleteEntry(id: entry.id)
                    dismiss()
                } catch {
                    print("Delete failed: \(error)")
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func loadPassword() {
        do {
            password = try VaultManager.shared.decryptPassword(for: entry)
            showingPassword = true
        } catch {
            password = "Decryption failed"
        }
    }
    
    private func loadNotes() {
        do {
            notes = try VaultManager.shared.decryptNotes(for: entry) ?? ""
        } catch {
            notes = ""
        }
    }
    
    private func saveChanges() {
        var updatedEntry = entry
        updatedEntry.title = title
        updatedEntry.username = username
        updatedEntry.url = url
        updatedEntry.categoryID = selectedCategory
        updatedEntry.isFavorite = isFavorite
        
        do {
            try VaultManager.shared.updateEntry(updatedEntry, newPassword: password, newNotes: notes)
        } catch {
            print("Update failed: \(error)")
        }
    }
    
    private func resetFields() {
        title = entry.title
        username = entry.username
        url = entry.url ?? ""
        password = ""
        notes = ""
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            UIPasteboard.general.string = ""
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
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "94a3b8"))
            Spacer()
            
            if isSecure {
                SecureField("", text: .constant(value))
                    .disabled(true)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Color(hex: "C5A059"))
                    .font(.system(.body, design: .monospaced))
            } else {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Color(hex: "C5A059"))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
