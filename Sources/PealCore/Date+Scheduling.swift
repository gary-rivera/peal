import Foundation

extension Date {
    /// 11:30:01 → 11:31; 11:30:00 stays 11:30.
    package var roundedUpToMinute: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }
}

extension Calendar {
    /// The next time the clock reads `time`'s hour and minute: today, unless
    /// that has already passed (before the current minute), then tomorrow.
    package func nextOccurrence(ofHourAndMinuteIn time: Date, after now: Date) -> Date {
        let hm = dateComponents([.hour, .minute], from: time)
        let minuteStart = dateInterval(of: .minute, for: now)!.start
        return nextDate(after: minuteStart.addingTimeInterval(-1), matching: hm,
                        matchingPolicy: .nextTime) ?? time
    }
}
