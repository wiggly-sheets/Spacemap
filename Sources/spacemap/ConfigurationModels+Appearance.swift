import Foundation
import CoreGraphics


enum HUDDisplayMode {
    case unified
    case separate
    case hidden
}

enum CellStyle: Int, CaseIterable, Identifiable, Equatable {
    case rects, hybrid, icons, thumbnails, simple
    var id: Int { rawValue }
}

enum HUDBackgroundStyle: String, CaseIterable, Identifiable, Codable, Equatable {
    case glass, solid
    var id: String { rawValue }
}
enum HUDGlassStyle: String, CaseIterable, Identifiable, Codable, Equatable {
    /// Left end of the native Liquid Glass scale: minimal backing.
    case clear
    /// Standard frosted material.
    case regular
    /// Accent tint over either material.
    case tinted

    var id: String { rawValue }

    /// Material the style draws with. Tinted picks its own material; clear and
    /// regular are fixed. Hard rename: `opaque` and `frosted` no longer decode.
    func material(tintedMaterial: HUDGlassMaterial) -> HUDGlassMaterial {
        switch self {
        case .clear: return .clear
        case .regular: return .regular
        case .tinted: return tintedMaterial
        }
    }

    /// Lowest opacity the style may render at. Glass below this reads as a
    /// flat desktop hole rather than glass, so the value is a floor, not a
    /// default. Tinted sits higher so its accent stays visible.
    var minimumOpacity: Double {
        switch self {
        case .clear: return 0.35
        case .regular: return 0.40
        case .tinted: return 0.45
        }
    }
}

/// The two native materials `NSGlassEffectView` exposes.
enum HUDGlassMaterial: String, CaseIterable, Identifiable, Equatable {
    case clear, regular
    var id: String { rawValue }
}

/// What the HUD's space cells draw behind their content when they do not match
/// the panel background.
enum SpacesBackgroundStyle: String, CaseIterable, Identifiable, Equatable {
    case none, solid, glass
    var id: String { rawValue }
}
enum ThemeMode: String, CaseIterable, Identifiable, Equatable { case light, dark, auto; var id: String { rawValue } }

enum HUDPosition: Equatable, Hashable {
    case center, top, bottom
    /// Fraction of the screen's spare width/height plus the display it was
    /// dragged on. `screen` is nil when the position has no display pairing.
    case custom(x: Double, y: Double, screen: String?)

    static let allPresets: [HUDPosition] = [.center, .top, .bottom]

    var label: String {
        switch self {
        case .center: return "Center"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .custom: return "Custom"
        }
    }

    

    func point(for panelSize: CGSize, screen: CGRect) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .center:
            x = screen.midX - panelSize.width / 2
            y = screen.midY - panelSize.height / 2
        case .top:
            x = screen.midX - panelSize.width / 2
            y = screen.maxY - panelSize.height - 40
        case .bottom:
            x = screen.midX - panelSize.width / 2
            y = screen.minY + 40
        case .custom(let px, let py, _):
            x = screen.minX + (screen.width - panelSize.width) * px
            y = screen.minY + (screen.height - panelSize.height) * py
        }
        return CGPoint(x: x, y: y)
    }

    /// Display identity of a custom position, nil for presets and for custom
    /// positions saved before the screen pairing existed.
    var screenIdentifier: String? {
        guard case .custom(_, _, let screen) = self else { return nil }
        return screen
    }
}
enum HUDPositionKind: String, CaseIterable {
    case center, top, bottom, custom

    init(from position: HUDPosition) {
        switch position {
        case .center: self = .center
        case .top: self = .top
        case .bottom: self = .bottom
        case .custom: self = .custom
        }
    }
}
