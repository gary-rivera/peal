import AppKit
import PealCore

/// The "New Timer" panel: interval and window steppers, Timed/Perpetuity mode,
/// the live timeline preview, sound and volume, and the Start now / At a time flow.
/// Every edit writes straight to the shared settings.
@MainActor
final class ConfigPanelController: NSObject {
    /// Start a timer at the given time; the app validates and closes the panel.
    var onStart: ((_ start: Date, _ perpetual: Bool) -> Void)?
    var onAudition: ((String) -> Void)?
    var onVolumeCommit: (() -> Void)?

    private let settings: SettingsStore
    private let panel: NSPanel

    private let intervalStepper = StepperControl(value: 1)
    private let intervalSeg = SegControl(items: TimeUnit.allCases.map(\.label), selected: 0)
    private let modeSeg = SegControl(items: ["Timed", "Perpetuity"], selected: 0)
    private let windowStepper = StepperControl(value: 1)
    private let windowSeg = SegControl(items: TimeUnit.allCases.map(\.label), selected: 0)
    private let timelineCard: TimelineCard
    private let soundPopup: SoundPopupControl
    private let previewButton = PreviewButton()
    private let volumeSlider = VolumeSlider(value: 1, width: 216)
    private let whenSeg = SegControl(items: ["Start now", "At a time"], selected: 0)
    private let startPicker = NSDatePicker()
    private let goButton = GoButton(title: "Start timer")
    // While false, the picker live-tracks the clock (next whole minute);
    // flips true on manual edit so the user's choice isn't clobbered.
    private var startPickerTouched = false

    private static let contentWidth: CGFloat = 493
    private static let padX: CGFloat = 26

    init(settings: SettingsStore, sounds: [String]) {
        self.settings = settings
        timelineCard = TimelineCard(frame: NSRect(x: 0, y: 0, width: Self.contentWidth,
                                                  height: TimelineCard.height(forWidth: Self.contentWidth)))
        soundPopup = SoundPopupControl(sounds: sounds, selected: settings.current.sound)
        panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        layOut()
        bindControls()
        settings.observe { [weak self] _ in self?.syncFromSettings() }
        syncFromSettings()
    }

    /// The panel when it's on screen, for presenting alerts as a sheet.
    var visibleWindow: NSWindow? { panel.isVisible ? panel : nil }

    func show() {
        whenSeg.selected = 0
        startPicker.isHidden = true
        goButton.title = "Start timer"
        startPickerTouched = false
        startPicker.dateValue = Date().roundedUpToMinute
        syncFromSettings()
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel.orderOut(nil) }

    /// An untouched "Start at" tracks the clock, rounded up to the next minute.
    func refresh(now: Date) {
        if panel.isVisible, !startPickerTouched { startPicker.dateValue = now.roundedUpToMinute }
    }

    // MARK: - Settings ↔ controls

    private func syncFromSettings() {
        let s = settings.current
        intervalStepper.value = max(1, Int(s.intervalValue))
        intervalSeg.selected = s.intervalUnit.rawValue
        windowStepper.value = max(1, Int(s.windowValue))
        windowSeg.selected = s.windowUnit.rawValue
        modeSeg.selected = s.isPerpetual ? 1 : 0
        windowStepper.isHidden = s.isPerpetual
        windowSeg.isHidden = s.isPerpetual
        soundPopup.select(s.sound)
        volumeSlider.value = s.volume
        // Re-render the tick-pattern preview and gate the start button on validity.
        timelineCard.update(s.config())
        goButton.isEnabled = timelineCard.isValid
    }

