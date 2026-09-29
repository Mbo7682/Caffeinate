import Foundation
import AppKit
import ServiceManagement

/// Runs and stops the system `caffeinate` command for timed or indefinite sessions.
@MainActor
final class CaffeinateManager: ObservableObject {
    private static let durationKey = "sessionDuration"
    private static let allowDisplaySleepKey = "allowDisplaySleep"
    private static let allowNotificationsKey = "allowNotifications"
    private static let activateAtLaunchKey = "activateAtLaunch"
    private static let activateOnPowerConnectKey = "activateOnPowerConnect"
    private static let deactivateOnPowerDisconnectKey = "deactivateOnPowerDisconnect"

    private let notifications = NotificationService()
    private let caffeinatePath = "/usr/bin/caffeinate"

    @Published private(set) var isActive = false
    @Published private(set) var health: KeepAwakeHealth = .idle
    @Published private(set) var sessionEndsAt: Date?
    @Published private(set) var remainingSeconds: Int = 0

    @Published var duration: SessionDuration {
        didSet {
            guard duration != oldValue else { return }
            persistDuration()
            if isActive {
                restartForDurationChange()
            }
        }
    }

    /// When true, do not pass `-d` (display may sleep; Mac stays awake via `-i`).
    @Published var allowDisplaySleep: Bool {
        didSet {
            guard allowDisplaySleep != oldValue else { return }
            UserDefaults.standard.set(allowDisplaySleep, forKey: Self.allowDisplaySleepKey)
            reapplyIfNeeded()
        }
    }

    @Published var allowNotifications: Bool {
        didSet {
            guard allowNotifications != oldValue else { return }
            UserDefaults.standard.set(allowNotifications, forKey: Self.allowNotificationsKey)
            notifications.isEnabled = allowNotifications
        }
    }

    @Published var activateAtLaunch: Bool {
        didSet {
            guard activateAtLaunch != oldValue else { return }
            UserDefaults.standard.set(activateAtLaunch, forKey: Self.activateAtLaunchKey)
        }
    }

