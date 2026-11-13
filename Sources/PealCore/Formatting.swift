import Foundation

package enum Format {
    /// h:mm:ss for an hour or more, else m:ss.
    package static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Time left until `elapsed` (negative while scheduled) reaches zero, rounded up.
    package static func countdown(fromElapsed elapsed: TimeInterval) -> String {
        clock((-elapsed).rounded(.up))
    }

    /// Compact duration: "45s", "45m", "1h30m".
    package static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60)m" : "\(s / 60)m\(s % 60)s" }
        let h = s / 3600, m = (s % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}
