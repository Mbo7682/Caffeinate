# Post-HIG fixes design (2.4)

**Branch:** `feature/post-hig-fixes` (includes Thomas Frisk HIG menu PR #2)  
**Date:** 2026-09-30  
**Status:** Draft for implementation

## Goal

On top of the Apple HIG `NSMenu` status item (2.3.x):

1. Drive the **native** macOS lock-screen message (`LoginwindowText`) automatically for every keep-awake session.
2. Make option/duration changes **apply while keep-awake is already on** (no off/on).
3. Keep **lid-closed / `-s` mode removed**.
4. Extend Duration with **Until…** (clock time), with past times rolling to tomorrow.
5. Fix and extend **GitHub update check**: correct repo, periodic checks, in-app download of `Caffinate-macOS.zip` and guided replace.

## Non-goals

- Reintroducing the custom glass popover.
- A Settings toggle for lock screen (always on for sessions).
- Free-form custom duration minutes beyond presets + Until….
- A full privileged helper / SMJobBless stack for lock screen (overkill for this release).
- Deep-linking only to System Settings without writing the preference.
- Sparkle / code-signed auto-replace without user confirmation (unsigned/ad-hoc apps still need user involvement for Gatekeeper).
- Checking forks other than the canonical `Mbo7682/Caffeinate` releases.

## Architecture

```
StatusItemController (NSMenu)
  ├─ Keep Mac Awake
  ├─ Duration submenu (presets + Until…)
  │     └─ Until… → small time panel → manager.selectUntil(time)
  ├─ Settings submenu (unchanged toggles)
  ├─ Update to vX… / Check for Updates…  (from UpdateChecker)
  └─ Quit

CaffeinateManager
  ├─ Session end mode: indefinite | minutes | until(Date)
  ├─ start/stop/reapply/restart
  └─ LockScreenMessageService  (set / clear / restore)

LockScreenMessageService
  └─ reads/writes /Library/Preferences/com.apple.loginwindow LoginwindowText
       (same store as System Settings → Lock Screen → Show message when locked)

UpdateChecker
  ├─ GET api.github.com/repos/Mbo7682/Caffeinate/releases/latest
  ├─ Prefer asset Caffinate-macOS.zip (browser_download_url)
  └─ download → unzip → confirm → replace running .app → relaunch
```

## 1. Native lock-screen message

### Behavior

| Event | Action |
|--------|--------|
| Keep-awake **starts** | Snapshot current `LoginwindowText` (if any). Write Caffinate message. |
| Keep-awake **stops** (user, timeout, quit, process end) | Restore snapshot, or delete key if there was no prior message. |
| Silent restart (options/duration change while active) | Update message text if end time changed; do **not** re-snapshot (keep original prior message). |
| App launch with no session | Do not touch lock-screen text. |

### Message text

- Indefinite: `Caffinate is keeping this Mac awake`
- Timed / Until: `Caffinate is keeping this Mac awake until HH:MM` (short time style, local)

### Privilege model

- Writing `/Library/Preferences/com.apple.loginwindow` requires admin.
- Ship a **narrow bundle helper** that only sets/clears `LoginwindowText` (same store System Settings uses).
- **First successful session** (or first write): admin `osascript` installs a minimal sudoers rule for that helper only, then writes the message. Subsequent start/stop/clear use passwordless `sudo` to the helper.
- If setup is declined or sudo later fails: fall back to a one-shot admin prompt for that write; on failure, notify and continue keep-awake without the lock message.
- On install/upgrade, remove any legacy broken sudoers path (existing `scripts/install.sh` already cleans `caffinate-lock-screen`).

### Constraints / macOS notes

- Empty / deleted `LoginwindowText` turns the System Settings “Show message when locked” affordance off; a non-empty string turns messaging on (GUI may lag until next lock).
- Lock screen does not always live-refresh if already locked; user may need to unlock/lock once after the first set (document in README briefly).
- Never leave a stale Caffinate message after stop/quit/timeout.

## 2. Live re-apply while active

### Already wired (verify + harden)

- `allowDisplaySleep` → `reapplyIfNeeded()` (preserve remaining countdown).
- Duration preset change while active → `restartForDurationChange()` (reset session clock).

### Required guarantees

- Changing **Allow Display Sleep**, **Duration preset**, or **Until…** while active updates the running `caffeinate` argv without requiring toggle off/on.
- Silent restarts: no start/stop notification spam (`notify: false`).
- Option-only restarts preserve remaining seconds; end-mode changes reset the end clock from the new selection.
- `activeArguments` comparison prevents no-op restarts.
- If desired args lose all keep-awake flags, stop the session.

### Tests

- Extend unit tests: `desiredArguments` with display sleep on/off; timed vs until; preserving remaining on option reapply.

## 3. Lid-closed mode

- Remain **removed**: no menu item, no `lidClosedTimerMode` preference, no `-s` in `CaffeinateCommandBuilder`.
- Do not restore from older UserDefaults (already purged keys on init in 2.3).

## 4. Duration + Until…

### Menu

Duration submenu:

1. Indefinitely  
2. 15 / 30 / 45 Minutes  
3. 1 / 4 / 8 Hours  
4. separator  
5. **Until…**

Parent title examples:

- `Duration — Indefinitely`
- `Duration — 30 Minutes`
- `Duration — Until 17:30`

### Until… panel

- Choosing **Until…** opens a small AppKit panel (not an `NSMenu` submenu) with:
  - Time picker (`NSDatePicker` date-and-time mode stripped to time, or hour/minute)
  - **Set** (primary) and **Cancel**
- Default picker value: next half-hour from now (or current time + 30m).
- On **Set**: compute end `Date` at that clock time; if ≤ now, use **tomorrow** at that time.
- Persist selection so relaunch remembers Until mode when it was last chosen (store wall-clock hour/minute + mode, re-resolve “next occurrence” on start).

### Session model

Extend `SessionDuration` (or sibling end-mode type) to support:

- `.indefinite`
- `.minutes(Int)` (existing presets)
- `.until(hour:minute:)` (or equivalent Codable form)

`seconds` / argv `-t` derived as `max(1, Int(end.timeIntervalSinceNow))` at start/restart.

Selecting a preset clears Until mode. Selecting Until… clears preset checkmarks and checks Until….

## 5. UI placement (HIG menu)

- Lock screen: **no** Settings row (always applied on session).
- Until…: Duration submenu only.
- Settings submenu unchanged otherwise (login, activate at launch, display sleep, notifications, power connect/disconnect, version).
- Updates: when newer release available → **Update to vX…**; always offer **Check for Updates…** near Quit (or only when idle/up-to-date so the menu isn’t empty of update actions).

## 6. GitHub updates (download + replace)

### Bug to fix

`UpdateChecker` currently defaults to `thomasfrisk/Caffeinate`. Canonical releases live on **`Mbo7682/Caffeinate`** (asset `Caffinate-macOS.zip`). Point the client at that repo.

### Check behavior

- Check on launch (existing).
- Re-check every **24 hours** while the app runs, and on **Check for Updates…**.
- Compare `tag_name` / `name` to `CFBundleShortVersionString` via `VersionCompare` (strip leading `v`).
- 404 / no releases → treat as up to date (keep current behavior).
- Parse release **assets**; select `Caffinate-macOS.zip` by name (fallback: first `.zip` asset). Store both `html_url` and asset `browser_download_url`.

### Install flow (user-initiated)

1. User chooses **Update to vX…** (or Check finds an update and they proceed).
2. Confirm sheet: “Download and install Caffinate vX? The app will quit and reopen.”
3. Download zip to a temp directory; unzip expecting `Caffinate.app` at the root (matches `scripts/build-for-release.sh`).
4. Validate unzipped bundle looks like an app (`Contents/Info.plist` present).
5. Stop keep-awake / clear lock message via normal termination path.
6. Replace the running app bundle with the new one:
   - Prefer swapping in place at `Bundle.main.bundleURL` when writable (typical `/Applications` or user-owned path).
   - Use a short shell/`ditto` handoff launched **outside** the app process so replace can succeed after quit (standard pattern: write a tiny script that waits for PID exit, copies new app, opens it, deletes temp).
7. If replace fails (permissions, Gatekeeper, missing asset): notification + open `html_url` in the browser as fallback.

### Menu states

| State | Menu |
|-------|------|
| `updateAvailable` | **Update to vX…** (starts download flow) + optional “View on GitHub” |
| `upToDate` / `idle` / `failed` | **Check for Updates…** |
| `checking` | Disabled “Checking…” row |

### Constraints

- Do not auto-download without a user click.
- Do not silently relaunch into a different path without confirmation.
- Ad-hoc / unsigned builds may still trip Gatekeeper after replace — document “right-click → Open” in README if needed.
- Release pipeline must keep publishing **`Caffinate-macOS.zip`** containing `Caffinate.app` (already true for v1.0.2).

## 7. Error handling

| Failure | Behavior |
|---------|----------|
| Lock message write fails | Notification; keep-awake continues. |
| Lock message clear/restore fails | Notification; log; best-effort retry once on quit. |
| Until panel cancelled | No change to duration. |
| `caffeinate` spawn fails | Existing broken/idle health + notification. |
| Update check network/API fail | `failed` state; Check for Updates remains available. |
| No zip asset on release | Notification; open release page in browser. |
| Download / unzip / replace fail | Notification; open release page; leave current app running if replace never started. |

## 8. Testing plan

- Unit: command builder timeout for until-derived seconds; duration Codable round-trip; past-time → tomorrow helper; version compare; asset picker prefers `Caffinate-macOS.zip`.
- Manual: start → lock → message visible; stop → previous message restored; toggle Allow Display Sleep while active; change preset while active; set Until… while active; quit while active clears Caffinate message.
- Confirm lid-closed absent from menu and argv.
- Manual updates: point at a test release or mock; Check for Updates; Update to vX downloads zip, replaces app, relaunches; failure path opens GitHub.

## 9. Implementation order

1. Fix `UpdateChecker` owner/repo + asset URL + periodic check + menu actions + download/replace handoff  
2. Session end-mode + Until… panel + menu wiring  
3. Harden live re-apply + tests  
4. `LockScreenMessageService` + start/stop/restore integration  
5. README/CHANGELOG notes (lock message, Until…, updates from `Mbo7682/Caffeinate`)

## Decisions log

| Topic | Choice |
|-------|--------|
| Lock screen integration | Native `LoginwindowText` (System Settings store) |
| Lock screen UX | Always on for sessions (no Settings toggle) |
| Until UX | Duration presets + Until… time panel |
| Past clock time | Roll to tomorrow |
| Lid-closed | Keep removed |
| Updates | Canonical `Mbo7682/Caffeinate`; download `Caffinate-macOS.zip` and guided replace |
| Overall approach | Lean restore + menu-native Until + in-app update install |
