import Foundation
import PealCore

/// The single shared copy of the user's timer settings. Every change is
/// persisted and broadcast, so the menu and config panel never hold stale copies.
@MainActor
final class SettingsStore {
    private(set) var current: TimerSettings
    private let defaults: UserDefaults
    private var observers: [(TimerSettings) -> Void] = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
        current = TimerSettings(defaults: defaults)
    }

    func update(_ change: (inout TimerSettings) -> Void) {
        change(&current)
        current.save(to: defaults)
        for observer in observers { observer(current) }
    }

    func observe(_ observer: @escaping (TimerSettings) -> Void) {
        observers.append(observer)
    }
}
