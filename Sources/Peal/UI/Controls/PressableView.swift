import AppKit

/// A custom-drawn button: tracks the press so subclasses can draw it, and fires
/// `onClick` when the press is released inside the view.
class PressableView: FlippedView {
    var onClick: (() -> Void)?
    var isEnabled = true { didSet { needsDisplay = true } }
    private(set) var isPressed = false { didSet { needsDisplay = true } }

    override func mouseDown(with e: NSEvent) {
        if isEnabled { isPressed = true }
    }

    override func mouseUp(with e: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        guard isEnabled, wasPressed, bounds.contains(convert(e.locationInWindow, from: nil)) else { return }
        onClick?()
    }
}
