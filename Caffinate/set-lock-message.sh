#!/bin/bash
# Sets the macOS lock screen message. Must be run with sudo or as root.
# Usage: set-lock-message.sh "message"   (use "" to clear)
defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText "$1"
