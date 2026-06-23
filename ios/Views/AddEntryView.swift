// VERSION_SINCED_2026_05_28_FINAL
import SwiftUI

struct AddEntryView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var selectedCategory: Category?
    @State private var isFavorite = false
    
    var body: some View {
        ZStack {
            Color(hex: "0B0C10").ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("NEW ENTRY")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "C5A059"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top)
                    
                    VStack(spacing: 16) {
                        InputField(label: "Title", text: $title)
                        InputField(label: "Username", text: $username)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PASSWORD")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "94a3b8"))
                            
                            HStack {
                                SecureField("", text: $password)
                                    .padding()
                                    .background(Color(hex: "0B0C10"))
                                    .foregroundColor(Color(hex: "C5A059"))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                    .font(.system(.body, design: .monospaced))
                                
                                Button(action: generatePassword) {
                                    Image(systemName: "gearshape.fill")
                                        .foregroundColor(Color(hex: "C5A059"))
                                        .padding()
                                        .background(Color(hex: "1B1C21"))
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                                }
                            }
                        }
                        
                        InputField(label: "URL", text: $url)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "94a3b8"))
                            
                            TextEditor(text: $notes)
                                .frame(height: 100)
                                .padding(4)
                                .background(Color(hex: "0B0C10"))
                                .foregroundColor(Color(hex: "C5A059"))
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORY")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "94a3b8"))
                            
                            Picker("Category", selection: $selectedCategory) {
                                Text("None").tag(Optional<Category>.none)
                                ForEach(VaultManager.shared.categories) { category in
                                    Text(category.name).tag(Optional(category))
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .padding()
                            .background(Color(hex: "0B0C10"))
                            .foregroundColor(Color(hex: "C5A059"))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                        }
                        
                        Toggle(isOn: $isFavorite) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(isFavorite ? Color(hex: "FFD700") : Color(hex: "C5A059"))
                                Text("Mark as Favorite")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(Color(hex: "C5A059"))
                            }
                        }
                        .toggleStyle(.switch)
                        .padding()
                        .background(Color(hex: "1B1C21"))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                    }
                    .padding()
                    .background(Color(hex: "1B1C21"))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Color(hex: "C5A059"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "1B1C21"))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "C5A059"), lineWidth: 1))
                        
                        Button("Save Entry") {
                            saveEntry()
                            dismiss()
                        }
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Color(hex: "0B0C10"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "C5A059"))
                        .cornerRadius(4)
                        .shadow(color: Color(hex: "8B6B32"), radius: 2, x: 0, y: 2)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: "1B1C21"), for: .navigationBar)
    }
    
    private func generatePassword() {
        password = CryptoService.shared.generatePassword()
    }
    
    private func saveEntry() {
        let newEntry = VaultEntry(
            title: title,
            username: username,
            password: "", // Encrypted version handled by Manager
            url: url,
            notes: "",    // Encrypted version handled by Manager
            categoryID: selectedCategory?.id,
            totpSecret: nil,
            isFavorite: isFavorite
        )
        
        do {
            try VaultManager.shared.addEntry(newEntry, password: password, notes: notes.isEmpty ? nil : notes)
        } catch {
            print("Save failed: \(error)")
        }
    }
}

struct InputField: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "94a3b8"))
            
            TextField("", text: $text)
                .padding()
                .background(Color(hex: "0B0C10"))
                .foregroundColor(Color(hex: "C5A059"))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "2D2E35"), lineWidth: 1))
                .font(.system(.body, design: .monospaced))
        }
    }
}
