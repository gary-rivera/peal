// Tickle — menu bar interview timer.
//
// Menu bar shows a metronome icon (filled while a timer is active) plus the
// featured timer's progress as "marks elapsed / total marks" (e.g. "3/9" for
// the 3rd of 9 interval marks in the window), "in 4:32" for the next scheduled
// timer, or "✓" when all timers have finished. "+N" marks additional timers.
//
// Each timer plays N rapid ticks at its Nth interval mark (1st mark = 1 tick,
// 2nd = 2, ...), a "Pop" when a scheduled timer begins, and stops itself with
// a double "Glass" chime when its time window ends.
//
// Perpetuity mode trades the window for the clock: marks anchor to the hour
// (:10, :20, … for a 10m interval), a "Submarine" bong at :00 resets the
// count, and the timer ticks forever until stopped by hand.
//
// Menu (per mockups/menu-redesign.html):
//   Start timer         open the configuration panel.
//   Start in perpetuity  begin an endless clock-anchored timer right away.
//   Play sample ticks   preview a 3-tick burst of the configured sound.
//   Tick volume         slider scaling every Tickle sound; shared with the
//                       config panel's slider and persisted.
//   <timer list>        rich custom rows grouped under section headers with a
//                       state dot and live count pill — Ongoing, Upcoming,
//                       Finished. Each row: colored accent dot, bold primary
//                       line (elapsed of window / start time), a badge
//                       ("3 / 9 ticks", "in 4:32"), a tick-marked progress
//                       track with fired marks lit and a live playhead, and a
//                       dimmed config line. Stop/Reset surface inline on hover.
//   Stop all            persistent footer button. Individual rows keep their
//                       hover Reset for removing a single timer.
//
// Configuration panel (per mockups/config-panel-redesign.html):
//   ± steppers with sec/min/hr unit segments for interval and window, a
//   Timed/Perpetuity mode segment on the window row, a live
//   "Interval time preview" timeline (every mark drawn as an escalating bar
//   stack, red when the window overflows the 9-mark ceiling, with an in-place
//   plain-language fix), a tick sound popup with ▶ preview, a tick volume
//   slider (global, mirrored in the menu), and a unified
//   start flow: a "Start now / At a time" segment feeding one primary button.
//   The button is disabled while the configuration is invalid.
//
// Config values persist across launches (UserDefaults) as defaults for the
// next timer; each launched timer keeps the settings it was started with.
//
// Build:  swiftc -O Tickle.swift -o tickle
// Run:    ./tickle             Quit from the menu, or: pkill tickle

import AppKit
import ObjectiveC

extension NSMenuItem {
    // macOS 26 auto-decorates standard selectors (e.g. terminate: → Quit icon)
    // with symbol images. Tickle's menu is fully custom-drawn, so suppress them
    // by swizzling the image getter to nil (Brent Simmons' technique).
    static func disableIcons() {
        guard let original = class_getInstanceMethod(NSMenuItem.self, #selector(getter: image)),
              let replacement = class_getInstanceMethod(NSMenuItem.self, #selector(returnNilInsteadOfImage))
        else { return }
        method_exchangeImplementations(original, replacement)
    }
    @objc private func returnNilInsteadOfImage() -> NSImage? { nil }
}

class TickTimer {
    let start: Date
    let intervalSeconds: Double
    let windowSeconds: Double
    let sound: String
    // Perpetuity mode: no window — marks anchor to the clock hour (:10, :20, …
    // for a 10m interval), a Submarine bong at :00 resets the count, and the
    // timer runs until stopped by hand.
    let isPerpetual: Bool
    var lastMark: Int
    var startAnnounced: Bool
    var stoppedAt: Date?

    init(start: Date, intervalSeconds: Double, windowSeconds: Double, sound: String,
         isPerpetual: Bool = false) {
        self.start = start
        self.intervalSeconds = intervalSeconds
        self.windowSeconds = windowSeconds
        self.sound = sound
        self.isPerpetual = isPerpetual
        let elapsed = Date().timeIntervalSince(start)
        // A backdated start resumes at the next mark — no catch-up burst.
        lastMark = isPerpetual ? Self.hourMark(at: Date(), interval: intervalSeconds)
                               : max(0, Int(elapsed / intervalSeconds))
        startAnnounced = elapsed >= 0
        // Backdated past its own window: created already finished, no chime.
        if windowSeconds > 0, elapsed >= windowSeconds {
            stoppedAt = start.addingTimeInterval(windowSeconds)
        }
    }

    static func secondsIntoHour(at date: Date) -> Double {
        date.timeIntervalSince(Calendar.current.dateInterval(of: .hour, for: date)!.start)
    }
    static func hourMark(at date: Date, interval: Double) -> Int {
        Int(secondsIntoHour(at: date) / interval)
    }
    // Audible marks per hour: the :00 mark is the reset, not a tick.
    static func marksPerHour(interval: Double) -> Int {
        guard interval > 0, interval < 3600 else { return 0 }
        let m = Int(3600 / interval)
        return 3600.truncatingRemainder(dividingBy: interval) == 0 ? m - 1 : m
    }

    var isStopped: Bool { stoppedAt != nil }
    var elapsed: TimeInterval { (stoppedAt ?? Date()).timeIntervalSince(start) }
    var isActive: Bool { !isStopped && elapsed >= 0 }
    var isScheduled: Bool { !isStopped && elapsed < 0 }
    var isFinished: Bool { isStopped && windowSeconds > 0 && elapsed >= windowSeconds }
    var totalMarks: Int {
        isPerpetual ? Self.marksPerHour(interval: intervalSeconds)
                    : (windowSeconds > 0 ? Int(windowSeconds / intervalSeconds) : 0)
    }
    var marksElapsed: Int {
        isPerpetual ? Self.hourMark(at: stoppedAt ?? Date(), interval: intervalSeconds)
                    : max(0, Int(elapsed / intervalSeconds))
    }
    // Progress along the row's track: window fraction, or position in the hour.
    var progress: Double {
        isPerpetual ? Self.secondsIntoHour(at: stoppedAt ?? Date()) / 3600
                    : (windowSeconds > 0 ? min(1, elapsed / windowSeconds) : 0)
    }
}

// MARK: - Design tokens (mockups/config-panel-redesign.html + menu-redesign.html)

enum Theme {
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: a)
    }
    // panel palette — brand pink-to-magenta ramp over plum-warmed darks
    static let accentSoft = hex(0xff8dc0)  // pink-300: chip text, bell, ▶
    static let accent     = hex(0xf65ca2)  // pink-400: ticks, tints
    static let accentDeep = hex(0xd62598)  // magenta-500: selection, CTA top
    static let magenta    = hex(0xa31c7f)  // magenta-600: CTA bottom
    static let red        = hex(0xff5f52)
    static let redSoft    = hex(0xff8f86)
    static let ink   = NSColor(white: 1, alpha: 0.92)
    static let ink2  = NSColor(white: 1, alpha: 0.60)
    static let ink3  = NSColor(white: 1, alpha: 0.38)
    static let line  = NSColor(white: 1, alpha: 0.09)
    static let line2 = NSColor(white: 1, alpha: 0.14)
    static let panelBG  = hex(0x282229)
    static let fieldBG  = hex(0x201a22)
    static let cardBG   = hex(0x261f28)
    static let cardBad  = hex(0x281c22)
    // menu palette
    static let sysGreen  = hex(0x30d158)
    static let sysOrange = hex(0xff9f0a)
    static let sysRed    = hex(0xff453a)
    static let sysGray   = hex(0x98989d)
    static let label  = hex(0xf5f5f7)
    static let label2 = NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.62)
    static let label3 = NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.34)

    static func caption(_ text: String) -> NSAttributedString {
        // Sentence-case field label, macOS style: quiet so the controls lead.
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: ink2,
        ])
    }
}

