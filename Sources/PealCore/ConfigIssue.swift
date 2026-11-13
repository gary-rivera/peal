import Foundation

/// Why a timer can't start. The single source of validation for both the
/// config panel's live preview and the start-time alert.
package enum ConfigIssue: Equatable, Sendable {
    case noMarks
    case tooManyMarks(Int)
    case windowElapsed

    /// One piece of an explanation; `emphasized` pieces render bold in the panel.
    package typealias Phrase = (text: String, emphasized: Bool)

    package func phrases(for mode: TimerMode) -> [Phrase] {
        let perpetual = mode == .perpetual
        switch self {
        case .noMarks:
            return [(perpetual ? "The interval is an hour or longer — no ticks would play."
                               : "The interval is longer than the window — no ticks would play.", false)]
        case .tooManyMarks(let marks):
            return [(perpetual ? "Each hour fits " : "This window fits ", false),
                    ("\(marks) marks", true),
                    (" — Peal plays at most \(TimerConfig.maxMarks). Lengthen the interval", false),
                    (perpetual ? "." : " or shorten the window.", false)]
        case .windowElapsed:
            return [("That start time's window has already fully elapsed. Pick a later time.", false)]
        }
    }

    package func message(for mode: TimerMode) -> String {
        phrases(for: mode).map(\.text).joined()
    }
}

extension TimerConfig {
    /// Problems with the interval/window shape itself, independent of start time.
    package var issue: ConfigIssue? {
        let marks = markCount
        if marks == 0 { return .noMarks }
        if marks > Self.maxMarks { return .tooManyMarks(marks) }
        return nil
    }

    /// Shape problems, plus a start so far in the past its window is already over.
    /// A past start inside its window is fine: the timer resumes at the next mark.
    package func issue(startingAt start: Date, now: Date) -> ConfigIssue? {
        if let issue { return issue }
        if let window, now.timeIntervalSince(start) >= window { return .windowElapsed }
        return nil
    }
}
