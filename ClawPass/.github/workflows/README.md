# GitHub Actions Setup for iOS Builds

## Automatic Builds

This workflow builds the iOS app on every push to `master` that changes the `ios/` folder.

### Build Types

1. **Simulator Build** - Runs on every push/PR (no signing needed)
2. **IPA Build** - Manual trigger or master branch (needs signing for device install)

## Setting Up Code Signing (Required for IPA)

To install the app on a real iPhone, you need:

### 1. Apple Developer Account
- Enroll at https://developer.apple.com/programs/
- $99/year

### 2. Create Signing Certificate
```bash
# On a Mac, open Keychain Access
# Request Certificate from Certificate Authority
# Upload to Apple Developer Portal
# Download and install

# Export as .p12
openssl pkcs12 -export \
  -in "Certificate.pem" \
  -inkey "private.key" \
  -out "Certificates.p12" \
  -password pass:YOUR_PASSWORD

# Base64 encode for GitHub secret
base64 -i Certificates.p12 | pbcopy
```

### 3. Create Provisioning Profile
- Apple Developer Portal → Certificates, Identifiers & Profiles
- Create App ID: `com.clawpass.ios`
- Create Development provisioning profile
- Download and keep safe

### 4. Add GitHub Secrets

Go to GitHub Repo → Settings → Secrets and variables → Actions

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `CERTIFICATE_P12` | Base64-encoded .p12 certificate |
| `CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `APPSTORE_ISSUER_ID` | Apple Developer Portal Issuer ID |
| `APPSTORE_API_KEY_ID` | App Store Connect API Key ID |
| `APPSTORE_API_PRIVATE_KEY` | App Store Connect API Private Key |

### 5. Alternative: Manual IPA Install

Without signing, you can still build and install via:

**Option A: AltStore (Free)**
1. Install AltServer on Windows/Mac
2. Connect iPhone via USB
3. Sideload the unsigned IPA

**Option B: Xcode + Free Developer Account**
1. Sign in with Apple ID in Xcode
2. Build to your device
3. Trust developer in Settings

## Current Status

The workflow will:
- ✅ Build for Simulator (always works)
- ⚠️ Build IPA (needs signing setup above)
- 📦 Upload artifacts for download

## Downloading Builds

1. Go to GitHub Repo → Actions tab
2. Click on the latest workflow run
3. Scroll to "Artifacts" section
4. Download `ClawPass-iOS.zip`

## Installing Unsigned IPA

```bash
# Using ideviceinstaller (requires jailbreak or AltStore)
ideviceinstaller -i ClawPass.ipa

# Or use AltStore for non-jailbroken devices
```
