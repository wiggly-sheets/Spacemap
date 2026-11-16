import SwiftUI
import AppKit

/// Resolves the configured HUD family once, with a system fallback.
enum HUDFont {
    static func font(name: String, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if !name.isEmpty, let nsFont = NSFont(name: name, size: size) {
            return Font(nsFont)
        }
        return .system(size: size, weight: weight)
    }
}
