import Foundation

/// How long a timer runs.
package enum TimerMode: Equatable, Sendable {
    /// Ticks across a fixed window, then finishes with a chime.
    case timed(window: TimeInterval)
    /// No window: marks anchor to the clock hour (:10, :20, … for a 10m
    /// interval), the count resets at :00, and the timer runs until stopped.
    case perpetual
}

/// The settings a timer launches with. Each timer keeps its own copy.
package struct TimerConfig: Equatable, Sendable {
    /// The most marks a single window (or clock hour) may hold.
    package static let maxMarks = 9

    package var interval: TimeInterval
    package var mode: TimerMode
    package var sound: String

    package init(interval: TimeInterval, mode: TimerMode, sound: String) {
        self.interval = interval
        self.mode = mode
        self.sound = sound
    }

    package var isPerpetual: Bool { mode == .perpetual }

    package var window: TimeInterval? {
        if case .timed(let window) = mode { window } else { nil }
    }

    /// Audible marks per window, or per clock hour (where :00 is the reset, not a tick).
    package var markCount: Int {
        guard interval > 0 else { return 0 }
        switch mode {
        case .timed(let window): return max(0, Int(window / interval))
        case .perpetual: return ClockHour.audibleMarks(interval: interval)
        }
    }

    /// The stretch of time one progress track covers: the window, or one clock hour.
    package var span: TimeInterval { window ?? ClockHour.duration }

    /// Where mark `index` (1-based) sits along the track, from 0 to 1.
    package func position(ofMark index: Int) -> Double {
        min(1, Double(index) * interval / span)
    }
}

/// Clock-hour arithmetic for perpetual timers.
package enum ClockHour {
    package static let duration: TimeInterval = 3600

    package static func secondsInto(_ date: Date, calendar: Calendar) -> TimeInterval {
        date.timeIntervalSince(calendar.dateInterval(of: .hour, for: date)!.start)
    }

    /// The interval mark most recently passed this hour (0 right after :00).
    package static func mark(at date: Date, interval: TimeInterval, calendar: Calendar) -> Int {
        guard interval > 0 else { return 0 }
        return Int(secondsInto(date, calendar: calendar) / interval)
    }

    /// Marks that tick each hour. An interval that divides the hour evenly
    /// lands its last mark on :00, which is the reset rather than a tick.
    package static func audibleMarks(interval: TimeInterval) -> Int {
        guard interval > 0, interval < duration else { return 0 }
        let marks = Int(duration / interval)
        return duration.truncatingRemainder(dividingBy: interval) == 0 ? marks - 1 : marks
    }
}
