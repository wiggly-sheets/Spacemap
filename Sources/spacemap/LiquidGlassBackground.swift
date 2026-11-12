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
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), GlassSupport.isAvailable {
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
            HUDSolidFill(cornerRadius: cornerRadius, color: themeColor, opacity: alpha)
        case .glass:
            switch glassStyle {
            case .clear:
                glassBody(material: .ultraThinMaterial, backing: scrim, backingOpacity: alpha * 0.15)
            case .opaque:
                glassBody(material: .regularMaterial, backing: scrim, backingOpacity: alpha)
            case .tinted:
                glassBody(material: .regularMaterial, backing: themeColor, backingOpacity: alpha)
            }
        }
    }

    private func glassBody(
        material: Material,
        backing: Color,
        backingOpacity: Double
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(backing.opacity(backingOpacity))
            Rectangle()
                .fill(material)
        }
        .overlay(HUDBorder(cornerRadius: cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

#if compiler(>=6.2)
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
            HUDSolidFill(cornerRadius: cornerRadius, color: themeColor, opacity: alpha)
        case .glass:
            switch glassStyle {
            case .clear:
                clearGlass
            case .opaque:
                glassBody(
                    backing: scrim,
                    backingOpacity: alpha,
                    material: .regular.interactive()
                )
            case .tinted:
                glassBody(
                    backing: themeColor,
                    backingOpacity: alpha,
                    material: .regular.interactive()
                )
            }
        }
    }

    @ViewBuilder
    private var clearGlass: some View {
        #if compiler(>=6.2)
        glassBody(
            backing: scrim,
            backingOpacity: alpha * 0.15,
            material: .clear.interactive()
        )
        #else
        glassBody(
            backing: scrim,
            backingOpacity: alpha * 0.15,
            material: .regular.interactive()
        )
        #endif
    }

    private func glassBody(
        backing: Color,
        backingOpacity: Double,
        material: Glass
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(backing.opacity(backingOpacity))
            Rectangle()
                .glassEffect(material, in: .rect(cornerRadius: cornerRadius))
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
    /// 0...1 fill alpha. Solid never blurs; this just makes it see-through.
    let opacity: Double

    var body: some View {
        Rectangle()
            .fill(color.opacity(opacity))
            .overlay(HUDBorder(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
