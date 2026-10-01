# Caffinate

Menu bar app that keeps your Mac awake so **processes keep running while locked**.

Uses a standard macOS menu bar menu (Apple HIG) wrapping `/usr/bin/caffeinate`, with live power-assertion health checks.

**Version:** 2.4.0 — see [CHANGELOG.md](CHANGELOG.md).

## Features

- **Keep Mac Awake** checkmark (title shows until-when when active)
- **Duration** submenu: indefinitely, 15m / 30m / 45m / 1h / 4h / 8h, **Until…** (clock time; past times roll to tomorrow)
- **Settings** submenu: launch at login, activate at launch, display sleep, notifications, power plug/unplug
- **Lock screen message** — while a session is active, sets the native macOS lock-screen text (`LoginwindowText`, same store as System Settings → Lock Screen). Indefinite sessions show a fixed message; timed / Until sessions include the end time. Restored when you stop or the session ends. First write may prompt for admin once; if the screen is already locked, unlock and lock once to see the new text.
- **Live re-apply** — changing Allow Display Sleep or duration while keep-awake is on updates the running session without toggling off/on
- **Check for Updates** / **Update to vX…** — downloads `Caffinate-macOS.zip` from [Mbo7682/Caffeinate](https://github.com/Mbo7682/Caffeinate/releases) and guides in-app replace
- Template menu-bar cup icon (filled while active)
- Safe quit (stops `caffeinate`)

Lid-closed / system-sleep (`-s`) mode is **not** included (removed in 2.0).

## Install

```bash
./scripts/install.sh
./scripts/install.sh --rebuild
```

### Uninstall

```bash
rm -rf /Applications/Caffinate.app
sudo rm -rf "/Library/Application Support/Caffinate" /etc/sudoers.d/caffinate-lock-screen
```

The second command removes the lock-screen helper the app installs on first use and the sudoers rule that lets it run without a password prompt. `./scripts/install.sh` also removes that rule so a replaced app re-registers it; expect one admin prompt after reinstalling.

After updating via **Update to vX…**, macOS Gatekeeper may block the replaced app. If so, right-click **Caffinate.app** → **Open** once.

## Development

Open `Caffinate.xcodeproj` in Xcode 15+, or:

```bash
./scripts/install.sh --rebuild
```

Requires macOS 14+.

## License

MIT
