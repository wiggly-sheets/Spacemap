import AppKit
import Foundation

extension GlyphStrip {
    // MARK: - Backgrounds

    /// Vertical inset so the fill does not touch the very top and bottom edges
    /// of the menu bar row. Doubles as the padding that keeps glyphs off the
    /// glass edge. Only applies to the glass mask; solid fills use full height.
    static let backdropVerticalInset: CGFloat = 2

    /// Alpha of the hover highlight, which always composites on top of the base
    /// backdrop.
    static let hoverHighlightOpacity: CGFloat = 0.18

    /// The layer drawn behind the whole strip. The material decides whether
    /// that layer exists at all — `.none` draws nothing, so callers guard on it
    /// before asking.
    ///
    /// The corner radius carries the shape: half the height or more is a pill,
    /// 0 is a square bar, and anything between is a rounded rectangle. It is
    /// capped here so an oversized radius can never bulge past the ends.
    ///
    /// - Parameter insetForGlass: When true (default), applies a small vertical
    ///   inset so the glass mask doesn't touch the menu bar edges. Set to false
    ///   for solid fills that should span the full panel height.
    static func backdrop(
        bounds: CGRect,
        cornerRadius: CGFloat,
        insetForGlass: Bool = true
    ) -> Backdrop {
        let rect = bounds.insetBy(dx: 0, dy: insetForGlass ? backdropVerticalInset : 0)
        return Backdrop(rect: rect, cornerRadius: min(cornerRadius, rect.height / 2))
    }

    /// The fill behind the hovered segment, sized to the glyphs it covers.
    ///
    /// `segmentRect` is the segment's content box — its slot trimmed horizontally
    /// by the padding that surrounds the glyphs, and still as tall as the whole
    /// menu bar row. The highlight instead wraps `runHeight`, the resolved text
    /// line box for this segment's glyphs (which depends on `indexSize` and
    /// `iconSize`), centred inside that rect and grown by `padding` on both axes
    /// so it never touches a glyph edge.
    ///
    /// `cornerRadius` here is `hoverCornerRadius`, deliberately separate from the
    /// `cornerRadius` key that shapes the background.
    ///
    /// Hovering the current space resolves identically to hovering any other
    /// segment — no current-space fill exists — so `highlightCurrentSpace` can
    /// never leave a mark by this route.
    ///
    /// `limits` is the region the highlight must stay inside (the painted
    /// backdrop intersected with the view bounds): `padding` can grow the rect
    /// past the strip's ends, and the result is clipped rather than allowed to
    /// bleed outside. Returns nil when nothing of the highlight remains inside.
    /// `centerLift` shifts center up (+) to even top/bottom; defaults 0.
    static func hoverFill(
        segmentRect: CGRect?,
        runHeight: CGFloat,
        padding: CGFloat,
        cornerRadius: CGFloat,
        within limits: CGRect? = nil,
        centerLift: CGFloat = 0
    ) -> Backdrop? {
        guard let segmentRect else { return nil }
        // A degenerate run height must not produce a taller highlight than the
        // row; fall back to the slot itself.
        let height = min(max(runHeight, 0), segmentRect.height) + padding * 2
        guard height > 0, segmentRect.width > 0 else { return nil }
        // Grown, like the height. Trimming instead made the highlight sit *inside*
        // the glyph box, and a wide `hoverPadding` could shrink a narrow segment's
        // highlight to nothing at all.
        let width = max(segmentRect.width + padding * 2, 0)
        guard width > 0 else { return nil }
        var rect = CGRect(
            x: segmentRect.midX - width / 2,
            y: segmentRect.midY - height / 2 + centerLift,
            width: width,
            height: height
        )
        if let limits {
            rect = rect.intersection(limits)
            guard rect.width > 0, rect.height > 0 else { return nil }
        }
        return Backdrop(rect: rect, cornerRadius: min(cornerRadius, rect.height / 2))
    }

    /// Visual lift for icon-font glyphs. sketchybar-app-font ink sits low in
    /// its em box next to system-font digits on the same baseline, so `.app`
    /// and `.nativeIcon` runs draw slightly higher. Every other run draws at
    /// the shared baseline.
    static let appGlyphLift: CGFloat = 1.5

