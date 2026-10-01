# Post-HIG Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On top of Thomas’s HIG menu branch, fix GitHub updates (correct repo + download/replace), add Duration Until…, harden live re-apply, and restore native lock-screen messaging for every keep-awake session.

**Architecture:** Keep the AppKit `NSMenu` status item. Extend `SessionDuration` with `.until(hour:minute:)`. Add `LockScreenMessageService` + bundle helper for `LoginwindowText`. Replace `UpdateChecker` defaults with `Mbo7682/Caffeinate`, parse zip assets, and hand off install via an external shell script after quit.

**Tech Stack:** Swift / AppKit / Combine, `/usr/bin/caffeinate`, GitHub Releases REST API, `osascript` + narrow sudoers helper for loginwindow prefs, XCTest via `xcodebuild test`.

**Spec:** `docs/superpowers/specs/2026-09-30-post-hig-fixes-design.md`

## Global Constraints

- Branch: `feature/post-hig-fixes` (already includes HIG menu commits).
- Canonical release repo: `Mbo7682/Caffeinate`.
- Release asset name: `Caffinate-macOS.zip` containing `Caffinate.app`.
- Lock screen: always set/clear for sessions (no Settings toggle); restore prior `LoginwindowText`.
- Past Until times roll to tomorrow.
- Lid-closed / `-s` stays removed.
- Do not auto-download updates without a user click.
- Prefer silent `caffeinate` restarts (`notify: false`) for option/duration changes while active.
- Add new Swift sources to `Caffinate.xcodeproj/project.pbxproj` (IDs follow existing `CAFF…` pattern) and Resources for the lock helper script.
- Run tests with: `xcodebuild -scheme Caffinate -destination 'platform=macOS' test`

## File map

| File | Responsibility |
|------|----------------|
| `Caffinate/UpdateChecker.swift` | GitHub latest check, asset URL, 24h timer, install entry point |
| `Caffinate/AppUpdateInstaller.swift` | Download zip, unzip, validate, launch replace handoff |
| `Caffinate/CaffeinateCommandBuilder.swift` | `SessionDuration` + until helpers (pure) |
| `Caffinate/UntilTimePanelController.swift` | Small NSPanel time picker |
| `Caffinate/StatusItemController.swift` | Duration Until…, update menu actions |
| `Caffinate/CaffeinateManager.swift` | Until selection, live re-apply, lock message lifecycle |
| `Caffinate/LockScreenMessageService.swift` | Snapshot / set / restore LoginwindowText |
| `Caffinate/set-lock-message.sh` | Root-only defaults write/delete for LoginwindowText |
| `CaffinateTests/CaffinateTests.swift` | Unit coverage for new pure logic |
| `README.md`, `CHANGELOG.md` | User-facing notes |
| `Caffinate.xcodeproj/project.pbxproj` | Register new sources/resources |

---

### Task 1: GitHub asset picker + fix UpdateChecker repo

**Files:**
- Modify: `Caffinate/UpdateChecker.swift`
- Modify: `CaffinateTests/CaffinateTests.swift`
- Modify: `Caffinate.xcodeproj/project.pbxproj` only if a new file is split out (prefer keeping helpers in `UpdateChecker.swift` for this task)

**Interfaces:**
- Produces: `UpdateChecker.preferredZipAssetURL(from assets: [GitHubAsset]) -> URL?`
- Produces: default `owner = "Mbo7682"`, `repo = "Caffeinate"`
- Produces: `State.updateAvailable(current:latest:releaseURL:assetURL:)` (asset URL optional)

- [ ] **Step 1: Write the failing tests**

Add to `CaffinateTests/CaffinateTests.swift`:

