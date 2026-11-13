import AppKit

func roundedPath(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawVerticalGradient(_ rect: NSRect, _ radius: CGFloat, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: top, ending: bottom)?.draw(in: roundedPath(rect, radius), angle: 90)
}

// Draw text centered horizontally and vertically within a rect.
extension NSAttributedString {
    func draw(centeredIn rect: NSRect) {
        let sz = size()
        draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }
}