    static func baselineLift(for run: Run) -> CGFloat {
        switch run {
        case .app, .nativeIcon:
            return appGlyphLift
        default:
            return 0
        }
    }

    /// Native runs paint an image when resolved, else their fallback glyph.
    static func isNativeIcon(_ run: Run) -> Bool {
        if case .nativeIcon = run { return true }
        return false
    }

    /// Neutral hairline for clear/regular. Tinted uses `glassStrokeColor`, whose
    /// theme blend matches the tinted backing.
    static func neutralGlassStrokeColor() -> NSColor { NSColor(white: 0.5, alpha: 1) }

    /// Fallback `NSVisualEffectView` material for the resolved material, so
    /// clear and regular stay distinct without native glass (pre-26, Reduce
    /// Transparency). Tinted keeps the saturated `.popover`.
    static func glassFallbackMaterial(for style: HUDGlassStyle, tintedMaterial: HUDGlassMaterial) -> NSVisualEffectView.Material {
        if style == .tinted, tintedMaterial == .clear { return .popover }
        return style.material(tintedMaterial: tintedMaterial) == .clear ? .underWindowBackground : .headerView
    }

    /// Fills a resolved backdrop, or strokes it for the glass edge. The only
    /// side-effecting part of the drawing pipeline; everything above it is pure
    /// and testable.
    static func fill(_ backdrop: Backdrop, color: NSColor, opacity: CGFloat) {
        color.withAlphaComponent(opacity).setFill()
        NSBezierPath(
            roundedRect: backdrop.rect,
            xRadius: backdrop.cornerRadius,
            yRadius: backdrop.cornerRadius
        ).fill()
    }

    /// 1px hairline inset by half its width so it lands fully inside `backdrop`.
    static func stroke(_ backdrop: Backdrop, color: NSColor, opacity: CGFloat) {
        let inset = backdrop.rect.insetBy(dx: 0.5, dy: 0.5)
        guard inset.width > 0, inset.height > 0 else { return }
        color.withAlphaComponent(opacity).setStroke()
        let path = NSBezierPath(
            roundedRect: inset,
            xRadius: max(backdrop.cornerRadius - 0.5, 0),
            yRadius: max(backdrop.cornerRadius - 0.5, 0)
        )
        path.lineWidth = 1
        path.stroke()
    }

    /// The subset of `GlyphStripConfig` that changes what segments contain.
    /// Snapshotted once per refresh so segment building never reads config.
    struct Options: Equatable {
        var showSpaceNumbers = true
        var spaceLabelStyle: GlyphStripSpaceLabelStyle = .numbers
        /// Active name profile's names, keyed by space index.
        var spaceNames: [Int: String] = [:]
        var showLayoutSuffix = true
        var showBSPLayoutBadge = true
        var showStackLayoutBadge = true
        var showFloatLayoutBadge = true
        var showAppIcons = true
        var iconSource: GlyphStripIconSource = .sbarFont
        var dedupeAppsPerSpace = true
        var maxIconsPerSpace = 8
        var showDisplaySeparators = true
        var showAddSpaceButton = true
        var showPlaceholders = true

        init(_ config: GlyphStripConfig, spaceNames: [Int: String] = [:]) {
            showSpaceNumbers = config.showSpaceNumbers
            spaceLabelStyle = config.spaceLabelStyle
            self.spaceNames = spaceNames
            showLayoutSuffix = config.showLayoutSuffix
            showBSPLayoutBadge = config.showBSPLayoutBadge
            showStackLayoutBadge = config.showStackLayoutBadge
            showFloatLayoutBadge = config.showFloatLayoutBadge
            showAppIcons = config.showAppIcons
            iconSource = config.iconSource
            dedupeAppsPerSpace = config.dedupeAppsPerSpace
            maxIconsPerSpace = max(0, config.maxIconsPerSpace)
            showDisplaySeparators = config.showDisplaySeparators
            showAddSpaceButton = config.showAddSpaceButton
            showPlaceholders = config.showPlaceholders
        }
    }
}
