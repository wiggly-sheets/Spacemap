import AppKit
import Foundation

extension GlyphStrip {
    // MARK: - Colours

    /// Sentinel for the colour that draws nothing. `color(for:theme:)` returns
    /// nil for it so callers skip a layer instead of drawing black.
    static let noColor = "none"

    /// Resolves a theme colour name to a drawable colour. `nil` for `noColor`,
    /// and `nil` for a name the theme does not define so callers fall back
    /// rather than drawing black.
    ///
    /// The strip is theme-driven: callers pass the fixed role names (`focused`,
    /// `text`, `cellBg`) — there are no per-element colour keys any more.
    static func color(for name: String, theme: AppTheme) -> NSColor? {
        guard name != noColor, let hex = theme.value(for: name) else { return nil }
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }

    /// How one run is painted: a theme colour role plus the alpha it draws at.
    struct RunStyle: Equatable {
        let colorName: String
        let alpha: CGFloat
    }

    /// Colour policy for one run.
    ///
    /// `isCurrent` is ignored entirely when `highlightCurrentSpace` is off, which
    /// is what makes the current space genuinely indistinguishable rather than
    /// merely painted in the dimmed colour. With the flag on, the current space
    /// and the add button draw in `focused`; everything resting draws in `text`.
    static func style(
        for run: Run,
        isCurrent: Bool,
        strip: GlyphStripConfig
    ) -> RunStyle {
        let highlighted = isCurrent && strip.highlightCurrentSpace
        var isAppGlyph = false
        if case .app = run { isAppGlyph = true }
        if isNativeIcon(run) { isAppGlyph = true }
        // Only the highlighted (current) space keeps full-strength glyphs.
        let alpha: CGFloat = isAppGlyph && !highlighted ? 0.55 : 1.0
        let name: String
        if highlighted {
            name = "focused"
        } else if case .add = run {
            name = "focused"
        } else {
            name = "text"
        }
        return RunStyle(colorName: name, alpha: alpha)
    }

    /// Picks a stroke colour that stays visible over a light or dark wallpaper.
    /// Uses the theme's own foreground/background pair instead of a hardcoded
    /// grey, so the glass edge tracks the active theme.
    static func glassStrokeColor(theme: AppTheme) -> NSColor {
        let border = color(for: "text", theme: theme) ?? .labelColor
        let background = color(for: "background", theme: theme) ?? .windowBackgroundColor
        // Border colour at lower alpha over the theme background reads as a
        // hairline in both light and dark themes.
        return border.withAlphaComponent(0.35).blended(withFraction: 0.5, of: background) ?? border
    }
}
