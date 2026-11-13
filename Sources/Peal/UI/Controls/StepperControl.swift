import AppKit

// ± stepper number control (.num in the mockup): 104×28, −/+ zones flanking the value.
final class StepperControl: FlippedView {
    var value: Int { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?
    private var hoverZone = -1
    private var pressZone = -1

    init(value: Int) {
        self.value = value
        super.init(frame: NSRect(x: 0, y: 0, width: 104, height: Theme.fieldHeight))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var hoverTrackingOptions: NSTrackingArea.Options? { .hover }
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
        let clip = NSBezierPath(roundedRect: r, radius: Theme.fieldRadius)
        clip.addClip()
        Theme.fieldBG.setFill(); r.fill()
        let zones = [NSRect(x: 0, y: 0, width: 30, height: r.height),
                     NSRect(x: r.width - 30, y: 0, width: 30, height: r.height)]
        for (i, zr) in zones.enumerated() {
            if pressZone == i {
                Theme.controlBG.setFill(); zr.fill()
            } else if hoverZone == i {
                zr.fillVerticalGradient(radius: 0, top: Theme.stepperZoneHoverTop, bottom: Theme.stepperZoneHoverBottom)
            } else {
                zr.fillVerticalGradient(radius: 0, top: Theme.stepperZoneTop, bottom: Theme.stepperZoneBottom)
            }
            let glyph = i == 0 ? "−" : "+"
            let a: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: Theme.ink]
            NSAttributedString(string: glyph, attributes: a).draw(centeredIn: zr)
        }
        NSAttributedString("\(value)", font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
                           color: .white).draw(centeredIn: r)
        r.strokeFieldBorder()
    }
}
