import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let unitNames = ["sec", "min", "hr"]
    static let unitSeconds: [Double] = [1, 60, 3600]

    var statusItem: NSStatusItem!
    var timers: [TickTimer] = []
    var rowViews: [TimerRowView] = []
    var footbar: FootbarView?
    var menuSignature = ""
    // Hold references so sounds aren't deallocated mid-playback.
    var sounds: [NSSound] = []

    // Defaults for the next timer (persisted).
    var intervalValue: Double = UserDefaults.standard.object(forKey: "intervalValue") as? Double ?? 10
    var intervalUnitIndex: Int = UserDefaults.standard.object(forKey: "intervalUnit") as? Int ?? 1
    var intervalSeconds: Double { intervalValue * Self.unitSeconds[intervalUnitIndex] }
    var windowValue: Double = UserDefaults.standard.object(forKey: "windowValue") as? Double
        ?? UserDefaults.standard.object(forKey: "windowMinutes") as? Double ?? 45
    var windowUnitIndex: Int = UserDefaults.standard.object(forKey: "windowUnit") as? Int ?? 1
    var windowSeconds: Double { windowValue * Self.unitSeconds[windowUnitIndex] }
    var tickSound: String = UserDefaults.standard.string(forKey: "tickSound") ?? "Tink"
    var perpetuity: Bool = UserDefaults.standard.bool(forKey: "perpetuity")
    // Global multiplier over every play() call's base volume (1 = full).
    var tickVolume: Double = UserDefaults.standard.object(forKey: "tickVolume") as? Double ?? 1

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
        timers.map { $0.isActive ? "a" : $0.isScheduled ? "u" : "f" }.joined()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = Theme.menuWidth
        menu.addItem(makeItem("Start timer", #selector(openConfig), ","))
        menu.addItem(makeItem("Start in perpetuity", #selector(startPerpetuity), "p"))
        menu.addItem(makeItem("Play sample ticks", #selector(testTicks), "t"))
        let volumeRow = VolumeSlider(title: "Tick volume", value: tickVolume,
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
                    guard !timer.isStopped else { return }
                    timer.stoppedAt = Date()
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
            addSection("Ongoing", dot: Theme.sysGreen, timers.filter { $0.isActive })
            addSection("Upcoming", dot: Theme.sysOrange, timers.filter { $0.isScheduled })
            addSection("Finished", dot: Theme.sysGray, timers.filter { $0.isStopped })
            let foot = FootbarView()
            foot.onStopAll = { [weak self] in self?.stopAllTimers() }
            foot.stopEnabled = timers.contains { $0.isActive }
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

    // 11:30:01 → 11:31; 11:30:00 stays 11:30.
    func ceilToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
    }

    func advance(_ t: TickTimer) {
        guard !t.isStopped else { return }
        let elapsed = Date().timeIntervalSince(t.start)
        guard elapsed >= 0 else { return }
        if !t.startAnnounced {
            t.startAnnounced = true
            play("Pop", times: 1, gap: 0)
        }
        // Window end: finish the timer — the Glass chime is the stop signal.
        if t.windowSeconds > 0, elapsed >= t.windowSeconds {
            t.stoppedAt = t.start.addingTimeInterval(t.windowSeconds)
            play("Glass", times: 2, gap: 0.6)
            return
        }
        let mark = t.isPerpetual ? TickTimer.hourMark(at: Date(), interval: t.intervalSeconds)
                                 : Int(elapsed / t.intervalSeconds)
        if mark > t.lastMark {
            t.lastMark = mark
            play(t.sound, times: mark, gap: 0.2)
        } else if mark < t.lastMark {
            // Top of the hour (perpetuity only — window marks never decrease):
            // a Submarine bong marks the reset, then the count restarts at 1.
            t.lastMark = mark
            play("Submarine", times: 1, gap: 0)
        }
    }

    func update() {
        for t in timers { advance(t) }

        // A timer changed section (upcoming → ongoing → finished): regroup.
        if sectionSignature() != menuSignature { rebuildMenu() }

        let anyActive = timers.contains { $0.isActive }
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
            startPicker.dateValue = ceilToMinute(Date())
        }
    }

    @objc func startPickerEdited() { startPickerTouched = true }

    func statusTitle() -> String {
        let extras = timers.count > 1 ? " +\(timers.count - 1)" : ""
        if let t = timers.filter({ $0.isActive }).min(by: { $0.start < $1.start }) {
            let text = t.totalMarks > 0 ? "\(t.marksElapsed)/\(t.totalMarks)" : clock(Int(t.elapsed))
            return text + extras
        }
        if let next = timers.filter({ $0.isScheduled }).min(by: { $0.start < $1.start }) {
            return "in " + clock(Int((-next.elapsed).rounded(.up))) + extras
        }
        return timers.isEmpty ? "" : "✓"
    }

    func validationError(startingAt start: Date, perpetual: Bool) -> String? {
        // Perpetuity never elapses; only the interval needs to fit the hour.
        if perpetual {
            let marks = TickTimer.marksPerHour(interval: intervalSeconds)
            if marks == 0 {
                return "The interval is an hour or longer — no ticks would play. Shorten the interval."
            }
            if marks > 9 {
                return "Each hour fits \(marks) tick marks — the most Peal supports is 9. Lengthen the interval."
            }
            return nil
        }
        // A past start is fine while its window is still in progress — the timer
        // backdates and resumes at the next interval mark. Only reject once the
        // whole window has already elapsed.
        if Date().timeIntervalSince(start) >= windowSeconds {
            return "That start time's window has already fully elapsed. Pick a later time."
        }
        let marks = Int(windowSeconds / intervalSeconds)
        if marks > 9 {
            return "This window fits \(marks) tick marks — the most Peal supports is 9. Lengthen the interval or shorten the window."
        }
        return nil
    }

    func addTimer(startingAt start: Date, perpetual: Bool) {
        if let message = validationError(startingAt: start, perpetual: perpetual) {
            let alert = NSAlert()
            alert.messageText = "Can't start timer"
            alert.informativeText = message
            alert.alertStyle = .warning
            if let panel = configPanel, panel.isVisible {
                alert.beginSheetModal(for: panel)
            } else {
                alert.runModal()
            }
            return
        }
        timers.append(TickTimer(start: start,
                                intervalSeconds: intervalSeconds,
                                windowSeconds: perpetual ? 0 : windowSeconds,
                                sound: tickSound,
                                isPerpetual: perpetual))
        timers.sort { $0.start < $1.start }
        rebuildMenu()
        update()
        configPanel?.orderOut(nil)
    }

    // Menu shortcut: an endless clock-anchored timer with the current interval
    // and sound, no config panel — and no change to the panel's saved default.
    @objc func startPerpetuity() { addTimer(startingAt: Date(), perpetual: true) }

    @objc func stopAllTimers() {
        let now = Date()
        for t in timers where t.isActive { t.stoppedAt = now }
        update()
    }

    @objc func testTicks() { play(tickSound, times: 3, gap: 0.2) }

    // One knob, two sliders: persist and keep menu + panel in step.
    func setTickVolume(_ v: Double) {
        tickVolume = v
        UserDefaults.standard.set(v, forKey: "tickVolume")
        menuVolumeSlider?.value = v
        panelVolumeSlider?.value = v
    }
    // A single tick at the new level, so releasing the slider answers "how loud?".
    func auditionVolume() { play(tickSound, times: 1, gap: 0) }

    static func availableSounds() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds"))?
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted() ?? []
        return names.isEmpty ? ["Tink"] : names
    }

    // The tick-volume slider IS the output level: 100% plays samples at full
    // NSSound volume (which still tops out at the Mac's output volume).
    func play(_ name: String, times: Int, gap: Double) {
        sounds.removeAll { !$0.isPlaying }
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * gap) { [weak self] in
                guard let self else { return }
                if let sound = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true) {
                    sound.volume = Float(self.tickVolume)
                    self.sounds.append(sound)
                    sound.play()
                }
            }
        }
    }

    // MARK: - Configuration panel

    @objc func openConfig() {
        if configPanel == nil { buildConfigPanel() }
        intervalStepper.value = max(1, Int(intervalValue))
        intervalSeg.selected = intervalUnitIndex
        windowStepper.value = max(1, Int(windowValue))
        windowSeg.selected = windowUnitIndex
        perpetuitySeg.selected = perpetuity ? 1 : 0
        windowStepper.isHidden = perpetuity
        windowSeg.isHidden = perpetuity
        soundPopup.select(tickSound)
        panelVolumeSlider.value = tickVolume
        whenSeg.selected = 0
        startPicker.isHidden = true
        goButton.title = "Start timer"
        startPickerTouched = false
        startPicker.dateValue = ceilToMinute(Date())
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

        // One caption + stepper + unit row; changes persist to UserDefaults and re-render the timeline.
        func valueUnitRow(_ caption: String, value: Double, unit: Int,
                          valueKey: String, valuePath: ReferenceWritableKeyPath<AppDelegate, Double>,
                          unitKey: String, unitPath: ReferenceWritableKeyPath<AppDelegate, Int>,
                          x: CGFloat = padX)
            -> (StepperControl, SegControl) {
            let cap = capLabel(caption)
            cap.setFrameOrigin(NSPoint(x: padX, y: y)); content.addSubview(cap)
            y += 16 + 7
            let stepper = StepperControl(value: max(1, Int(value)))
            stepper.setFrameOrigin(NSPoint(x: x, y: y)); content.addSubview(stepper)
            let seg = SegControl(items: Self.unitNames, selected: unit)
            seg.setFrameOrigin(NSPoint(x: x + 104 + 12, y: y)); content.addSubview(seg)
            stepper.onChange = { [weak self] v in
                self?[keyPath: valuePath] = Double(v)
                UserDefaults.standard.set(Double(v), forKey: valueKey)
                self?.renderTimeline()
            }
            seg.onChange = { [weak self] idx in
                self?[keyPath: unitPath] = idx
                UserDefaults.standard.set(idx, forKey: unitKey)
                self?.renderTimeline()
            }
            return (stepper, seg)
        }

        // Tick every
        (intervalStepper, intervalSeg) = valueUnitRow("Interval", value: intervalValue, unit: intervalUnitIndex,
                                                      valueKey: "intervalValue", valuePath: \.intervalValue,
                                                      unitKey: "intervalUnit", unitPath: \.intervalUnitIndex)
        y += 28 + 24

        // Over a window of — or in perpetuity, ticking to the clock hour forever.
        // The mode segment leads the row; the window controls hide in perpetuity.
        perpetuitySeg = SegControl(items: ["Timed", "Perpetuity"], selected: perpetuity ? 1 : 0)
        (windowStepper, windowSeg) = valueUnitRow("Window", value: windowValue, unit: windowUnitIndex,
                                                  valueKey: "windowValue", valuePath: \.windowValue,
                                                  unitKey: "windowUnit", unitPath: \.windowUnitIndex,
                                                  x: padX + perpetuitySeg.frame.width + 12)
        perpetuitySeg.setFrameOrigin(NSPoint(x: padX, y: y))
        content.addSubview(perpetuitySeg)
        perpetuitySeg.onChange = { [weak self] idx in
            guard let self else { return }
            self.perpetuity = idx == 1
            UserDefaults.standard.set(self.perpetuity, forKey: "perpetuity")
            self.windowStepper.isHidden = self.perpetuity
            self.windowSeg.isHidden = self.perpetuity
            self.renderTimeline()
        }
        windowStepper.isHidden = perpetuity
        windowSeg.isHidden = perpetuity
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
        soundPopup = SoundPopupControl(sounds: Self.availableSounds(), selected: tickSound)
        soundPopup.setFrameOrigin(NSPoint(x: padX, y: y))
        soundPopup.onCommit = { [weak self] name in
            guard let self else { return }
            self.tickSound = name
            UserDefaults.standard.set(name, forKey: "tickSound")
            audition(name)  // confirm the pick
        }
        soundPopup.onAudition = audition
        content.addSubview(soundPopup)
        let preview = PreviewButton()
        preview.setFrameOrigin(NSPoint(x: padX + 176 + 12, y: y))
        preview.onClick = { [weak self] in
            guard let self else { return }
            audition(self.tickSound)
        }
        content.addSubview(preview)
        y += 28 + 24

        // Tick volume (global — scales every Peal sound, live)
        let cap4 = capLabel("Tick volume")
        cap4.setFrameOrigin(NSPoint(x: padX, y: y)); content.addSubview(cap4)
        y += 16 + 7
        panelVolumeSlider = VolumeSlider(value: tickVolume, width: 216)
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
        startPicker.dateValue = ceilToMinute(Date())
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
            if self.whenSeg.selected == 0 { self.addTimer(startingAt: Date(), perpetual: self.perpetuity) }
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
        timelineCard.update(interval: intervalSeconds, window: windowSeconds, perpetual: perpetuity)
        goButton.isEnabled = timelineCard.isValid
    }

    func scheduleStart() {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: startPicker.dateValue)
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hm.hour
        comps.minute = hm.minute
        guard let date = cal.date(from: comps) else { return }
        addTimer(startingAt: date, perpetual: perpetuity)
    }
}
