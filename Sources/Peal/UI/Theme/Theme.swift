import AppKit

enum Theme {
    static let menuWidth: CGFloat = 334  // every menu row view and the menu itself
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: a)
    }
    // panel palette — brand pink-to-magenta ramp over plum-warmed darks
    static let accentSoft = hex(0xff8dc0)  // pink-300: chip text, bell, ▶
    static let accent     = hex(0xf65ca2)  // pink-400: ticks, tints
    static let accentDeep = hex(0xd62598)  // magenta-500: selection, CTA top
    static let magenta    = hex(0xa31c7f)  // magenta-600: CTA bottom
    static let red        = hex(0xff5f52)
    static let redSoft    = hex(0xff8f86)
    static let ink   = NSColor(white: 1, alpha: 0.92)
    static let ink2  = NSColor(white: 1, alpha: 0.60)
    static let ink3  = NSColor(white: 1, alpha: 0.38)
    static let line  = NSColor(white: 1, alpha: 0.09)
    static let line2 = NSColor(white: 1, alpha: 0.14)
    static let panelBG  = hex(0x282229)
    static let fieldBG  = hex(0x201a22)
    static let cardBG   = hex(0x261f28)
    static let cardBad  = hex(0x281c22)
    // menu palette
    static let sysGreen  = hex(0x30d158)
    static let sysOrange = hex(0xff9f0a)
    static let sysRed    = hex(0xff453a)
    static let sysGray   = hex(0x98989d)
    static let label  = hex(0xf5f5f7)
    static let label2 = NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.62)
    static let label3 = NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.34)

    static func caption(_ text: String) -> NSAttributedString {
        // Sentence-case field label, macOS style: quiet so the controls lead.
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: ink2,
        ])
    }
}
