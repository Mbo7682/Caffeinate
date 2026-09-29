# Changelog

All notable changes to Caffinate are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.3.4] - 2026-09-29

### Fixed

- Menu SF Symbol icons now render (explicit 16×16 template images — AppKit was dropping zero-size symbols)

### Changed

- Duration parent title shows the current selection (e.g. “Duration — Indefinitely”)

## [2.3.3] - 2026-09-29

### Added

- SF Symbol icons on menu items (cup, timer, gear, settings toggles) — sparingly per Menus HIG

### Changed

- Duration parent shows current selection in its tooltip

## [2.3.2] - 2026-09-29

### Changed

- Merged status into the **Keep Mac Awake** checkmark (e.g. “Keep Mac Awake · until you stop”) — no separate grey header row

## [2.3.1] - 2026-09-29

### Changed

- **Settings** is a submenu (like Duration), not a separate window

## [2.3.0] - 2026-09-29

### Changed

- Menu bar extra uses a standard `NSMenu` (Apple HIG) instead of a custom popover
- Template cup icon; Duration and Settings as submenus; Settings window removed in 2.3.1

### Removed

- Custom glass popover UI (`PopoverView`)

## [2.1.0] - 2026-09-29

### Added

- Caffeinated-style menu: on/off toggle, duration chips (∞ / 15 / 30 / 45 / 1h / 4h / 8h / 12h), “Active until …”
- Settings: launch at login, activate at launch, allow display to sleep, notifications, power connect/disconnect
- Timed sessions via `caffeinate -t`

### Changed

- Default allows display sleep (Mac stays awake; screen may blank) — matches “processes keep running while locked”

## [2.0.0] - 2026-09-29

### Changed

- **A+ cleanup** — one job: keep processes running while the Mac is locked
- Options reduced to **Stay awake** (`-i`) and **Screen** (`-d`)
- Status is the animated coffee cup (no status sentence clutter)
- Health still verified live via `pmset` power assertions

### Removed

- Lock-screen message feature (`LockScreenService` and admin prompts)
- Timeout, lid-closed / system-sleep (`-s`), User active (`-u`), Disk (`-m`)
- Legacy UserDefaults keys from older builds

## [1.3.3] - 2026-09-29

### Fixed

- Lock-screen note was written to disk but often invisible until `loginwindow` reloaded. After saving, Caffinate now soft-reloads loginwindow and tells you to lock with ⌃⌘Q (and unlock/lock once more if needed).

## [1.3.2] - 2026-09-29

### Fixed

- Lock-screen control looked disabled on macOS 27 because the popover was a non-activating panel. It is now a keyable panel and uses the same on/off checkmark as Display / Idle.
- Turning lock screen on/off no longer freezes the popover while waiting for the admin password prompt.



### Removed

- Timeout and Lid closed mode controls from the popover (not part of the primary Display + Idle walk-away flow)

## [1.3.0] - 2026-09-29

### Added

- **Live re-apply** — changing Display / Idle / Disk / User active, timeout, or lid-closed mode while Start is active silently restarts `caffeinate` with the new arguments (no Stop/Start, no start/stop notification spam)
- Always passes `-w <appPID>` so keep-awake assertions die if the app quits hard
- Caption under Options while running: “Changes apply immediately while running.”
- Unit tests for argument building, desired-args live-apply shape, version compare, and lock-message sanitization

### Changed

- Restored modern stack: `NSStatusItem` + keyable `NSPanel` (no `MenuBarExtra`), split services (`CaffeinateCommandBuilder`, `LockScreenService`, `NotificationService`, `VersionCompare`)
- Options-only restarts **preserve** remaining countdown time; changing the timeout value restarts the countdown from the new timeout
- Clearing all keep-awake options while active stops keep-awake instead of running empty `caffeinate`
- Lid-closed still requires a valid timeout; `-s` is not applied until timeout is set (notifies if toggled on without one while active)
- Update check points at `thomasfrisk/Caffeinate`; HTTP 404 → up to date
- Version **1.3.0** (build 5)

### Removed

- Bundle dependency on `set-lock-message.sh` / sudoers-based lock-screen setup
- “Re-enter password” / sudoers UI

## [1.2.0] - 2026-08-10

### Added

- `NSStatusItem` + keyable floating panel (reliable text-field focus)
- Lock screen via admin `osascript` defaults write/delete (no sudoers)
- Notification pending-retry after permission grant
- Quit cleanup for orphan `caffeinate` and lock-screen text

### Changed

- Hide manual “System sleep” row; drive `-s` from lid-closed mode only
- Persist options / timeout / toggles in UserDefaults
- Update checker owner set to fork; 404 treated as up to date

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
