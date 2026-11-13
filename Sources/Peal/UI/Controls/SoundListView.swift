import AppKit

// Scrolling list inside the sound popup (mockups sound-popup proposal): plum
// surface, magenta hover row, pink check on the current sound. Hovering a row
// for 0.4s auditions it without committing.
final class SoundListView: FlippedView {
    private let sounds: [String]
    private let selectedIndex: Int
    private var highlighted: Int
    private var scrollOffset: CGFloat = 0
    var onCommit: ((String) -> Void)?
    var onAudition: ((String) -> Void)?
    var onClose: (() -> Void)?
    private var auditionTimer: Timer?

    private static let rowH: CGFloat = 26
    private static let pad: CGFloat = 5
    private static let maxVisible = 9

    init(sounds: [String], selectedIndex: Int, width: CGFloat) {
        self.sounds = sounds
        self.selectedIndex = selectedIndex
        self.highlighted = selectedIndex
        let visible = min(Self.maxVisible, sounds.count)
        super.init(frame: NSRect(x: 0, y: 0, width: width,
                                 height: CGFloat(visible) * Self.rowH + Self.pad * 2))
        // open with the current sound centered
        scrollOffset = clampOffset(
            CGFloat(selectedIndex) * Self.rowH + Self.rowH / 2 - innerHeight / 2)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var innerHeight: CGFloat { bounds.height - Self.pad * 2 }
    private var contentHeight: CGFloat { CGFloat(sounds.count) * Self.rowH }
    private func clampOffset(_ v: CGFloat) -> CGFloat {
        max(0, min(v, contentHeight - innerHeight))
    }
    func cancelAudition() { auditionTimer?.invalidate(); auditionTimer = nil }

    private func rowRect(_ i: Int) -> NSRect {
        NSRect(x: Self.pad, y: Self.pad + CGFloat(i) * Self.rowH - scrollOffset,
               width: bounds.width - Self.pad * 2, height: Self.rowH)
    }
    private func rowAt(_ p: NSPoint) -> Int {
        guard p.y >= Self.pad, p.y <= bounds.height - Self.pad else { return -1 }
        let i = Int((p.y - Self.pad + scrollOffset) / Self.rowH)
        return i >= 0 && i < sounds.count ? i : -1
    }

    // First click must register even though the borderless window is never key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect] }
    override func mouseMoved(with e: NSEvent) {
        setHighlight(rowAt(convert(e.locationInWindow, from: nil)), audition: true)
    }
    override func mouseExited(with e: NSEvent) { setHighlight(-1, audition: false) }
    override func mouseUp(with e: NSEvent) {
        let i = rowAt(convert(e.locationInWindow, from: nil))
        if i >= 0 { onCommit?(sounds[i]) }
    }
    override func scrollWheel(with e: NSEvent) {
        let delta = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 6
        scrollOffset = clampOffset(scrollOffset - delta)
        setHighlight(rowAt(convert(e.locationInWindow, from: nil)), audition: true)
        needsDisplay = true
    }

    private func setHighlight(_ i: Int, audition: Bool) {
        guard i != highlighted else { return }
        highlighted = i
        needsDisplay = true
        cancelAudition()
        guard audition, i >= 0 else { return }
        auditionTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.highlighted == i else { return }
                self.onAudition?(self.sounds[i])
            }
        }
    }
    private func keyboardHighlight(_ i: Int) {
        cancelAudition()
        highlighted = i
        let top = CGFloat(i) * Self.rowH
        if top < scrollOffset { scrollOffset = top }
        else if top + Self.rowH > scrollOffset + innerHeight {
            scrollOffset = top + Self.rowH - innerHeight
        }
        needsDisplay = true
    }

    // Arrow keys, Return/Space to commit, Esc to close, first-letter type-ahead
    // — everything NSPopUpButton used to give for free. Returns true if handled.
    func handleKey(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 125: // down
            let base = highlighted >= 0 ? highlighted : selectedIndex - 1
            keyboardHighlight(min(sounds.count - 1, base + 1))
            return true
        case 126: // up
            let base = highlighted >= 0 ? highlighted : selectedIndex + 1
            keyboardHighlight(max(0, base - 1))
            return true
        case 36, 76, 49: // return, keypad enter, space
            if highlighted >= 0 { onCommit?(sounds[highlighted]) } else { onClose?() }
            return true
        case 53: // esc
            onClose?()
            return true
        default:
            guard let ch = e.charactersIgnoringModifiers?.lowercased().first,
                  ch.isLetter else { return false }
            let n = sounds.count
            for step in 1...n { // cycle to the next name starting with the letter
                let i = (highlighted + step + n) % n
                if sounds[i].lowercased().hasPrefix(String(ch)) {
                    keyboardHighlight(i)
                    break
                }
            }
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let card = roundedPath(r.insetBy(dx: 0.5, dy: 0.5), 9)
        Theme.hex(0x2a2330).setFill(); card.fill()
        Theme.hex(0x443b4a).setStroke(); card.stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        roundedPath(r.insetBy(dx: Self.pad, dy: Self.pad), 5).addClip()
        for i in 0..<sounds.count {
            let rr = rowRect(i)
            guard rr.maxY > 0, rr.minY < r.height else { continue }
            let hovered = i == highlighted
            let isSelected = i == selectedIndex
            if hovered { Theme.accentDeep.setFill(); roundedPath(rr, 5).fill() }
            if isSelected {
                let check = NSAttributedString(string: "✓", attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: hovered ? NSColor.white : Theme.accentSoft])
                let csz = check.size()
                check.draw(at: NSPoint(x: rr.minX + 8, y: rr.midY - csz.height / 2))
            }
            let name = NSAttributedString(string: sounds[i], attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
                .foregroundColor: hovered || isSelected ? NSColor.white : Theme.ink])
            let nsz = name.size()
            name.draw(at: NSPoint(x: rr.minX + 8 + 12 + 8, y: rr.midY - nsz.height / 2))
            if hovered {
                let hint = NSAttributedString(string: "▶", attributes: [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor(white: 1, alpha: 0.75)])
                let hsz = hint.size()
                hint.draw(at: NSPoint(x: rr.maxX - 10 - hsz.width, y: rr.midY - hsz.height / 2))
            }
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // overflow fades in place of a scroller
        let menuBG = Theme.hex(0x2a2330)
        let fadeW = r.width - Self.pad * 2
        if scrollOffset > 0.5 {
            NSGradient(starting: menuBG, ending: menuBG.withAlphaComponent(0))?
                .draw(in: NSRect(x: Self.pad, y: Self.pad, width: fadeW, height: 22), angle: 90)
        }
        if scrollOffset < contentHeight - innerHeight - 0.5 {
            NSGradient(starting: menuBG.withAlphaComponent(0), ending: menuBG)?
                .draw(in: NSRect(x: Self.pad, y: r.height - Self.pad - 22,
                                 width: fadeW, height: 22), angle: 90)
        }
    }
}
