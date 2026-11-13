import Foundation
import Testing
@testable import PealCore

// A top-of-the-hour instant (1_800_000_000 is divisible by 3600) and a UTC
// calendar, so clock-hour math is deterministic in any local time zone.
private let topOfHour = Date(timeIntervalSince1970: 1_800_000_000)
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func minutes(_ m: Double) -> TimeInterval { m * 60 }
private func timed(every interval: Double, over window: Double) -> TimerConfig {
    TimerConfig(interval: minutes(interval), mode: .timed(window: minutes(window)), sound: "Tink")
}
private func perpetual(every interval: Double) -> TimerConfig {
    TimerConfig(interval: minutes(interval), mode: .perpetual, sound: "Tink")
}

@Suite struct MarkScheduleTests {
    @Test(arguments: [(600.0, 5), (900, 3), (420, 8), (3600, 0), (0, 0), (-5, 0)])
    func audibleMarksPerHour(interval: Double, expected: Int) {
        #expect(ClockHour.audibleMarks(interval: interval) == expected)
    }

    @Test func timedMarkCount() {
        #expect(timed(every: 10, over: 45).markCount == 4)
        #expect(timed(every: 50, over: 45).markCount == 0)
        #expect(TimerConfig(interval: 0, mode: .timed(window: 60), sound: "").markCount == 0)
    }

    // Regression: menu rows used to space marks evenly (mark 4 of 4 at 100%).
    @Test func marksSitAtTheirTrueTimes() {
        let config = timed(every: 10, over: 45)
        #expect(config.position(ofMark: 4) == 40.0 / 45.0)
        #expect(config.position(ofMark: 9) == 1)  // clamped
        #expect(perpetual(every: 10).position(ofMark: 3) == 0.5)
    }
}

@Suite struct ConfigIssueTests {
    @Test func shapeIssues() {
        #expect(timed(every: 10, over: 45).issue == nil)
        #expect(timed(every: 50, over: 45).issue == .noMarks)
        #expect(timed(every: 1, over: 10).issue == .tooManyMarks(10))
        #expect(perpetual(every: 60).issue == .noMarks)
        #expect(perpetual(every: 5).issue == .tooManyMarks(11))
    }

    @Test func pastStartIsFineUntilItsWindowHasElapsed() {
        let config = timed(every: 10, over: 45)
        let now = topOfHour
        #expect(config.issue(startingAt: now - minutes(44), now: now) == nil)
        #expect(config.issue(startingAt: now - minutes(45), now: now) == .windowElapsed)
        #expect(perpetual(every: 10).issue(startingAt: now - minutes(500), now: now) == nil)
    }

    @Test func alertAndPanelShareOneMessage() {
        let message = ConfigIssue.tooManyMarks(12).message(for: .perpetual)
        #expect(message == "Each hour fits 12 marks — Peal plays at most 9. Lengthen the interval.")
    }
}

@Suite struct TickTimerTests {
    @Test func scheduledTimerPopsAtStartThenTicksEachMark() {
        let start = topOfHour + minutes(5)
        let t = TickTimer(start: start, config: timed(every: 10, over: 45), now: topOfHour, calendar: utc)
        #expect(t.phase(at: topOfHour) == .scheduled)
        #expect(t.advance(now: topOfHour) == [])
        #expect(t.advance(now: start) == [.started])
        #expect(t.advance(now: start + minutes(10)) == [.ticks(1)])
        #expect(t.advance(now: start + minutes(10.5)) == [])
        #expect(t.advance(now: start + minutes(20)) == [.ticks(2)])
    }

    @Test func backdatedStartResumesWithoutCatchUpBurst() {
        let now = topOfHour
        let t = TickTimer(start: now - minutes(25), config: timed(every: 10, over: 45), now: now, calendar: utc)
        #expect(t.startAnnounced)
        #expect(t.lastFiredMark == 2)
        #expect(t.advance(now: now) == [])
        #expect(t.advance(now: now + minutes(5)) == [.ticks(3)])
    }

