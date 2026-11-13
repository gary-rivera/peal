import AppKit

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
