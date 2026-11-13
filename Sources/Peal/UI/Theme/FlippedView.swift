import AppKit

// A view that lays out top-down. Subclasses opt into hover tracking by
// returning the tracking options they need.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var hoverTrackingOptions: NSTrackingArea.Options? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard let options = hoverTrackingOptions else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }
}
