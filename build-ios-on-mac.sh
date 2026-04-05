#!/bin/bash

# ClawPass iOS Build Script for Mac
# Run this on your Mac mini

set -e

echo "=========================================="
echo "ClawPass iOS Build Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This script must be run on macOS${NC}"
    exit 1
fi

echo "Step 1: Checking prerequisites..."

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Xcode is not installed!${NC}"
    echo ""
    echo "Please install Xcode from the Mac App Store:"
    echo "1. Open App Store"
    echo "2. Search for 'Xcode'"
    echo "3. Click 'Get' or 'Install'"
    echo "4. Wait for download (about 10-20 GB, may take 30-60 minutes)"
    echo "5. Open Xcode at least once to complete installation"
    echo ""
    echo "After Xcode is installed, run this script again."
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version | head -n 1)
echo -e "${GREEN}✓ Found: $XCODE_VERSION${NC}"

# Accept Xcode license if needed
if ! xcodebuild -license check &> /dev/null; then
    echo ""
    echo -e "${YELLOW}Xcode license needs to be accepted.${NC}"
    echo "Running: sudo xcodebuild -license accept"
    sudo xcodebuild -license accept
fi

# Check for command line tools
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Please complete the installation in the dialog, then run this script again."
    exit 0
fi

echo -e "${GREEN}✓ Command line tools installed${NC}"

# Create working directory
WORK_DIR="$HOME/ClawPass-Build"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo ""
echo "Step 2: Getting the source code..."

# Check if we need to copy from Windows
if [ ! -d "$WORK_DIR/ClawPass" ]; then
    echo ""
    echo -e "${YELLOW}Source code not found.${NC}"
    echo ""
    echo "Please copy the ClawPass iOS project from your Windows machine:"
    echo ""
    echo "Option A - File Sharing:"
    echo "  1. On Windows, right-click the folder: C:\Users\Reno\.openclaw\workspace\projects\password-manager\ClawPass\ios"
    echo "  2. Select 'Properties' → 'Sharing' → 'Share'"
    echo "  3. Note the network path (e.g., \\YOUR_PC\ios)"
    echo "  4. On this Mac, open Finder → Go → Connect to Server"
    echo "  5. Enter: smb://YOUR_PC_IP/ios"
    echo "  6. Copy the files to: $WORK_DIR"
    echo ""
    echo "Option B - USB Drive:"
    echo "  1. Copy the folder to a USB drive on Windows"
    echo "  2. Plug into this Mac"
    echo "  3. Copy the files to: $WORK_DIR"
    echo ""
    echo "Option C - Direct copy command (if Windows has SSH):"
    echo "  Run this on Windows (with WSL or Git Bash):"
    echo "  scp -r projects/password-manager/ClawPass/ios/* new@192.168.4.103:~/ClawPass-Build/"
    echo ""
    echo "Once copied, run this script again."
    exit 1
fi

echo -e "${GREEN}✓ Source code found${NC}"

cd "$WORK_DIR/ios"

echo ""
echo "Step 3: Building ClawPass..."
echo "This may take a few minutes..."
echo ""

# Clean any previous builds
rm -rf build DerivedData

# Build the app
xcodebuild \
    -project ClawPass.xcodeproj \
    -scheme ClawPass \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}Build failed!${NC}"
    echo "Check the error messages above."
    exit 1
fi

echo -e "${GREEN}✓ Build successful${NC}"

# Find the built app
APP_PATH=$(find build/DerivedData -name "ClawPass.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}Error: Could not find built .app bundle${NC}"
    exit 1
fi

echo ""
echo "Step 4: Creating IPA file..."

# Create Payload directory
mkdir -p build/Payload
cp -R "$APP_PATH" build/Payload/

# Create IPA
cd build
zip -r ClawPass.ipa Payload

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create IPA${NC}"
    exit 1
fi

echo -e "${GREEN}✓ IPA created successfully!${NC}"
echo ""
echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo ""
echo "IPA Location:"
echo "  $WORK_DIR/ios/build/ClawPass.ipa"
echo ""
echo "File size:"
ls -lh ClawPass.ipa
echo ""
echo "Next steps:"
echo "  1. Transfer the IPA to your iPhone using AltStore"
echo "     a. Install AltServer on your Windows PC"
echo "     b. Install AltStore on your iPhone"
echo "     c. Connect iPhone to PC via USB"
echo "     d. In AltStore, tap '+' and select ClawPass.ipa"
echo ""
echo "  2. Or transfer via AirDrop/email:"
echo "     a. Right-click ClawPass.ipa"
echo "     b. Share → AirDrop to your iPhone"
echo "     c. Open in AltStore"
echo ""
echo -e "${GREEN}Done!${NC}"
