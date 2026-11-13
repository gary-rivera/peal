import AppKit

/// The menu bar button: a bell (filled while a timer runs) plus status text.
@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var menu: NSMenu? {
        get { item.menu }
        set { item.menu = newValue }
    }

    func render(title: String, active: Bool) {
        let icon = NSImage(systemSymbolName: active ? "bell.fill" : "bell", accessibilityDescription: "Peal")
        icon?.isTemplate = true
        item.button?.image = icon
        item.button?.title = title.isEmpty ? "" : " " + title
    }
}
