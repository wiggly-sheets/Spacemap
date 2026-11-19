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

    /// Explicit memberwise init: the failable colour init below removes the
    /// compiler-synthesized one.
    init(
        background: UInt32,
        focused: UInt32,
        text: UInt32,
        dropTarget: UInt32,
        cellBg: UInt32,
        cellBgFocused: UInt32,
        rect1: UInt32,
        rect2: UInt32,
        rect3: UInt32
    ) {
        self.background = background
        self.focused = focused
        self.text = text
        self.dropTarget = dropTarget
        self.cellBg = cellBg
        self.cellBgFocused = cellBgFocused
        self.rect1 = rect1
        self.rect2 = rect2
        self.rect3 = rect3
    }

    /// The one required-key check. Extra keys are ignored; a missing rect falls
    /// back to `focused`. The exact camelCase key wins, so case-variant
    /// duplicates resolve the same way every time; otherwise the on-disk
    /// lowercase names are matched.
    init?(colors: [String: UInt32]) {
        var lowered: [String: UInt32] = [:]
        for key in colors.keys.sorted() where lowered[key.lowercased()] == nil {
            lowered[key.lowercased()] = colors[key]
        }
        func value(_ key: String) -> UInt32? {
            colors[key] ?? lowered[key.lowercased()]
        }
        guard let background = value("background"),
              let focused = value("focused"),
              let text = value("text"),
              let dropTarget = value("dropTarget"),
              let cellBg = value("cellBg"),
              let cellBgFocused = value("cellBgFocused") else { return nil }
        self.init(
            background: background, focused: focused, text: text,
            dropTarget: dropTarget, cellBg: cellBg, cellBgFocused: cellBgFocused,
            rect1: value("rect1") ?? focused,
            rect2: value("rect2") ?? focused,
            rect3: value("rect3") ?? focused
        )
    }

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
}
