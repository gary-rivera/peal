import Foundation

package enum TimeUnit: Int, CaseIterable, Sendable {
    case sec, min, hr

    package var seconds: TimeInterval {
        switch self {
        case .sec: 1
        case .min: 60
        case .hr: 3600
        }
    }

    package var label: String { "\(self)" }
}

/// The config panel's choices, persisted as defaults for the next timer.
package struct TimerSettings: Equatable, Sendable {
    package static let defaultSound = "Tink"

    package var intervalValue: Double = 10
    package var intervalUnit: TimeUnit = .min
    package var windowValue: Double = 45
    package var windowUnit: TimeUnit = .min
    package var sound = defaultSound
    package var isPerpetual = false
    /// Global multiplier over every sound's volume (1 = full).
    package var volume: Double = 1

    package init() {}

    package var intervalSeconds: TimeInterval { intervalValue * intervalUnit.seconds }
    package var windowSeconds: TimeInterval { windowValue * windowUnit.seconds }

    /// The config a timer launched now would use, optionally forcing perpetuity.
    package func config(perpetual: Bool? = nil) -> TimerConfig {
        let mode: TimerMode = (perpetual ?? isPerpetual) ? .perpetual : .timed(window: windowSeconds)
        return TimerConfig(interval: intervalSeconds, mode: mode, sound: sound)
    }

    // MARK: Persistence

    private enum Key: String {
        case intervalValue, intervalUnit, windowValue, windowUnit
        case sound = "tickSound"
        case isPerpetual = "perpetuity"
        case volume = "tickVolume"
    }

    package init(defaults: UserDefaults) {
        func value<T>(_ key: Key) -> T? { defaults.object(forKey: key.rawValue) as? T }
        func unit(_ key: Key) -> TimeUnit? { value(key).flatMap(TimeUnit.init(rawValue:)) }
        intervalValue = value(.intervalValue) ?? intervalValue
        intervalUnit = unit(.intervalUnit) ?? intervalUnit
        windowValue = value(.windowValue) ?? windowValue
        windowUnit = unit(.windowUnit) ?? windowUnit
        sound = value(.sound) ?? sound
        isPerpetual = value(.isPerpetual) ?? isPerpetual
        volume = value(.volume) ?? volume
    }

    package func save(to defaults: UserDefaults) {
        let values: [Key: Any] = [
            .intervalValue: intervalValue, .intervalUnit: intervalUnit.rawValue,
            .windowValue: windowValue, .windowUnit: windowUnit.rawValue,
            .sound: sound, .isPerpetual: isPerpetual, .volume: volume,
        ]
        for (key, value) in values { defaults.set(value, forKey: key.rawValue) }
    }
}
