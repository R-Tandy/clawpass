#!/bin/bash

# Quick copy script - Run this on Windows (Git Bash or WSL) to copy files to Mac
# Then SSH into the Mac and run the build script

echo "Copying ClawPass source to Mac mini..."
echo ""

# Make sure we're in the right directory
cd "$(dirname "$0")"

# Copy the files
scp -r ios/* new@192.168.4.103:~/ClawPass-Build/

if [ $? -eq 0 ]; then
    echo ""
    echo "Files copied successfully!"
    echo ""
    echo "Now SSH into the Mac and run the build:"
    echo "  ssh new@192.168.4.103"
    echo "  bash ~/ClawPass-Build/build-ios-on-mac.sh"
else
    echo "Copy failed. Make sure the Mac is online and SSH is enabled."
fi
