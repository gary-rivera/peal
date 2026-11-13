import AppKit
import PealCore

/// Builds the status item's menu: actions, the tick-volume row, timers
/// grouped by section, and the Stop all footer.
@MainActor
final class MenuController: NSObject {
    var onOpenConfig: (() -> Void)?
    var onStartPerpetuity: (() -> Void)?
    var onPlaySample: (() -> Void)?
    var onVolumeCommit: (() -> Void)?
    /// A row or the footer changed the timer list; the app should re-render.
    var onTimersChanged: (() -> Void)?
    /// A new menu was built; install it on the status item.
    var onRebuild: ((NSMenu) -> Void)?

    private let store: TimerStore
    private let settings: SettingsStore
    private var volumeSlider: VolumeSlider?
    private var rowViews: [TimerRowView] = []
    private var footbar: FootbarView?
    private var builtSections: [Section] = []

    private enum Section: CaseIterable {
        case ongoing, upcoming, finished

        init(_ phase: TickTimer.Phase) {
            switch phase {
            case .running: self = .ongoing
            case .scheduled: self = .upcoming
            case .finished, .stopped: self = .finished
            }
        }

        var title: String {
            switch self {
            case .ongoing: "Ongoing"
            case .upcoming: "Upcoming"
            case .finished: "Finished"
            }
        }

        var dot: NSColor {
            switch self {
            case .ongoing: Theme.sysGreen
            case .upcoming: Theme.sysOrange
            case .finished: Theme.sysGray
            }
        }
    }

    init(store: TimerStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        super.init()
        settings.observe { [weak self] in self?.volumeSlider?.value = $0.volume }
    }

    /// Redraws live rows, rebuilding first if any timer changed section.
    func refresh(now: Date) {
        if sections(at: now) != builtSections { rebuild(now: now) }
        for row in rowViews { row.refresh() }
        footbar?.stopEnabled = store.hasRunning(at: now)
    }

    func rebuild(now: Date) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = Theme.menuWidth
        menu.addItem(actionItem("Start timer", #selector(openConfig), ","))
        menu.addItem(actionItem("Start in perpetuity", #selector(startPerpetuity), "p"))
        menu.addItem(actionItem("Play sample ticks", #selector(playSample), "t"))
        menu.addItem(viewItem(makeVolumeSlider()))
        menu.addItem(.separator())

        rowViews = []
        footbar = nil
        if store.isEmpty {
            let none = NSMenuItem(title: "No timers", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for section in Section.allCases {
                let timers = store.timers.filter { Section($0.phase(at: now)) == section }
                guard !timers.isEmpty else { continue }
                menu.addItem(viewItem(SectionHeaderView(section.title, dot: section.dot, count: timers.count)))
                for timer in timers { menu.addItem(viewItem(makeRow(for: timer))) }
            }
            let foot = FootbarView()
            foot.onStopAll = { [weak self] in
                self?.store.stopAll(at: Date())
                self?.onTimersChanged?()
            }
            foot.stopEnabled = store.hasRunning(at: now)
            menu.addItem(viewItem(foot))
            footbar = foot
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Peal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        builtSections = sections(at: now)
        onRebuild?(menu)
    }

    // MARK: - Pieces

    private func sections(at now: Date) -> [Section] {
        store.timers.map { Section($0.phase(at: now)) }
    }

    private func makeVolumeSlider() -> VolumeSlider {
        let slider = VolumeSlider(title: "Tick volume", value: settings.current.volume,
                                  width: Theme.menuWidth, insetX: 16)
        slider.onChange = { [weak self] v in self?.settings.update { $0.volume = v } }
        slider.onCommit = { [weak self] in self?.onVolumeCommit?() }
        volumeSlider = slider
        return slider
    }

    private func makeRow(for timer: TickTimer) -> TimerRowView {
        let row = TimerRowView(timer: timer)
        row.onStop = { [weak self] in
            timer.stop(at: Date())
            self?.onTimersChanged?()
        }
        row.onReset = { [weak self] in
            guard let self else { return }
            store.remove(timer)
            rebuild(now: Date())
            onTimersChanged?()
        }
        rowViews.append(row)
        return row
    }

    private func actionItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    @objc private func openConfig() { onOpenConfig?() }
    @objc private func startPerpetuity() { onStartPerpetuity?() }
    @objc private func playSample() { onPlaySample?() }
}
