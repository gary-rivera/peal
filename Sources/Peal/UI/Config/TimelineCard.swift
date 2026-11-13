import AppKit
import PealCore

// THE CENTERPIECE — live tick-pattern timeline (.timeline-card in the mockup).
final class TimelineCard: FlippedView {
    // Perpetuity previews one clock hour of the endless pattern.
    private(set) var config = TimerConfig(interval: 360, mode: .timed(window: 3600), sound: "")
    var isValid: Bool { config.issue == nil }

    // The note sentence carries the explanation; the legend is one quiet line.
    private static let legendTexts = [
        "Each mark is one interval — bar height = ticks played; the bell ends the window.",
        "Each mark is one interval — bar height = ticks played; the count resets on the hour.",
    ]
    private var legendText: String { Self.legendTexts[config.isPerpetual ? 1 : 0] }

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

    func update(_ config: TimerConfig) {
        self.config = config
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let m = config.markCount
        let issue = config.issue
        let bad = issue != nil

        // card body + tint + border
        let card = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), radius: 14)
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
        switch issue {
        case .tooManyMarks: countText = "\(m) marks — max \(TimerConfig.maxMarks)"
        case .noMarks: countText = "no marks"
        default: countText = "\(m) mark" + (m == 1 ? "" : "s")
        }
        let count = NSAttributedString(countText, font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                                       color: bad ? Theme.redSoft : Theme.accentSoft)
        let csz = count.size()
        let pill = NSRect(x: r.width - 18 - csz.width - 18, y: 15,
                          width: csz.width + 18, height: 19)
        let pillTint = bad ? Theme.red : Theme.accent
        count.drawPill(in: pill, fill: pillTint.withAlphaComponent(0.14), stroke: pillTint.withAlphaComponent(0.28))

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
                let cx = x0 + (x1 - x0) * CGFloat(config.position(ofMark: i))
                Theme.line2.setFill()
                NSRect(x: cx - 1, y: baseY - 2 - 8, width: 2, height: 8).fill()
                let withinLimit = i <= TimerConfig.maxMarks
                let bars = withinLimit ? i : 1
                let color = withinLimit ? Theme.accent : Theme.red
                let lowestBarY: CGFloat = baseY - 2 - 8 - 6 - 5
                withShadow(color.withAlphaComponent(0.45), blur: 6) {
                    color.setFill()
                    for bar in 0..<bars {
                        let by = lowestBarY - CGFloat(bar) * 7
                        NSBezierPath(roundedRect: NSRect(x: cx - 6, y: by, width: 12, height: 5), radius: 2).fill()
                    }
                }
                let no = NSAttributedString("\(i)", font: numFont, color: Theme.ink3)
                let nsz = no.size()
                no.draw(at: NSPoint(x: cx - nsz.width / 2, y: baseY + 6))
            }
        }
        // end cap: the window's chime bell, or perpetuity's hourly reset arrow
        if let glyph = config.isPerpetual ? Self.repeatImage : Self.bellImage {
            let gsz = glyph.size
            glyph.draw(in: NSRect(x: x1 - gsz.width / 2, y: baseY - 4 - gsz.height,
                                  width: gsz.width, height: gsz.height),
                       from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }

        // note
        let segments: [ConfigIssue.Phrase]
        let baseColor = bad ? Theme.redSoft : Theme.ink2, boldColor = Theme.ink
        let every = Format.duration(config.interval)
        if let issue {
            segments = issue.phrases(for: config.mode)
        } else if let window = config.window {
            segments = [("A tick every ", false), (every, true),
                        (" across ", false), (Format.duration(window), true),
                        (": bursts grow ", false), ("1 → \(m)", true),
                        (", then a double chime.", false)]
        } else {
            segments = [("A tick every ", false), (every, true),
                        (" past the hour: bursts grow ", false), ("1 → \(m)", true),
                        (", resetting with a bong each hour, forever.", false)]
        }
        let note = NSMutableAttributedString()
        for (text, bold) in segments {
            note.append(NSAttributedString(text, font: .systemFont(ofSize: 12.5, weight: bold ? .semibold : .regular),
                                           color: bold ? boldColor : baseColor))
        }
        let noteY = baseY + 26
        note.draw(in: NSRect(x: 18, y: noteY, width: r.width - 36, height: 34))

        // legend: one quiet line under the note
        let legendLines = Self.legendLineCount(width: r.width)
        NSAttributedString(legendText, font: .systemFont(ofSize: 11), color: Theme.ink3)
            .draw(in: NSRect(x: 18, y: noteY + 34 + 2,
                             width: r.width - 36, height: CGFloat(legendLines) * 15))
    }
}
