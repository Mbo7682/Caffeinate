#!/bin/bash
# Sets or clears macOS LoginwindowText (System Settings → Lock Screen message).
# Usage: set-lock-message.sh --set "message"
#        set-lock-message.sh --clear     # delete key
set -e

PLIST="/Library/Preferences/com.apple.loginwindow"

case "${1:-}" in
  --set)
    [[ "$#" -eq 2 ]] || exit 64
    /usr/bin/defaults write "$PLIST" LoginwindowText "$2"
    ;;
  --clear)
    [[ "$#" -eq 1 ]] || exit 64
    /usr/bin/defaults delete "$PLIST" LoginwindowText 2>/dev/null || true
    ;;
  *)
    exit 64
    ;;
esac