// A view that lays out top-down. Subclasses opt into hover tracking by
// returning the tracking options they need.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var hoverTrackingOptions: NSTrackingArea.Options? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard let options = hoverTrackingOptions else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }
}

func roundedPath(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawVerticalGradient(_ rect: NSRect, _ radius: CGFloat, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: top, ending: bottom)?.draw(in: roundedPath(rect, radius), angle: 90)
}

// h:mm:ss for an hour or more, else m:ss.
func clock(_ seconds: Int) -> String {
    seconds >= 3600
        ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

// Compact duration: "45s", "45m", "1h30m".
func shortDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    if s < 3600 { return s % 60 == 0 ? "\(s / 60)m" : "\(s / 60)m\(s % 60)s" }
    let h = s / 3600, m = (s % 3600) / 60
    return m == 0 ? "\(h)h" : "\(h)h\(m)m"
}

// Draw text centered horizontally and vertically within a rect.
extension NSAttributedString {
    func draw(centeredIn rect: NSRect) {
        let sz = size()
        draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }
}

// MARK: - Config panel controls

// ± stepper number control (.num in the mockup): 104×28, −/+ zones flanking the value.
final class StepperControl: FlippedView {
    var value: Int { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?
    private var hoverZone = -1
    private var pressZone = -1

    init(value: Int) {
        self.value = value
        super.init(frame: NSRect(x: 0, y: 0, width: 104, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect] }
    private func zone(_ p: NSPoint) -> Int { p.x < 30 ? 0 : (p.x > bounds.width - 30 ? 1 : -1) }
    override func mouseMoved(with e: NSEvent) {
        let z = zone(convert(e.locationInWindow, from: nil))
        if z != hoverZone { hoverZone = z; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) { hoverZone = -1; pressZone = -1; needsDisplay = true }
    override func mouseDown(with e: NSEvent) {
        pressZone = zone(convert(e.locationInWindow, from: nil)); needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) {
        let z = zone(convert(e.locationInWindow, from: nil))
        if z >= 0 && z == pressZone {
            value = max(1, value + (z == 0 ? -1 : 1))
            onChange?(value)
        }
        pressZone = -1; needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let clip = roundedPath(r, 7)
        clip.addClip()
        Theme.fieldBG.setFill(); r.fill()
        let zones = [NSRect(x: 0, y: 0, width: 30, height: r.height),
                     NSRect(x: r.width - 30, y: 0, width: 30, height: r.height)]
        for (i, zr) in zones.enumerated() {
            if pressZone == i {
                Theme.hex(0x2b2530).setFill(); zr.fill()
            } else if hoverZone == i {
                drawVerticalGradient(zr, 0, Theme.hex(0x483f4c), Theme.hex(0x3b3440))
            } else {
                drawVerticalGradient(zr, 0, Theme.hex(0x3a3340), Theme.hex(0x322c37))
            }
            let glyph = i == 0 ? "−" : "+"
            let a: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: Theme.ink]
            NSAttributedString(string: glyph, attributes: a).draw(centeredIn: zr)
        }
        NSAttributedString(string: "\(value)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white]).draw(centeredIn: r)
        NSColor(white: 0, alpha: 0.55).setStroke()
        roundedPath(r.insetBy(dx: 0.25, dy: 0.25), 7).stroke()
    }
}

// macOS-style segmented control (.seg in the mockup).
final class SegControl: FlippedView {
    let items: [String]
    var selected: Int { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?
    private let cellWidths: [CGFloat]

    init(items: [String], selected: Int) {
        self.items = items
        self.selected = selected
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        cellWidths = items.map { item in
            ceil(NSAttributedString(string: item, attributes: [.font: font]).size().width) + 24
        }
        let w = cellWidths.reduce(0, +) + 4
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with e: NSEvent) {
        var x: CGFloat = 2
        let p = convert(e.locationInWindow, from: nil)
        for (i, w) in cellWidths.enumerated() {
            if p.x >= x && p.x < x + w {
                if selected != i { selected = i; onChange?(i) }
                return
            }
            x += w
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        Theme.fieldBG.setFill(); roundedPath(r, 7).fill()
        var x: CGFloat = 2
        for (i, w) in cellWidths.enumerated() {
            let cell = NSRect(x: x, y: 2, width: w, height: r.height - 4)
            if i == selected {
                Theme.accentDeep.setFill()
                roundedPath(cell, 5).fill()
            }
            let font = NSFont.systemFont(ofSize: 12.5, weight: i == selected ? .semibold : .medium)
            let color: NSColor = i == selected ? .white : Theme.ink2
            NSAttributedString(string: items[i], attributes: [.font: font, .foregroundColor: color])
                .draw(centeredIn: cell)
            x += w
        }
        NSColor(white: 0, alpha: 0.55).setStroke()
        roundedPath(r.insetBy(dx: 0.25, dy: 0.25), 7).stroke()
    }
}

// THE CENTERPIECE — live tick-pattern timeline (.timeline-card in the mockup).
final class TimelineCard: FlippedView {
    var intervalSeconds: Double = 6
    var windowSeconds: Double = 60
    var isPerpetual = false
    var isValid: Bool {
        let m = marks
        return m > 0 && m <= 9
    }
    private var marks: Int {
        isPerpetual ? TickTimer.marksPerHour(interval: intervalSeconds)
                    : (intervalSeconds > 0 ? Int(windowSeconds / intervalSeconds) : 0)
    }
    // Perpetuity previews one clock hour of the endless pattern.
    private var effectiveWindow: Double { isPerpetual ? 3600 : windowSeconds }

    // The note sentence carries the explanation; the legend is one quiet line.
    private static let legendTexts = [
        "Each mark is one interval — bar height = ticks played; the bell ends the window.",
        "Each mark is one interval — bar height = ticks played; the count resets on the hour.",
    ]
    private var legendText: String { Self.legendTexts[isPerpetual ? 1 : 0] }

    // End-cap glyph as a brand-tinted SF Symbol (emoji can't take the accent color).
    private static func tintedSymbol(_ name: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        else { return nil }
        return NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            Theme.accentSoft.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
    private static let bellImage = tintedSymbol("bell.fill")          // window's end chime
    private static let repeatImage = tintedSymbol("arrow.clockwise")  // perpetuity's hourly reset

    static func height(forWidth width: CGFloat) -> CGFloat {
        // 18 pad + 16 head + 22 gap + 74 track + 26 numbers + 34 note + legend + 14 pad
        let lines = legendLineCount(width: width)
        return 18 + 16 + 22 + 74 + 26 + 34 + 2 + CGFloat(lines) * 15 + 14
    }
    private static func legendLineCount(width: CGFloat) -> Int {
        // Size for whichever legend variant wraps to more lines.
        let font = NSFont.systemFont(ofSize: 11)
        return legendTexts.map { text in
            let w = ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
            return max(1, Int(ceil(w / (width - 36))))
        }.max()!
    }

    func update(interval: Double, window: Double, perpetual: Bool) {
        intervalSeconds = interval
        windowSeconds = window
        isPerpetual = perpetual
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let m = marks
        let over = m > 9
        let bad = over || m == 0

        // card body + tint + border
        let card = roundedPath(r.insetBy(dx: 0.5, dy: 0.5), 14)
        (bad ? Theme.cardBad : Theme.cardBG).setFill(); card.fill()
        NSGraphicsContext.current?.saveGraphicsState()
        card.addClip()
        let tint = bad ? Theme.red.withAlphaComponent(0.14) : Theme.accent.withAlphaComponent(0.10)
        NSGradient(starting: tint, ending: .clear)?.draw(
            fromCenter: NSPoint(x: 0, y: 0), radius: 0,
            toCenter: NSPoint(x: 0, y: 0), radius: r.width * 0.72, options: [])
        NSGraphicsContext.current?.restoreGraphicsState()
        (bad ? Theme.red.withAlphaComponent(0.45) : Theme.line2).setStroke()
        card.lineWidth = 1
        card.stroke()

        // header: quiet label left, marks-count chip right
        Theme.caption("Interval time preview").draw(at: NSPoint(x: 18, y: 16))
        let countText: String
        if over { countText = "\(m) marks — max 9" }
        else if m == 0 { countText = "no marks" }
        else { countText = "\(m) mark" + (m == 1 ? "" : "s") }
        let count = NSAttributedString(string: countText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: bad ? Theme.redSoft : Theme.accentSoft])
        let csz = count.size()
        let pill = NSRect(x: r.width - 18 - csz.width - 18, y: 15,
                          width: csz.width + 18, height: 19)
        let pillTint = bad ? Theme.red : Theme.accent
        pillTint.withAlphaComponent(0.14).setFill()
        roundedPath(pill, 9.5).fill()
        pillTint.withAlphaComponent(0.28).setStroke()
        roundedPath(pill.insetBy(dx: 0.5, dy: 0.5), 9.5).stroke()
        count.draw(centeredIn: pill)

        // track
        let x0 = 18.0 + 6, x1 = r.width - 18 - 6
        let baseY = 18 + 16 + 22 + 74.0
        Theme.line2.setFill()
        NSRect(x: x0, y: baseY - 2, width: x1 - x0, height: 2).fill()
        NSRect(x: x0, y: baseY - 9, width: 2, height: 16).fill()   // start cap
        NSRect(x: x1 - 2, y: baseY - 9, width: 2, height: 16).fill() // end cap

        // marks: stem + escalating bar stack + number
        if m > 0 {
            let shown = min(m, 12)
            let numFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            for i in 1...shown {
                let frac = min(1, Double(i) * intervalSeconds / effectiveWindow)
                let cx = x0 + (x1 - x0) * CGFloat(frac)
                Theme.line2.setFill()
                NSRect(x: cx - 1, y: baseY - 2 - 8, width: 2, height: 8).fill()
                let bars = i <= 9 ? i : 1
                let color = i <= 9 ? Theme.accent : Theme.red
                NSGraphicsContext.current?.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = color.withAlphaComponent(0.45)
                glow.shadowBlurRadius = 6
                glow.set()
                var by = baseY - 2 - 8 - 6 - 5
                for _ in 0..<bars {
                    color.setFill()
                    roundedPath(NSRect(x: cx - 6, y: by, width: 12, height: 5), 2).fill()
                    by -= 7
                }
                NSGraphicsContext.current?.restoreGraphicsState()
                let no = NSAttributedString(string: "\(i)", attributes: [
                    .font: numFont, .foregroundColor: Theme.ink3])
                let nsz = no.size()
                no.draw(at: NSPoint(x: cx - nsz.width / 2, y: baseY + 6))
            }
        }
        // end cap: the window's chime bell, or perpetuity's hourly reset arrow
        if let glyph = isPerpetual ? Self.repeatImage : Self.bellImage {
            let gsz = glyph.size
            glyph.draw(in: NSRect(x: x1 - gsz.width / 2, y: baseY - 4 - gsz.height,
                                  width: gsz.width, height: gsz.height),
                       from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }

        // note
        var segments: [(String, Bool)]
        let baseColor: NSColor, boldColor: NSColor
        if over {
            baseColor = Theme.redSoft; boldColor = Theme.ink
            segments = [(isPerpetual ? "Each hour fits " : "This window fits ", false),
                        ("\(m) marks", true),
                        (" — Tickle plays at most 9. Lengthen the interval", false),
                        (isPerpetual ? "." : " or shorten the window.", false)]
        } else if m == 0 {
            baseColor = Theme.redSoft; boldColor = Theme.ink
            segments = [(isPerpetual
                ? "The interval is an hour or longer — no ticks would play."
                : "The interval is longer than the window — no ticks would play.", false)]
        } else if isPerpetual {
            baseColor = Theme.ink2; boldColor = Theme.ink
            segments = [("A tick every ", false), (shortDuration(intervalSeconds), true),
                        (" past the hour: bursts grow ", false), ("1 → \(m)", true),
                        (", resetting with a bong each hour, forever.", false)]
        } else {
            baseColor = Theme.ink2; boldColor = Theme.ink
            segments = [("A tick every ", false), (shortDuration(intervalSeconds), true),
                        (" across ", false), (shortDuration(windowSeconds), true),
                        (": bursts grow ", false), ("1 → \(m)", true),
                        (", then a double chime.", false)]
        }
        let note = NSMutableAttributedString()
        for (text, bold) in segments {
            note.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: bold ? .semibold : .regular),
                .foregroundColor: bold ? boldColor : baseColor]))
        }
        let noteY = baseY + 26
        note.draw(in: NSRect(x: 18, y: noteY, width: r.width - 36, height: 34))

        // legend: one quiet line under the note
        let legendLines = Self.legendLineCount(width: r.width)
        NSAttributedString(string: legendText, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.ink3])
            .draw(in: NSRect(x: 18, y: noteY + 34 + 2,
                             width: r.width - 36, height: CGFloat(legendLines) * 15))
    }
}

// Primary start button (.go in the mockup): pink-magenta gradient, disabled = flat gray.
final class GoButton: FlippedView {
    var title: String { didSet { sizeToFitTitle(); needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    // When set, the button keeps this right edge as its title changes width.
    var rightAnchorX: CGFloat?
    private var pressed = false

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 32))
        sizeToFitTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func sizeToFitTitle() {
        let w = ceil(NSAttributedString(string: title + "  ▸", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).size().width) + 38
        setFrameSize(NSSize(width: w, height: 32))
        if let ax = rightAnchorX {
            setFrameOrigin(NSPoint(x: ax - w, y: frame.origin.y))
        }
    }

