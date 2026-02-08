#!/usr/bin/env bash
# Build Caffinate for Release and package it for sharing.
# Run from the project root (directory containing Caffinate.xcodeproj).
# Requires Xcode (xcode-select pointing at Xcode.app).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="Caffinate"
OUTPUT_DIR="$PROJECT_DIR/dist"
ZIP_NAME="Caffinate-macOS.zip"

cd "$PROJECT_DIR"

echo "Building Caffinate (Release)..."
xcodebuild -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$PROJECT_DIR/build" \
  build

APP_PATH="build/Build/Products/Release/Caffinate.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: $APP_PATH not found after build."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
echo "Copying app to $OUTPUT_DIR/..."
rm -rf "$OUTPUT_DIR/Caffinate.app"
cp -R "$APP_PATH" "$OUTPUT_DIR/"

echo "Creating $OUTPUT_DIR/$ZIP_NAME ..."
cd "$OUTPUT_DIR"
zip -r -y "$ZIP_NAME" "Caffinate.app"
cd "$PROJECT_DIR"

echo ""
echo "Done."
echo "  App:  $OUTPUT_DIR/Caffinate.app"
echo "  Zip:  $OUTPUT_DIR/$ZIP_NAME"
echo ""
echo "To share: send the zip file. Your friend should:"
echo "  1. Unzip and move Caffinate.app to Applications (or leave in Downloads)."
echo "  2. Open the app (menu bar icon appears)."
echo "  3. If macOS blocks it: right-click the app → Open → Open."
