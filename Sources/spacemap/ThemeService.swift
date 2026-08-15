import AppKit

final class ThemeService {

    private let themeManager: ThemeManager

    init(themeManager: ThemeManager = ThemeManager()) {
        self.themeManager = themeManager
    }

    func reload() {
        themeManager.reload()
    }

    func named(_ name: String) -> AppTheme {
        themeManager.named(name)
    }

    func allNames() -> [String] {
        themeManager.allNames()
    }

    static func themesDir() -> URL {
        ThemeManager.themesDir()
    }
}
