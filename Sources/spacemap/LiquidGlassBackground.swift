import SwiftUI
import AppKit

/// Tinted glass keeps some translucency even at full opacity: a solid accent
/// wash would hide the glass instead of tinting it.
struct HUDBackground: View {
    let style: HUDBackgroundStyle
    let glassStyle: HUDGlassStyle
    let cornerRadius: CGFloat
    /// Effective per-style opacity, already resolved by the caller.
    let alpha: Double
    let isDarkMode: Bool
    let themeColor: Color      // Color(hex: resolvedTheme.background)
    /// Accent used for the tinted sub-type, so the tint cannot collapse into
    /// the same dark/light surface as the opaque style.
    let tintColor: Color
    /// Material under the accent for tinted glass.
    var glassTintedMaterial: HUDGlassMaterial = .clear

    /// Native panel glass supplies the material; this view draws only the
    /// border so a scrim or material cannot flatten the effect.
    var usesNativeGlass: Bool = false

    /// Neutral scrim that keeps dark/light HUDs legible over any wallpaper.
    private var scrim: Color {
        if isDarkMode {
            return Color(red: 0.04, green: 0.04, blue: 0.06)
        }
        return Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    var body: some View {
        if usesNativeGlass, style == .glass {
            Color.clear.overlay(HUDBorder(cornerRadius: cornerRadius))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *), GlassSupport.isAvailable {
                ModernHUDBackground(
                    style: style, glassStyle: glassStyle, cornerRadius: cornerRadius,
                    alpha: alpha, themeColor: themeColor, tintColor: tintColor,
                    glassTintedMaterial: glassTintedMaterial,
                    backing: glassStyle == .tinted ? tintColor : scrim
                )
            } else {
                fallbackBody
            }
            #else
            fallbackBody
            #endif
        }
    }

    @ViewBuilder
    private var fallbackBody: some View {
        switch style {
        case .solid:
            HUDSolidFill(cornerRadius: cornerRadius, color: themeColor, opacity: alpha)
        case .glass:
            switch glassStyle.material(tintedMaterial: glassTintedMaterial) {
            case .clear:
                glassBody(material: .ultraThinMaterial, backing: glassStyle == .tinted ? tintColor : scrim, backingOpacity: alpha)
            case .regular:
                glassBody(material: .regularMaterial, backing: glassStyle == .tinted ? tintColor : scrim, backingOpacity: alpha)
            }
        }
    }

    private func glassBody(
        material: Material,
        backing: Color,
        backingOpacity: Double
    ) -> some View {
        // The backing sits *over* the material: Liquid Glass samples the
        // window backdrop, not sibling layers, so a fill underneath it is
        // invisible and the opacity control would do nothing.
        ZStack {
            Rectangle()
                .fill(material)
            Rectangle()
                .fill(backing.opacity(backingOpacity))
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
    let themeColor: Color
    let tintColor: Color
    let glassTintedMaterial: HUDGlassMaterial
    let backing: Color

    var body: some View {
        switch style {
        case .solid:
            HUDSolidFill(cornerRadius: cornerRadius, color: themeColor, opacity: alpha)
        case .glass:
            // SwiftUI's own glass modifier, not a hosting wrapper: an
            // `NSGlassEffectView` inside `.background` only composites against
            // the cells above it, so the panel outside them stayed flat.
            // The scrim sits UNDER the material; a fill above it washes the
            // glass out, and the opacity slider still scales it.
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backing.opacity(alpha))
                Color.clear
                    .glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay(HUDBorder(cornerRadius: cornerRadius))
        }
    }

    private var glass: Glass {
        let base: Glass = glassStyle.material(tintedMaterial: glassTintedMaterial) == .clear ? .clear : .regular
        return glassStyle == .tinted ? base.tint(tintColor) : base
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
