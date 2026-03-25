# Changelog

All notable changes to Caffinate are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.2] - 2026-03-25

### Added

- Lid-closed keep-awake mode with a required timeout
- GitHub releases version update check (shows “Updates” only when a newer release exists)
- Right-click on the menu bar icon for quick Start/Stop
- “Re-enter password” button when lock-screen sudo configuration needs credentials again

### Changed

- Popover UI tightened: Start/Stop moved into the header and updated styling

## [1.0.1] - 2026-03-03

### Added

- Timeout countdown in the popover header while Caffinate is active.
- Lock screen message end-time format when timeout is enabled (for example: “keeping awake until 17:30”).

### Fixed

- Lock screen message now clears when the caffeinate process terminates (including timeout completion).
- Start/Stop button hit area now responds across the full button surface, not only text/icon.
- Active-state header highlight now fills to the very top edge of the popover.

### Changed

- Active-state UI uses a clearer red-tinted visual treatment for both header and Stop button.
- Documented lock-screen behavior: login window text does not live-refresh while already locked (macOS limitation).

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

