import AppKit

// Primary start button (.go in the mockup): pink-magenta gradient, disabled = flat gray.
final class GoButton: PressableView {
    var title: String { didSet { sizeToFitTitle(); needsDisplay = true } }
    // When set, the button keeps this right edge as its title changes width.
    var rightAnchorX: CGFloat?

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 32))
        sizeToFitTitle()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func sizeToFitTitle() {
        let w = ceil(NSAttributedString(string: title + "  ▸", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).size().width) + 38
        setFrameSize(NSSize(width: w, height: 32))
        if let ax = rightAnchorX {
            setFrameOrigin(NSPoint(x: ax - w, y: frame.origin.y))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var r = bounds
        if isPressed { r.origin.y += 1 }
        if isEnabled {
            withShadow(Theme.accentDeep.withAlphaComponent(0.4), blur: 10, offset: NSSize(width: 0, height: -3)) {
                r.fillVerticalGradient(radius: 8, top: Theme.accentDeep, bottom: Theme.magenta)
            }
        } else {
            Theme.buttonDisabled.setFill(); NSBezierPath(roundedRect: r, radius: 8).fill()
        }
        let color: NSColor = isEnabled ? .white : Theme.ink3
        let s = NSMutableAttributedString(title, font: .systemFont(ofSize: 13, weight: .semibold),
                                          color: color)
        s.append(NSAttributedString("  ▸", font: .systemFont(ofSize: 10.5, weight: .semibold), color: color))
        s.draw(centeredIn: r)
    }
}
