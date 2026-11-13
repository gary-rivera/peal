import Foundation

// One-time carry-over of settings saved before the Tickle → Peal rename, when
// the bundle ID was com.garyrivera.tickle. Runs before AppDelegate reads its
// defaults. Delete once no pre-rename installs remain.
func migrateTickleDefaults() {
    let defaults = UserDefaults.standard
    guard let id = Bundle.main.bundleIdentifier,
          defaults.persistentDomain(forName: id) == nil,
          let legacy = defaults.persistentDomain(forName: "com.garyrivera.tickle")
    else { return }
    defaults.setPersistentDomain(legacy, forName: id)
}