```swift
func testPreferredZipAssetPrefersNamedZip() {
    let assets = [
        UpdateChecker.GitHubAsset(name: "notes.txt", browserDownloadUrl: "https://example.com/notes.txt"),
        UpdateChecker.GitHubAsset(name: "Caffinate-macOS.zip", browserDownloadUrl: "https://example.com/Caffinate-macOS.zip"),
        UpdateChecker.GitHubAsset(name: "other.zip", browserDownloadUrl: "https://example.com/other.zip")
    ]
    XCTAssertEqual(
        UpdateChecker.preferredZipAssetURL(from: assets)?.absoluteString,
        "https://example.com/Caffinate-macOS.zip"
    )
}

func testPreferredZipAssetFallsBackToFirstZip() {
    let assets = [
        UpdateChecker.GitHubAsset(name: "readme.md", browserDownloadUrl: "https://example.com/readme.md"),
        UpdateChecker.GitHubAsset(name: "build.zip", browserDownloadUrl: "https://example.com/build.zip")
    ]
    XCTAssertEqual(
        UpdateChecker.preferredZipAssetURL(from: assets)?.absoluteString,
        "https://example.com/build.zip"
    )
}
```

Make `GitHubAsset` and `preferredZipAssetURL` accessible (`internal` / nested types used from tests via `@testable import Caffinate`).

- [ ] **Step 2: Run tests — expect fail**

Run: `xcodebuild -scheme Caffinate -destination 'platform=macOS' test -only-testing:CaffinateTests/CaffinateTests/testPreferredZipAssetPrefersNamedZip`

Expected: compile error or FAIL (symbol missing).

- [ ] **Step 3: Implement asset picker + repo default + decode assets**

In `UpdateChecker.swift`:

```swift
init(
    owner: String = "Mbo7682",
    repo: String = "Caffeinate",
    session: URLSession = .shared
) { ... }

enum State: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case updateAvailable(current: String, latest: String, releaseURL: URL, assetURL: URL?)
    case failed(message: String)
}

struct GitHubAsset: Decodable, Equatable {
    let name: String?
    let browserDownloadUrl: String?
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

static func preferredZipAssetURL(from assets: [GitHubAsset]) -> URL? {
    let zips = assets.compactMap { asset -> (String, URL)? in
        guard let name = asset.name, name.lowercased().hasSuffix(".zip"),
              let s = asset.browserDownloadUrl, let url = URL(string: s) else { return nil }
        return (name, url)
    }
    if let preferred = zips.first(where: { $0.0 == "Caffinate-macOS.zip" }) {
        return preferred.1
    }
    return zips.first?.1
}
```

Extend `GitHubLatestRelease` with `assets: [GitHubAsset]?`. When building `updateAvailable`, pass `preferredZipAssetURL(from: decoded.assets ?? [])`.

Update `StatusItemController` call sites that pattern-match `.updateAvailable` to the new associated values (keep opening release URL for now if install is not wired yet — next tasks).

- [ ] **Step 4: Run tests — expect pass**

Run: `xcodebuild -scheme Caffinate -destination 'platform=macOS' test -only-testing:CaffinateTests`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Caffinate/UpdateChecker.swift Caffinate/StatusItemController.swift CaffinateTests/CaffinateTests.swift
git commit -m "fix: point update checks at Mbo7682/Caffeinate and prefer zip asset"
```

---

### Task 2: Periodic check + Check for Updates menu

**Files:**
- Modify: `Caffinate/UpdateChecker.swift`
- Modify: `Caffinate/StatusItemController.swift`

**Interfaces:**
- Consumes: Task 1 `State` / `check()`
- Produces: `UpdateChecker.startPeriodicChecks(interval: TimeInterval = 86_400)`
- Produces: menu actions `checkForUpdates` / `installUpdate`

- [ ] **Step 1: Add periodic timer to UpdateChecker**

```swift
private var periodicTask: Task<Void, Never>?

func startPeriodicChecks(interval: TimeInterval = 86_400) {
    periodicTask?.cancel()
    periodicTask = Task { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.check()
        }
    }
}
```

Call `startPeriodicChecks()` from `CaffinateApp` / `AppDelegate` after creating `UpdateChecker` (in addition to the existing launch `check()`).

- [ ] **Step 2: Wire menu rows in StatusItemController.rebuildMenu**

Near Quit:

```swift
menu.addItem(.separator())

