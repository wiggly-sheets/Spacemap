import Foundation

struct AppTheme: Equatable {
    let background: UInt32
    let focused: UInt32
    let text: UInt32
    let dropTarget: UInt32
    let cellBg: UInt32
    let cellBgFocused: UInt32
    let rect1: UInt32
    let rect2: UInt32
    let rect3: UInt32

    /// Every colour a theme exposes, in the order the settings dropdowns offer
    /// them. This is the whole vocabulary: any UI that lets the user pick a
    /// theme-derived colour must offer exactly these names.
    static let colorNames = [
        "background", "focused", "text", "dropTarget",
        "cellBg", "cellBgFocused", "rect1", "rect2", "rect3"
    ]

    func value(for name: String) -> UInt32? {
        switch name.lowercased() {
        case "background": return background
        case "focused": return focused
        case "text": return text
        case "droptarget": return dropTarget
        case "cellbg": return cellBg
        case "cellbgfocused": return cellBgFocused
        case "rect1": return rect1
        case "rect2": return rect2
        case "rect3": return rect3
        default: return nil
        }
    }

    static let `default` = AppTheme(
        background: 0xf2f2f7, focused: 0x007aff, text: 0x333333,
        dropTarget: 0x007aff, cellBg: 0xe5e5ea, cellBgFocused: 0xd1d1d6,
        rect1: 0x007aff, rect2: 0x5ac8fa, rect3: 0x34c759
    )
    static func named(_ name: String) -> AppTheme {
        let themeService = ThemeManager.shared
        return themeService.named(name)
    }
}