    override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        pressed = true; needsDisplay = true
    }
    override func mouseUp(with e: NSEvent) {
        let wasPressed = pressed
        pressed = false; needsDisplay = true
        guard isEnabled, wasPressed,
              bounds.contains(convert(e.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        var r = bounds
        if pressed { r.origin.y += 1 }
        if isEnabled {
            NSGraphicsContext.current?.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = Theme.accentDeep.withAlphaComponent(0.4)
            glow.shadowBlurRadius = 10
            glow.shadowOffset = NSSize(width: 0, height: -3)
            glow.set()
            drawVerticalGradient(r, 8, Theme.accentDeep, Theme.magenta)
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            Theme.hex(0x39323b).setFill(); roundedPath(r, 8).fill()
        }
        let color: NSColor = isEnabled ? .white : Theme.ink3
        let s = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color])
        s.append(NSAttributedString(string: "  ▸", attributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: color]))
        s.draw(centeredIn: r)
    }
}

// 28×28 ▶ sound preview tile (.sound-preview in the mockup): subtle pink tint.
final class PreviewButton: FlippedView {
    var onClick: (() -> Void)?
    private var pressed = false
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28)) }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with e: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        pressed = false; needsDisplay = true
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() }
    }
    override func draw(_ dirtyRect: NSRect) {
        Theme.accent.withAlphaComponent(pressed ? 0.26 : 0.14).setFill()
        roundedPath(bounds, 7).fill()
        Theme.accent.withAlphaComponent(0.28).setStroke()
        roundedPath(bounds.insetBy(dx: 0.5, dy: 0.5), 7).stroke()
        NSAttributedString(string: "▶", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.accentSoft])
            .draw(centeredIn: bounds)
    }
}

