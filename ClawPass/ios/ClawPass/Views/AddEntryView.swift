import SwiftUI

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vaultManager = VaultManager.shared
    
    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var selectedCategory: Category?
    @State private var isFavorite = false
    
    @State private var showingPasswordGenerator = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @State private var passwordLength: Double = 16
    @State private var useSymbols = true
    @State private var useNumbers = true
    @State private var useUppercase = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Entry Details") {
                    TextField("Title", text: $title)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    
                    HStack {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        
                        Button(action: { showingPasswordGenerator = true }) {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    
                    TextField("Website URL", text: $url)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None")
                            .tag(nil as Category?)
                        
                        ForEach(vaultManager.categories) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.name)
                            }
                            .tag(category as Category?)
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Toggle("Add to Favorites", isOn: $isFavorite)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(title.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
            .sheet(isPresented: $showingPasswordGenerator) {
                PasswordGeneratorView(
                    password: $password,
                    isPresented: $showingPasswordGenerator
                )
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveEntry() {
        let entry = VaultEntry(
            title: title,
            username: username,
            password: password,
            url: url.isEmpty ? nil : url,
            notes: notes.isEmpty ? nil : notes,
            categoryID: selectedCategory?.id,
            isFavorite: isFavorite
        )
        
        do {
            try vaultManager.addEntry(entry, password: password, notes: notes.isEmpty ? nil : notes)
            dismiss()
        } catch {
            errorMessage = "Failed to save entry: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct PasswordGeneratorView: View {
    @Binding var password: String
    @Binding var isPresented: Bool
    
    @State private var length: Double = 16
    @State private var useUppercase = true
    @State private var useLowercase = true
    @State private var useNumbers = true
    @State private var useSymbols = true
    
    private var generatedPassword: String {
        CryptoService.shared.generatePassword(
            length: Int(length),
            useUppercase: useUppercase,
            useLowercase: useLowercase,
            useNumbers: useNumbers,
            useSymbols: useSymbols
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Generated Password") {
                    Text(generatedPassword)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 8)
                    
                    Button("Copy to Clipboard") {
                        UIPasteboard.general.string = generatedPassword
                    }
                    
                    Button("Use This Password") {
                        password = generatedPassword
                        isPresented = false
                    }
                    .foregroundColor(.accentColor)
                }
                
                Section("Options") {
                    VStack(alignment: .leading) {
                        Text("Length: \(Int(length))")
                            .font(.subheadline)
                        Slider(value: $length, in: 8...64, step: 1)
                    }
                    
                    Toggle("Uppercase (A-Z)", isOn: $useUppercase)
                    Toggle("Lowercase (a-z)", isOn: $useLowercase)
                    Toggle("Numbers (0-9)", isOn: $useNumbers)
                    Toggle("Symbols (!@#$%)", isOn: $useSymbols)
                }
            }
            .navigationTitle("Password Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
