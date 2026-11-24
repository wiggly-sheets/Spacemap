import Foundation
import CoreGraphics

extension ConfigSchema {
    static func displayNavigationWrap(from name: String) -> DisplayNavigationWrap? {
        switch name.lowercased() {
        case "within": return .within
        case "between": return .between
        default: return nil
        }
    }

    static func updateMode(from name: String) -> UpdateMode? {
        switch name.lowercased() {
        case "auto": return .auto
        case "notify": return .notify
        case "off": return .off
        default: return nil
        }
    }

    /// A fraction 0...1 from a raw TOML number. Out-of-range values decode nil
    /// so the key falls back to its default instead of clamping.
    static func rangedDouble(_ raw: Any) -> Double? {
        guard let value = double(raw), (0...1).contains(value) else { return nil }
        return value
    }

    static func double(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return nil
    }

    /// Only an `Int` in 0...21 counts; `15.0` and oversized values decode nil
    /// so the key falls back to its default instead of clamping.
    static func variant(_ raw: Any) -> Int? {
        guard let value = raw as? Int, (0...21).contains(value) else { return nil }
        return value
    }

    static func themeMode(from raw: Any) -> ThemeMode? {
        guard let name = raw as? String else { return nil }
        switch name.lowercased() {
        case "light": return .light
        case "dark": return .dark
        case "auto": return .auto
        default: return nil
        }
    }

    static func positiveInt(_ raw: Any) -> Int? {
        guard let value = raw as? Int, value > 0 else { return nil }
        return value
    }

    static func nonNegativeInt(_ raw: Any) -> Int? {
        guard let value = raw as? Int, value >= 0 else { return nil }
        return value
    }

    static func bool(_ raw: Any) -> Bool? {
        raw as? Bool
    }

    static func cellStyle(from name: String) -> CellStyle? {
        switch name.lowercased() {
        case "rects": return .rects
        case "hybrid": return .hybrid
        case "icons": return .icons
        case "thumbnails": return .thumbnails
        case "simple": return .simple
        default: return nil
        }
    }

    static func showMode(from name: String) -> ShowMode? {
        switch name.lowercased() {
        case "active": return .active
        case "all": return .all
        default: return nil
        }
    }

    static func multiMonitorHUDMode(from name: String) -> MultiMonitorHUDMode? {
        switch name.lowercased() {
        case "separate": return .separate
        case "unified": return .unified
        default: return nil
        }
    }

    static func hudVisibility(from name: String) -> SeparateHUDVisibility? {
        switch name.lowercased() {
        case "active": return .active
        case "all": return .all
        default: return nil
        }
    }
}
