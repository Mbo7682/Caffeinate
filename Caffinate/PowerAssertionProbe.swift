import Foundation

/// Snapshot of whether our `caffeinate` child is alive and which power assertions it holds.
struct PowerAssertionSnapshot: Equatable {
    let processAlive: Bool
    /// Assertion type names from `pmset -g assertions`.
    let heldTypes: Set<String>
}

enum KeepAwakeHealth: Equatable {
    case idle
    case checking
    case working(heldLabels: [String])
    case broken(reason: String)

    var shortStatus: String {
        switch self {
        case .idle:
            return "Off"
        case .checking:
            return "Checking…"
        case .working:
            return "Keeping Mac awake"
        case .broken(let reason):
            return "Not working · \(reason)"
        }
    }

    var isHealthy: Bool {
        if case .working = self { return true }
        return false
    }
}

/// Reads `pmset -g assertions` and matches lines owned by our `caffeinate` PID.
enum PowerAssertionProbe {
    static func expectedTypes(fromArguments args: [String]) -> Set<String> {
        var expected = Set<String>()
        if args.contains("-d") { expected.insert("PreventUserIdleDisplaySleep") }
        if args.contains("-i") { expected.insert("PreventUserIdleSystemSleep") }
        return expected
    }

    static func humanLabel(forAssertionType type: String) -> String {
        switch type {
        case "PreventUserIdleDisplaySleep": return "Screen"
        case "PreventUserIdleSystemSleep": return "Stay awake"
        default: return type
        }
    }

    static func evaluate(
        processAlive: Bool,
        heldTypes: Set<String>,
        expectedTypes: Set<String>
    ) -> KeepAwakeHealth {
        guard processAlive else {
            return .broken(reason: "caffeinate quit")
        }
        guard !expectedTypes.isEmpty else {
            return .broken(reason: "no keep-awake options")
        }
        let missing = expectedTypes.subtracting(heldTypes)
        if missing.isEmpty {
            let labels = expectedTypes
                .sorted()
                .map(humanLabel(forAssertionType:))
            return .working(heldLabels: labels)
        }
        let missingLabels = missing.sorted().map(humanLabel(forAssertionType:)).joined(separator: ", ")
        return .broken(reason: "missing \(missingLabels)")
    }

    static func assertionsHeld(byCaffeinatePID pid: Int32, in output: String) -> Set<String> {
        var held = Set<String>()
        let needle = "pid \(pid)(caffeinate):"
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(needle) else { continue }
            if let type = assertionType(in: String(trimmed)) {
                held.insert(type)
            }
        }
        return held
    }

    static func assertionType(in line: String) -> String? {
        let known = [
            "PreventUserIdleDisplaySleep",
            "PreventUserIdleSystemSleep"
        ]
        for type in known {
            if line.contains(type) { return type }
        }
        return nil
    }

    static func fetchPmsetAssertionsOutput() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "assertions"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return "" }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    static func snapshot(caffeinatePID: Int32?, processAlive: Bool) -> PowerAssertionSnapshot {
        guard let pid = caffeinatePID, processAlive else {
            return PowerAssertionSnapshot(processAlive: processAlive, heldTypes: [])
        }
        let output = fetchPmsetAssertionsOutput()
        let held = assertionsHeld(byCaffeinatePID: pid, in: output)
        return PowerAssertionSnapshot(processAlive: true, heldTypes: held)
    }
}