    @Published var launchAtLogin: Bool = false {
        didSet {
            guard !isLoadingPreferences, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var activateOnPowerConnect: Bool {
        didSet {
            guard activateOnPowerConnect != oldValue else { return }
            UserDefaults.standard.set(activateOnPowerConnect, forKey: Self.activateOnPowerConnectKey)
        }
    }

    @Published var deactivateOnPowerDisconnect: Bool {
        didSet {
            guard deactivateOnPowerDisconnect != oldValue else { return }
            UserDefaults.standard.set(deactivateOnPowerDisconnect, forKey: Self.deactivateOnPowerDisconnectKey)
        }
    }

    private var process: Process?
    private var healthMonitorTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var powerPollTask: Task<Void, Never>?
    private var userInitiatedStop = false
    private var suppressTerminationNotification = false
    private var isLoadingPreferences = true
    private var lastOnAC: Bool?
    private(set) var activeArguments: [String] = []
    private var sessionStartedAt: Date?

    var statusSubtitle: String {
        if !isActive { return "Off" }
        if case .broken(let reason) = health {
            return "Not working · \(reason)"
        }
        if case .checking = health {
            return "Starting…"
        }
        if let end = sessionEndsAt {
            return "Active until \(Self.endTimeFormatter.string(from: end))"
        }
        return "Active · until you stop"
    }

    /// Single checkable menu title (status folded into “Keep Mac Awake”).
    var menuToggleTitle: String {
        if !isActive { return "Keep Mac Awake" }
        if case .broken(let reason) = health {
            return "Keep Mac Awake · not working (\(reason))"
        }
        if case .checking = health {
            return "Keep Mac Awake · starting…"
        }
        if let end = sessionEndsAt {
            return "Keep Mac Awake · until \(Self.endTimeFormatter.string(from: end))"
        }
        return "Keep Mac Awake · until you stop"
    }

    private static let endTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    init() {
        for key in [
            "showOnLockScreen", "lidClosedTimerMode", "hasTimeout", "timeoutSeconds",
            "lockScreenSudoersSetupDone", "caffeinateOptions"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        if let data = UserDefaults.standard.data(forKey: Self.durationKey),
           let decoded = try? JSONDecoder().decode(SessionDuration.self, from: data) {
            // Drop removed 12h preset if it was saved previously.
            if case .minutes(720) = decoded {
                self.duration = .minutes(480)
            } else {
                self.duration = decoded
            }
        } else {
            self.duration = .indefinite
        }

        self.allowDisplaySleep = UserDefaults.standard.object(forKey: Self.allowDisplaySleepKey) as? Bool ?? true
        self.allowNotifications = UserDefaults.standard.object(forKey: Self.allowNotificationsKey) as? Bool ?? true
        self.activateAtLaunch = UserDefaults.standard.bool(forKey: Self.activateAtLaunchKey)
        self.activateOnPowerConnect = UserDefaults.standard.bool(forKey: Self.activateOnPowerConnectKey)
        self.deactivateOnPowerDisconnect = UserDefaults.standard.bool(forKey: Self.deactivateOnPowerDisconnectKey)
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        notifications.isEnabled = allowNotifications
        isLoadingPreferences = false
        lastOnAC = isOnPowerAdapter()
        startPowerPolling()
    }

    func desiredArguments(preservingRemaining: Int? = nil) -> [String] {
        let timeout: Int?
        if let preservingRemaining, preservingRemaining > 0 {
            timeout = preservingRemaining
        } else {
            timeout = duration.seconds
        }
        return CaffeinateCommandBuilder.buildArguments(
            preventIdleSleep: true,
            preventDisplaySleep: !allowDisplaySleep,
            timeoutSeconds: timeout
        ) + ["-w", "\(ProcessInfo.processInfo.processIdentifier)"]
    }

    /// Select a duration and start (or restart) keep-awake immediately.
    func selectDuration(_ newDuration: SessionDuration) {
        let changed = duration != newDuration
        if changed {
            duration = newDuration
        }
        if !isActive {
            start()
        } else if !changed {
            restartForDurationChange()
        }
        // If changed while active, `duration` didSet already restarted.
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    func start() {
        guard !isActive else { return }
        let args = desiredArguments()
        guard CaffeinateCommandBuilder.hasEffectiveKeepAwakeFlags(args) else {
            notify(title: "Caffinate", body: "Could not start keep-awake.")
            return
        }
        spawn(with: args, notifyStarted: true, resetSessionClock: true)
    }

    func stop() {
        guard isActive || process != nil else { return }
        userInitiatedStop = true
        suppressTerminationNotification = false
        teardownSessionMonitors(clearClock: true)
        process?.terminate()
        process = nil
        isActive = false
        health = .idle
        notify(title: "Caffinate", body: "Keep-awake stopped.")
    }

    func prepareForTermination() {
        userInitiatedStop = true
        suppressTerminationNotification = true
        powerPollTask?.cancel()
        teardownSessionMonitors(clearClock: true)
        process?.terminate()
        process = nil
        isActive = false
        health = .idle
        activeArguments = []
    }

    func handleAppDidFinishLaunching() {
        if activateAtLaunch {
            start()
        }
    }

    func requestNotificationPermission() async {
        guard allowNotifications else { return }
        await notifications.requestPermission()
    }

    func reapplyIfNeeded() {
        guard isActive else { return }
        let remaining = duration.seconds == nil ? nil : max(1, remainingSeconds)
        let desired = desiredArguments(preservingRemaining: remaining)
        guard CaffeinateCommandBuilder.hasEffectiveKeepAwakeFlags(desired) else {
            stop()
            return
        }
        guard desired != activeArguments else { return }
        restart(with: desired, notify: false, resetSessionClock: false)
    }

    // MARK: - Private

    private func restartForDurationChange() {
        restart(with: desiredArguments(), notify: false, resetSessionClock: true)
    }

    private func restart(with args: [String], notify: Bool, resetSessionClock: Bool) {
        suppressTerminationNotification = true
        process?.terminate()
        process = nil
        spawn(with: args, notifyStarted: notify, resetSessionClock: resetSessionClock)
    }

    private func spawn(with args: [String], notifyStarted: Bool, resetSessionClock: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: caffeinatePath)
        task.arguments = args
        task.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                self?.handleProcessEnded(for: ended)
            }
        }

        do {
            try task.run()
            process = task
            isActive = true
            activeArguments = args
            userInitiatedStop = false
            suppressTerminationNotification = false
            health = .checking
            startHealthMonitor()

            if resetSessionClock {
                sessionStartedAt = Date()
                if let seconds = duration.seconds {
                    sessionEndsAt = Date().addingTimeInterval(TimeInterval(seconds))
                    remainingSeconds = seconds
                    startCountdown(total: seconds)
                } else {
                    sessionEndsAt = nil
                    remainingSeconds = 0
                    countdownTask?.cancel()
                    countdownTask = nil
                }
            } else if let seconds = duration.seconds, let start = sessionStartedAt {
                let elapsed = Int(Date().timeIntervalSince(start))
                remainingSeconds = max(0, seconds - elapsed)
                sessionEndsAt = start.addingTimeInterval(TimeInterval(seconds))
                startCountdown(total: seconds)
            }

            if notifyStarted {
                notify(title: "Caffinate", body: "Processes keep running while the Mac is locked.")
            }
        } catch {
            isActive = false
            activeArguments = []
            health = .broken(reason: "failed to start")
            teardownSessionMonitors(clearClock: true)
            suppressTerminationNotification = false
            notify(title: "Caffinate", body: "Failed to start: \(error.localizedDescription)")
        }
    }

    private func handleProcessEnded(for ended: Process) {
        if let current = process, current !== ended { return }

        if suppressTerminationNotification {
            suppressTerminationNotification = false
            if isActive { return }
        }

        teardownSessionMonitors(clearClock: true)
        process = nil
        activeArguments = []
        let wasActive = isActive
        isActive = false
        health = .idle

        if wasActive && !userInitiatedStop {
            notify(title: "Caffinate", body: "Keep-awake stopped.")
        }
        userInitiatedStop = false
    }

    private func startCountdown(total: Int) {
        countdownTask?.cancel()
        guard let start = sessionStartedAt else { return }
        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let elapsed = Int(Date().timeIntervalSince(start))
                let remaining = max(0, total - elapsed)
                self.remainingSeconds = remaining
                self.sessionEndsAt = start.addingTimeInterval(TimeInterval(total))
                if remaining <= 0 {
                    if self.process?.isRunning == true {
                        self.userInitiatedStop = true
                        self.process?.terminate()
                    }
                    return
                }
            }
        }
    }

    private func startHealthMonitor() {
        healthMonitorTask?.cancel()
        healthMonitorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            while !Task.isCancelled {
                guard let self, self.isActive else { return }
                await self.refreshHealth()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func refreshHealth() async {
        let pid = process?.processIdentifier
        let alive = process?.isRunning == true
        let expected = PowerAssertionProbe.expectedTypes(fromArguments: activeArguments)
        let snapshot = await Task.detached(priority: .utility) {
            PowerAssertionProbe.snapshot(caffeinatePID: pid, processAlive: alive)
        }.value
        guard !Task.isCancelled, isActive else { return }
        health = PowerAssertionProbe.evaluate(
            processAlive: snapshot.processAlive,
            heldTypes: snapshot.heldTypes,
            expectedTypes: expected
        )
    }

    private func teardownSessionMonitors(clearClock: Bool) {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        if clearClock {
            sessionStartedAt = nil
            sessionEndsAt = nil
            remainingSeconds = 0
        }
    }

    private func persistDuration() {
        if let data = try? JSONEncoder().encode(duration) {
            UserDefaults.standard.set(data, forKey: Self.durationKey)
        }
    }

    private func notify(title: String, body: String) {
        guard allowNotifications else { return }
        notifications.send(title: title, body: body)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isLoadingPreferences = true
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            isLoadingPreferences = false
            notify(title: "Caffinate", body: "Could not update Login Items. Try System Settings → General → Login Items.")
        }
    }

    private func startPowerPolling() {
        powerPollTask?.cancel()
        powerPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.handlePowerSourceMaybeChanged()
            }
        }
    }

    private func handlePowerSourceMaybeChanged() {
        let onAC = isOnPowerAdapter()
        defer { lastOnAC = onAC }
        guard let previous = lastOnAC else { return }
        if onAC && !previous && activateOnPowerConnect && !isActive {
            start()
        } else if !onAC && previous && deactivateOnPowerDisconnect && isActive {
            stop()
        }
    }

    private func isOnPowerAdapter() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "batt"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return text.contains("AC Power")
        } catch {
            return true
        }
    }
}