// Horizontal volume slider shared by the menu's "Tick volume" row and the
// config panel: accent-filled track, white knob, live percentage readout.
// Scales every sound Tickle plays.
final class VolumeSlider: FlippedView {
    var value: Double { didSet { if value != oldValue { needsDisplay = true } } }  // 0…1
    var onChange: ((Double) -> Void)?  // continuous while dragging
    var onCommit: (() -> Void)?        // on release — audition point
    private let title: NSAttributedString?
    private let insetX: CGFloat

    init(title: String? = nil, value: Double, width: CGFloat, insetX: CGFloat = 0) {
        self.title = title.map {
            NSAttributedString(string: $0, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: Theme.label2])
        }
        self.value = value
        self.insetX = insetX
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    private var trackX0: CGFloat { insetX + (title.map { ceil($0.size().width) + 12 } ?? 0) }
    private var trackX1: CGFloat { bounds.width - insetX - 42 }

    // First drag must register even when the host window is never key (menu rows).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func setValue(from e: NSEvent) {
        let x = convert(e.locationInWindow, from: nil).x
        value = min(1, max(0, (x - trackX0) / (trackX1 - trackX0)))
        onChange?(value)
    }
    override func mouseDown(with e: NSEvent) { setValue(from: e) }
    override func mouseDragged(with e: NSEvent) { setValue(from: e) }
    override func mouseUp(with e: NSEvent) { onCommit?() }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        if let title {
            title.draw(at: NSPoint(x: insetX, y: midY - title.size().height / 2))
        }
        let track = NSRect(x: trackX0, y: midY - 3, width: trackX1 - trackX0, height: 6)
        NSColor(white: 1, alpha: 0.10).setFill()
        roundedPath(track, 3).fill()
        let fillW = track.width * CGFloat(value)
        if fillW > 0 {
            drawVerticalGradient(NSRect(x: track.minX, y: track.minY, width: fillW, height: 6),
                                 3, Theme.accent, Theme.accentDeep)
        }
        NSGraphicsContext.current?.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor(white: 0, alpha: 0.5)
        sh.shadowBlurRadius = 3
        sh.shadowOffset = NSSize(width: 0, height: -1)
        sh.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: track.minX + fillW - 7, y: midY - 7,
                                    width: 14, height: 14)).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        let pct = NSAttributedString(string: "\(Int((value * 100).rounded()))%", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: Theme.label2])
        let psz = pct.size()
        pct.draw(at: NSPoint(x: bounds.width - insetX - psz.width, y: midY - psz.height / 2))
    }
}

