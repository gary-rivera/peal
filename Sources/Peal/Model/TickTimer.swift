import Foundation

class TickTimer {
    let start: Date
    let intervalSeconds: Double
    let windowSeconds: Double
    let sound: String
    // Perpetuity mode: no window — marks anchor to the clock hour (:10, :20, …
    // for a 10m interval), a Submarine bong at :00 resets the count, and the
    // timer runs until stopped by hand.
    let isPerpetual: Bool
    var lastMark: Int
    var startAnnounced: Bool
    var stoppedAt: Date?

    init(start: Date, intervalSeconds: Double, windowSeconds: Double, sound: String,
         isPerpetual: Bool = false) {
        self.start = start
        self.intervalSeconds = intervalSeconds
        self.windowSeconds = windowSeconds
        self.sound = sound
        self.isPerpetual = isPerpetual
        let elapsed = Date().timeIntervalSince(start)
        // A backdated start resumes at the next mark — no catch-up burst.
        lastMark = isPerpetual ? Self.hourMark(at: Date(), interval: intervalSeconds)
                               : max(0, Int(elapsed / intervalSeconds))
        startAnnounced = elapsed >= 0
        // Backdated past its own window: created already finished, no chime.
        if windowSeconds > 0, elapsed >= windowSeconds {
            stoppedAt = start.addingTimeInterval(windowSeconds)
        }
    }

    static func secondsIntoHour(at date: Date) -> Double {
        date.timeIntervalSince(Calendar.current.dateInterval(of: .hour, for: date)!.start)
    }
    static func hourMark(at date: Date, interval: Double) -> Int {
        Int(secondsIntoHour(at: date) / interval)
    }
    // Audible marks per hour: the :00 mark is the reset, not a tick.
    static func marksPerHour(interval: Double) -> Int {
        guard interval > 0, interval < 3600 else { return 0 }
        let m = Int(3600 / interval)
        return 3600.truncatingRemainder(dividingBy: interval) == 0 ? m - 1 : m
    }

    var isStopped: Bool { stoppedAt != nil }
    var elapsed: TimeInterval { (stoppedAt ?? Date()).timeIntervalSince(start) }
    var isActive: Bool { !isStopped && elapsed >= 0 }
    var isScheduled: Bool { !isStopped && elapsed < 0 }
    var isFinished: Bool { isStopped && windowSeconds > 0 && elapsed >= windowSeconds }
    var totalMarks: Int {
        isPerpetual ? Self.marksPerHour(interval: intervalSeconds)
                    : (windowSeconds > 0 ? Int(windowSeconds / intervalSeconds) : 0)
    }
    var marksElapsed: Int {
        isPerpetual ? Self.hourMark(at: stoppedAt ?? Date(), interval: intervalSeconds)
                    : max(0, Int(elapsed / intervalSeconds))
    }
    // Progress along the row's track: window fraction, or position in the hour.
    var progress: Double {
        isPerpetual ? Self.secondsIntoHour(at: stoppedAt ?? Date()) / 3600
                    : (windowSeconds > 0 ? min(1, elapsed / windowSeconds) : 0)
    }
}
