import SwiftUI
import AppKit

struct HUDBackground: View {
    let style: HUDBackgroundStyle
    let glassStyle: HUDGlassStyle
    let cornerRadius: CGFloat
    let alpha: Double          // config.backgroundAlpha 0...1
    let isDarkMode: Bool
    let themeColor: Color      // Color(hex: resolvedTheme.background)

    /// Neutral scrim that keeps dark/light HUDs legible over any wallpaper.
    private var scrim: Color {
        if isDarkMode {
            return Color(red: 0.04, green: 0.04, blue: 0.06)
        }
        return Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    var body: some View {
        #if compiler(>=6.0)
        if #available(macOS 26.0, *) {
            ModernHUDBackground(
                style: style, glassStyle: glassStyle, cornerRadius: cornerRadius,
                alpha: alpha, scrim: scrim, themeColor: themeColor
            )
        } else {
            fallbackBody
        }
        #else
        fallbackBody
        #endif
    }

    @ViewBuilder
    private var fallbackBody: some View {
        switch style {
        case .transparent:
            HUDBorder(cornerRadius: cornerRadius)
        case .solid:
            HUDSolidFill(cornerRadius: cornerRadius, color: themeColor)
        case .glass:
            switch glassStyle {
            case .clear:
                glassBody(materialOpacity: 0.5, scrimOpacity: alpha * 0.15, tint: nil)
            case .frosted:
                glassBody(materialOpacity: 1, scrimOpacity: alpha * 0.4, tint: nil)
            case .tinted:
                glassBody(materialOpacity: 1, scrimOpacity: alpha * 0.4, tint: themeColor.opacity(alpha))
            }
        }
    }

    private func glassBody(materialOpacity: Double, scrimOpacity: Double, tint: Color?) -> some View {
        ZStack {
            Rectangle()
                .fill(scrim.opacity(scrimOpacity))
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(materialOpacity)
            if let tint {
                Rectangle()
                    .fill(tint)
            }
        }
        .overlay(HUDBorder(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

#if compiler(>=6.0)
@available(macOS 26.0, *)
private struct ModernHUDBackground: View {
    let style: HUDBackgroundStyle
    let glassStyle: HUDGlassStyle
    let cornerRadius: CGFloat
    let alpha: Double
    let scrim: Color
    let themeColor: Color

    var body: some View {
        switch style {
        case .transparent:
            HUDBorder(cornerRadius: cornerRadius)
        case .solid:
            HUDSolidFill(cornerRadius: cornerRadius, color: themeColor)
        case .glass:
            switch glassStyle {
            case .clear:
                clearGlass
            case .frosted:
                glassBody(scrimOpacity: alpha * 0.4, material: .regular.interactive(), tint: nil)
            case .tinted:
                glassBody(
                    scrimOpacity: alpha * 0.4,
                    material: .regular.interactive(),
                    tint: themeColor.opacity(alpha)
                )
            }
        }
    }

    @ViewBuilder
    private var clearGlass: some View {
        #if compiler(>=6.2)
        glassBody(scrimOpacity: alpha * 0.15, material: .clear.interactive(), tint: nil)
        #else
        glassBody(scrimOpacity: alpha * 0.15, material: .regular.interactive(), tint: nil)
        #endif
    }

    private func glassBody(scrimOpacity: Double, material: Glass, tint: Color?) -> some View {
        ZStack {
            Rectangle()
                .fill(scrim.opacity(scrimOpacity))
            Rectangle()
                .glassEffect(material, in: .rect(cornerRadius: cornerRadius))
            if let tint {
                Rectangle()
                    .fill(tint)
            }
        }
        .overlay(HUDBorder(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
#endif

private struct HUDBorder: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
    }
}

private struct HUDSolidFill: View {
    let cornerRadius: CGFloat
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .overlay(HUDBorder(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