// Scrolling list inside the sound popup (mockups sound-popup proposal): plum
// surface, magenta hover row, pink check on the current sound. Hovering a row
// for 0.4s auditions it without committing.
final class SoundListView: FlippedView {
    private let sounds: [String]
    private let selectedIndex: Int
    private var highlighted: Int
    private var scrollOffset: CGFloat = 0
    var onCommit: ((String) -> Void)?
    var onAudition: ((String) -> Void)?
    var onClose: (() -> Void)?
    private var auditionTimer: Timer?

    private static let rowH: CGFloat = 26
    private static let pad: CGFloat = 5
    private static let maxVisible = 9

    init(sounds: [String], selectedIndex: Int, width: CGFloat) {
        self.sounds = sounds
        self.selectedIndex = selectedIndex
        self.highlighted = selectedIndex
        let visible = min(Self.maxVisible, sounds.count)
        super.init(frame: NSRect(x: 0, y: 0, width: width,
                                 height: CGFloat(visible) * Self.rowH + Self.pad * 2))
        // open with the current sound centered
        scrollOffset = clampOffset(
            CGFloat(selectedIndex) * Self.rowH + Self.rowH / 2 - innerHeight / 2)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var innerHeight: CGFloat { bounds.height - Self.pad * 2 }
    private var contentHeight: CGFloat { CGFloat(sounds.count) * Self.rowH }
    private func clampOffset(_ v: CGFloat) -> CGFloat {
        max(0, min(v, contentHeight - innerHeight))
    }
    func cancelAudition() { auditionTimer?.invalidate(); auditionTimer = nil }

    private func rowRect(_ i: Int) -> NSRect {
        NSRect(x: Self.pad, y: Self.pad + CGFloat(i) * Self.rowH - scrollOffset,
               width: bounds.width - Self.pad * 2, height: Self.rowH)
    }
    private func rowAt(_ p: NSPoint) -> Int {
        guard p.y >= Self.pad, p.y <= bounds.height - Self.pad else { return -1 }
        let i = Int((p.y - Self.pad + scrollOffset) / Self.rowH)
        return i >= 0 && i < sounds.count ? i : -1
    }

    // First click must register even though the borderless window is never key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect] }
    override func mouseMoved(with e: NSEvent) {
        setHighlight(rowAt(convert(e.locationInWindow, from: nil)), audition: true)
    }
    override func mouseExited(with e: NSEvent) { setHighlight(-1, audition: false) }
    override func mouseUp(with e: NSEvent) {
        let i = rowAt(convert(e.locationInWindow, from: nil))
        if i >= 0 { onCommit?(sounds[i]) }
    }
    override func scrollWheel(with e: NSEvent) {
        let delta = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 6
        scrollOffset = clampOffset(scrollOffset - delta)
        setHighlight(rowAt(convert(e.locationInWindow, from: nil)), audition: true)
        needsDisplay = true
    }

    private func setHighlight(_ i: Int, audition: Bool) {
        guard i != highlighted else { return }
        highlighted = i
        needsDisplay = true
        cancelAudition()
        guard audition, i >= 0 else { return }
        auditionTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.highlighted == i else { return }
                self.onAudition?(self.sounds[i])
            }
        }
    }
    private func keyboardHighlight(_ i: Int) {
        cancelAudition()
        highlighted = i
        let top = CGFloat(i) * Self.rowH
        if top < scrollOffset { scrollOffset = top }
        else if top + Self.rowH > scrollOffset + innerHeight {
            scrollOffset = top + Self.rowH - innerHeight
        }
        needsDisplay = true
    }

    // Arrow keys, Return/Space to commit, Esc to close, first-letter type-ahead
    // — everything NSPopUpButton used to give for free. Returns true if handled.
    func handleKey(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 125: // down
            let base = highlighted >= 0 ? highlighted : selectedIndex - 1
            keyboardHighlight(min(sounds.count - 1, base + 1))
            return true
        case 126: // up
            let base = highlighted >= 0 ? highlighted : selectedIndex + 1
            keyboardHighlight(max(0, base - 1))
            return true
        case 36, 76, 49: // return, keypad enter, space
            if highlighted >= 0 { onCommit?(sounds[highlighted]) } else { onClose?() }
            return true
        case 53: // esc
            onClose?()
            return true
        default:
            guard let ch = e.charactersIgnoringModifiers?.lowercased().first,
                  ch.isLetter else { return false }
            let n = sounds.count
            for step in 1...n { // cycle to the next name starting with the letter
                let i = (highlighted + step + n) % n
                if sounds[i].lowercased().hasPrefix(String(ch)) {
                    keyboardHighlight(i)
                    break
                }
            }
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let card = roundedPath(r.insetBy(dx: 0.5, dy: 0.5), 9)
        Theme.hex(0x2a2330).setFill(); card.fill()
        Theme.hex(0x443b4a).setStroke(); card.stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        roundedPath(r.insetBy(dx: Self.pad, dy: Self.pad), 5).addClip()
        for i in 0..<sounds.count {
            let rr = rowRect(i)
            guard rr.maxY > 0, rr.minY < r.height else { continue }
            let hovered = i == highlighted
            let isSelected = i == selectedIndex
            if hovered { Theme.accentDeep.setFill(); roundedPath(rr, 5).fill() }
            if isSelected {
                let check = NSAttributedString(string: "✓", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: hovered ? NSColor.white : Theme.accentSoft])
                let csz = check.size()
                check.draw(at: NSPoint(x: rr.minX + 8, y: rr.midY - csz.height / 2))
            }
            let name = NSAttributedString(string: sounds[i], attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
                .foregroundColor: hovered || isSelected ? NSColor.white : Theme.ink])
            let nsz = name.size()
            name.draw(at: NSPoint(x: rr.minX + 8 + 12 + 8, y: rr.midY - nsz.height / 2))
            if hovered {
                let hint = NSAttributedString(string: "▶", attributes: [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor(white: 1, alpha: 0.75)])
                let hsz = hint.size()
                hint.draw(at: NSPoint(x: rr.maxX - 10 - hsz.width, y: rr.midY - hsz.height / 2))
            }
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // overflow fades in place of a scroller
        let menuBG = Theme.hex(0x2a2330)
        let fadeW = r.width - Self.pad * 2
        if scrollOffset > 0.5 {
            NSGradient(starting: menuBG, ending: menuBG.withAlphaComponent(0))?
                .draw(in: NSRect(x: Self.pad, y: Self.pad, width: fadeW, height: 22), angle: 90)
        }
        if scrollOffset < contentHeight - innerHeight - 0.5 {
            NSGradient(starting: menuBG.withAlphaComponent(0), ending: menuBG)?
                .draw(in: NSRect(x: Self.pad, y: r.height - Self.pad - 22,
                                 width: fadeW, height: 22), angle: 90)
        }
    }
}

