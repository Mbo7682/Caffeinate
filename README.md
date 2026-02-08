# Caffinate

A small macOS menu bar app that runs the system `caffeinate` command so your Mac stays awake while locked. Uses a liquid-glass style UI and supports all caffeinate options.

**Version:** 1.0.0 — see [CHANGELOG.md](CHANGELOG.md) for release history.

## Features

- **Menu bar only** — runs from the menu bar; no dock icon (`LSUIElement`)
- **Caffeinate options** — Display (-d), Idle (-i), AC power (-s), User active (-u), Disk (-m)
- **Optional timeout** — run for a set number of seconds (-t)
- **Notifications** — notifies when keep-awake is started or stopped
- **Show on lock screen** — optional: set the system lock screen message to “Caffinate is keeping this Mac awake” while running (uses the same message as System Settings → Lock Screen; may prompt for your password to set/clear)
- **SwiftUI** — frosted glass / ultra-thin material popover (liquid-glass style on recent macOS)

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ to build

## Prerequisites (one-time)

To build this app you need **Xcode** (not only Command Line Tools). Prereqs that are already set up:

- **Homebrew** and **mas** (Mac App Store CLI) are installed.

To install Xcode (large download, ~12GB), run this in **Terminal** (so you can enter your password if prompted):

```bash
mas install 497799835
```

When the install finishes, point the active developer directory to Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Alternatively, install Xcode from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835) in the usual way, then run the `xcode-select` command above.

## Build and run

1. Open `Caffinate.xcodeproj` in Xcode.
2. Choose the **Caffinate** scheme and **My Mac** as destination.
3. Press **Run** (⌘R).

The app will appear in the menu bar. Click it to open the popover, choose options, and tap **Start** to run `caffeinate`. Allow notifications when prompted to get start/stop alerts.

## Building for distribution (sharing with others)

To build a **Release** version you can share (e.g. as a zip):

**Option A – Script (recommended)**  
From the project root, run:

```bash
./scripts/build-for-release.sh
```

This builds the app and creates:
- `dist/Caffinate.app` — the app bundle
- `dist/Caffinate-macOS.zip` — ready to send

**Option B – Xcode**  
1. **Product → Scheme → Edit Scheme** → set **Run** to **Release** (or leave **Build Configuration** as Release for Archive).  
2. **Product → Archive**.  
3. In the Organizer window: **Distribute App** → **Copy App** (or **Custom** → export as Mac Application).  
4. Zip the resulting `Caffinate.app` and share the zip.

**For your friend**  
- Unzip and move `Caffinate.app` to **Applications** (or keep it in Downloads).  
- Double‑click to open. The app runs from the **menu bar** (no dock icon).  
- If macOS says the app is from an unidentified developer: **right‑click** the app → **Open** → **Open** once; after that it will open normally.

The app is not notarized, so Gatekeeper may require that one-time “Open” step.

## Caffinate options (short reference)

| Option     | Flag | Description                          |
|-----------|------|--------------------------------------|
| Display   | `-d` | Prevent display from sleeping        |
| Idle      | `-i` | Prevent system from idle sleeping    |
| AC power  | `-s` | Prevent system sleep (AC power only) |
| User active| `-u` | Declare user active (default 5 s unless timeout set) |
| Disk      | `-m` | Prevent disk from idle sleeping      |
| Timeout   | `-t N` | Run for N seconds (optional)       |

Default selection is **Display** and **Idle**, which is a good choice for “stay awake while locked.”

## License

MIT
