import Foundation
import UserNotifications

/// Runs and stops the system caffeinate command with configurable options.
@MainActor
final class CaffeinateManager: ObservableObject {
    private static let showOnLockScreenKey = "showOnLockScreen"

    /// When true, sets the system lock screen message so it's visible when the Mac is locked.
    @Published var showOnLockScreen: Bool {
        didSet {
            UserDefaults.standard.set(showOnLockScreen, forKey: Self.showOnLockScreenKey)
            if showOnLockScreen {
                // Only prompt when the toggle is turned on (one-time setup for password-free start/stop).
                runLockScreenOneTimeSetup()
            }
            if isActive {
                setLockScreenMessage(showOnLockScreen ? "Caffinate is keeping this Mac awake" : "")
            }
        }
    }

    private static let lockScreenSetupDoneKey = "lockScreenSudoersSetupDone"

    /// True after the user has completed one-time setup (when they toggled "Show on lock screen" on).
    @Published private(set) var lockScreenSetupDone: Bool = false

    private let lockScreenHelperPath: String? = {
        Bundle.main.path(forResource: "set-lock-message", ofType: "sh")
    }()

    init() {
        self.showOnLockScreen = UserDefaults.standard.bool(forKey: Self.showOnLockScreenKey)
        self.lockScreenSetupDone = UserDefaults.standard.bool(forKey: Self.lockScreenSetupDoneKey)
        if lockScreenSetupDone && lockScreenHelperPath == nil {
            self.lockScreenSetupDone = false
            UserDefaults.standard.set(false, forKey: Self.lockScreenSetupDoneKey)
        }
    }
    enum Option: String, CaseIterable {
        case preventDisplaySleep = "Display"
        case preventIdleSleep = "Idle"
        case preventSystemSleepOnAC = "AC power"
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
            case .preventSystemSleepOnAC: return "No sleep on AC only"
            case .userActive: return "User active (set timeout or lasts 5 sec)"
            case .preventDiskSleep: return "Prevent disk idle sleep"
            }
        }
    }

    @Published private(set) var isActive = false
    @Published var options: Set<Option> = [.preventIdleSleep, .preventDisplaySleep]
    @Published var timeoutSeconds: String = "" // empty = no timeout
    @Published var hasTimeout: Bool = false

    private var process: Process?
    private let caffeinatePath = "/usr/bin/caffeinate"

    var timeoutValue: Int? {
        guard hasTimeout, let n = Int(timeoutSeconds.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        return n
    }

    func start() {
        guard !isActive else { return }
        let args = buildArguments()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: caffeinatePath)
        task.arguments = args
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                self?.isActive = false
                self?.sendNotification(title: "Caffinate", body: "Keep-awake stopped.")
            }
        }
        do {
            try task.run()
            process = task
            isActive = true
            if showOnLockScreen {
                setLockScreenMessage("Caffinate is keeping this Mac awake")
            }
            sendNotification(title: "Caffinate", body: "Mac will stay awake while locked.")
        } catch {
            sendNotification(title: "Caffinate", body: "Failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
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
                    if self.isActive {
                        self.setLockScreenMessage("Caffinate is keeping this Mac awake")
                    }
                    self.sendNotification(title: "Caffinate", body: "Lock screen setup complete. Start/stop won’t ask for your password.")
                } else {
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["/bin/bash", scriptPath, message]
        task.terminationHandler = { [weak self] process in
            guard process.terminationStatus != 0 else { return }
            Task { @MainActor in
                self?.sendNotification(
                    title: "Caffinate",
                    body: "Could not update lock screen. Turn the lock screen option off and on again to re-enter your password."
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