// Hand-drawn replacement for NSPopUpButton: shares the 28px field style of the
// steppers/segments and opens a SoundListView in a borderless child window.
final class SoundPopupControl: FlippedView {
    private(set) var selectedSound: String
    private let sounds: [String]
    var onCommit: ((String) -> Void)?
    var onAudition: ((String) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    private var menuWindow: NSWindow?
    private var monitors: [Any] = []
    private var resignObserver: Any?
    var isOpen: Bool { menuWindow != nil }

    init(sounds: [String], selected: String) {
        self.sounds = sounds
        self.selectedSound = sounds.contains(selected) ? selected : (sounds.first ?? "Tink")
        super.init(frame: NSRect(x: 0, y: 0, width: 176, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ sound: String) {
        guard sounds.contains(sound) else { return }
        selectedSound = sound
        needsDisplay = true
    }

    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .activeAlways, .inVisibleRect] }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func mouseDown(with e: NSEvent) { isOpen ? closeMenu() : openMenu() }

    private func openMenu() {
        guard menuWindow == nil, let panel = window else { return }
        let list = SoundListView(sounds: sounds,
                                 selectedIndex: sounds.firstIndex(of: selectedSound) ?? 0,
                                 width: frame.width)
        list.onCommit = { [weak self] s in
            guard let self else { return }
            self.select(s)
            self.closeMenu()
            self.onCommit?(s)
        }
        list.onAudition = { [weak self] s in self?.onAudition?(s) }
        list.onClose = { [weak self] in self?.closeMenu() }

        let win = NSWindow(contentRect: NSRect(origin: .zero, size: list.frame.size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isReleasedWhenClosed = false
        win.contentView = list

        // Below the control; flips above it if the screen runs out.
        let ctrl = panel.convertToScreen(convert(bounds, to: nil))
        var oy = ctrl.minY - 4 - list.frame.height
        if let visible = panel.screen?.visibleFrame, oy < visible.minY {
            oy = ctrl.maxY + 4
        }
        win.setFrameOrigin(NSPoint(x: ctrl.minX, y: oy))
        panel.addChildWindow(win, ordered: .above)
        menuWindow = win
        needsDisplay = true

        // Click inside the list or on the control passes through; anywhere else closes.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                    handler: { [weak self] e in
            guard let self else { return e }
            if e.window == self.menuWindow { return e }
            if e.window == self.window,
               self.bounds.contains(self.convert(e.locationInWindow, from: nil)) { return e }
            self.closeMenu()
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self, let list = self.menuWindow?.contentView as? SoundListView else { return e }
            return list.handleKey(e) ? nil : e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                     handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeMenu() }
        }) {
            monitors.append(m)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.closeMenu() } }
    }

    private func closeMenu() {
        guard let win = menuWindow else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        (win.contentView as? SoundListView)?.cancelAudition()
        window?.removeChildWindow(win)
        win.orderOut(nil)
        menuWindow = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        (hovering || isOpen ? Theme.hex(0x332c39) : Theme.hex(0x2b2530)).setFill()
        roundedPath(r, 7).fill()
        (isOpen ? Theme.accent.withAlphaComponent(0.45) : NSColor(white: 0, alpha: 0.55)).setStroke()
        roundedPath(r.insetBy(dx: 0.25, dy: 0.25), 7).stroke()
        let title = NSAttributedString(string: selectedSound, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.ink])
        title.draw(at: NSPoint(x: 11, y: r.midY - title.size().height / 2))
        // double chevron
        Theme.ink3.setStroke()
        let cx = r.width - 14
        for (baseY, apexY) in [(11.5, 8.0), (16.5, 20.0)] {
            let p = NSBezierPath()
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to: NSPoint(x: cx - 3.5, y: baseY))
            p.line(to: NSPoint(x: cx, y: apexY))
            p.line(to: NSPoint(x: cx + 3.5, y: baseY))
            p.stroke()
        }
    }
}

// MARK: - Menu row views (mockups/menu-redesign.html)

private let menuWidth: CGFloat = 334

// Section header with state dot + live count pill (.rich-header in the mockup).
final class SectionHeaderView: FlippedView {
    private let text: String
    private let dotColor: NSColor
    private let count: Int
    init(_ text: String, dot: NSColor, count: Int) {
        self.text = text
        self.dotColor = dot
        self.count = count
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 25))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 12, width: 6, height: 6)).fill()
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Theme.label2]).draw(at: NSPoint(x: 31, y: 8))
        let pill = NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: Theme.label3])
        let psz = pill.size()
        let pw = max(16, psz.width + 12)
        let pr = NSRect(x: bounds.width - 16 - pw, y: 8, width: pw, height: 15)
        NSColor(white: 1, alpha: 0.06).setFill()
        roundedPath(pr, 7.5).fill()
        pill.draw(centeredIn: pr)
    }
}

// Rich timer row (.rich in the mockup): accent dot, two text tiers, tick-marked
// progress track with playhead, and hover-revealed Stop/Reset actions.
final class TimerRowView: FlippedView {
    let timer: TickTimer
    var onStop: (() -> Void)?
    var onReset: (() -> Void)?
    private var hovering = false
    private var hoverAction = -1  // index into actionRects

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private enum State { case on, up, fin, stop }
    private var state: State {
        if timer.isActive { return .on }
        if timer.isScheduled { return .up }
        return timer.isFinished ? .fin : .stop
    }

    // Actions available per state: (glyph, isDanger, handler kind 0=stop 1=reset)
    private var actions: [(String, Bool, Int)] {
        state == .on ? [("■", false, 0), ("✕", true, 1)] : [("✕", true, 1)]
    }

