#!/usr/bin/env bash
# Build (if needed) and install Caffinate.app to /Applications.
# Uses dist/Caffinate.app as the source (see build-for-release.sh); never installs
# from build/ derived data. Default destination is /Applications/Caffinate.app.
# Run from anywhere: ./scripts/install.sh
#
# Options:
#   --rebuild   Force a fresh Release build before installing
#   --no-open   Install without launching the app afterward
#   --help      Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Caffinate.app"
DIST_APP="$PROJECT_DIR/dist/$APP_NAME"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DEST="$INSTALL_DIR/$APP_NAME"

REBUILD=0
OPEN_AFTER=1

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=1 ;;
    --no-open) OPEN_AFTER=0 ;;
    --help|-h) usage ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Try: $0 --help" >&2
      exit 1
      ;;
  esac
done

cd "$PROJECT_DIR"

if [[ "$REBUILD" -eq 1 || ! -d "$DIST_APP" ]]; then
  echo "Building Release..."
  "$SCRIPT_DIR/build-for-release.sh"
fi

if [[ ! -d "$DIST_APP" ]]; then
  echo "Error: $DIST_APP not found." >&2
  exit 1
fi

# Clear quarantine so Gatekeeper doesn't block a locally built app.
xattr -dr com.apple.quarantine "$DIST_APP" 2>/dev/null || true

echo "Installing to ${DEST}..."
if [[ -d "$DEST" ]]; then
  # Quit running instance if present (menu bar app; ignore failure).
  osascript -e 'tell application "Caffinate" to quit' 2>/dev/null || true
  sleep 0.5
  pkill -x Caffinate 2>/dev/null || true
  sleep 0.3
  rm -rf "$DEST"
fi

# Remove legacy insecure sudoers rule from pre-1.1 builds (best-effort; may need admin).
if [[ -f /etc/sudoers.d/caffinate-lock-screen ]]; then
  echo "Removing legacy /etc/sudoers.d/caffinate-lock-screen (may prompt for password)..."
  osascript -e 'do shell script "rm -f /etc/sudoers.d/caffinate-lock-screen" with administrator privileges' 2>/dev/null || true
fi

cp -R "$DIST_APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Drop build/dev copies so Spotlight only indexes /Applications/Caffinate.app.
# Keep dist/*.zip for sharing; remove the unpackaged .app next to it.
rm -rf "$PROJECT_DIR/build"
rm -rf "$DIST_APP"

echo "Installed: $DEST"
VERSION="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unknown)"
BUILD="$(defaults read "$DEST/Contents/Info" CFBundleVersion 2>/dev/null || echo unknown)"
echo "Version: $VERSION ($BUILD)"

if [[ "$OPEN_AFTER" -eq 1 ]]; then
  echo "Launching Caffinate (menu bar)..."
  open "$DEST"
fi

echo ""
echo "Done. Look for the coffee cup in the menu bar."
echo "  One install location: $DEST"
echo "  Reinstall later:  ./scripts/install.sh"
echo "  Rebuild+install:  ./scripts/install.sh --rebuild"
echo "  Uninstall:        rm -rf \"$DEST\""
