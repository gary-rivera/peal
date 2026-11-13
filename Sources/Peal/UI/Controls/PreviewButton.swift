import AppKit

// 28×28 ▶ sound preview tile: subtle pink tint.
final class PreviewButton: PressableView {
    init() { super.init(frame: NSRect(x: 0, y: 0, width: Theme.fieldHeight, height: Theme.fieldHeight)) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        Theme.accent.withAlphaComponent(isPressed ? 0.26 : 0.14).setFill()
        NSBezierPath(roundedRect: bounds, radius: 7).fill()
        Theme.accent.withAlphaComponent(0.28).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), radius: 7).stroke()
        NSAttributedString("▶", font: .systemFont(ofSize: 12), color: Theme.accentSoft)
            .draw(centeredIn: bounds)
    }
}
