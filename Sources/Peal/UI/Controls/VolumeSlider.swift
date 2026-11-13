import AppKit

// Horizontal volume slider shared by the menu's "Tick volume" row and the
// config panel: accent-filled track, white knob, live percentage readout.
// Scales every sound Peal plays.
final class VolumeSlider: FlippedView {
    var value: Double { didSet { if value != oldValue { needsDisplay = true } } }  // 0…1
    var onChange: ((Double) -> Void)?  // continuous while dragging
    var onCommit: (() -> Void)?        // on release — audition point
    private let title: NSAttributedString?
    private let insetX: CGFloat

    init(title: String? = nil, value: Double, width: CGFloat, insetX: CGFloat = 0) {
        self.title = title.map {
            NSAttributedString($0, font: .systemFont(ofSize: 12, weight: .medium), color: Theme.label2)
        }
        self.value = value
        self.insetX = insetX
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Theme.fieldHeight))
    }
    @available(*, unavailable)
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
        NSBezierPath(roundedRect: track, radius: 3).fill()
        let fillW = track.width * CGFloat(value)
        if fillW > 0 {
            NSRect(x: track.minX, y: track.minY, width: fillW, height: 6)
                .fillVerticalGradient(radius: 3, top: Theme.accent, bottom: Theme.accentDeep)
        }
        withShadow(NSColor(white: 0, alpha: 0.5), blur: 3, offset: NSSize(width: 0, height: -1)) {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: track.minX + fillW - 7, y: midY - 7, width: 14, height: 14)).fill()
        }
        let pct = NSAttributedString("\(Int((value * 100).rounded()))%", font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                                     color: Theme.label2)
        let psz = pct.size()
        pct.draw(at: NSPoint(x: bounds.width - insetX - psz.width, y: midY - psz.height / 2))
    }
}