switch updateChecker.state {
case .updateAvailable(_, let latest, let releaseURL, let assetURL):
    let update = NSMenuItem(
        title: MenuGlyph.titled(MenuGlyph.update, "Update to v\(latest)…"),
        action: #selector(installUpdate(_:)),
        keyEquivalent: ""
    )
    update.target = self
    update.representedObject = UpdateMenuContext(releaseURL: releaseURL, assetURL: assetURL, latest: latest)
    menu.addItem(update)
case .checking:
    let checking = NSMenuItem(title: "Checking for Updates…", action: nil, keyEquivalent: "")
    checking.isEnabled = false
    menu.addItem(checking)
default:
    let check = NSMenuItem(
        title: MenuGlyph.titled(MenuGlyph.update, "Check for Updates…"),
        action: #selector(checkForUpdates),
        keyEquivalent: ""
    )
    check.target = self
    menu.addItem(check)
}
```

```swift
private struct UpdateMenuContext {
    let releaseURL: URL
    let assetURL: URL?
    let latest: String
}

@objc private func checkForUpdates() {
    Task { await updateChecker.check() }
}

@objc private func installUpdate(_ sender: NSMenuItem) {
    guard let ctx = sender.representedObject as? UpdateMenuContext else { return }
    // Task 3 replaces this body with AppUpdateInstaller; for now open releaseURL if no installer yet.
    NSWorkspace.shared.open(ctx.releaseURL)
}
```

- [ ] **Step 3: Manual smoke**

Run the app (`./scripts/install.sh --rebuild` or Xcode). Open menu: should show **Check for Updates…** (current latest is 1.0.2; app may be 2.3.x so **Update to v…** may appear if GitHub latest is older — note: if local version is newer than GitHub, menu shows Check). Force `check()` and confirm no crash and repo is Mbo7682 (optional: temporarily log the request URL).

- [ ] **Step 4: Commit**

```bash
git add Caffinate/UpdateChecker.swift Caffinate/StatusItemController.swift Caffinate/CaffinateApp.swift
git commit -m "feat: periodic update checks and Check for Updates menu item"
```

---

### Task 3: Download zip and replace app handoff

**Files:**
- Create: `Caffinate/AppUpdateInstaller.swift`
- Modify: `Caffinate/StatusItemController.swift`
- Modify: `Caffinate/CaffinateApp.swift` (pass manager for clean shutdown if needed)
- Modify: `Caffinate.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `AppUpdateInstaller.install(assetURL:releaseURL:latest:prepareForQuit:)` async
- Consumes: `UpdateMenuContext` from Task 2

- [ ] **Step 1: Add AppUpdateInstaller.swift**

```swift
import AppKit
import Foundation

enum AppUpdateInstaller {
    enum InstallError: LocalizedError {
        case missingAsset
        case downloadFailed
        case invalidZip
        case replaceFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAsset: return "This release has no downloadable zip."
            case .downloadFailed: return "Could not download the update."
            case .invalidZip: return "The update archive did not contain Caffinate.app."
            case .replaceFailed(let s): return s
            }
        }
    }

    @MainActor
    static func confirmAndInstall(
        assetURL: URL?,
        releaseURL: URL,
        latest: String,
        prepareForQuit: () -> Void
    ) async {
        let alert = NSAlert()
        alert.messageText = "Update to v\(latest)?"
        alert.informativeText = "Download and install Caffinate v\(latest)? The app will quit and reopen."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let assetURL else {
            NSWorkspace.shared.open(releaseURL)
            return
        }

        do {
            let newApp = try await downloadAndUnzip(assetURL: assetURL)
            prepareForQuit()
            try launchReplaceHandoff(newAppURL: newApp, targetAppURL: Bundle.main.bundleURL)
            NSApp.terminate(nil)
        } catch {
            let fail = NSAlert()
            fail.messageText = "Update failed"
            fail.informativeText = error.localizedDescription + "\n\nOpening the release page instead."
            fail.runModal()
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private static func downloadAndUnzip(assetURL: URL) async throws -> URL {
        let (fileURL, response) = try await URLSession.shared.download(from: assetURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InstallError.downloadFailed
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaffinateUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zipPath = work.appendingPathComponent("Caffinate-macOS.zip")
        try? FileManager.default.removeItem(at: zipPath)
        try FileManager.default.moveItem(at: fileURL, to: zipPath)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-xk", zipPath.path, work.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw InstallError.invalidZip }

        let appURL = work.appendingPathComponent("Caffinate.app")
        guard FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Contents/Info.plist").path) else {
            throw InstallError.invalidZip
        }
        return appURL
    }

    private static func launchReplaceHandoff(newAppURL: URL, targetAppURL: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        ditto "$1" "$2"
        open "$2"
        rm -rf "$(dirname "$1")"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("caffinate-update-handoff-\(pid).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, newAppURL.path, targetAppURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
    }
}
```

