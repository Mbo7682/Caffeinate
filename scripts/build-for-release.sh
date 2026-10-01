#!/usr/bin/env bash
# Build Caffinate for Release, Developer ID–sign, optionally notarize, and zip.
# Intermediate Xcode output lives under build/ (gitignored); packaged output is
# dist/Caffinate.app (+ dist/Caffinate-macOS.zip).
#
# Signing materials (not in git): ~/.caffinate-signing/
#   signing.keychain-db, p12.pass, and optionally AuthKey_*.p8 + api-key.json
#   api-key.json shape: {"key_id":"...","issuer_id":"...","key_path":"/abs/path/AuthKey_xxx.p8"}
#
# Run from the project root. Requires Xcode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="Caffinate"
OUTPUT_DIR="$PROJECT_DIR/dist"
ZIP_NAME="Caffinate-macOS.zip"
SIGN_DIR="${CAFFINATE_SIGN_DIR:-$HOME/.caffinate-signing}"
KEYCHAIN="$SIGN_DIR/signing.keychain-db"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: Michael Ostergaard (8RNSYLW2VB)}"
TEAM_ID="${DEVELOPMENT_TEAM:-8RNSYLW2VB}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

cd "$PROJECT_DIR"

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "Error: signing keychain not found at $KEYCHAIN"
  echo "Create a Developer ID Application identity first (see docs / setup notes)."
  exit 1
fi
if [[ ! -f "$SIGN_DIR/p12.pass" ]]; then
  echo "Error: missing $SIGN_DIR/p12.pass"
  exit 1
fi

KC_PASS="$(cat "$SIGN_DIR/p12.pass")"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
# Prefer our signing keychain for this process without permanently rewriting user search list
EXISTING="$(security list-keychains -d user | tr -d '"')"
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo "Building Caffinate (Release)..."
xcodebuild -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$PROJECT_DIR/build" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="build/Build/Products/Release/Caffinate.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: $APP_PATH not found after build."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
echo "Copying app to $OUTPUT_DIR/..."
rm -rf "$OUTPUT_DIR/Caffinate.app"
cp -R "$APP_PATH" "$OUTPUT_DIR/Caffinate.app"

echo "Signing with $IDENTITY ..."
codesign --force --deep --options runtime --timestamp \
  --sign "$IDENTITY" \
  --keychain "$KEYCHAIN" \
  "$OUTPUT_DIR/Caffinate.app"

codesign --verify --verbose=2 "$OUTPUT_DIR/Caffinate.app"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  API_JSON="$SIGN_DIR/api-key.json"
  if [[ -f "$API_JSON" ]]; then
    KEY_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["key_id"])' "$API_JSON")"
    ISSUER_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["issuer_id"])' "$API_JSON")"
    KEY_PATH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["key_path"])' "$API_JSON")"
    echo "Notarizing with App Store Connect API key $KEY_ID ..."
    # Zip for upload (notarytool wants a zip/dmg/pkg)
    NOTARY_ZIP="$OUTPUT_DIR/.notarize-Caffinate.zip"
    rm -f "$NOTARY_ZIP"
    ditto -c -k --keepParent "$OUTPUT_DIR/Caffinate.app" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" \
      --key "$KEY_PATH" \
      --key-id "$KEY_ID" \
      --issuer "$ISSUER_ID" \
      --wait
    xcrun stapler staple "$OUTPUT_DIR/Caffinate.app"
    rm -f "$NOTARY_ZIP"
    echo "Notarization stapled."
  else
    echo "Note: $API_JSON not found — skipping notarization (signed only)."
    echo "Gatekeeper may still warn until the app is notarized."
  fi
fi

echo "Creating $OUTPUT_DIR/$ZIP_NAME ..."
cd "$OUTPUT_DIR"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "Caffinate.app" "$ZIP_NAME"
cd "$PROJECT_DIR"

echo ""
echo "Done."
echo "  App:  $OUTPUT_DIR/Caffinate.app"
echo "  Zip:  $OUTPUT_DIR/$ZIP_NAME"
echo "  Team: $TEAM_ID"
echo "  Sign: $IDENTITY"
codesign -dv --verbose=2 "$OUTPUT_DIR/Caffinate.app" 2>&1 | grep -E 'Authority|TeamIdentifier|flags' || true
