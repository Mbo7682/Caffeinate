import Foundation
import UserNotifications

/// Runs and stops the system caffeinate command with configurable options.
@MainActor
final class CaffeinateManager: ObservableObject {
    private static let lidClosedTimerModeKey = "lidClosedTimerMode"
    private static let lockScreenNotificationsEnabledKey = "lockScreenNotificationsEnabled"
    private static let endingSoonNotificationId = "caffinate-ending-soon"
    private static let notificationHistoryClearDelaySeconds: TimeInterval = 35

    private let screenLockedNotificationName = Notification.Name("com.apple.screenIsLocked")
    private var screenLockObserver: NSObjectProtocol?

    /// When true, uses notifications that appear on the lock screen.
    @Published var lockScreenNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lockScreenNotificationsEnabled, forKey: Self.lockScreenNotificationsEnabledKey)
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

    init() {
        self.lockScreenNotificationsEnabled = UserDefaults.standard.bool(forKey: Self.lockScreenNotificationsEnabledKey)
        self.lidClosedTimerMode = UserDefaults.standard.bool(forKey: Self.lidClosedTimerModeKey)
        if lidClosedTimerMode {
            options.insert(.preventSystemSleepOnAC)
        }
        // Keep Notification Center history clean on launch.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: screenLockedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenLocked()
        }
    }

    deinit {
        if let screenLockObserver {
            DistributedNotificationCenter.default().removeObserver(screenLockObserver)
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
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.endingSoonNotificationId])
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
                scheduleEndingSoonNotification(timeoutSeconds: timeout)
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.endingSoonNotificationId])
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
            self.scheduleNotificationHistoryCleanup(after: Self.notificationHistoryClearDelaySeconds)
        }
    }

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func scheduleEndingSoonNotification(timeoutSeconds: Int) {
        guard lockScreenNotificationsEnabled else { return }
        guard timeoutSeconds > 10 else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(timeoutSeconds - 10),
            repeats: false
        )

        let content = UNMutableNotificationContent()
        content.title = "Caffinate"
        content.body = "Ending in 10 seconds."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.endingSoonNotificationId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
        scheduleNotificationHistoryCleanup(
            after: TimeInterval(timeoutSeconds - 10) + Self.notificationHistoryClearDelaySeconds
        )
    }

    private func handleScreenLocked() {
        guard lockScreenNotificationsEnabled, isActive else { return }

        // macOS controls the banner duration; this is intended as a brief reminder at lock time.
        let body: String
        if timeoutValue != nil, remainingSeconds > 0 {
            body = "Caffinate is keeping your Mac awake. \(remainingSeconds)s remaining."
        } else {
            body = "Caffinate is keeping your Mac awake."
        }
        sendNotification(title: "Caffinate", body: body)
    }

    private func scheduleNotificationHistoryCleanup(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
    }
}