Register the new file in `project.pbxproj` (new `CAFF…` IDs in BuildFile, FileReference, Caffinate group, Sources phase).

- [ ] **Step 2: Hook StatusItemController.installUpdate**

```swift
@objc private func installUpdate(_ sender: NSMenuItem) {
    guard let ctx = sender.representedObject as? UpdateMenuContext else { return }
    Task { @MainActor in
        await AppUpdateInstaller.confirmAndInstall(
            assetURL: ctx.assetURL,
            releaseURL: ctx.releaseURL,
            latest: ctx.latest,
            prepareForQuit: { [weak self] in
                self?.manager.prepareForTermination()
            }
        )
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Caffinate -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Caffinate/AppUpdateInstaller.swift Caffinate/StatusItemController.swift Caffinate.xcodeproj/project.pbxproj
git commit -m "feat: download GitHub zip and replace app on update"
```

---

### Task 4: SessionDuration.until + next-occurrence helper

**Files:**
- Modify: `Caffinate/CaffeinateCommandBuilder.swift` (`SessionDuration`)
- Modify: `CaffinateTests/CaffinateTests.swift`

**Interfaces:**
- Produces: `SessionDuration.until(hour: Int, minute: Int)`
- Produces: `SessionDuration.menuTitle`, `seconds(from now: Date = Date()) -> Int?`
- Produces: `SessionDuration.nextOccurrence(hour:minute:from:) -> Date`

- [ ] **Step 1: Write failing tests**

```swift
func testUntilMenuTitle() {
    XCTAssertEqual(SessionDuration.until(hour: 17, minute: 30).menuTitle, "Until 17:30")
}

func testNextOccurrenceRollsToTomorrowWhenPast() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 18, minute: 0))!
    let end = SessionDuration.nextOccurrence(hour: 17, minute: 30, from: now, calendar: cal)
    let parts = cal.dateComponents([.day, .hour, .minute], from: end)
    XCTAssertEqual(parts.day, 1) // Oct 1 if using full components — assert year/month/day explicitly:
    XCTAssertEqual(cal.component(.day, from: end), 1)
    XCTAssertEqual(cal.component(.month, from: end), 10)
    XCTAssertEqual(cal.component(.hour, from: end), 17)
    XCTAssertEqual(cal.component(.minute, from: end), 30)
}

func testUntilSecondsFromNow() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 16, minute: 0))!
    let seconds = SessionDuration.until(hour: 17, minute: 0).seconds(from: now, calendar: cal)
    XCTAssertEqual(seconds, 3600)
}
```

- [ ] **Step 2: Run — expect fail**

Run: `xcodebuild -scheme Caffinate -destination 'platform=macOS' test -only-testing:CaffinateTests/CaffinateTests/testUntilMenuTitle`

Expected: FAIL / compile error.

- [ ] **Step 3: Implement SessionDuration.until**

Replace/extend in `CaffeinateCommandBuilder.swift`:

```swift
enum SessionDuration: Equatable, Hashable, Codable {
    case indefinite
    case minutes(Int)
    case until(hour: Int, minute: Int)

    /// Legacy: minutes/indefinite only. Prefer `seconds(from:calendar:)`.
    var seconds: Int? {
        seconds(from: Date())
    }

    func seconds(from now: Date, calendar: Calendar = .current) -> Int? {
        switch self {
        case .indefinite: return nil
        case .minutes(let m): return max(1, m) * 60
        case .until(let hour, let minute):
            let end = Self.nextOccurrence(hour: hour, minute: minute, from: now, calendar: calendar)
            return max(1, Int(end.timeIntervalSince(now)))
        }
    }

    static func nextOccurrence(hour: Int, minute: Int, from now: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        let today = calendar.date(from: components) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
    }

    var menuTitle: String {
        switch self {
        case .indefinite: return "Indefinitely"
        case .minutes(15): return "15 Minutes"
        case .minutes(30): return "30 Minutes"
        case .minutes(45): return "45 Minutes"
        case .minutes(60): return "1 Hour"
        case .minutes(240): return "4 Hours"
        case .minutes(480): return "8 Hours"
        case .minutes(let m) where m < 60: return "\(m) Minutes"
        case .minutes(let m): return "\(m / 60) Hours"
        case .until(let h, let m):
            return String(format: "Until %02d:%02d", h, m)
        }
    }
}
```

