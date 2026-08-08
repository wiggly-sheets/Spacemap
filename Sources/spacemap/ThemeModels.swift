import Foundation

struct AppTheme: Equatable {
    let background: UInt32      // HUD grid background
    let focused: UInt32         // Focused space border/highlight
    let text: UInt32            // Text color
    let dropTarget: UInt32      // Drop target highlight
    let cellBg: UInt32          // Unfocused cell fill
    let cellBgFocused: UInt32   // Focused cell fill
    let rect1: UInt32           // Window rect color 1
    let rect2: UInt32           // Window rect color 2
    let rect3: UInt32           // Window rect color 3

    static let `default` = AppTheme(
        background: 0xf2f2f7, focused: 0x007aff, text: 0x333333,
        dropTarget: 0x007aff, cellBg: 0xe5e5ea, cellBgFocused: 0xd1d1d6,
        rect1: 0x007aff, rect2: 0x5ac8fa, rect3: 0x34c759
    )
    static let tokyonight = AppTheme(
        background: 0x1a1b26, focused: 0x7aa2f7, text: 0xa9b1d6,
        dropTarget: 0xbb9af7, cellBg: 0x1a1b26, cellBgFocused: 0x1a1b26,
        rect1: 0x7aa2f7, rect2: 0xbb9af7, rect3: 0x9ece6a
    )
    static let catppuccin = AppTheme(
        background: 0x1e1e2e, focused: 0xcba6f7, text: 0xcdd6f4,
        dropTarget: 0xf5c2e7, cellBg: 0x313244, cellBgFocused: 0x45475a,
        rect1: 0xcba6f7, rect2: 0xf5c2e7, rect3: 0xa6e3a1
    )
    static let monokaiDark = AppTheme(
        background: 0x272822, focused: 0xa6e22e, text: 0xf8f8f2,
        dropTarget: 0xfd971f, cellBg: 0x3e3d32, cellBgFocused: 0x49483e,
        rect1: 0xa6e22e, rect2: 0xfd971f, rect3: 0x66d9ef
    )
    static let monokaiLight = AppTheme(
        background: 0xfafafa, focused: 0xa6e22e, text: 0x272822,
        dropTarget: 0xfd971f, cellBg: 0xe8e8d8, cellBgFocused: 0xd6d6c8,
        rect1: 0x7ec837, rect2: 0xf38634, rect3: 0x2cc5a6
    )
    static let dracula = AppTheme(
        background: 0x282a36, focused: 0xbd93f9, text: 0xf8f8f2,
        dropTarget: 0xff79c6, cellBg: 0x44475a, cellBgFocused: 0x565a79,
        rect1: 0xbd93f9, rect2: 0xff79c6, rect3: 0x50fa7b
    )
    static let ayu = AppTheme(
        background: 0x0b0e14, focused: 0xff8f40, text: 0xbfbdb6,
        dropTarget: 0xf07178, cellBg: 0x1a1f29, cellBgFocused: 0x2a3140,
        rect1: 0xff8f40, rect2: 0xf07178, rect3: 0xc2d94c
    )
    static let github = AppTheme(
        background: 0x0d1117, focused: 0x3fb950, text: 0xc9d1d9,
        dropTarget: 0x58a6ff, cellBg: 0x161b22, cellBgFocused: 0x21262d,
        rect1: 0x3fb950, rect2: 0x58a6ff, rect3: 0xd2a8ff
    )
    static let vscode = AppTheme(
        background: 0x1e1e1e, focused: 0x007acc, text: 0xcccccc,
        dropTarget: 0x4ec9b0, cellBg: 0x252526, cellBgFocused: 0x333333,
        rect1: 0x007acc, rect2: 0x4ec9b0, rect3: 0xdcdcaa
    )
    static let xcode = AppTheme(
        background: 0x1f1f24, focused: 0x5e9eff, text: 0xffffff,
        dropTarget: 0x6c5ce7, cellBg: 0x2c2c32, cellBgFocused: 0x3a3a42,
        rect1: 0x5e9eff, rect2: 0x6c5ce7, rect3: 0xff6b6b
    )
    static let nord = AppTheme(
        background: 0x2e3440, focused: 0x88c0d0, text: 0xd8dee9,
        dropTarget: 0x81a1c1, cellBg: 0x3b4252, cellBgFocused: 0x434c5e,
        rect1: 0x88c0d0, rect2: 0x81a1c1, rect3: 0xa3be8c
    )
    static let atomOneDark = AppTheme(
        background: 0x282c34, focused: 0x61afef, text: 0xabb2bf,
        dropTarget: 0x98c379, cellBg: 0x2c323c, cellBgFocused: 0x3a404a,
        rect1: 0x61afef, rect2: 0x98c379, rect3: 0xc678dd
    )

    static func named(_ name: String) -> AppTheme {
        // This is a temporary workaround until we can inject the ThemeService properly
        // In the ideal implementation, this would use an injected ThemeService
        let themeService = ThemeService()
        return themeService.named(name)
    }
}
