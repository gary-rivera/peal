import Foundation

/// Every timer the app knows about, kept sorted by start time.
package final class TimerStore {
    package private(set) var timers: [TickTimer] = []

    package init() {}

    package var isEmpty: Bool { timers.isEmpty }

    package func add(_ timer: TickTimer) {
        let index = timers.firstIndex { $0.start > timer.start } ?? timers.endIndex
        timers.insert(timer, at: index)
    }

    package func remove(_ timer: TickTimer) {
        timers.removeAll { $0 === timer }
    }

    package func stopAll(at now: Date) {
        for timer in timers where timer.phase(at: now) == .running { timer.stop(at: now) }
    }

    /// Advances every timer to `now`, returning each event with the timer it came from.
    package func advance(now: Date) -> [(timer: TickTimer, event: TickTimer.Event)] {
        timers.flatMap { timer in timer.advance(now: now).map { (timer, $0) } }
    }

    package func timers(in phases: Set<TickTimer.Phase>, at now: Date) -> [TickTimer] {
        timers.filter { phases.contains($0.phase(at: now)) }
    }

    package func hasRunning(at now: Date) -> Bool {
        timers.contains { $0.phase(at: now) == .running }
    }

    /// Menu bar text for the earliest running timer ("3/9"), else the next
    /// scheduled one ("in 4:32"), else "✓" once all are done. "+N" counts the rest.
    package func statusTitle(at now: Date) -> String {
        let extras = timers.count > 1 ? " +\(timers.count - 1)" : ""
        if let t = timers.first(where: { $0.phase(at: now) == .running }) {
            let marks = t.config.markCount
            let text = marks > 0 ? "\(t.marksElapsed(at: now))/\(marks)" : Format.clock(t.elapsed(at: now))
            return text + extras
        }
        if let next = timers.first(where: { $0.phase(at: now) == .scheduled }) {
            return "in " + Format.countdown(fromElapsed: next.elapsed(at: now)) + extras
        }
        return timers.isEmpty ? "" : "✓"
    }
}
