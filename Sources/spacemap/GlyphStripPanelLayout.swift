import AppKit
import ApplicationServices
import CoreText

extension GlyphStripPanelController {
    // MARK: - Render layout

    /// One render for `bounds`: the value every draw and hit test reads.
    ///
    /// `statusItem` centres the slots in the whole button, because a menu-bar
    /// item can be wider than the strip, and shrinks native icons to the row
    /// height, which is what that surface drew and hit-tested before.
    func layout(in bounds: CGRect, statusItem: Bool) -> GlyphStrip.SegmentLayout {
        var input = GlyphStrip.LayoutInput(
            slots: slots(in: bounds, statusItem: statusItem),
            advances: advances(in: bounds, statusItem: statusItem),
            gaps: runGaps
        )
        if !statusItem {
            if isStackedVertical {
                input.placement = .stacked
                input.lines = stackedLines(in: input.slots)
                input.inkCenters = inkCenters(for: input.lines)
            } else if isVerticalLayout {
                input.placement = .centered
            } else {
                input.placement = .inline(inset: Self.segmentPadding)
            }
        }
        return GlyphStrip.layout(
            segments: segments,
            state: coordinator.state,
            options: renderOptions,
            input: input
        )
    }

    /// The panel's own render, inset by the strip padding.
    var layout: GlyphStrip.SegmentLayout {
        let bounds = viewBounds
        if let cachedLayout, cachedLayoutBounds == bounds { return cachedLayout }
        let resolved = layout(in: bounds, statusItem: false)
        layoutBuildCount += 1
        cachedLayout = resolved
        cachedLayoutBounds = bounds
        return resolved
    }

    /// The menu-bar item's render, cached on the button bounds so a draw and
    /// the mouse-drag hit tests behind it share one pass.
    func statusItemLayout(in bounds: CGRect) -> GlyphStrip.SegmentLayout {
        if let cachedStatusLayout, cachedStatusLayoutBounds == bounds { return cachedStatusLayout }
        let resolved = layout(in: bounds, statusItem: true)
        cachedStatusLayout = resolved
        cachedStatusLayoutBounds = bounds
        return resolved
    }

    /// Hit slot of every segment in `bounds`.
    private func slots(in bounds: CGRect, statusItem: Bool) -> [CGRect] {
        guard !bounds.isEmpty, !segmentWidths.isEmpty else { return [] }
        if statusItem {
            let total = segmentWidths.reduce(0, +)
            let content = CGRect(
                x: max((bounds.width - total) / 2, 0),
                y: 0,
                width: total,
                height: bounds.height
            )
            return GlyphStrip.horizontalSlots(widths: segmentWidths, in: content)
        }
        let content = contentBounds(in: bounds)
        if isVerticalLayout {
            let heights = segmentWidths.indices.map { verticalSegmentHeight($0) }
            if heights.reduce(0, +) > content.height {
                return GlyphStrip.verticalColumnSlots(
                    heights: heights,
                    in: content,
                    available: content.height,
                    columnGap: Self.verticalColumnGap
                )
            }
            return GlyphStrip.verticalSlots(heights: heights, in: content)
        }
        return GlyphStrip.horizontalSlots(widths: segmentWidths, in: content)
    }

    /// Measured advance of every run. The status item shrinks a resolved native
    /// icon to the row height, the way it always drew it.
    private func advances(in bounds: CGRect, statusItem: Bool) -> [[CGFloat]] {
        guard statusItem else { return runAdvances }
        return runAdvances.enumerated().map { offset, widths in
            widths.enumerated().map { index, width in
                nativeIcon(segment: offset, run: index) == nil
                    ? width
                    : min(width, bounds.height - 4)
            }
        }
    }

    /// One line per run for the stacked vertical layout.
    private func stackedLines(in slots: [CGRect]) -> [[CGRect]] {
        attributedRuns.indices.map { offset in
            guard slots.indices.contains(offset) else { return [] }
            return GlyphStrip.stackedLines(
                count: attributedRuns[offset].count,
                lineHeight: contentLineHeight,
                indexGap: stackedGap(before: 1),
                iconGap: stackedGap(before: 2),
                in: slots[offset].insetBy(dx: 0, dy: hoverPadding)
            )
        }
    }

    /// Ink-centre x of each stacked run; nil centres the advance box, which is
    /// what native icons need.
    private func inkCenters(for lines: [[CGRect]]) -> [[CGFloat?]] {
        attributedRuns.indices.map { offset in
            attributedRuns[offset].indices.map { index in
                guard nativeIcon(segment: offset, run: index) == nil,
                      lines.indices.contains(offset),
                      lines[offset].indices.contains(index) else { return nil }
                return GlyphStripView.inkCenteredX(
                    for: attributedRuns[offset][index],
                    in: lines[offset][index]
                )
            }
        }
    }

    /// Gap between wrapped vertical columns.
    static let verticalColumnGap: CGFloat = 8

    // MARK: - Drawing inputs

    var runs: [[NSAttributedString]] { attributedRuns }

