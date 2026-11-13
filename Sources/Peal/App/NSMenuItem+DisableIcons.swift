import AppKit
import ObjectiveC

extension NSMenuItem {
    // macOS 26 auto-decorates standard selectors (e.g. terminate: → Quit icon)
    // with symbol images. Peal's menu is fully custom-drawn, so suppress them
    // by swizzling the image getter to nil (Brent Simmons' technique).
    static func disableIcons() {
        guard let original = class_getInstanceMethod(NSMenuItem.self, #selector(getter: image)),
              let replacement = class_getInstanceMethod(NSMenuItem.self, #selector(returnNilInsteadOfImage))
        else { return }
        method_exchangeImplementations(original, replacement)
    }
    @objc private func returnNilInsteadOfImage() -> NSImage? { nil }
}
