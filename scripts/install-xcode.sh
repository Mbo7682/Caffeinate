#!/usr/bin/env bash
# Install Xcode from the Mac App Store and set it as the active developer directory.
# Run this in Terminal so you can enter your password if sudo is required.

set -e

echo "Installing Xcode from the App Store (this may take a while)..."
mas install 497799835

echo "Setting Xcode as active developer directory..."
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

echo "Accepting Xcode license (if prompted)..."
sudo xcodebuild -license accept 2>/dev/null || true

echo "Done. You can open Caffinate.xcodeproj in Xcode and build."