Update `CaffeinateManager.desiredArguments` to use `duration.seconds(from:)` (same as `.seconds` default).

- [ ] **Step 4: Run tests — pass**

Run: `xcodebuild -scheme Caffinate -destination 'platform=macOS' test -only-testing:CaffinateTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Caffinate/CaffeinateCommandBuilder.swift Caffinate/CaffeinateManager.swift CaffinateTests/CaffinateTests.swift
git commit -m "feat: add SessionDuration.until with tomorrow roll-over"
```

---

### Task 5: Until… panel + Duration menu wiring

**Files:**
- Create: `Caffinate/UntilTimePanelController.swift`
- Modify: `Caffinate/StatusItemController.swift`
- Modify: `Caffinate/CaffeinateManager.swift` (`selectUntil`)
- Modify: `Caffinate.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SessionDuration.until`, `nextOccurrence`
- Produces: `CaffeinateManager.selectUntil(hour:minute:)`
- Produces: `UntilTimePanelController.present(onSet:)`

- [ ] **Step 1: Add selectUntil on manager**

```swift
func selectUntil(hour: Int, minute: Int) {
    selectDuration(.until(hour: hour, minute: minute))
}
```

Ensure `restartForDurationChange` / `spawn` use `duration.seconds(from: Date())` so Until resolves at start time.

- [ ] **Step 2: Implement UntilTimePanelController**

```swift
import AppKit

@MainActor
final class UntilTimePanelController: NSObject {
    private var panel: NSPanel?
    private var picker: NSDatePicker?
    private var onSet: ((Int, Int) -> Void)?

    func present(onSet: @escaping (Int, Int) -> Void) {
        self.onSet = onSet
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Keep awake until"
        panel.isFloatingPanel = true
        panel.level = .floating

        let picker = NSDatePicker(frame: NSRect(x: 40, y: 60, width: 200, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        picker.datePickerMode = .single
        picker.dateValue = Self.defaultTime()
        panel.contentView?.addSubview(picker)

        let set = NSButton(title: "Set", target: self, action: #selector(setTapped))
        set.frame = NSRect(x: 150, y: 16, width: 80, height: 32)
        set.keyEquivalent = "\r"
        panel.contentView?.addSubview(set)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.frame = NSRect(x: 60, y: 16, width: 80, height: 32)
        panel.contentView?.addSubview(cancel)

        self.picker = picker
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func defaultTime() -> Date {
        let cal = Calendar.current
        let now = Date()
        let next = now.addingTimeInterval(30 * 60)
        // Snap display to next half-hour-ish via components
        return next
    }

    @objc private func setTapped() {
        guard let date = picker?.dateValue else { return }
        let h = Calendar.current.component(.hour, from: date)
        let m = Calendar.current.component(.minute, from: date)
        onSet?(h, m)
        panel?.close()
        panel = nil
    }

    @objc private func cancelTapped() {
        panel?.close()
        panel = nil
    }
}
```

Keep a strong `untilPanelController` property on `StatusItemController` so the panel isn’t deallocated.

- [ ] **Step 3: Duration submenu — add Until…**

In `makeDurationMenu()` after presets:

```swift
menu.addItem(.separator())
let untilItem = NSMenuItem(
    title: MenuGlyph.titled(MenuGlyph.timed, "Until…"),
    action: #selector(openUntilPanel),
    keyEquivalent: ""
)
untilItem.target = self
if case .until = manager.duration { untilItem.state = .on }
menu.addItem(untilItem)
```

Preset checkmarks: only `.on` when `manager.duration == preset` (Until won’t match presets).

```swift
@objc private func openUntilPanel() {
    untilPanelController.present { [weak self] hour, minute in
        self?.manager.selectUntil(hour: hour, minute: minute)
    }
}
```

Parent title already uses `manager.duration.menuTitle` → shows `Until HH:MM`.

- [ ] **Step 4: Build + unit tests**