    /// Per-run y lift over the shared baseline: `appGlyphLift` for icon-font
    /// and native-icon runs, zero for index/placeholder/overflow/separator/add.
    func drawLift(segment offset: Int, run index: Int) -> CGFloat {
        guard segments.indices.contains(offset), segments[offset].runs.indices.contains(index) else { return 0 }
        return GlyphStrip.baselineLift(for: segments[offset].runs[index])
    }
    var hovered: Int? { hoveredSegment }
    var isPositionLocked: Bool {
        let screen = panelScreen() ?? targetScreen()
        return config.glyphStrip.isPositionLocked(hasNotch: screen.map(Self.hasNotch) ?? false)
    }
    fileprivate var backgroundMaterial: GlyphStripBackgroundMaterial {
        config.glyphStrip.resolvedBackgroundMaterial(hud: config)
    }
    var glassStyle: HUDGlassStyle {
        config.glyphStrip.resolvedGlassStyle(hud: config)
    }
    var glassVariant: Int {
        config.glyphStrip.resolvedGlassVariant(hud: config)
    }
    var glassTintedMaterial: HUDGlassMaterial {
        config.glyphStrip.resolvedGlassTintedMaterial(hud: config)
    }
    var backgroundOpacity: CGFloat {
        CGFloat(config.glyphStrip.resolvedBackgroundOpacity(hud: config))
    }
    fileprivate var cornerRadius: CGFloat { CGFloat(config.glyphStrip.cornerRadius) }
    var hoverPadding: CGFloat { CGFloat(config.glyphStrip.hoverPadding) }
    var hoverCornerRadius: CGFloat { CGFloat(config.glyphStrip.hoverCornerRadius) }
    var borderEnabled: Bool { config.glyphStrip.borderEnabled }

    /// The resolved text line box for a segment's runs, from real font metrics.
    ///
    /// The hover highlight is sized to this rather than to the menu bar row, so a
    /// 12pt strip does not get a 37.5pt-tall highlight.
    func runHeight(forSegment index: Int) -> CGFloat {
        // Stacked vertical highlights the whole block of lines, not one run.
        if isStackedVertical {
            return max(verticalSegmentHeight(index) - hoverPadding * 2, 0)
        }
        guard attributedRuns.indices.contains(index) else { return 0 }
        let fonts = attributedRuns[index].map { GlyphStripView.font(of: $0) }
        guard !fonts.isEmpty else { return 0 }
        let ascender = fonts.map(\.ascender).max() ?? 0
        let descender = fonts.map(\.descender).min() ?? 0
        return ascender - descender
    }

    /// The content height of the strip — the tallest resolved line box across
    /// all runs. Used to size the solid/glass backdrop to the actual glyph
    /// content. Reads font metrics directly so stacked vertical layout can ask
    /// for it from `runHeight(forSegment:)` without recursing.
    var contentHeight: CGFloat {
        let fonts = attributedRuns.flatMap { $0.map { GlyphStripView.font(of: $0) } }
        guard !fonts.isEmpty else { return viewBounds.height }
        let ascender = fonts.map(\.ascender).max() ?? 0
        let descender = fonts.map(\.descender).min() ?? 0
        return ascender - descender
    }

    /// Tallest ascender across all runs. Pairs with `contentHeight` to place one
    /// shared baseline, so every segment sits on same line.
    fileprivate var contentAscender: CGFloat {
        attributedRuns.flatMap { $0.map { GlyphStripView.font(of: $0).ascender } }.max() ?? 0
    }

    /// Top of content box centered in `bounds`. Feeds `contentBaselineY(in:)`
    /// so glyphs center on the same point as the backdrop.
    func contentY(in bounds: CGRect) -> CGFloat {
        bounds.minY + (bounds.height - contentHeight) / 2
    }

    /// Single global baseline for all segments: content box centered in `bounds`,
    /// offset by tallest ascender. Same y-center as backdrop. `NSView` is
    /// y-up here (not flipped), so the baseline sits one ascender *below* the
    /// box top: `contentY + contentHeight - contentAscender`.
    func contentBaselineY(in bounds: CGRect) -> CGFloat {
        guard !attributedRuns.isEmpty else { return bounds.minY }
        return contentY(in: bounds) + contentHeight - contentAscender
    }

    /// The theme the strip's colours resolve against: its own `theme` key when
    /// set, otherwise the main HUD's theme.
    var effectiveThemeName: String {
        themeStore.resolvedThemeName(strip: config.glyphStrip, hudTheme: config.theme)
    }

    /// The solid material's fill, at `backgroundOpacity`. Matches the HUD's
    /// `background` role when copying the HUD appearance (the HUD solid fill
    /// uses that role); otherwise the strip's own `cellBg`.
    var solidColor: NSColor {
        let role = config.glyphStrip.matchHUDAppearance ? "background" : "cellBg"
        return GlyphStrip.color(for: role, theme: themeStore.named(effectiveThemeName))
            ?? .windowBackgroundColor
    }

