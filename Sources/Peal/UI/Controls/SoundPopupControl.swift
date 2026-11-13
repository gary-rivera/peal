import AppKit
import PealCore

// Hand-drawn replacement for NSPopUpButton: shares the 28px field style of the
// steppers/segments and opens a SoundListView in a borderless child window.
final class SoundPopupControl: FlippedView {
    private(set) var selectedSound: String
    private let sounds: [String]
    var onCommit: ((String) -> Void)?
    var onAudition: ((String) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    private var menuWindow: NSWindow?
    private var monitors: [Any] = []
    private var resignObserver: Any?
    var isOpen: Bool { menuWindow != nil }

    init(sounds: [String], selected: String) {
        self.sounds = sounds
        self.selectedSound = sounds.contains(selected) ? selected : (sounds.first ?? TimerSettings.defaultSound)
        super.init(frame: NSRect(x: 0, y: 0, width: 176, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ sound: String) {
        guard sounds.contains(sound) else { return }
        selectedSound = sound
        needsDisplay = true
    }

    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .activeAlways, .inVisibleRect] }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func mouseDown(with e: NSEvent) { isOpen ? closeMenu() : openMenu() }

    private func openMenu() {
        guard menuWindow == nil, let panel = window else { return }
        let list = SoundListView(sounds: sounds,
                                 selectedIndex: sounds.firstIndex(of: selectedSound) ?? 0,
                                 width: frame.width)
        list.onCommit = { [weak self] s in
            guard let self else { return }
            self.select(s)
            self.closeMenu()
            self.onCommit?(s)
        }
        list.onAudition = { [weak self] s in self?.onAudition?(s) }
        list.onClose = { [weak self] in self?.closeMenu() }

        let win = NSWindow(contentRect: NSRect(origin: .zero, size: list.frame.size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isReleasedWhenClosed = false
        win.contentView = list

        // Below the control; flips above it if the screen runs out.
        let ctrl = panel.convertToScreen(convert(bounds, to: nil))
        var oy = ctrl.minY - 4 - list.frame.height
        if let visible = panel.screen?.visibleFrame, oy < visible.minY {
            oy = ctrl.maxY + 4
        }
        win.setFrameOrigin(NSPoint(x: ctrl.minX, y: oy))
        panel.addChildWindow(win, ordered: .above)
        menuWindow = win
        needsDisplay = true

        // Click inside the list or on the control passes through; anywhere else closes.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                    handler: { [weak self] e in
            guard let self else { return e }
            if e.window == self.menuWindow { return e }
            if e.window == self.window,
               self.bounds.contains(self.convert(e.locationInWindow, from: nil)) { return e }
            self.closeMenu()
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self, let list = self.menuWindow?.contentView as? SoundListView else { return e }
            return list.handleKey(e) ? nil : e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                     handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeMenu() }
        }) {
            monitors.append(m)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.closeMenu() } }
    }

    private func closeMenu() {
        guard let win = menuWindow else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        (win.contentView as? SoundListView)?.cancelAudition()
        window?.removeChildWindow(win)
        win.orderOut(nil)
        menuWindow = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        (hovering || isOpen ? Theme.hex(0x332c39) : Theme.hex(0x2b2530)).setFill()
        roundedPath(r, 7).fill()
        (isOpen ? Theme.accent.withAlphaComponent(0.45) : NSColor(white: 0, alpha: 0.55)).setStroke()
        roundedPath(r.insetBy(dx: 0.25, dy: 0.25), 7).stroke()
        let title = NSAttributedString(string: selectedSound, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.ink])
        title.draw(at: NSPoint(x: 11, y: r.midY - title.size().height / 2))
        // double chevron
        Theme.ink3.setStroke()
        let cx = r.width - 14
        for (baseY, apexY) in [(11.5, 8.0), (16.5, 20.0)] {
            let p = NSBezierPath()
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to: NSPoint(x: cx - 3.5, y: baseY))
            p.line(to: NSPoint(x: cx, y: apexY))
            p.line(to: NSPoint(x: cx + 3.5, y: baseY))
            p.stroke()
        }
    }
}
