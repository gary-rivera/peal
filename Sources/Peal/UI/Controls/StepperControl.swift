import AppKit

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
