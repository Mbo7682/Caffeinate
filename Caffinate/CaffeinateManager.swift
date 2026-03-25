import Foundation
import UserNotifications

/// Runs and stops the system caffeinate command with configurable options.
@MainActor
final class CaffeinateManager: ObservableObject {
    private static let showOnLockScreenKey = "showOnLockScreen"
    private static let lidClosedTimerModeKey = "lidClosedTimerMode"

    /// When true, sets the system lock screen message so it's visible when the Mac is locked.
    @Published var showOnLockScreen: Bool {
        didSet {
            UserDefaults.standard.set(showOnLockScreen, forKey: Self.showOnLockScreenKey)
            if showOnLockScreen {
                // Only prompt when the toggle is turned on (one-time setup for password-free start/stop).
                runLockScreenOneTimeSetup()
            }
            if !showOnLockScreen {
                lockScreenPasswordReentryNeeded = false
            }
            if isActive {
                setLockScreenMessage(showOnLockScreen ? "Caffinate is keeping this Mac awake" : "")
            }
        }
    }

    /// When enabled, start adds `-s` (AC-only system sleep prevention) so the Mac can stay awake with lid closed.
    /// This is most useful when combined with a timeout.
    @Published var lidClosedTimerMode: Bool {
        didSet {
            UserDefaults.standard.set(lidClosedTimerMode, forKey: Self.lidClosedTimerModeKey)
            if lidClosedTimerMode {
                options.insert(.preventSystemSleepOnAC)
            } else {
                options.remove(.preventSystemSleepOnAC)
            }
        }
    }

    private static let lockScreenSetupDoneKey = "lockScreenSudoersSetupDone"

    /// True after the user has completed one-time setup (when they toggled "Show on lock screen" on).
    @Published private(set) var lockScreenSetupDone: Bool = false
    /// True when lock-screen sudo configuration needs the user to re-enter their admin password.
    @Published private(set) var lockScreenPasswordReentryNeeded: Bool = false

    private let lockScreenHelperPath: String? = {
        Bundle.main.path(forResource: "set-lock-message", ofType: "sh")
    }()

    init() {
        self.showOnLockScreen = UserDefaults.standard.bool(forKey: Self.showOnLockScreenKey)
        self.lidClosedTimerMode = UserDefaults.standard.bool(forKey: Self.lidClosedTimerModeKey)
        self.lockScreenSetupDone = UserDefaults.standard.bool(forKey: Self.lockScreenSetupDoneKey)
        if lockScreenSetupDone && lockScreenHelperPath == nil {
            self.lockScreenSetupDone = false
            UserDefaults.standard.set(false, forKey: Self.lockScreenSetupDoneKey)
        }
        if lidClosedTimerMode {
            options.insert(.preventSystemSleepOnAC)
        }

        // If the user previously enabled "Show on lock screen", proactively detect
        // whether sudo permissions still require a password so the UI can show
        // "Re-enter password" immediately (without waiting for Start).
        if showOnLockScreen, lockScreenSetupDone {
            probeLockScreenPasswordRequirement()
        }
    }

    /// Uses `sudo -n` to check whether the helper command requires the admin password.
    /// Does not prompt; on failure we surface the "Re-enter password" UI.
    private func probeLockScreenPasswordRequirement() {
        guard let scriptPath = lockScreenHelperPath else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/bin/bash", scriptPath, ""]
        task.terminationHandler = { [weak self] process in
            guard let self else { return }
            let status = process.terminationStatus
            Task { @MainActor in
                // Only update the re-entry flag; keep `lockScreenSetupDone` as-is.
                self.lockScreenPasswordReentryNeeded = status != 0
                if status != 0 {
                    self.sendNotification(
                        title: "Caffinate",
                        body: "Lock screen permissions need your admin password. Open the app and use “Re-enter password”."
                    )
                }
            }
        }

        do {
            try task.run()
        } catch {
            // If probing fails for some reason, keep the existing state rather than changing flags incorrectly.
        }
    }
    enum Option: String, CaseIterable {
        case preventDisplaySleep = "Display"
        case preventIdleSleep = "Idle"
        case preventSystemSleepOnAC = "System sleep"
        case userActive = "User active"
        case preventDiskSleep = "Disk"

        var flag: String {
            switch self {
            case .preventDisplaySleep: return "d"
            case .preventIdleSleep: return "i"
            case .preventSystemSleepOnAC: return "s"
            case .userActive: return "u"
            case .preventDiskSleep: return "m"
            }
        }

        var help: String {
            switch self {
            case .preventDisplaySleep: return "Keep display on"
            case .preventIdleSleep: return "Prevent idle sleep"
            case .preventSystemSleepOnAC: return "Prevent system sleep"
            case .userActive: return "User active (set timeout or lasts 5 sec)"
            case .preventDiskSleep: return "Prevent disk idle sleep"
            }
        }
    }

    @Published private(set) var isActive = false
    @Published var options: Set<Option> = [.preventIdleSleep, .preventDisplaySleep]
    @Published var timeoutSeconds: String = "" // empty = no timeout
    @Published var hasTimeout: Bool = false
    @Published private(set) var remainingSeconds: Int = 0

    private var process: Process?
    private var startTime: Date?
    private var countdownTimer: Timer?
    private let caffeinatePath = "/usr/bin/caffeinate"

