import Foundation

/// Builds `caffeinate` argv (pure, testable). Does not include `-w` — the manager appends it.
enum CaffeinateCommandBuilder {
    /// Keep-awake flags (`-i`, optional `-d`, optional `-t`). No `-w`.
    static func buildArguments(
        preventIdleSleep: Bool,
        preventDisplaySleep: Bool,
        timeoutSeconds: Int?
    ) -> [String] {
        var args: [String] = []
        if preventIdleSleep { args.append("-i") }
        if preventDisplaySleep { args.append("-d") }
        if let timeoutSeconds, timeoutSeconds > 0 {
            args.append(contentsOf: ["-t", "\(timeoutSeconds)"])
        }
        return args
    }

    static func hasEffectiveKeepAwakeFlags(_ args: [String]) -> Bool {
        let keepAwake = Set(["-d", "-i"])
        return args.contains { keepAwake.contains($0) }
    }
}

/// How long a keep-awake session should last.
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

    var chipLabel: String {
        switch self {
        case .indefinite: return "∞"
        case .minutes(let m) where m < 60: return "\(m)"
        case .minutes(let m): return String(format: "%02d", m / 60)
        case .until(let h, let m): return String(format: "%02d:%02d", h, m)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .indefinite: return "Indefinitely"
        case .minutes(let m) where m < 60: return "\(m) minutes"
        case .minutes(let m): return "\(m / 60) hours"
        case .until(let h, let m): return String(format: "Until %02d:%02d", h, m)
        }
    }

    /// Title for a standard `NSMenu` item.
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

    static let presets: [SessionDuration] = [
        .indefinite,
        .minutes(15),
        .minutes(30),
        .minutes(45),
        .minutes(60),
        .minutes(240),
        .minutes(480)
    ]
}
