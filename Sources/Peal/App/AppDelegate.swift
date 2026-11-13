import AppKit
import PealCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timers: [TickTimer] = []
    var rowViews: [TimerRowView] = []
    var footbar: FootbarView?
    var menuSignature = ""
    // Hold references so sounds aren't deallocated mid-playback.
    var sounds: [NSSound] = []

    // Defaults for the next timer; every change persists.
    var settings = TimerSettings(defaults: .standard) {
        didSet { settings.save(to: .standard) }
    }

    var configPanel: NSPanel?
    var intervalStepper: StepperControl!
    var intervalSeg: SegControl!
    var windowStepper: StepperControl!
    var windowSeg: SegControl!
    var perpetuitySeg: SegControl!
    var menuVolumeSlider: VolumeSlider?
    var panelVolumeSlider: VolumeSlider!
    var timelineCard: TimelineCard!
    var soundPopup: SoundPopupControl!
    var whenSeg: SegControl!
    var startPicker: NSDatePicker!
    var goButton: GoButton!
    // While false, the picker live-tracks the clock (next whole minute);
    // flips true on manual edit so the user's choice isn't clobbered.
    var startPickerTouched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()

        // .common mode keeps the timer firing while the menu is open.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        update()
    }

    // MARK: - Menu

    func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // One character per timer's section; when it changes, the menu needs rebuilding.
    func sectionSignature() -> String {
        let now = Date()
        return timers.map { t in
            switch t.phase(at: now) {
            case .running: "a"
            case .scheduled: "u"
            case .finished, .stopped: "f"
            }
        }.joined()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = Theme.menuWidth
        menu.addItem(makeItem("Start timer", #selector(openConfig), ","))
        menu.addItem(makeItem("Start in perpetuity", #selector(startPerpetuity), "p"))
        menu.addItem(makeItem("Play sample ticks", #selector(testTicks), "t"))
        let volumeRow = VolumeSlider(title: "Tick volume", value: settings.volume,
                                     width: Theme.menuWidth, insetX: 16)
        volumeRow.onChange = { [weak self] v in self?.setTickVolume(v) }
        volumeRow.onCommit = { [weak self] in self?.auditionVolume() }
        let volumeItem = NSMenuItem()
        volumeItem.view = volumeRow
        menu.addItem(volumeItem)
        menuVolumeSlider = volumeRow
        menu.addItem(.separator())

        rowViews = []
        footbar = nil

        func addSection(_ header: String, dot: NSColor, _ list: [TickTimer]) {
            guard !list.isEmpty else { return }
            let headerItem = NSMenuItem()
            headerItem.view = SectionHeaderView(header, dot: dot, count: list.count)
            menu.addItem(headerItem)
            for timer in list {
                let row = TimerRowView(timer: timer)
                row.onStop = { [weak self] in
                    timer.stop(at: Date())
                    self?.update()
                }
                row.onReset = { [weak self] in
                    guard let self else { return }
                    self.timers.removeAll { $0 === timer }
                    self.rebuildMenu()
                    self.update()
                }
                let item = NSMenuItem()
                item.view = row
                menu.addItem(item)
                rowViews.append(row)
            }
        }

        if timers.isEmpty {
            let none = NSMenuItem(title: "No timers", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            let now = Date()
            addSection("Ongoing", dot: Theme.sysGreen, timers.filter { $0.phase(at: now) == .running })
            addSection("Upcoming", dot: Theme.sysOrange, timers.filter { $0.phase(at: now) == .scheduled })
            addSection("Finished", dot: Theme.sysGray, timers.filter { $0.isStopped })
            let foot = FootbarView()
            foot.onStopAll = { [weak self] in self?.stopAllTimers() }
            foot.stopEnabled = timers.contains { $0.phase(at: now) == .running }
            let footItem = NSMenuItem()
            footItem.view = foot
            menu.addItem(footItem)
            footbar = foot
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Peal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        menuSignature = sectionSignature()
    }

    // MARK: - Timer core

    // Each timer event's sound: Pop at a scheduled start, N ticks at the Nth
    // mark, a Submarine bong at perpetuity's top of the hour, and a double
    // Glass chime as the window-end stop signal.
    func play(_ event: TickTimer.Event, of timer: TickTimer) {
        switch event {
        case .started: play("Pop", times: 1, gap: 0)
        case .ticks(let count): play(timer.config.sound, times: count, gap: 0.2)
        case .hourReset: play("Submarine", times: 1, gap: 0)
        case .finished: play("Glass", times: 2, gap: 0.6)
        }
    }

    func update() {
        let now = Date()
        for t in timers {
            for event in t.advance(now: now) { play(event, of: t) }
        }

        // A timer changed section (upcoming → ongoing → finished): regroup.
        if sectionSignature() != menuSignature { rebuildMenu() }

        let anyActive = timers.contains { $0.phase(at: now) == .running }
        let icon = NSImage(systemSymbolName: anyActive ? "bell.fill" : "bell",
                           accessibilityDescription: "Peal")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let text = statusTitle()
        statusItem.button?.title = text.isEmpty ? "" : " " + text

        for row in rowViews { row.refresh() }
        footbar?.stopEnabled = anyActive

        // Untouched "Start at" tracks the clock, rounded up to the next minute.
        if let panel = configPanel, panel.isVisible, !startPickerTouched {
            startPicker.dateValue = now.roundedUpToMinute
        }
    }

    @objc func startPickerEdited() { startPickerTouched = true }

    // Timers are kept sorted by start, so the first match is the earliest.
    func statusTitle() -> String {
        let now = Date()
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

    func addTimer(startingAt start: Date, perpetual: Bool) {
        let config = settings.config(perpetual: perpetual)
        if let issue = config.issue(startingAt: start, now: Date()) {
            let alert = NSAlert()
            alert.messageText = "Can't start timer"
            alert.informativeText = issue.message(for: config.mode)
            alert.alertStyle = .warning
            if let panel = configPanel, panel.isVisible {
                alert.beginSheetModal(for: panel)
            } else {
                alert.runModal()
            }
            return
        }
        timers.append(TickTimer(start: start, config: config))
        timers.sort { $0.start < $1.start }
        rebuildMenu()
        update()
        configPanel?.orderOut(nil)
    }

    // Menu shortcut: an endless clock-anchored timer with the saved interval
    // and sound, skipping the config panel. The saved Timed/Perpetuity choice
    // is left as is.
    @objc func startPerpetuity() { addTimer(startingAt: Date(), perpetual: true) }

    @objc func stopAllTimers() {
        let now = Date()
        for t in timers where t.phase(at: now) == .running { t.stop(at: now) }
        update()
    }

    @objc func testTicks() { play(settings.sound, times: 3, gap: 0.2) }

    // One knob, two sliders: persist and keep menu + panel in step.
    func setTickVolume(_ v: Double) {
        settings.volume = v
        menuVolumeSlider?.value = v
        panelVolumeSlider?.value = v
    }
    // A single tick at the new level, so releasing the slider answers "how loud?".
    func auditionVolume() { play(settings.sound, times: 1, gap: 0) }

    static func availableSounds() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds"))?
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted() ?? []
        return names.isEmpty ? [TimerSettings.defaultSound] : names
    }

    // The tick-volume slider IS the output level: 100% plays samples at full
    // NSSound volume (which still tops out at the Mac's output volume).
    func play(_ name: String, times: Int, gap: Double) {
        sounds.removeAll { !$0.isPlaying }
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * gap) { [weak self] in
                guard let self else { return }
                if let sound = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true) {
                    sound.volume = Float(self.settings.volume)
                    self.sounds.append(sound)
                    sound.play()
                }
            }
        }
    }

    // MARK: - Configuration panel

    @objc func openConfig() {
        if configPanel == nil { buildConfigPanel() }
        intervalStepper.value = max(1, Int(settings.intervalValue))
        intervalSeg.selected = settings.intervalUnit.rawValue
        windowStepper.value = max(1, Int(settings.windowValue))
        windowSeg.selected = settings.windowUnit.rawValue
        perpetuitySeg.selected = settings.isPerpetual ? 1 : 0
        windowStepper.isHidden = settings.isPerpetual
        windowSeg.isHidden = settings.isPerpetual
        soundPopup.select(settings.sound)
        panelVolumeSlider.value = settings.volume
        whenSeg.selected = 0
        startPicker.isHidden = true
        goButton.title = "Start timer"
        startPickerTouched = false
        startPicker.dateValue = Date().roundedUpToMinute
        renderTimeline()
        NSApp.activate(ignoringOtherApps: true)
        configPanel!.center()
        configPanel!.makeKeyAndOrderFront(nil)
    }

    func buildConfigPanel() {
        let contentW: CGFloat = 493
        let padX: CGFloat = 26
        let content = FlippedView()

        func capLabel(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithAttributedString: Theme.caption(text))
            l.sizeToFit()
            return l
        }
        var y: CGFloat = 22

        // One caption + stepper + unit row; changes update settings and re-render the timeline.
        func valueUnitRow(_ caption: String,
                          value valuePath: WritableKeyPath<TimerSettings, Double>,
                          unit unitPath: WritableKeyPath<TimerSettings, TimeUnit>,
                          x: CGFloat = padX)
            -> (StepperControl, SegControl) {
            let cap = capLabel(caption)
            cap.setFrameOrigin(NSPoint(x: padX, y: y)); content.addSubview(cap)
            y += 16 + 7
            let stepper = StepperControl(value: max(1, Int(settings[keyPath: valuePath])))
            stepper.setFrameOrigin(NSPoint(x: x, y: y)); content.addSubview(stepper)
            let seg = SegControl(items: TimeUnit.allCases.map(\.label),
                                 selected: settings[keyPath: unitPath].rawValue)
            seg.setFrameOrigin(NSPoint(x: x + 104 + 12, y: y)); content.addSubview(seg)
            stepper.onChange = { [weak self] v in
                self?.settings[keyPath: valuePath] = Double(v)
                self?.renderTimeline()
            }
            seg.onChange = { [weak self] idx in
                self?.settings[keyPath: unitPath] = TimeUnit(rawValue: idx) ?? .min
                self?.renderTimeline()
            }
            return (stepper, seg)
        }

        // Tick every
        (intervalStepper, intervalSeg) = valueUnitRow("Interval", value: \.intervalValue, unit: \.intervalUnit)
        y += 28 + 24

        // Over a window of — or in perpetuity, ticking to the clock hour forever.
        // The mode segment leads the row; the window controls hide in perpetuity.
        perpetuitySeg = SegControl(items: ["Timed", "Perpetuity"], selected: settings.isPerpetual ? 1 : 0)
        (windowStepper, windowSeg) = valueUnitRow("Window", value: \.windowValue, unit: \.windowUnit,
                                                  x: padX + perpetuitySeg.frame.width + 12)
        perpetuitySeg.setFrameOrigin(NSPoint(x: padX, y: y))
        content.addSubview(perpetuitySeg)
        perpetuitySeg.onChange = { [weak self] idx in
            guard let self else { return }
            self.settings.isPerpetual = idx == 1
            self.windowStepper.isHidden = self.settings.isPerpetual
            self.windowSeg.isHidden = self.settings.isPerpetual
            self.renderTimeline()
        }
        windowStepper.isHidden = settings.isPerpetual
        windowSeg.isHidden = settings.isPerpetual
        y += 28 + 12

        // Centerpiece timeline
        let cardH = TimelineCard.height(forWidth: contentW)
        timelineCard = TimelineCard(frame: NSRect(x: padX, y: y, width: contentW, height: cardH))
        content.addSubview(timelineCard)
        y += cardH + 16

        // Tick sound
        let cap3 = capLabel("Counter sound")
        cap3.setFrameOrigin(NSPoint(x: padX, y: y)); content.addSubview(cap3)
        y += 16 + 7
        let audition: (String) -> Void = { [weak self] name in self?.play(name, times: 1, gap: 0) }
        soundPopup = SoundPopupControl(sounds: Self.availableSounds(), selected: settings.sound)
        soundPopup.setFrameOrigin(NSPoint(x: padX, y: y))
        soundPopup.onCommit = { [weak self] name in
            guard let self else { return }
            self.settings.sound = name
            audition(name)  // confirm the pick
        }
        soundPopup.onAudition = audition
        content.addSubview(soundPopup)
        let preview = PreviewButton()
        preview.setFrameOrigin(NSPoint(x: padX + 176 + 12, y: y))
        preview.onClick = { [weak self] in
            guard let self else { return }
            audition(self.settings.sound)
        }
        content.addSubview(preview)
        y += 28 + 24

        // Tick volume (global — scales every Peal sound, live)
        let cap4 = capLabel("Tick volume")
        cap4.setFrameOrigin(NSPoint(x: padX, y: y)); content.addSubview(cap4)
        y += 16 + 7
        panelVolumeSlider = VolumeSlider(value: settings.volume, width: 216)
        panelVolumeSlider.setFrameOrigin(NSPoint(x: padX, y: y))
        panelVolumeSlider.onChange = { [weak self] v in self?.setTickVolume(v) }
        panelVolumeSlider.onCommit = { [weak self] in self?.auditionVolume() }
        content.addSubview(panelVolumeSlider)
        y += 28 + 22

        // Footer: hairline, Now / At-a-time segment, primary button
        let hairline = FlippedView(frame: NSRect(x: padX, y: y, width: contentW, height: 1))
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.line.cgColor
        content.addSubview(hairline)
        y += 1 + 18

        whenSeg = SegControl(items: ["Start now", "At a time"], selected: 0)
        whenSeg.setFrameOrigin(NSPoint(x: padX, y: y + 2)); content.addSubview(whenSeg)
        whenSeg.onChange = { [weak self] idx in
            guard let self else { return }
            self.startPicker.isHidden = idx == 0
            self.goButton.title = idx == 0 ? "Start timer" : "Schedule timer"
        }
        startPicker = NSDatePicker()
        startPicker.datePickerStyle = .textFieldAndStepper
        startPicker.datePickerElements = .hourMinute
        startPicker.dateValue = Date().roundedUpToMinute
        startPicker.target = self
        startPicker.action = #selector(startPickerEdited)
        startPicker.sizeToFit()
        startPicker.setFrameOrigin(NSPoint(x: padX + whenSeg.frame.width + 14,
                                           y: y + 15 - startPicker.frame.height / 2))
        startPicker.isHidden = true
        content.addSubview(startPicker)

        goButton = GoButton(title: "Start timer")
        goButton.rightAnchorX = padX + contentW
        goButton.setFrameOrigin(NSPoint(x: padX + contentW - goButton.frame.width, y: y))
        goButton.onClick = { [weak self] in
            guard let self else { return }
            if self.whenSeg.selected == 0 { self.addTimer(startingAt: Date(), perpetual: self.settings.isPerpetual) }
            else { self.scheduleStart() }
        }
        content.addSubview(goButton)
        y += 32 + 24

        let size = NSSize(width: contentW + padX * 2, height: y)
        content.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "New Timer"
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = Theme.panelBG
        panel.contentView = content
        renderTimeline()

        configPanel = panel
    }

    // Re-render the tick-pattern preview and gate the start button on validity.
    func renderTimeline() {
        timelineCard.update(settings.config())
        goButton.isEnabled = timelineCard.isValid
    }

    func scheduleStart() {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: startPicker.dateValue)
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hm.hour
        comps.minute = hm.minute
        guard let date = cal.date(from: comps) else { return }
        addTimer(startingAt: date, perpetual: settings.isPerpetual)
    }
}