    var timeoutValue: Int? {
        guard hasTimeout, let n = Int(timeoutSeconds.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        return n
    }

    func start() {
        guard !isActive else { return }
        // Lid-closed mode is intended for time-bounded “keep awake”.
        // Enforce that a valid timeout is set; otherwise we risk an unintended indefinite keep-awake.
        if lidClosedTimerMode && timeoutValue == nil {
            sendNotification(
                title: "Caffinate",
                body: "Lid closed mode requires a timeout. Enable Timeout (seconds) and set a value > 0."
            )
            return
        }
        if lidClosedTimerMode {
            options.insert(.preventSystemSleepOnAC)
        } else {
            options.remove(.preventSystemSleepOnAC)
        }
        let args = buildArguments()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: caffeinatePath)
        task.arguments = args
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.countdownTimer?.invalidate()
                self?.countdownTimer = nil
                self?.startTime = nil
                self?.remainingSeconds = 0
                self?.process = nil
                self?.isActive = false
                // Clear lock screen message when process terminates (delay ensures it executes)
                if self?.showOnLockScreen ?? false {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.setLockScreenMessage("")
                    }
                }
                self?.sendNotification(title: "Caffinate", body: "Keep-awake stopped.")
            }
        }
        do {
            try task.run()
            process = task
            isActive = true
            
            // Start countdown timer if timeout is set
            if let timeout = timeoutValue {
                startTime = Date()
                remainingSeconds = timeout
                countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    let elapsed = Int(Date().timeIntervalSince(self.startTime ?? Date()))
                    let remaining = max(0, timeout - elapsed)
                    self.remainingSeconds = remaining
                    if remaining <= 0 {
                        self.countdownTimer?.invalidate()
                        self.countdownTimer = nil
                    }
                }
            }
            
            if showOnLockScreen {
                let message = buildLockScreenMessage()
                setLockScreenMessage(message)
            }
            sendNotification(title: "Caffinate", body: "Mac will stay awake while locked.")
        } catch {
            sendNotification(title: "Caffinate", body: "Failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        startTime = nil
        remainingSeconds = 0
        if showOnLockScreen {
            setLockScreenMessage("")
        }
        process?.terminate()
        process = nil
        isActive = false
    }

    func toggle(_ option: Option) {
        if options.contains(option) {
            options.remove(option)
        } else {
            options.insert(option)
        }
    }

    private func buildArguments() -> [String] {
        var args: [String] = []
        for opt in Option.allCases where options.contains(opt) {
            args.append("-\(opt.flag)")
        }
        if let t = timeoutValue {
            args.append(contentsOf: ["-t", "\(t)"])
        }
        return args
    }

    private func sendNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                Task { @MainActor in await self.requestNotificationPermission() }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Lock screen message

    private func buildLockScreenMessage() -> String {
        if let timeout = timeoutValue, let startTime = startTime {
            let endTime = startTime.addingTimeInterval(TimeInterval(timeout))
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let endTimeString = formatter.string(from: endTime)
            return "Caffinate is keeping awake until \(endTimeString)"
        }
        return "Caffinate is keeping this Mac awake"
    }

    /// One-time setup when user toggles "Show on lock screen" on: installs sudoers rule so start/stop don't prompt.
    func runLockScreenOneTimeSetup() {
        guard let scriptPath = lockScreenHelperPath else {
            sendNotification(title: "Caffinate", body: "Helper script not found. Rebuild the app.")
            return
        }
        let username = NSUserName()
        let sudoersLine = "\(username) ALL=(ALL) NOPASSWD: /bin/bash \(scriptPath) *"
            .replacingOccurrences(of: "'", with: "'\\''")
        let installCommand = "echo '\(sudoersLine)' | tee /etc/sudoers.d/caffinate-lock-screen > /dev/null && chmod 440 /etc/sudoers.d/caffinate-lock-screen"
        let script = "do shell script \"\(installCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self = self else { return }
                if process.terminationStatus == 0 {
                    UserDefaults.standard.set(true, forKey: Self.lockScreenSetupDoneKey)
                    self.lockScreenSetupDone = true
                    self.lockScreenPasswordReentryNeeded = false
                    if self.isActive {
                        self.setLockScreenMessage("Caffinate is keeping this Mac awake")
                    }
                    self.sendNotification(title: "Caffinate", body: "Lock screen setup complete. Start/stop won’t ask for your password.")
                } else {
                    self.lockScreenPasswordReentryNeeded = true
                    self.sendNotification(title: "Caffinate", body: "Lock screen setup failed. You may need to enter your password when starting or stopping.")
                }
            }
        }
        do {
            try task.run()
        } catch {
            sendNotification(title: "Caffinate", body: "Setup failed: \(error.localizedDescription)")
        }
    }

    /// Sets or clears the lock screen message. Uses sudo + helper (no prompt) when setup was done on toggle.
    func setLockScreenMessage(_ message: String) {
        guard let scriptPath = lockScreenHelperPath, lockScreenSetupDone else { return }
        let lockScreenSetupDoneKey = Self.lockScreenSetupDoneKey
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["/bin/bash", scriptPath, message]
        task.terminationHandler = { [weak self] process in
            guard let self, process.terminationStatus != 0 else { return }
            Task { @MainActor in
                // If sudo fails (e.g. password required again), mark setup as not complete
                // so the UI can offer re-entering the password.
                UserDefaults.standard.set(false, forKey: lockScreenSetupDoneKey)
                self.lockScreenSetupDone = false
                self.lockScreenPasswordReentryNeeded = true
                self.sendNotification(
                    title: "Caffinate",
                    body: "Could not update lock screen. Use the 'Re-enter password' button in the app to try again."
                )
            }
        }
        do {
            try task.run()
        } catch {
            sendNotification(
                title: "Caffinate",
                body: "Could not update lock screen: \(error.localizedDescription)"
            )
        }
    }
}
