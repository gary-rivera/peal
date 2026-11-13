import AppKit

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
