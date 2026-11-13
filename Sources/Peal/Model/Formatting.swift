import Foundation

// h:mm:ss for an hour or more, else m:ss.
func clock(_ seconds: Int) -> String {
    seconds >= 3600
        ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

// Compact duration: "45s", "45m", "1h30m".
func shortDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    if s < 3600 { return s % 60 == 0 ? "\(s / 60)m" : "\(s / 60)m\(s % 60)s" }
    let h = s / 3600, m = (s % 3600) / 60
    return m == 0 ? "\(h)h" : "\(h)h\(m)m"
}