Run: `xcodebuild -scheme Caffinate -destination 'platform=macOS' test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Caffinate/UntilTimePanelController.swift Caffinate/StatusItemController.swift Caffinate/CaffeinateManager.swift Caffinate.xcodeproj/project.pbxproj
git commit -m "feat: Duration Until… time panel"
```

---

### Task 6: Harden live re-apply

**Files:**
- Modify: `Caffinate/CaffeinateManager.swift`
- Modify: `CaffinateTests/CaffinateTests.swift`

**Interfaces:**
- Consumes: `desiredArguments(preservingRemaining:)`, `reapplyIfNeeded()`, `selectDuration`

- [ ] **Step 1: Add test for preserving remaining on option reapply shape**

```swift
@MainActor
func testDesiredArgumentsPreservingRemaining() {
    let manager = CaffeinateManager()
    manager.duration = .minutes(30)
    manager.allowDisplaySleep = true
    let args = manager.desiredArguments(preservingRemaining: 120)
    XCTAssertEqual(args.firstIndex(of: "-t").map { args[$0 + 1] }, Optional("120"))
}
```

- [ ] **Step 2: Verify didSets**

Confirm in `CaffeinateManager`:

- `allowDisplaySleep` → `reapplyIfNeeded()`
- `duration` didSet → `restartForDurationChange()` when `isActive`
- `selectDuration` / `selectUntil` go through the same path

If `reapplyIfNeeded` compares args incorrectly for Until (seconds drift), compare flag sets (`-i`/`-d`) + whether timeout presence matches, **or** always restart on Until/duration change via `restartForDurationChange` only (already) and keep `reapplyIfNeeded` for display-sleep only. Spec: option-only preserves remaining — current code is correct; add a comment if clarifying.

- [ ] **Step 3: Manual checklist (document in commit body if needed)**

While app running and Keep Mac Awake on: toggle Allow Display Sleep; change 15m → 1h; set Until… — each should change behavior without requiring off/on; no start/stop notification spam.

- [ ] **Step 4: Commit**

```bash
git add Caffinate/CaffeinateManager.swift CaffinateTests/CaffinateTests.swift
git commit -m "test: cover live re-apply remaining timeout args"
```

---

### Task 7: LockScreenMessageService + helper script

**Files:**
- Create: `Caffinate/LockScreenMessageService.swift`
- Create: `Caffinate/set-lock-message.sh`
- Modify: `Caffinate.xcodeproj/project.pbxproj` (Sources + Resources Copy Bundle Resources)
- Modify: `CaffinateTests/CaffinateTests.swift` (message builder pure tests if extracted)

**Interfaces:**
- Produces: `LockScreenMessageService.applyForSession(end: Date?) async -> Bool`
- Produces: `LockScreenMessageService.restoreAfterSession() async`
- Produces: `LockScreenMessageService.message(end: Date?) -> String`

- [ ] **Step 1: Helper script**

`Caffinate/set-lock-message.sh`:

```bash
#!/bin/bash
# Sets or clears macOS LoginwindowText (System Settings → Lock Screen message).
# Usage: set-lock-message.sh "message"   # set
#        set-lock-message.sh --clear     # delete key
set -e
PLIST="/Library/Preferences/com.apple.loginwindow"
if [[ "$1" == "--clear" ]]; then
  defaults delete "$PLIST" LoginwindowText 2>/dev/null || true
else
  defaults write "$PLIST" LoginwindowText "$1"
fi
```

- [ ] **Step 2: LockScreenMessageService**

```swift
import Foundation

@MainActor
final class LockScreenMessageService {
    private var previousMessage: String?
    private var didSnapshot = false
    private let setupDoneKey = "lockScreenHelperSetupDone"

    static func message(end: Date?) -> String {
        if let end {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return "Caffinate is keeping this Mac awake until \(f.string(from: end))"
        }
        return "Caffinate is keeping this Mac awake"
    }

    func applyForSession(end: Date?) async {
        if !didSnapshot {
            previousMessage = readLoginwindowText()
            didSnapshot = true
        }
        _ = await writeMessage(Self.message(end: end))
    }

    func updateMessageIfNeeded(end: Date?) async {
        guard didSnapshot else { return }
        _ = await writeMessage(Self.message(end: end))
    }

    func restoreAfterSession() async {
        guard didSnapshot else { return }
        if let previousMessage, !previousMessage.isEmpty {
            _ = await writeMessage(previousMessage)
        } else {
            _ = await clearMessage()
        }
        previousMessage = nil
        didSnapshot = false
    }

    // Implement read via `defaults read`, write via sudo helper / osascript admin fallback
    // as described in the spec privilege model.
}
```