    private func bindControls() {
        func bind(_ stepper: StepperControl, _ seg: SegControl,
                  value: WritableKeyPath<TimerSettings, Double>, unit: WritableKeyPath<TimerSettings, TimeUnit>) {
            stepper.onChange = { [weak self] v in self?.settings.update { $0[keyPath: value] = Double(v) } }
            seg.onChange = { [weak self] i in
                self?.settings.update { $0[keyPath: unit] = TimeUnit(rawValue: i) ?? .min }
            }
        }
        bind(intervalStepper, intervalSeg, value: \.intervalValue, unit: \.intervalUnit)
        bind(windowStepper, windowSeg, value: \.windowValue, unit: \.windowUnit)
        modeSeg.onChange = { [weak self] i in self?.settings.update { $0.isPerpetual = i == 1 } }

        soundPopup.onCommit = { [weak self] name in
            self?.settings.update { $0.sound = name }
            self?.onAudition?(name)  // confirm the pick
        }
        soundPopup.onAudition = { [weak self] name in self?.onAudition?(name) }
        previewButton.onClick = { [weak self] in
            guard let self else { return }
            onAudition?(settings.current.sound)
        }
        volumeSlider.onChange = { [weak self] v in self?.settings.update { $0.volume = v } }
        volumeSlider.onCommit = { [weak self] in self?.onVolumeCommit?() }

        whenSeg.onChange = { [weak self] i in
            guard let self else { return }
            startPicker.isHidden = i == 0
            goButton.title = i == 0 ? "Start timer" : "Schedule timer"
        }
        startPicker.target = self
        startPicker.action = #selector(startPickerEdited)
        goButton.onClick = { [weak self] in
            guard let self else { return }
            let start = whenSeg.selected == 0 ? Date() : scheduledStart()
            onStart?(start, settings.current.isPerpetual)
        }
    }

    @objc private func startPickerEdited() { startPickerTouched = true }

    /// Today at the picker's hour and minute.
    private func scheduledStart() -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: startPicker.dateValue)
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hm.hour
        comps.minute = hm.minute
        return cal.date(from: comps) ?? startPicker.dateValue
    }

    // MARK: - Layout

    private func layOut() {
        let padX = Self.padX, contentW = Self.contentWidth
        let content = FlippedView()
        var y: CGFloat = 22

        func place(_ view: NSView, x: CGFloat = padX, dy: CGFloat = 0) {
            view.setFrameOrigin(NSPoint(x: x, y: y + dy))
            content.addSubview(view)
        }
        func caption(_ text: String) {
            let label = NSTextField(labelWithAttributedString: Theme.caption(text))
            label.sizeToFit()
            place(label)
            y += 16 + 7
        }

        // Tick every
        caption("Interval")
        place(intervalStepper)
        place(intervalSeg, x: padX + intervalStepper.frame.width + 12)
        y += 28 + 24

        // Over a window of — or in perpetuity, ticking to the clock hour forever.
        // The mode segment leads the row; the window controls hide in perpetuity.
        caption("Window")
        place(modeSeg)
        let windowX = padX + modeSeg.frame.width + 12
        place(windowStepper, x: windowX)
        place(windowSeg, x: windowX + windowStepper.frame.width + 12)
        y += 28 + 12

        // Centerpiece timeline
        place(timelineCard)
        y += timelineCard.frame.height + 16

        caption("Counter sound")
        place(soundPopup)
        place(previewButton, x: padX + soundPopup.frame.width + 12)
        y += 28 + 24

        // Tick volume (global — scales every Peal sound, live)
        caption("Tick volume")
        place(volumeSlider)
        y += 28 + 22

        // Footer: hairline, Now / At-a-time segment, primary button
        let hairline = FlippedView(frame: NSRect(x: 0, y: 0, width: contentW, height: 1))
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.line.cgColor
        place(hairline)
        y += 1 + 18

        place(whenSeg, dy: 2)
        startPicker.datePickerStyle = .textFieldAndStepper
        startPicker.datePickerElements = .hourMinute
        startPicker.sizeToFit()
        startPicker.isHidden = true
        place(startPicker, x: padX + whenSeg.frame.width + 14, dy: 15 - startPicker.frame.height / 2)
        goButton.rightAnchorX = padX + contentW
        place(goButton, x: padX + contentW - goButton.frame.width)
        y += 32 + 24

        let size = NSSize(width: contentW + padX * 2, height: y)
        content.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.title = "New Timer"
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = Theme.panelBG
        panel.contentView = content
    }
}
