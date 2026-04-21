import SwiftUI
import LocalAuthentication
import UIKit

struct ContentView: View {
    @StateObject private var vaultManager = VaultManager.shared
    @State private var showingSetup = false
    @State private var showingUnlock = false
    
    var body: some View {
        Group {
            if vaultManager.isUnlocked {
                VaultView()
            } else if showingSetup {
                SetupView(onComplete: {
                    showingSetup = false
                    showingUnlock = true
                })
            } else {
                UnlockView()
            }
        }
        .onAppear {
            checkVaultStatus()
        }
    }
    
    private func checkVaultStatus() {
        // Check if vault exists
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vault.db")
        
        if !FileManager.default.fileExists(atPath: path.path) {
            showingSetup = true
        } else {
            showingUnlock = true
        }
    }
}

struct UnlockView: View {
    @State private var password = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var useBiometric = false
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("ClawPass")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            SecureField("Master Password", text: $password)
                .textContentType(.password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 300)
                .onSubmit { unlock() }
            
            Button(action: unlock) {
                Text("Unlock")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(password.isEmpty)
            
            Button(action: unlockWithBiometric) {
                HStack {
                    Image(systemName: "faceid")
                    Text("Use Face ID")
                }
            }
            .disabled(!LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))
        }
        .padding()
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func unlock() {
        do {
            try VaultManager.shared.unlock(with: password)
        } catch {
            errorMessage = "Invalid password"
            showingError = true
        }
    }
    
    private func unlockWithBiometric() {
        Task {
            do {
                let success = try await CryptoService.shared.authenticateWithBiometric(
                    reason: "Unlock ClawPass"
                )
                if success {
                    // Note: Biometric unlocks the keychain, we'd need to
                    // implement secure key storage from keychain
                    // For now, this is a placeholder
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

struct VaultView: View {
    @StateObject private var vaultManager = VaultManager.shared
    @State private var showingAddEntry = false
    @State private var showingSync = false
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    
    var filteredEntries: [VaultEntry] {
        var entries = vaultManager.entries
        
        if let category = selectedCategory {
            entries = entries.filter { $0.categoryID == category.id }
        }
        
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return entries.sorted { $0.isFavorite && !$1.isFavorite }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredEntries) { entry in
                    NavigationLink(destination: EntryDetailView(entry: entry)) {
                        EntryRowView(entry: entry)
                    }
                }
            }
            .navigationTitle("Passwords")
            .searchable(text: $searchText, prompt: "Search passwords")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { vaultManager.lock() }) {
                        Image(systemName: "lock.fill")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showingSync = true }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(vaultManager.syncStatus.contains("Connected") ? .green : .primary)
                        }
                        
                        Button(action: { showingAddEntry = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                AddEntryView()
            }
            .sheet(isPresented: $showingSync) {
                SyncView()
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
                Text(entry.username)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
        }
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
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(password.isEmpty || password != confirmPassword)
                
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
        
        do {
            try VaultManager.shared.initialize(with: password)
            onComplete()
        } catch {
            errorMessage = "Failed to create vault: \(error.localizedDescription)"
            showingError = true
        }
    }
}
