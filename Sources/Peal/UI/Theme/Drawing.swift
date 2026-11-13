import AppKit

extension NSBezierPath {
    convenience init(roundedRect rect: NSRect, radius: CGFloat) {
        self.init(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

extension NSRect {
    /// Fills this rect, with rounded corners, using a top-to-bottom gradient.
    func fillVerticalGradient(radius: CGFloat, top: NSColor, bottom: NSColor) {
        NSGradient(starting: top, ending: bottom)?.draw(in: NSBezierPath(roundedRect: self, radius: radius), angle: 90)
    }

    /// The hairline border shared by the panel's input fields.
    func strokeFieldBorder(_ color: NSColor = Theme.fieldBorder) {
        color.setStroke()
        NSBezierPath(roundedRect: insetBy(dx: 0.25, dy: 0.25), radius: Theme.fieldRadius).stroke()
    }
}

/// Runs `draw` with a drop shadow (or glow, at zero offset), then restores
/// the graphics state so the shadow doesn't leak into later drawing.
func withShadow(_ color: NSColor, blur: CGFloat, offset: NSSize = .zero, _ draw: () -> Void) {
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.current?.restoreGraphicsState()
}

extension NSAttributedString {
    convenience init(_ string: String, font: NSFont, color: NSColor) {
        self.init(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    /// Draws the text centered horizontally and vertically within `rect`.
    func draw(centeredIn rect: NSRect) {
        let sz = size()
        draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }

    /// Draws the text centered on a capsule filling `rect`, with an optional hairline.
    func drawPill(in rect: NSRect, fill: NSColor, stroke: NSColor? = nil) {
        let radius = rect.height / 2
        fill.setFill()
        NSBezierPath(roundedRect: rect, radius: radius).fill()
        if let stroke {
            stroke.setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), radius: radius).stroke()
        }
        draw(centeredIn: rect)
    }
}

extension NSTrackingArea.Options {
    /// Enter/exit plus move events, whether or not the app is active.
    static let hover: Self = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
}
