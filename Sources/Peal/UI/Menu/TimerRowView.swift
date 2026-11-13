import AppKit
import PealCore

// Rich timer row (.rich in the mockup): accent dot, two text tiers, tick-marked
// progress track with playhead, and hover-revealed Stop/Reset actions.
final class TimerRowView: FlippedView {
    let timer: TickTimer
    var onStop: (() -> Void)?
    var onReset: (() -> Void)?
    private var hovering = false
    private var hoverAction = -1  // index into actionRects

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private enum Action {
        case stop, reset
        var glyph: String { self == .stop ? "■" : "✕" }
        var isDanger: Bool { self == .reset }
    }

    // Hover actions, right to left: running timers can also be stopped.
    private var actions: [Action] {
        timer.phase(at: Date()) == .running ? [.stop, .reset] : [.reset]
    }

    init(timer: TickTimer) {
        self.timer = timer
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.menuWidth, height: 72))
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() { needsDisplay = true }

    override var hoverTrackingOptions: NSTrackingArea.Options? { [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect] }
    private var actionRects: [NSRect] {
        var rects: [NSRect] = []
        var x = bounds.width - 14 - 23
        for _ in actions {
            rects.append(NSRect(x: x, y: 9, width: 23, height: 23))
            x -= 28
        }
        return rects
    }
    override func mouseEntered(with e: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovering = false; hoverAction = -1; needsDisplay = true }
    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        hovering = true
        let idx = actionRects.firstIndex(where: { $0.contains(p) }) ?? -1
        if idx != hoverAction { hoverAction = idx; needsDisplay = true }
    }
    override func mouseUp(with e: NSEvent) {
        guard hovering else { return }
        let p = convert(e.locationInWindow, from: nil)
        if let idx = actionRects.firstIndex(where: { $0.contains(p) }) {
            enclosingMenuItem?.menu?.cancelTracking()
            switch actions[idx] {
            case .stop: onStop?()
            case .reset: onReset?()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = timer
        let now = Date()
        let st = t.phase(at: now)
        let elapsed = t.elapsed(at: now)
        let window = t.config.window ?? 0
        let markCount = t.config.markCount
        // hover background
        if hovering {
            NSColor(white: 1, alpha: 0.07).setFill()
            roundedPath(bounds.insetBy(dx: 5, dy: 2), 7).fill()
        }

        let accent: NSColor = switch st {
        case .running: Theme.sysGreen
        case .scheduled: Theme.sysOrange
        case .finished: Theme.sysGray
        case .stopped: Theme.sysRed
        }
        // accent dot (+ soft ring)
        let topCY: CGFloat = 10 + 8.5
        NSColor(white: 1, alpha: 0.04).setFill()
        NSBezierPath(ovalIn: NSRect(x: 15 - 3, y: topCY - 7, width: 14, height: 14)).fill()
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 15, y: topCY - 4, width: 8, height: 8)).fill()
        if st == .finished || st == .stopped {
            let glyph = st == .finished ? "✓" : "■"
            let g = NSAttributedString(string: glyph, attributes: [
                .font: NSFont.systemFont(ofSize: st == .finished ? 6 : 5, weight: .black),
                .foregroundColor: Theme.hex(0x0e0f13)])
            let gsz = g.size()
            g.draw(at: NSPoint(x: 19 - gsz.width / 2, y: topCY - gsz.height / 2))
        }

        // title
        let bold = NSFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .semibold)
        let dim: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5), .foregroundColor: Theme.label3]
        let title = NSMutableAttributedString()
        switch st {
        case .running:
            title.append(NSAttributedString(string: Format.clock(elapsed), attributes: [
                .font: bold, .foregroundColor: Theme.label]))
            if t.config.isPerpetual {
                title.append(NSAttributedString(string: " · perpetuity", attributes: dim))
            } else {
                title.append(NSAttributedString(string: " of ", attributes: dim))
                title.append(NSAttributedString(string: Format.clock(window), attributes: [
                    .font: bold, .foregroundColor: Theme.label]))
            }
        case .scheduled:
            title.append(NSAttributedString(string: "Starts \(Self.timeFormatter.string(from: t.start))", attributes: [
                .font: bold, .foregroundColor: Theme.label]))
        case .finished:
            title.append(NSAttributedString(string: "Completed", attributes: [
                .font: bold, .foregroundColor: Theme.label2]))
            title.append(NSAttributedString(string: " · ", attributes: dim))
            title.append(NSAttributedString(string: Format.clock(window), attributes: [
                .font: bold, .foregroundColor: Theme.label2]))
        case .stopped:
            title.append(NSAttributedString(string: "Stopped at \(Format.clock(elapsed))", attributes: [
                .font: bold, .foregroundColor: Theme.label2]))
        }
        title.draw(at: NSPoint(x: 32, y: 10))

        // badge (hidden while hovering — the actions take its corner)
        if !hovering {
            let badgeText = st == .scheduled
                ? "in \(Format.countdown(fromElapsed: elapsed))"
                : "\(min(t.marksElapsed(at: now), markCount)) / \(markCount) ticks"
            let b = NSAttributedString(string: badgeText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: Theme.label2])
            let bsz = b.size()
            let br = NSRect(x: bounds.width - 15 - bsz.width - 14, y: 10.5,
                            width: bsz.width + 14, height: 17)
            NSColor(white: 1, alpha: 0.08).setFill()
            roundedPath(br, 8.5).fill()
            b.draw(centeredIn: br)
        } else {
            // hover actions
            for (i, rect) in actionRects.enumerated() {
                let action = actions[i]
                var bg = NSColor(white: 1, alpha: 0.10)
                var fg = Theme.label
                if i == hoverAction {
                    if action.isDanger { bg = Theme.sysRed; fg = .white }
                    else { bg = Theme.sysOrange; fg = Theme.hex(0x111111) }
                }
                bg.setFill(); roundedPath(rect, 6).fill()
                NSColor(white: 1, alpha: 0.14).setStroke()
                roundedPath(rect.insetBy(dx: 0.25, dy: 0.25), 6).stroke()
                NSAttributedString(string: action.glyph, attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: fg])
                    .draw(centeredIn: rect)
            }
        }

        // tick-marked progress track
        let tx0: CGFloat = 32, tx1 = bounds.width - 15
        let trackY: CGFloat = 10 + 17 + 8
        let track = NSRect(x: tx0, y: trackY, width: tx1 - tx0, height: 6)
        NSColor(white: 1, alpha: 0.10).setFill()
        roundedPath(track, 3).fill()
        let frac: CGFloat
        switch st {
        case .running, .stopped: frac = t.progress(at: now)
        case .scheduled: frac = 0
        case .finished: frac = 1
        }
        if frac > 0 {
            let fill = NSRect(x: tx0, y: trackY, width: (tx1 - tx0) * frac, height: 6)
            NSGraphicsContext.current?.saveGraphicsState()
            if st == .running {
                let glow = NSShadow()
                glow.shadowColor = Theme.sysGreen.withAlphaComponent(0.35)
                glow.shadowBlurRadius = 10
                glow.set()
            }
            switch st {
            case .running: drawVerticalGradient(fill, 3, Theme.hex(0x2bbe50), Theme.sysGreen)
            case .scheduled: Theme.sysOrange.setFill(); roundedPath(fill, 3).fill()
            case .finished: NSGradient(starting: Theme.hex(0x5a5a5f), ending: Theme.hex(0x8a8a8f))?
                .draw(in: roundedPath(fill, 3), angle: 0)
            case .stopped: NSGradient(starting: Theme.hex(0xc4362c), ending: Theme.sysRed)?
                .draw(in: roundedPath(fill, 3), angle: 0)
            }
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        // interval marks
        if markCount > 0 {
            let marksElapsed = t.marksElapsed(at: now)
            for i in 1...markCount {
                // Marks sit at their true times along the window (or clock hour).
                let mx = tx0 + (tx1 - tx0) * CGFloat(t.config.position(ofMark: i))
                let fired = i <= marksElapsed && st != .scheduled
                if fired {
                    NSGraphicsContext.current?.saveGraphicsState()
                    let glow = NSShadow()
                    glow.shadowColor = NSColor(white: 1, alpha: 0.7)
                    glow.shadowBlurRadius = 5
                    glow.set()
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: NSRect(x: mx - 1.5, y: trackY + 1.5, width: 3, height: 3)).fill()
                    NSGraphicsContext.current?.restoreGraphicsState()
                } else {
                    NSColor(white: 1, alpha: 0.28).setFill()
                    NSBezierPath(ovalIn: NSRect(x: mx - 1, y: trackY + 2, width: 2, height: 2)).fill()
                }
            }
        }
        // live playhead (running rows only)
        if st == .running {
            let hx = tx0 + (tx1 - tx0) * frac
            NSGraphicsContext.current?.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor(white: 0, alpha: 0.5)
            sh.shadowBlurRadius = 3
            sh.shadowOffset = NSSize(width: 0, height: -1)
            sh.set()
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: hx - 7.5, y: trackY + 3 - 7.5, width: 15, height: 15)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: hx - 5.5, y: trackY + 3 - 5.5, width: 11, height: 11)).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // config sub-line
        let subFont = NSFont.systemFont(ofSize: 11.5)
        let subBold = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let subColor = Theme.label2
        let subBoldColor = NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.78)
        var parts: [NSAttributedString] = []
        func plain(_ s: String) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: subFont, .foregroundColor: subColor])
        }
        func boldPair(_ a: String, _ b: String) -> NSAttributedString {
            let s = NSMutableAttributedString(attributedString: plain(a))
            s.append(NSAttributedString(string: b, attributes: [.font: subBold, .foregroundColor: subBoldColor]))
            return s
        }
        let every = boldPair("Every ", Format.duration(t.config.interval))
        let sound = boldPair("♪ ", t.config.sound)
        switch st {
        case .running:
            parts = [every, sound]
        case .scheduled:
            // Perpetual timers have no window to show.
            parts = (t.config.window.map { [plain("\(Format.duration($0)) window")] } ?? []) + [every, sound]
        case .finished, .stopped:
            parts = [every]
        }
        var sx: CGFloat = 32
        let subY = trackY + 6 + 1 + 4
        for (i, part) in parts.enumerated() {
            if i > 0 {
                Theme.label3.setFill()
                NSBezierPath(ovalIn: NSRect(x: sx + 7, y: subY + 7, width: 2, height: 2)).fill()
                sx += 16
            }
            part.draw(at: NSPoint(x: sx, y: subY))
            sx += ceil(part.size().width)
        }
    }
}