    /// The glass layer only exists for `.liquidGlass`.
    var usesGlass: Bool { backgroundMaterial == .liquidGlass }

    /// The flat fill only exists for `.solid`, at `backgroundOpacity`.
    var usesSolid: Bool { backgroundMaterial == .solid }

    /// No backdrop at all when the material is `.none`. Single source of truth
    /// for `layout()` and `draw()`.
    fileprivate var drawsBackdrop: Bool { backgroundMaterial != .none }

    /// Single resolved backdrop shared by the solid fill and the glass mask so
    /// the two rects cannot disagree. `nil` when nothing is painted, or when
    /// the shape degenerates.
    func backdrop(in bounds: CGRect) -> GlyphStrip.Backdrop? {
        guard drawsBackdrop else { return nil }
        let resolved = GlyphStrip.backdrop(bounds: bounds, cornerRadius: cornerRadius, insetForGlass: usesGlass)
        let clipped = resolved.rect.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return GlyphStrip.Backdrop(rect: clipped, cornerRadius: resolved.cornerRadius)
    }

    /// Outline path when no fill painted: the same rounded rect as
    /// `backdrop`, so material `.none` still outlines a pill, bar, or radius.
    func borderBackdrop(in bounds: CGRect) -> GlyphStrip.Backdrop? {
        let resolved = GlyphStrip.backdrop(bounds: bounds, cornerRadius: cornerRadius, insetForGlass: usesGlass)
        let clipped = resolved.rect.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return GlyphStrip.Backdrop(rect: clipped, cornerRadius: resolved.cornerRadius)
    }

    var strokeColor: NSColor {
        GlyphStrip.glassStrokeColor(theme: themeStore.named(effectiveThemeName))
    }

    /// Native glass tint for the tinted sub-type, `nil` for clear/opaque.
    /// The theme's accent, not its background: tinting with the surface colour
    /// reads as a slightly darker opaque glass instead of a tinted one.
    var glassTintColor: NSColor? {
        guard glassStyle == .tinted else { return nil }
        return GlyphStrip.color(for: "focused", theme: themeStore.named(effectiveThemeName)) ?? solidColor
    }

    /// Tinted glass gets the theme-blended hairline; clear/opaque stay neutral.
    var glassEdgeColor: NSColor {
        glassStyle == .tinted ? strokeColor : GlyphStrip.neutralGlassStrokeColor()
    }

    /// The hover highlight always uses the theme's `focused` role.
    var hoverColor: NSColor {
        GlyphStrip.color(for: "focused", theme: themeStore.named(effectiveThemeName)) ?? .labelColor
    }

    static func attributedRun(
        for run: GlyphStrip.Run,
        strip: GlyphStripConfig,
        theme: AppTheme,
        style: GlyphStrip.RunStyle,
        face: AppGlyphFont?
    ) -> NSAttributedString {
        let indexSize = CGFloat(strip.indexSize)
        let text: String
        let font: NSFont
        switch run {
        case .index(let value):
            text = value
            font = .systemFont(ofSize: indexSize)
        case .app(let value):
            text = value
            font = appFont(size: CGFloat(strip.iconSize), face: face)
        case .nativeIcon(_, _, let fallback):
            // The image (when resolved) blits at draw time; the fallback
            // glyph carries the colour and line metrics for both paths.
            text = fallback
            font = appFont(size: CGFloat(strip.iconSize), face: face)
        case .overflow(let count):
            text = "+\(count)"
            font = .systemFont(ofSize: indexSize)
        case .placeholder:
            text = GlyphStrip.placeholderGlyph
            font = .systemFont(ofSize: indexSize)
        case .separator:
            text = "|"
            font = .systemFont(ofSize: indexSize)
        case .add:
            text = "+"
            font = .boldSystemFont(ofSize: indexSize + 2)
        }
        let color = GlyphStrip.color(for: style.colorName, theme: theme) ?? .labelColor
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color.withAlphaComponent(style.alpha)
        ])
    }

    static var horizontalPadding: CGFloat { segmentPadding }

    private static var didLogUnresolvedFace = false

    /// Render path must agree with metadata: the face comes from the parsed
    /// file, never from a family-name lookup that could resolve a different
    /// installed release and paint another app's icon.
    fileprivate static func appFont(size: CGFloat, face: AppGlyphFont?) -> NSFont {
        if let face = face?.face(size: size) { return face }
        if !didLogUnresolvedFace {
            didLogUnresolvedFace = true
            NSLog("spacemap/GlyphStrip: sketchybar-app-font face unavailable; falling back to system font")
        }
        return .systemFont(ofSize: size)
    }

    /// Resolved native icon for a run, or nil on a miss (fallback paints).
    /// Non-native runs always read nil: only `rebuildRuns` writes images.
    func nativeIcon(segment offset: Int, run index: Int) -> NSImage? {
        guard nativeIcons.indices.contains(offset),
              nativeIcons[offset].indices.contains(index) else { return nil }
        return nativeIcons[offset][index]
    }
}
