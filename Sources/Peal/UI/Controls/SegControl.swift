import AppKit

// macOS-style segmented control (.seg in the mockup).
final class SegControl: FlippedView {
    let items: [String]
    var selected: Int { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?
    private let cellWidths: [CGFloat]

    init(items: [String], selected: Int) {
        self.items = items
        self.selected = selected
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        cellWidths = items.map { item in
            ceil(NSAttributedString(string: item, attributes: [.font: font]).size().width) + 24
        }
        let w = cellWidths.reduce(0, +) + 4
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with e: NSEvent) {
        var x: CGFloat = 2
        let p = convert(e.locationInWindow, from: nil)
        for (i, w) in cellWidths.enumerated() {
            if p.x >= x && p.x < x + w {
                if selected != i { selected = i; onChange?(i) }
                return
            }
            x += w
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        Theme.fieldBG.setFill(); roundedPath(r, 7).fill()
        var x: CGFloat = 2
        for (i, w) in cellWidths.enumerated() {
            let cell = NSRect(x: x, y: 2, width: w, height: r.height - 4)
            if i == selected {
                Theme.accentDeep.setFill()
                roundedPath(cell, 5).fill()
            }
            let font = NSFont.systemFont(ofSize: 12.5, weight: i == selected ? .semibold : .medium)
            let color: NSColor = i == selected ? .white : Theme.ink2
            NSAttributedString(string: items[i], attributes: [.font: font, .foregroundColor: color])
                .draw(centeredIn: cell)
            x += w
        }
        NSColor(white: 0, alpha: 0.55).setStroke()
        roundedPath(r.insetBy(dx: 0.25, dy: 0.25), 7).stroke()
    }
}
