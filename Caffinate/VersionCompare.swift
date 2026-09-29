import Foundation

enum VersionCompare {
    /// True when `a` is a newer semantic-ish dotted version than `b`.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0) ?? 0 }
        }
        let ap = parts(a)
        let bp = parts(b)
        let n = max(ap.count, bp.count)
        for i in 0..<n {
            let ai = i < ap.count ? ap[i] : 0
            let bi = i < bp.count ? bp[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}
