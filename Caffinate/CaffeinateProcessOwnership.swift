import Darwin
import Foundation

/// Decides which live `caffeinate` processes this app still owns.
/// Matching is pure so tests can use a `ps` snapshot without signaling anyone.
enum CaffeinateProcessOwnership {
    struct ListedProcess: Equatable {
        var pid: Int32
        var ppid: Int32
        var command: String
    }

    struct Plan: Equatable {
        var pidsToSignal: [Int32]
        /// Process to leave running while the switch is on and we still want one session.
        var pidToKeep: Int32?
    }

    static func parseProcessList(_ output: String) -> [ListedProcess] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { return nil }
            let command = parts.count == 3 ? String(parts[2]) : ""
            return ListedProcess(pid: pid, ppid: ppid, command: command)
        }
    }

    /// Off: signal every `caffeinate` we own.
    /// On: keep the tracked pid, or the oldest owned pid if the handle was lost, and signal the rest.
    static func plan(
        ourPID: Int32,
        isActive: Bool,
        trackedPID: Int32?,
        processes: [ListedProcess]
    ) -> Plan {
        let owned = processes.compactMap { proc -> Int32? in
            guard proc.pid != ourPID, isCaffeinate(proc.command) else { return nil }
            if proc.ppid == ourPID || waits(on: ourPID, command: proc.command) {
                return proc.pid
            }
            return nil
        }

        if !isActive {
            return Plan(pidsToSignal: owned, pidToKeep: nil)
        }
        if let trackedPID, owned.contains(trackedPID) {
            return Plan(
                pidsToSignal: owned.filter { $0 != trackedPID },
                pidToKeep: trackedPID
            )
        }
        guard let keep = owned.min() else {
            return Plan(pidsToSignal: [], pidToKeep: nil)
        }
        return Plan(pidsToSignal: owned.filter { $0 != keep }, pidToKeep: keep)
    }

    static func currentProcessList() -> String {
        // `Process.waitUntilExit` deadlocks on the main thread because process
        // exit is delivered on the main run loop. `posix_spawn` + `waitpid` does not.
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return "" }
        defer { posix_spawn_file_actions_destroy(&actions) }

        var fds = [Int32](repeating: 0, count: 2)
        guard pipe(&fds) == 0 else { return "" }
        defer { close(fds[0]) }
        posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])

        var pid: pid_t = 0
        let args = ["/bin/ps", "-ax", "-o", "pid=,ppid=,command="]
        let cArgs = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = cArgs
        argv.append(nil)
        let spawned = posix_spawn(&pid, "/bin/ps", &actions, nil, &argv, environ)
        close(fds[1])
        guard spawned == 0 else { return "" }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fds[0], &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        guard status == 0 else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func signal(_ pids: [Int32]) {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for pid in pids where pid > 0 && pid != selfPID {
            _ = kill(pid, SIGTERM)
        }
    }

    private static func isCaffeinate(_ command: String) -> Bool {
        guard let exe = command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first else {
            return false
        }
        return exe == "caffeinate" || exe.hasSuffix("/caffeinate")
    }

    private static func waits(on pid: Int32, command: String) -> Bool {
        let tokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for (index, token) in tokens.enumerated() {
            if token == "-w", tokens.indices.contains(index + 1), Int32(tokens[index + 1]) == pid {
                return true
            }
            if token.hasPrefix("-w"), let attached = Int32(token.dropFirst(2)), attached == pid {
                return true
            }
        }
        return false
    }
}
