import Foundation

@MainActor
final class LockScreenMessageService {
    enum SnapshotReadResult {
        case value(String)
        case missing
        case failure
    }

    private static let setupDoneKey = "lockScreenHelperSetupDone"
    private static let hasSnapshotKey = "lockScreenHasSnapshot"
    private static let snapshotKey = "lockScreenPreviousMessage"
    nonisolated private static let messagePrefix = "Caffinate is keeping this Mac awake"
    nonisolated private static let installedHelperPath = "/Library/Application Support/Caffinate/set-lock-message.sh"
    nonisolated private static let sudoersPath = "/etc/sudoers.d/caffinate-lock-screen"

    private var previousMessage: String?
    private var didSnapshot = false
    private let readMessageOverride: (() async -> SnapshotReadResult)?
    private let writeMessageOverride: ((String) async -> Bool)?
    private let clearMessageOverride: (() async -> Bool)?

    init(
        readMessage: (() async -> SnapshotReadResult)? = nil,
        writeMessage: ((String) async -> Bool)? = nil,
        clearMessage: (() async -> Bool)? = nil
    ) {
        readMessageOverride = readMessage
        writeMessageOverride = writeMessage
        clearMessageOverride = clearMessage
    }

    nonisolated static func message(end: Date?) -> String {
        guard let end else {
            return messagePrefix
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(messagePrefix) until \(formatter.string(from: end))"
    }

    func applyForSession(end: Date?) async -> Bool {
        if !didSnapshot {
            let result = await readMessage()
            switch result {
            case .value(let message):
                previousMessage = message
            case .missing:
                previousMessage = nil
            case .failure:
                return false
            }
            didSnapshot = true
            persistSnapshot()
        }
        return await writeMessage(Self.message(end: end))
    }

    /// After a crash or force-quit the message is still ours, so restore the persisted snapshot at launch.
    func reconcileAfterUnexpectedExit() async {
        guard !didSnapshot, UserDefaults.standard.bool(forKey: Self.hasSnapshotKey) else { return }

        switch await readMessage() {
        case .failure:
            // Keep the snapshot so a later launch can still restore it.
            return
        case .missing:
            clearPersistedSnapshot()
            return
        case .value(let current):
            guard current.hasPrefix(Self.messagePrefix) else {
                // Someone else owns the message now; leave it alone.
                clearPersistedSnapshot()
                return
            }
        }

        previousMessage = UserDefaults.standard.string(forKey: Self.snapshotKey)
        didSnapshot = true
        await restoreAfterSession()
    }

    func updateMessageIfNeeded(end: Date?) async {
        guard didSnapshot else { return }
        _ = await writeMessage(Self.message(end: end))
    }

    func restoreAfterSession() async {
        guard didSnapshot else { return }

        let restored: Bool
        if let previousMessage {
            restored = await writeMessage(previousMessage)
        } else {
            restored = await clearMessage()
        }

        if restored {
            previousMessage = nil
            didSnapshot = false
            clearPersistedSnapshot()
        }
    }

    private func persistSnapshot() {
        UserDefaults.standard.set(true, forKey: Self.hasSnapshotKey)
        if let previousMessage {
            UserDefaults.standard.set(previousMessage, forKey: Self.snapshotKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
        }
    }

    private func clearPersistedSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.hasSnapshotKey)
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
    }

    private func readMessage() async -> SnapshotReadResult {
        if let readMessageOverride {
            return await readMessageOverride()
        }
        return await Self.readLoginwindowText()
    }

    private func writeMessage(_ message: String) async -> Bool {
        if let writeMessageOverride {
            return await writeMessageOverride(message)
        }
        return await runHelper(arguments: ["--set", message])
    }

    private func clearMessage() async -> Bool {
        if let clearMessageOverride {
            return await clearMessageOverride()
        }
        return await runHelper(arguments: ["--clear"])
    }

    private func runHelper(arguments: [String]) async -> Bool {
        guard let helperPath = Bundle.main.path(forResource: "set-lock-message", ofType: "sh") else {
            return false
        }

        let ranWithoutPrompt = await Task.detached(priority: .utility) {
            Self.run(
                executable: "/usr/bin/sudo",
                arguments: ["-n", Self.installedHelperPath] + arguments
            ).status == 0
        }.value

        if ranWithoutPrompt {
            UserDefaults.standard.set(true, forKey: Self.setupDoneKey)
            return true
        }

        UserDefaults.standard.set(false, forKey: Self.setupDoneKey)
        let installedAndRan = await Task.detached(priority: .userInitiated) {
            Self.installSudoersAndRun(helperPath: helperPath, arguments: arguments)
        }.value
        UserDefaults.standard.set(installedAndRan, forKey: Self.setupDoneKey)
        return installedAndRan
    }

    nonisolated private static func readLoginwindowText() async -> SnapshotReadResult {
        await Task.detached(priority: .utility) {
            let result = run(
                executable: "/usr/bin/defaults",
                arguments: ["read", "/Library/Preferences/com.apple.loginwindow", "LoginwindowText"]
            )
            if result.status == 0 {
                return .value(result.output.trimmingCharacters(in: .newlines))
            }

            let domainResult = run(
                executable: "/usr/bin/defaults",
                arguments: ["read", "/Library/Preferences/com.apple.loginwindow"]
            )
            return domainResult.status == 0 ? .missing : .failure
        }.value
    }

    nonisolated private static func installSudoersAndRun(
        helperPath: String,
        arguments: [String]
    ) -> Bool {
        let helperDirectory = (installedHelperPath as NSString).deletingLastPathComponent
        let sudoersHelperPath = sudoersEscaped(installedHelperPath)
        let sudoersLine = "\(sudoersEscaped(NSUserName())) ALL=(root) NOPASSWD: \(sudoersHelperPath) --set *, \(sudoersHelperPath) --clear"
        let temporaryPath = "\(sudoersPath).tmp"
        let helperCommand = ([shellQuoted(installedHelperPath)] + arguments.map(shellQuoted)).joined(separator: " ")
        let command = [
            "/bin/rm -f \(shellQuoted(temporaryPath))",
            "/usr/bin/install -d -o root -g wheel -m 755 \(shellQuoted(helperDirectory))",
            "/usr/bin/install -o root -g wheel -m 755 \(shellQuoted(helperPath)) \(shellQuoted(installedHelperPath))",
            "/usr/bin/printf '%s\\n' \(shellQuoted(sudoersLine)) > \(shellQuoted(temporaryPath))",
            "/usr/sbin/visudo -cf \(shellQuoted(temporaryPath))",
            "/usr/bin/install -o root -g wheel -m 440 \(shellQuoted(temporaryPath)) \(shellQuoted(sudoersPath))",
            "/bin/rm -f \(shellQuoted(temporaryPath))",
            helperCommand
        ].joined(separator: " && ")

        let appleScript = """
        on run argv
            do shell script (item 1 of argv) with administrator privileges
        end run
        """
        return run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", appleScript, command]
        ).status == 0
    }

    nonisolated private static func run(
        executable: String,
        arguments: [String]
    ) -> (status: Int32, output: String) {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
            return (
                process.terminationStatus,
                String(data: data, encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, "")
        }
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    nonisolated private static func sudoersEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: " ", with: "\\ ")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "=", with: "\\=")
    }
}