    @Test func windowEndFinishesTheTimer() {
        let t = TickTimer(start: topOfHour, config: timed(every: 10, over: 45), now: topOfHour, calendar: utc)
        let end = topOfHour + minutes(45)
        #expect(t.advance(now: end + 1) == [.finished])
        #expect(t.phase(at: end + 60) == .finished)
        #expect(t.elapsed(at: end + 60) == minutes(45))
        #expect(t.progress(at: end + 60) == 1)
        #expect(t.advance(now: end + 60) == [])
    }

    @Test func backdatedPastItsWindowIsCreatedFinished() {
        let now = topOfHour
        let t = TickTimer(start: now - minutes(50), config: timed(every: 10, over: 45), now: now, calendar: utc)
        #expect(t.phase(at: now) == .finished)
        #expect(t.advance(now: now) == [])
    }

    @Test func stoppingFreezesTheTimer() {
        let t = TickTimer(start: topOfHour, config: timed(every: 10, over: 45), now: topOfHour, calendar: utc)
        t.stop(at: topOfHour + minutes(12))
        let later = topOfHour + minutes(30)
        #expect(t.phase(at: later) == .stopped)
        #expect(t.elapsed(at: later) == minutes(12))
        #expect(t.marksElapsed(at: later) == 1)
        #expect(t.advance(now: later) == [])
    }

    @Test func perpetuityAnchorsToTheClockHourAndResetsAtTheTop() {
        let start = topOfHour + minutes(5)
        let t = TickTimer(start: start, config: perpetual(every: 10), now: start, calendar: utc)
        #expect(t.lastFiredMark == 0)
        #expect(t.advance(now: topOfHour + minutes(10)) == [.ticks(1)])
        #expect(t.advance(now: topOfHour + minutes(50)) == [.ticks(5)])
        #expect(t.progress(at: topOfHour + minutes(30)) == 0.5)
        #expect(t.advance(now: topOfHour + minutes(60)) == [.hourReset])
        #expect(t.advance(now: topOfHour + minutes(70)) == [.ticks(1)])
        #expect(t.phase(at: topOfHour + minutes(600)) == .running)
    }
}

@Suite struct FormatTests {
    @Test func clock() {
        #expect(Format.clock(59) == "0:59")
        #expect(Format.clock(3725) == "1:02:05")
        #expect(Format.countdown(fromElapsed: -4.2) == "0:05")
    }

    @Test func duration() {
        #expect(Format.duration(45) == "45s")
        #expect(Format.duration(90) == "1m30s")
        #expect(Format.duration(2700) == "45m")
        #expect(Format.duration(5400) == "1h30m")
        #expect(Format.duration(7200) == "2h")
    }

    @Test func roundedUpToMinute() {
        #expect(topOfHour.roundedUpToMinute == topOfHour)
        #expect((topOfHour + 1).roundedUpToMinute == topOfHour + 60)
    }
}

@Suite struct TimerSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "PealCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func roundTripsThroughUserDefaults() {
        let defaults = freshDefaults()
        var settings = TimerSettings()
        settings.intervalValue = 5
        settings.intervalUnit = .sec
        settings.windowUnit = .hr
        settings.sound = "Glass"
        settings.isPerpetual = true
        settings.volume = 0.4
        settings.save(to: defaults)
        #expect(TimerSettings(defaults: defaults) == settings)
    }

    @Test func emptyDefaultsGiveTheDefaults() {
        #expect(TimerSettings(defaults: freshDefaults()) == TimerSettings())
    }

    // Regression: a bad saved unit index used to crash on array lookup.
    @Test func corruptUnitFallsBackToMinutes() {
        let defaults = freshDefaults()
        defaults.set(99, forKey: "intervalUnit")
        #expect(TimerSettings(defaults: defaults).intervalUnit == .min)
    }

    @Test func configHonorsPerpetuityOverride() {
        let settings = TimerSettings()
        #expect(settings.config().mode == .timed(window: minutes(45)))
        #expect(settings.config(perpetual: true).mode == .perpetual)
        #expect(settings.config().interval == minutes(10))
    }
}
