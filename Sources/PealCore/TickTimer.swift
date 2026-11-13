import Foundation

/// One running, scheduled, or finished timer. Every query takes `now` so that
/// a single redraw reads one consistent instant and tests control the clock.
package final class TickTimer {
    package enum Phase: Equatable, Sendable {
        case scheduled, running, finished, stopped
    }

    /// What happened during one `advance(now:)`; the app maps these to sounds.
    package enum Event: Equatable, Sendable {
        case started            // a scheduled timer just began
        case ticks(Int)         // the Nth mark passed: play N ticks
        case hourReset          // perpetuity rolled past :00
        case finished           // the window ended
    }

    package let start: Date
    package let config: TimerConfig
    private let calendar: Calendar
    package private(set) var lastFiredMark: Int
    package private(set) var startAnnounced: Bool
    package private(set) var stoppedAt: Date?

    package init(start: Date, config: TimerConfig, now: Date = Date(), calendar: Calendar = .current) {
        self.start = start
        self.config = config
        self.calendar = calendar
        lastFiredMark = 0
        let elapsed = now.timeIntervalSince(start)
        startAnnounced = elapsed >= 0
        // A backdated start resumes at the next mark: no catch-up burst.
        lastFiredMark = mark(at: now)
        // Backdated past its own window: created already finished, no chime.
        if let window = config.window, elapsed >= window {
            stoppedAt = start.addingTimeInterval(window)
        }
    }

    package func phase(at now: Date) -> Phase {
        if let stoppedAt {
            let completedWindow = config.window.map { stoppedAt.timeIntervalSince(start) >= $0 } ?? false
            return completedWindow ? .finished : .stopped
        }
        return now < start ? .scheduled : .running
    }

    /// Time since start, frozen once stopped. Negative while scheduled.
    package func elapsed(at now: Date) -> TimeInterval {
        (stoppedAt ?? now).timeIntervalSince(start)
    }

    package func marksElapsed(at now: Date) -> Int { mark(at: stoppedAt ?? now) }

    /// Progress along the row's track: window fraction, or position in the hour.
    package func progress(at now: Date) -> Double {
        let end = stoppedAt ?? now
        switch config.mode {
        case .perpetual:
            return ClockHour.secondsInto(end, calendar: calendar) / ClockHour.duration
        case .timed(let window):
            return window > 0 ? min(1, end.timeIntervalSince(start) / window) : 0
        }
    }

    package func stop(at now: Date) {
        guard stoppedAt == nil else { return }
        stoppedAt = now
    }

    /// Moves the timer to `now` and reports what should be heard.
    package func advance(now: Date) -> [Event] {
        guard stoppedAt == nil, now >= start else { return [] }
        var events: [Event] = []
        if !startAnnounced {
            startAnnounced = true
            events.append(.started)
        }
        if let window = config.window, now.timeIntervalSince(start) >= window {
            stoppedAt = start.addingTimeInterval(window)
            return events + [.finished]
        }
        let mark = mark(at: now)
        if mark > lastFiredMark {
            events.append(.ticks(mark))
        } else if mark < lastFiredMark {
            // Window marks never decrease, so this is perpetuity's top of the hour.
            events.append(.hourReset)
        }
        lastFiredMark = mark
        return events
    }

    /// The interval mark most recently passed at `date`.
    private func mark(at date: Date) -> Int {
        guard config.interval > 0 else { return 0 }
        switch config.mode {
        case .perpetual:
            return ClockHour.mark(at: date, interval: config.interval, calendar: calendar)
        case .timed:
            return max(0, Int(date.timeIntervalSince(start) / config.interval))
        }
    }
}
