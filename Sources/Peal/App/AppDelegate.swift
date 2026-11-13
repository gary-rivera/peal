import AppKit
import PealCore

/// Owns the app's objects and wires them together; holds no UI or timer logic.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore(defaults: .standard)
    private let store = TimerStore()
    private let sound = SoundPlayer()
    private lazy var statusItem = StatusItemController()
    private lazy var menu = makeMenu()
    private var configPanel: ConfigPanelController?  // built on first open
    private var clock: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        sound.volume = settings.current.volume
        settings.observe { [sound] in sound.volume = $0.volume }

        menu.rebuild(now: Date())

        // .common mode keeps the timer firing while the menu is open.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        tick()
    }

    private func makeMenu() -> MenuController {
        let menu = MenuController(store: store, settings: settings)
        menu.onRebuild = { [weak self] in self?.statusItem.menu = $0 }
        menu.onTimersChanged = { [weak self] in self?.refresh() }
        menu.onOpenConfig = { [weak self] in self?.openConfig() }
        // Skips the panel; the saved Timed/Perpetuity choice is left as is.
        menu.onStartPerpetuity = { [weak self] in self?.startTimer(at: Date(), perpetual: true) }
        menu.onPlaySample = { [weak self] in self?.playTicks(3) }
        menu.onVolumeCommit = { [weak self] in self?.playTicks(1) }
        return menu
    }

    /// Once a second: advance every timer, play what it reports, re-render.
    private func tick() {
        let now = Date()
        for (timer, event) in store.advance(now: now) {
            sound.play(event, tickSound: timer.config.sound)
        }
        refresh(now: now)
    }

    private func refresh(now: Date = Date()) {
        menu.refresh(now: now)
        statusItem.render(title: store.statusTitle(at: now), active: store.hasRunning(at: now))
        configPanel?.refresh(now: now)
    }

    /// Validates the saved settings for this start; on success adds the timer
    /// and closes the panel, otherwise explains why in an alert.
    private func startTimer(at start: Date, perpetual: Bool) {
        let config = settings.current.config(perpetual: perpetual)
        if let issue = config.issue(startingAt: start, now: Date()) {
            showAlert("Can't start timer", issue.message(for: config.mode))
            return
        }
        store.add(TickTimer(start: start, config: config))
        menu.rebuild(now: Date())
        refresh()
        configPanel?.close()
    }

    private func openConfig() {
        if configPanel == nil {
            let panel = ConfigPanelController(settings: settings, sounds: SoundPlayer.availableSounds())
            panel.onStart = { [weak self] start, perpetual in self?.startTimer(at: start, perpetual: perpetual) }
            panel.onAudition = { [sound] name in sound.play(name) }
            panel.onVolumeCommit = { [weak self] in self?.playTicks(1) }
            configPanel = panel
        }
        configPanel?.show()
    }

    /// A burst of the saved tick sound; one tick after a volume change answers "how loud?".
    private func playTicks(_ count: Int) {
        sound.play(settings.current.sound, times: count, gap: 0.2)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window = configPanel?.visibleWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