    init(timer: TickTimer) {
        self.timer = timer
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 72))
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() { needsDisplay = true }

    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect] }
    private var actionRects: [NSRect] {
        var rects: [NSRect] = []
        var x = bounds.width - 14 - 23
        for _ in actions {
            rects.append(NSRect(x: x, y: 9, width: 23, height: 23))
            x -= 28
        }
        return rects
    }
    override func mouseEntered(with e: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovering = false; hoverAction = -1; needsDisplay = true }
    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        hovering = true
        let idx = actionRects.firstIndex(where: { $0.contains(p) }) ?? -1
        if idx != hoverAction { hoverAction = idx; needsDisplay = true }
    }
    override func mouseUp(with e: NSEvent) {
        guard hovering else { return }
        let p = convert(e.locationInWindow, from: nil)
        if let idx = actionRects.firstIndex(where: { $0.contains(p) }) {
            enclosingMenuItem?.menu?.cancelTracking()
            if actions[idx].2 == 0 { onStop?() } else { onReset?() }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = timer
        let st = state
        // hover background
        if hovering {
            NSColor(white: 1, alpha: 0.07).setFill()
            roundedPath(bounds.insetBy(dx: 5, dy: 2), 7).fill()
        }

        let accent: NSColor = [State.on: Theme.sysGreen, .up: Theme.sysOrange,
                               .fin: Theme.sysGray, .stop: Theme.sysRed][st]!
        // accent dot (+ soft ring)
        let topCY: CGFloat = 10 + 8.5
        NSColor(white: 1, alpha: 0.04).setFill()
        NSBezierPath(ovalIn: NSRect(x: 15 - 3, y: topCY - 7, width: 14, height: 14)).fill()
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 15, y: topCY - 4, width: 8, height: 8)).fill()
        if st == .fin || st == .stop {
            let glyph = st == .fin ? "✓" : "■"
            let g = NSAttributedString(string: glyph, attributes: [
                .font: NSFont.systemFont(ofSize: st == .fin ? 6 : 5, weight: .black),
                .foregroundColor: Theme.hex(0x0e0f13)])
            let gsz = g.size()
            g.draw(at: NSPoint(x: 19 - gsz.width / 2, y: topCY - gsz.height / 2))
        }

        // title
        let bold = NSFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .semibold)
        let dim: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5), .foregroundColor: Theme.label3]
        let title = NSMutableAttributedString()
        switch st {
        case .on:
            title.append(NSAttributedString(string: clock(Int(t.elapsed)), attributes: [
                .font: bold, .foregroundColor: Theme.label]))
            if t.isPerpetual {
                title.append(NSAttributedString(string: " · perpetuity", attributes: dim))
            } else {
                title.append(NSAttributedString(string: " of ", attributes: dim))
                title.append(NSAttributedString(string: clock(Int(t.windowSeconds)), attributes: [
                    .font: bold, .foregroundColor: Theme.label]))
            }
        case .up:
            title.append(NSAttributedString(string: "Starts \(Self.timeFormatter.string(from: t.start))", attributes: [
                .font: bold, .foregroundColor: Theme.label]))
        case .fin:
            title.append(NSAttributedString(string: "Completed", attributes: [
                .font: bold, .foregroundColor: Theme.label2]))
            title.append(NSAttributedString(string: " · ", attributes: dim))
            title.append(NSAttributedString(string: clock(Int(t.windowSeconds)), attributes: [
                .font: bold, .foregroundColor: Theme.label2]))
        case .stop:
            title.append(NSAttributedString(string: "Stopped at \(clock(Int(t.elapsed)))", attributes: [
                .font: bold, .foregroundColor: Theme.label2]))
        }
        title.draw(at: NSPoint(x: 32, y: 10))

        // badge (hidden while hovering — the actions take its corner)
        if !hovering {
            let badgeText = st == .up
                ? "in \(clock(Int((-t.elapsed).rounded(.up))))"
                : "\(min(t.marksElapsed, t.totalMarks)) / \(t.totalMarks) ticks"
            let b = NSAttributedString(string: badgeText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: Theme.label2])
            let bsz = b.size()
            let br = NSRect(x: bounds.width - 15 - bsz.width - 14, y: 10.5,
                            width: bsz.width + 14, height: 17)
            NSColor(white: 1, alpha: 0.08).setFill()
            roundedPath(br, 8.5).fill()
            b.draw(centeredIn: br)
        } else {
            // hover actions
            for (i, rect) in actionRects.enumerated() {
                let (glyph, danger, _) = actions[i]
                var bg = NSColor(white: 1, alpha: 0.10)
                var fg = Theme.label
                if i == hoverAction {
                    if danger { bg = Theme.sysRed; fg = .white }
                    else { bg = Theme.sysOrange; fg = Theme.hex(0x111111) }
                }
                bg.setFill(); roundedPath(rect, 6).fill()
                NSColor(white: 1, alpha: 0.14).setStroke()
                roundedPath(rect.insetBy(dx: 0.25, dy: 0.25), 6).stroke()
                NSAttributedString(string: glyph, attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: fg])
                    .draw(centeredIn: rect)
            }
        }

        // tick-marked progress track
        let tx0: CGFloat = 32, tx1 = bounds.width - 15
        let trackY: CGFloat = 10 + 17 + 8
        let track = NSRect(x: tx0, y: trackY, width: tx1 - tx0, height: 6)
        NSColor(white: 1, alpha: 0.10).setFill()
        roundedPath(track, 3).fill()
        let frac: CGFloat
        switch st {
        case .on, .stop: frac = t.progress
        case .up: frac = 0
        case .fin: frac = 1
        }
        if frac > 0 {
            let fill = NSRect(x: tx0, y: trackY, width: (tx1 - tx0) * frac, height: 6)
            NSGraphicsContext.current?.saveGraphicsState()
            if st == .on {
                let glow = NSShadow()
                glow.shadowColor = Theme.sysGreen.withAlphaComponent(0.35)
                glow.shadowBlurRadius = 10
                glow.set()
            }
            switch st {
            case .on: drawVerticalGradient(fill, 3, Theme.hex(0x2bbe50), Theme.sysGreen)
            case .up: Theme.sysOrange.setFill(); roundedPath(fill, 3).fill()
            case .fin: NSGradient(starting: Theme.hex(0x5a5a5f), ending: Theme.hex(0x8a8a8f))?
                .draw(in: roundedPath(fill, 3), angle: 0)
            case .stop: NSGradient(starting: Theme.hex(0xc4362c), ending: Theme.sysRed)?
                .draw(in: roundedPath(fill, 3), angle: 0)
            }
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        // interval marks
        if t.totalMarks > 0 {
            for i in 1...t.totalMarks {
                // Perpetuity's track is one clock hour; marks sit at their true times.
                let pos = t.isPerpetual ? Double(i) * t.intervalSeconds / 3600
                                        : Double(i) / Double(t.totalMarks)
                let mx = tx0 + (tx1 - tx0) * CGFloat(pos)
                let fired = i <= t.marksElapsed && st != .up
                if fired {
                    NSGraphicsContext.current?.saveGraphicsState()
                    let glow = NSShadow()
                    glow.shadowColor = NSColor(white: 1, alpha: 0.7)
                    glow.shadowBlurRadius = 5
                    glow.set()
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: NSRect(x: mx - 1.5, y: trackY + 1.5, width: 3, height: 3)).fill()
                    NSGraphicsContext.current?.restoreGraphicsState()
                } else {
                    NSColor(white: 1, alpha: 0.28).setFill()
                    NSBezierPath(ovalIn: NSRect(x: mx - 1, y: trackY + 2, width: 2, height: 2)).fill()
                }
            }
        }
        // live playhead (running rows only)
        if st == .on {
            let hx = tx0 + (tx1 - tx0) * frac
            NSGraphicsContext.current?.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor(white: 0, alpha: 0.5)
            sh.shadowBlurRadius = 3
            sh.shadowOffset = NSSize(width: 0, height: -1)
            sh.set()
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: hx - 7.5, y: trackY + 3 - 7.5, width: 15, height: 15)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: hx - 5.5, y: trackY + 3 - 5.5, width: 11, height: 11)).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // config sub-line
        let subFont = NSFont.systemFont(ofSize: 11.5)
        let subBold = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let subColor = Theme.label2
        let subBoldColor = NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.78)
        var parts: [NSAttributedString] = []
        func plain(_ s: String) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: subFont, .foregroundColor: subColor])
        }
        func boldPair(_ a: String, _ b: String) -> NSAttributedString {
            let s = NSMutableAttributedString(attributedString: plain(a))
            s.append(NSAttributedString(string: b, attributes: [.font: subBold, .foregroundColor: subBoldColor]))
            return s
        }
        switch st {
        case .on:
            parts = [boldPair("Every ", shortDuration(t.intervalSeconds)), boldPair("♪ ", t.sound)]
        case .up:
            parts = [plain("\(shortDuration(t.windowSeconds)) window"),
                     boldPair("Every ", shortDuration(t.intervalSeconds)), boldPair("♪ ", t.sound)]
        case .fin, .stop:
            parts = [boldPair("Every ", shortDuration(t.intervalSeconds))]
        }
        var sx: CGFloat = 32
        let subY = trackY + 6 + 1 + 4
        for (i, part) in parts.enumerated() {
            if i > 0 {
                Theme.label3.setFill()
                NSBezierPath(ovalIn: NSRect(x: sx + 7, y: subY + 7, width: 2, height: 2)).fill()
                sx += 16
            }
            part.draw(at: NSPoint(x: sx, y: subY))
            sx += ceil(part.size().width)
        }
    }
}

