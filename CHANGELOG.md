# Changelog

All notable changes to Caffinate are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2025-02-08

### Added

- Menu bar app (icon only) that runs the system `caffeinate` command to keep the Mac awake while locked.
- Support for all caffeinate options: Display (-d), Idle (-i), AC power (-s), User active (-u), Disk (-m), and optional timeout (-t).
- Notifications when keep-awake is started or stopped.
- Optional “Show on lock screen”: sets the system lock screen message to “Caffinate is keeping this Mac awake” while running.
- One-time setup for lock screen message so the system only prompts for your password once.
- Custom app icon (coffee cup) for the app and notifications.
- Frosted / liquid-glass style popover UI (SwiftUI, macOS 14+).
- Build script and README instructions for building a shareable Release build (zip for distribution).

### Technical

- macOS 14.0 (Sonoma) or later.
- SwiftUI, MenuBarExtra (.window style), no dock icon (LSUIElement).

