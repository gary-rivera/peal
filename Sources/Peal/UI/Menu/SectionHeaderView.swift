import AppKit

// Section header with state dot + live count pill (.rich-header in the mockup).
final class SectionHeaderView: FlippedView {
    private let text: String
    private let dotColor: NSColor
    private let count: Int
    init(_ text: String, dot: NSColor, count: Int) {
        self.text = text
        self.dotColor = dot
        self.count = count
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.menuWidth, height: 25))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 12, width: 6, height: 6)).fill()
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Theme.label2]).draw(at: NSPoint(x: 31, y: 8))
        let pill = NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: Theme.label3])
        let psz = pill.size()
        let pw = max(16, psz.width + 12)
        let pr = NSRect(x: bounds.width - 16 - pw, y: 8, width: pw, height: 15)
        NSColor(white: 1, alpha: 0.06).setFill()
        roundedPath(pr, 7.5).fill()
        pill.draw(centeredIn: pr)
    }
}