Implement `writeMessage` / `clearMessage` / one-time sudoers install using the same patterns as the pre-HIG manager (osascript `do shell script … with administrator privileges` to install `/etc/sudoers.d/caffinate-lock-screen` limited to the helper path, then `sudo -n` for subsequent calls). On failure return `false` (caller notifies).

- [ ] **Step 3: Unit test message builder**

```swift
func testLockScreenMessageIndefinite() {
    XCTAssertEqual(
        LockScreenMessageService.message(end: nil),
        "Caffinate is keeping this Mac awake"
    )
}
```

- [ ] **Step 4: Register script in Copy Bundle Resources and Swift file in Sources**

- [ ] **Step 5: Commit**

```bash
git add Caffinate/LockScreenMessageService.swift Caffinate/set-lock-message.sh Caffinate.xcodeproj/project.pbxproj CaffinateTests/CaffinateTests.swift
git commit -m "feat: native LoginwindowText lock screen helper service"
```

---

### Task 8: Wire lock screen into session lifecycle

**Files:**
- Modify: `Caffinate/CaffeinateManager.swift`

**Interfaces:**
- Consumes: `LockScreenMessageService.applyForSession` / `updateMessageIfNeeded` / `restoreAfterSession`

- [ ] **Step 1: Own a LockScreenMessageService on the manager**

Call:

- `spawn` success → `Task { await lockScreen.applyForSession(end: sessionEndsAt) }`
- silent duration restart after clock reset → `updateMessageIfNeeded(end:)`
- `stop`, `handleProcessEnded` (when session ends), `prepareForTermination` → `await restoreAfterSession()` (use `Task` + coordinate so quit waits reasonably, or call synchronously via semaphore-free best effort before terminate)

Never re-snapshot on silent restart.

- [ ] **Step 2: On write failure**

```swift
notify(title: "Caffinate", body: "Could not update the lock screen message.")
```

Keep-awake continues.

- [ ] **Step 3: Build + test**

Run: `xcodebuild -scheme Caffinate -destination 'platform=macOS' test`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Caffinate/CaffeinateManager.swift
git commit -m "feat: set and restore lock screen message for keep-awake sessions"
```

---

### Task 9: Docs + version notes

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `Caffinate/Info.plist` (or project `MARKETING_VERSION`) only if bumping to 2.4.0 as part of this branch — bump to **2.4.0** when features land.

- [ ] **Step 1: CHANGELOG entry for 2.4.0**

Document: Until…, live re-apply note, native lock message, update download from Mbo7682, lid-closed remains removed.

- [ ] **Step 2: README**

- Duration includes Until…
- Lock screen message uses System Settings store; may need unlock/lock once; admin prompt on first use
- Updates: Check for Updates / Update to vX downloads `Caffinate-macOS.zip`
- Gatekeeper: right-click → Open if blocked after update

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md Caffinate.xcodeproj/project.pbxproj Caffinate/Info.plist
git commit -m "docs: note 2.4 Until, lock screen, and GitHub updates"
```

---

## Spec coverage check

| Spec item | Task |
|-----------|------|
| Native LoginwindowText set/restore | 7, 8 |
| Always-on lock message (no toggle) | 8 |
| Live re-apply | 6 (+ existing manager; Until via 5) |
| Lid-closed stays removed | No task adds it (verify in 9 README) |
| Until… panel + tomorrow roll | 4, 5 |
| Fix update repo + zip asset | 1 |
| Periodic check + menu | 2 |
| Download/replace update | 3 |
| README/CHANGELOG | 9 |

## Placeholder / consistency review

- `State.updateAvailable` associated value names: `releaseURL` + `assetURL` used consistently in Tasks 1–3.
- `SessionDuration.until(hour:minute:)` used consistently in Tasks 4–5.
- `LockScreenMessageService.message(end:)` used in Tasks 7–8.
- No TBD/TODO left in steps.
