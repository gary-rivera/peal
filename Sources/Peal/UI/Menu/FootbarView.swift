import AppKit

// Persistent Stop all footer (.footbar in the mockup, minus Reset all).
final class FootbarView: FlippedView {
    var onStopAll: (() -> Void)?
    var stopEnabled = true { didSet { needsDisplay = true } }
    private var hovering = false

    init() { super.init(frame: NSRect(x: 0, y: 0, width: Theme.menuWidth, height: 43)) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var buttonRect: NSRect {
        NSRect(x: 13, y: 14, width: bounds.width - 26, height: 25)
    }
    override var hoverTrackingOptions: NSTrackingArea.Options? { .hover }
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
        bg.setFill(); NSBezierPath(roundedRect: buttonRect, radius: 6).fill()
        NSAttributedString("Stop all", font: .systemFont(ofSize: 12, weight: .medium), color: fg)
            .draw(centeredIn: buttonRect)
    }
}
