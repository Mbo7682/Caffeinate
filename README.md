# Caffinate

Menu bar app that keeps your Mac awake so **processes keep running while locked**.

Uses a standard macOS menu bar menu (Apple HIG) wrapping `/usr/bin/caffeinate`, with live power-assertion health checks.

**Version:** 2.3.3 — see [CHANGELOG.md](CHANGELOG.md).

## Features

- **Keep Mac Awake** checkmark (title shows until-when when active)
- **Duration** submenu: indefinitely, 15m / 30m / 45m / 1h / 4h / 8h
- **Settings** submenu: launch at login, activate at launch, display sleep, notifications, power plug/unplug
- Template menu-bar cup icon (filled while active)
- Safe quit (stops `caffeinate`)

## Install

```bash
./scripts/install.sh
./scripts/install.sh --rebuild
```

```bash
rm -rf /Applications/Caffinate.app
```

## Development

Open `Caffinate.xcodeproj` in Xcode 15+, or:

```bash
./scripts/install.sh --rebuild
```

Requires macOS 14+.

## License

MIT
