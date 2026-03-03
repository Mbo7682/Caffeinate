# Caffinate: AI Coding Agent Instructions

## Project Overview

**Caffinate** is a lightweight macOS menu bar application that runs the system `caffeinate` command to prevent the Mac from sleeping while locked. It provides a frameless SwiftUI popover UI with configurable sleep-prevention options, optional timeout, and an advanced lock screen message feature.

**Key Properties:**
- Menu bar only (no Dock icon via `LSUIElement`)
- SwiftUI with frosted-glass UI
- Requires macOS 14.0+, Xcode 15+
- Single app target with bundled helper script

---

## Architecture & Data Flow

### Core Components

1. **[CaffeinateApp.swift](Caffinate/CaffinateApp.swift)** — Entry point  
   - Creates a `MenuBarExtra` scene with coffee cup icon label
   - Icon toggles between filled/unfilled based on `manager.isActive`
   - Window size: 280×420 points

2. **[CaffeinateManager.swift](Caffinate/CaffeinateManager.swift)** — State & process management  
   - `@MainActor` final class managing the caffeinate process
   - Published properties: `isActive`, `options`, `timeoutSeconds`, `hasTimeout`, `showOnLockScreen`, `lockScreenSetupDone`
   - Enum `Option: CaseIterable` maps user choices to caffeinate flags (`-d`, `-i`, `-s`, `-u`, `-m`)
   - Routes notifications through `UNUserNotificationCenter`

3. **[PopoverView.swift](Caffinate/PopoverView.swift)** — Reactive UI  
   - Vertical stack with sections: header, options toggles, timeout input, lock screen toggle, main start/stop, quit button
   - Uses `@ObservedObject` to react to manager changes
   - `OptionRow` component for each caffeinate option

### Data Flow

```
User toggles option → PopoverView → manager.toggle(option) → updates options Set
User presses Start → manager.start() → builds args from options/timeout → 
  Process.run(/usr/bin/caffeinate) → isActive = true → notification posted
When process terminates → terminationHandler → isActive = false → stop notification
```

### Persistence

- User preferences stored in `UserDefaults.standard`:  
  `"showOnLockScreen"` → bool  
  `"lockScreenSudoersSetupDone"` → bool (one-time flag)

---

## Critical Workflows

### Building & Running

```bash
# Development build in Xcode
1. Open Caffinate.xcodeproj
2. Select Caffinate scheme, destination "My Mac"
3. ⌘R to run

# Release build (for distribution)
./scripts/build-for-release.sh
# Creates: dist/Caffinate.app and dist/Caffinate-macOS.zip
```

### Lock Screen Message Feature

The lock screen functionality involves **privileged operations** requiring special handling:

1. **First-time setup** (`runLockScreenOneTimeSetup()`):  
   - User toggles "Show on lock screen" → prompts for admin password via `osascript`  
   - Installs sudoers rule: `username ALL=(ALL) NOPASSWD: /bin/bash /path/to/set-lock-message.sh *`
   - Flags `lockScreenSetupDone` in UserDefaults
2. **Runtime updates** (`setLockScreenMessage()`):  
   - Calls `/usr/bin/sudo /bin/bash set-lock-message.sh "message"`  
   - Helper script writes to `/Library/Preferences/com.apple.loginwindow/LoginwindowText`
   - No password prompt (passwordless via sudoers rule)

**Important:** The helper script `[set-lock-message.sh](Caffinate/set-lock-message.sh)` must be:
- Bundled with the app (in Xcode: Build Phases → Copy Bundle Resources)
- Located via `Bundle.main.path(forResource: "set-lock-message", ofType: "sh")`

---

## Project-Specific Patterns

### Thread Safety

All state mutations happen on the main thread via `@MainActor`:
```swift
@MainActor
final class CaffeinateManager: ObservableObject { ... }
```

Async work uses `Task { @MainActor in ... }` to return to main thread.

### Process Management

- Create `Process`, set `executableURL`, `arguments`, and `terminationHandler`  
- Handler runs on a background thread; use `Task { @MainActor in ... }` to update UI
- Always call `task.run()` (not `task.launch()` for macOS 10.12+)

### Notification Pattern

`sendNotification(title:body:)` checks authorization before posting:
```swift
UNUserNotificationCenter.current().getNotificationSettings { settings in
    if settings.authorizationStatus == .authorized { /* post */ }
}
```

Permission request is async:
```swift
let center = UNUserNotificationCenter.current()
_ = try? await center.requestAuthorization(options: [.alert, .sound])
```

### Option Toggles

Caffeinate options are managed as a `Set<Option>`:
```swift
@Published var options: Set<Option> = [.preventIdleSleep, .preventDisplaySleep]

func toggle(_ option: Option) {
    if options.contains(option) { options.remove(option) } 
    else { options.insert(option) }
}
```

Loop through `Option.allCases` in UI to iterate and map to flags.

---

## Integration Points & External Dependencies

### System Commands

- `/usr/bin/caffeinate` — core sleep-prevention utility  
- `/usr/bin/osascript` — elevate to admin for first-time sudoers setup
- `/usr/bin/sudo` — run lock screen helper script without password (post-setup)
- `/bin/bash` — execute helper script

### Frameworks

- **SwiftUI** — UI framework
- **Foundation** — Process, UserDefaults, UNUserNotificationCenter
- **AppKit** — (imported in PopoverView for potential NSUserName or future features)
- **UserNotifications** — notification delivery

### Bundle Resources

- `set-lock-message.sh` — included in app bundle; used for lock screen message updates

---

## Common Modification Patterns

### Adding a New Caffeinate Option

1. Add case to `CaffeinateManager.Option` enum with flag and help text
2. UI automatically renders in PopoverView (iterates `Option.allCases`)
3. Arguments built in `buildArguments()` based on options Set

### Changing UI Layout

PopoverView sections are independently stacked. Dividers separate them. Modify padding/spacing in sections or swap section order in `VStack`.

### Modifying Notifications

All notifications go through `sendNotification(title:body:)`. Search for this call to see all notification points: start, stop, errors, lock screen setup completion.

---

## Common Pitfalls

- **Process not found:** Path must be absolute (e.g., `/usr/bin/caffeinate`, not `caffeinate`)
- **Helper script not bundled:** Build Phases must include it; check with `Bundle.main.path(...)`
- **Sudoers rule not persisted:** One-time setup flag (`lockScreenSetupDone`) must be saved before calling privileged operations
- **Main thread updates:** Process terminationHandler runs off-main; always wrap UI updates in `Task { @MainActor in ... }`

---

## Entry Points for Modifications

- **UI changes:** PopoverView sections
- **Caffeinate options:** CaffeinateManager.Option enum
- **Notifications:** CaffeinateManager notification calls
- **Preferences:** Add new published properties and UserDefaults keys in CaffeinateManager.init
- **Lock screen logic:** runLockScreenOneTimeSetup() and setLockScreenMessage()