// Persistent Stop all footer (.footbar in the mockup, minus Reset all).
final class FootbarView: FlippedView {
    var onStopAll: (() -> Void)?
    var stopEnabled = true { didSet { needsDisplay = true } }
    private var hovering = false

    init() { super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 43)) }
    required init?(coder: NSCoder) { fatalError() }

    private var buttonRect: NSRect {
        NSRect(x: 13, y: 14, width: bounds.width - 26, height: 25)
    }
    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect] }
    override func mouseMoved(with e: NSEvent) {
        let over = buttonRect.contains(convert(e.locationInWindow, from: nil))
        if over != hovering { hovering = over; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        guard stopEnabled, buttonRect.contains(convert(e.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onStopAll?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.55).setFill()
        NSRect(x: 5, y: 6, width: bounds.width - 10, height: 0.5).fill()
        var bg = NSColor(white: 1, alpha: 0.05)
        var fg = Theme.label2
        if stopEnabled && hovering { bg = NSColor(white: 1, alpha: 0.10); fg = Theme.label }
        if !stopEnabled { fg = fg.withAlphaComponent(0.25) }
        bg.setFill(); roundedPath(buttonRect, 6).fill()
        NSAttributedString(string: "Stop all", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: fg])
            .draw(centeredIn: buttonRect)
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let unitNames = ["sec", "min", "hr"]
    static let unitSeconds: [Double] = [1, 60, 3600]

    var statusItem: NSStatusItem!
    var menuIcon: NSImage?
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
        // Feather template image from the bundle (image(forResource:) also picks
        // up the @2x variant); falls back to the SF metronome when run bare.
        if let feather = Bundle.main.image(forResource: "MenuIcon") {
            feather.isTemplate = true
            feather.size = NSSize(width: 18, height: 18)
            menuIcon = feather
        }
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
        menu.minimumWidth = menuWidth
        menu.addItem(makeItem("Start timer", #selector(openConfig), ","))
        menu.addItem(makeItem("Start in perpetuity", #selector(startPerpetuity), "p"))
        menu.addItem(makeItem("Play sample ticks", #selector(testTicks), "t"))
        let volumeRow = VolumeSlider(title: "Tick volume", value: tickVolume,
                                     width: menuWidth, insetX: 16)
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
        menu.addItem(NSMenuItem(title: "Quit Tickle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        if let feather = menuIcon {
            statusItem.button?.image = feather
            statusItem.button?.appearsDisabled = !anyActive
        } else {
            let icon = NSImage(systemSymbolName: anyActive ? "metronome.fill" : "metronome",
                               accessibilityDescription: "Tickle")
            icon?.isTemplate = true
            statusItem.button?.image = icon
        }
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
                return "Each hour fits \(marks) tick marks — the most Tickle supports is 9. Lengthen the interval."
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
            return "This window fits \(marks) tick marks — the most Tickle supports is 9. Lengthen the interval or shorten the window."
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

        // Tick volume (global — scales every Tickle sound, live)
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

MainActor.assumeIsolated {
    NSMenuItem.disableIcons()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    withExtendedLifetime(delegate) { app.run() }  // app.delegate is weak
}
