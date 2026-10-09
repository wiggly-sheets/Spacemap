import AppKit
import Foundation

/// Compact menu-bar strip: one segment per yabai space plus an optional `+`.
///
/// Pure model — the panel and its view live in `GlyphStripPanel.swift`.
enum GlyphStrip {

    /// What a click on a segment resolves to. `focusSpace` and `destroySpace`
    /// carry an index; the window-scoped commands do not.
    enum Command: Equatable {
        case focusSpace(Int)
        case destroySpace(Int)
        case moveFocusedWindowToSpace(Int)
        case mergeIntoSpace(Int)
        case toggleFullscreen
        case floatWindow
        case balanceWindows
        case createSpace
    }

    enum Run: Equatable {
        /// `index`, `overflow` and `separator` text use the system font; app
        /// glyphs use sketchybar-app-font.
        case index(String)
        case app(String)
        /// Native app icon: `app` (+`pid` fast path) resolves the NSImage via
        /// IconCache, `glyph` is the sbar fallback painted on a miss.
        case nativeIcon(app: String, pid: Int32?, glyph: String)
        case overflow(Int)
        case placeholder
        case separator
        case add
    }

    struct Segment: Equatable {
        /// nil for the separator and add segments, which have no space.
        let spaceIndex: Int?
        let runs: [Run]
    }

    // MARK: - Placement

    /// The shape a resolved backdrop asks the view to fill. Kept separate from
    /// `GlyphStripShape` so the drawn geometry can be asserted in tests without
    /// inspecting AppKit state.
    enum BackdropShape: Equatable {
        /// Draw nothing.
        case none
        /// Fully rounded ends — a capsule.
        case capsule
        /// Square ends — one continuous bar.
        case bar
        /// Rounded rectangle with an explicit radius, already capped to half the
        /// rect's height.
        case rounded(CGFloat)
    }

    struct Backdrop: Equatable {
        let shape: BackdropShape
        let rect: CGRect

        /// Corner radius the native glass view needs for this backdrop: a
        /// capsule rounds to half the height, a rounded rect carries its
        /// capped radius, bar/none need no rounding.
        var glassCornerRadius: CGFloat {
            switch shape {
            case .capsule:
                return rect.height / 2
            case .rounded(let radius):
                return radius
            case .bar, .none:
                return 0
            }
        }
    }

    /// Placement of the strip inside the menu bar row.
    ///
    /// - Parameters:
    ///   - menuBarRow: the full top row of the target display.
    ///   - leftNotchArea: `NSScreen.auxiliaryTopLeftArea`, or `nil` on a display
    ///     with no notch (AppKit reports an empty rect there).
    ///   - rightNotchArea: `NSScreen.auxiliaryTopRightArea`, likewise `nil`.
    ///   - margin: gap between the strip and the notch edge, in points.
    ///   - yOffset: vertical nudge in screen-reading terms. **Positive moves the
    ///     strip DOWN, into the screen interior.** AppKit's origin is bottom-left,
    ///     so the subtraction is deliberate rather than a naive `+`.
    ///   - xOffset: horizontal offset from `menuBarRow.minX`, only used by
    ///     `.custom`; the other positions anchor to the notch or row edges.
    ///
    /// Unlike `x`, `yOffset` is not clamped back into the row: the panel is
    /// ordered at `.statusBar` level and a user who asks to nudge the strip down
    /// gets it moved. Clamping would silently ignore the one thing the key is
    /// for, and the panel is only a few points tall, so the worst case is that it
    /// briefly overlaps the first row of menu bar items.
    ///
    /// Overflow: content wider than the row shrinks to the row width,
    /// left-aligned at `menuBarRow.minX`. Clamping x alone would hang the
    /// excess off the right edge.
    static func frame(
        contentSize: CGSize,
        menuBarRow: CGRect,
        leftNotchArea: CGRect?,
        rightNotchArea: CGRect?,
        position: GlyphStripPosition,
        margin: CGFloat,
        yOffset: CGFloat = 0,
        xOffset: CGFloat = 0
    ) -> CGRect {
        let height = min(contentSize.height, menuBarRow.height)
        let width = min(max(contentSize.width, 0), menuBarRow.width)
        let x: CGFloat
        switch position {
        case .leftOfNotch:
            if let left = leftNotchArea, !left.isEmpty {
                // `leftNotchArea` is the unobscured strip to the LEFT of the
                // notch, so its maxX is the notch's left edge. The strip belongs
                // to that side: its right edge goes there, otherwise it renders
                // inside the camera housing.
                x = left.maxX - margin - width
            } else {
                x = menuBarRow.minX + margin
            }
        case .rightOfNotch:
            if let right = rightNotchArea, !right.isEmpty {
                x = right.minX + margin
            } else {
                x = menuBarRow.maxX - margin - width
            }
        case .center:
            let area = notchArea(left: leftNotchArea, right: rightNotchArea, menuBarRow: menuBarRow)
            x = area.midX - width / 2
        case .custom:
            x = menuBarRow.minX + xOffset
        }
        // Never let the strip hang off the side of the row.
        let clampedX = min(max(x, menuBarRow.minX), max(menuBarRow.minX, menuBarRow.maxX - width))
        return CGRect(
            x: clampedX,
            // Vertical centring inside the row, then the user's nudge. AppKit y
            // grows upward, so subtracting is what moves the strip DOWN.
            // yOffset 0 is centered: positive moves down, negative moves up.
            y: menuBarRow.minY + (menuBarRow.height - height) / 2 - yOffset,
            width: width,
            height: height
        )
    }

    /// The `.custom` offsets that reproduce `frame` relative to `menuBarRow` —
    /// the inverse of `frame(...)` for the geometry it was given. Used to turn
    /// a dragged panel frame back into config keys.
    ///
    /// `xOffset` is an `Int` in config, so x is rounded; replaying the result
    /// can land up to half a point from `frame`, which `frame`'s own row clamp
    /// absorbs. `yOffset` uses `frame.height` because that is the height
    /// `frame(...)` placed the strip at (content height clamped to the row).
    static func customOffsets(for frame: CGRect, menuBarRow: CGRect) -> (xOffset: Int, yOffset: Double) {
        let x = frame.minX - menuBarRow.minX
        let y = menuBarRow.minY + (menuBarRow.height - frame.height) / 2 - frame.minY
        return (Int(x.rounded()), y)
    }

    /// Pointer travel, in screen points, that separates a click from a drag.
    static let dragThreshold: CGFloat = 4

    /// True once the pointer has moved `threshold` points from the press — the
    /// strip should follow the pointer instead of firing the press's click.
    static func exceedsDragThreshold(_ delta: CGVector, threshold: CGFloat = dragThreshold) -> Bool {
        max(abs(delta.dx), abs(delta.dy)) >= threshold
    }

    /// The gap between the two notch areas, or the whole row when the display
    /// has no notch.
    private static func notchArea(left: CGRect?, right: CGRect?, menuBarRow: CGRect) -> CGRect {
        guard let left, !left.isEmpty, let right, !right.isEmpty else { return menuBarRow }
        return CGRect(
            x: left.maxX,
            y: menuBarRow.minY,
            width: max(right.minX - left.maxX, 0),
            height: menuBarRow.height
        )
    }

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

    // MARK: - Backgrounds

    /// Vertical inset so the fill does not touch the very top and bottom edges
    /// of the menu bar row. Doubles as the padding that keeps glyphs off the
    /// glass edge. Only applies to the glass mask; solid fills use full height.
    static let backdropVerticalInset: CGFloat = 2

    /// Alpha of the hover highlight, which always composites on top of the base
    /// backdrop.
    static let hoverHighlightOpacity: CGFloat = 0.18

    /// The layer drawn behind the whole strip, resolved from the configured
    /// shape. The material decides whether that layer exists at all — `.none`
    /// draws nothing, so callers guard on it before asking.
    ///
    /// `.pill` resolves to a capsule covering the full content width. `.bar` is
    /// one continuous square-ended bar. `.roundedRect` rounds at `cornerRadius`
    /// (capped to half the height, so an oversized radius collapses to a
    /// capsule) and is the shape the glass clips to.
    ///
    /// - Parameter insetForGlass: When true (default), applies a small vertical
    ///   inset so the glass mask doesn't touch the menu bar edges. Set to false
    ///   for solid fills that should span the full panel height.
    static func backdrop(
        for shape: GlyphStripShape,
        bounds: CGRect,
        cornerRadius: CGFloat,
        insetForGlass: Bool = true
    ) -> Backdrop {
        let rect = bounds.insetBy(dx: 0, dy: insetForGlass ? backdropVerticalInset : 0)
        switch shape {
        case .none:
            return Backdrop(shape: .none, rect: rect)
        case .pill:
            return Backdrop(shape: .capsule, rect: rect)
        case .bar:
            return Backdrop(shape: .bar, rect: rect)
        case .roundedRect:
            return Backdrop(shape: .rounded(min(cornerRadius, rect.height / 2)), rect: rect)
        }
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
        return Backdrop(shape: .rounded(min(cornerRadius, rect.height / 2)), rect: rect)
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

    /// Native glass tint alpha for an amount: `nil` at/below the clear
    /// threshold (ultraclear, no tint), else `0.08 + 0.30*t`. No public blur
    /// radius API exists, so tint + fill overlay carry the whole effect.
    static func glassTintAlpha(for amount: Double) -> Double? {
        guard amount > GlyphStripGlassAmount.clearThreshold else { return nil }
        return 0.08 + 0.30 * amount
    }

    /// Flat fill overlay opacity for an amount: `0.10 + 0.55*t`. Painted under
    /// the glyphs on the glass path; view alpha stays 1.0.
    static func glassFillOpacity(for amount: Double) -> Double {
        0.10 + 0.55 * amount
    }

    /// Tint-off hairline: achromatic mid-gray. The themed stroke blends the
    /// theme's text/background hues, which would edge a tint-off strip in
    /// theme colour.
    static func neutralGlassStrokeColor() -> NSColor { NSColor(white: 0.5, alpha: 1) }

    /// Fallback `NSVisualEffectView` material. Tint-on keeps the saturated
    /// `.popover`/`.menu` pair; tint-off uses `.headerView`, the least
    /// wallpaper-saturated stock material, so no theme or wallpaper warmth
    /// leaks in. Tint-off alpha is always 1.0 (set at the call site): anything
    /// lower bleeds the warm menu bar through the sibling blur view, and that
    /// bleed is what made the yellow worse toward the slider max.
    static func glassFallbackMaterial(for amount: Double, useThemeTint: Bool) -> NSVisualEffectView.Material {
        guard useThemeTint else { return .headerView }
        return glassUsesPopoverMaterial(for: amount) ? .popover : .menu
    }

    /// Fallback `NSVisualEffectView` recipe: saturated `.popover` at/above the
    /// centre notch, lighter `.menu` below. Keeps the legacy sides
    /// (`blurred` 0.5 -> popover, `transparent` 0.15 -> menu).
    static func glassUsesPopoverMaterial(for amount: Double) -> Bool {
        amount >= GlyphStripGlassAmount.default
    }

    /// Fills a resolved backdrop, or strokes it for the glass edge. The only
    /// side-effecting part of the drawing pipeline; everything above it is pure
    /// and testable.
    static func fill(_ backdrop: Backdrop, color: NSColor, opacity: CGFloat) {
        color.withAlphaComponent(opacity).setFill()
        switch backdrop.shape {
        case .none:
            return
        case .capsule:
            // Fully rounded ends, not an ellipse: the radius is half the height,
            // which is what makes a wide capsule read as a pill.
            NSBezierPath(
                roundedRect: backdrop.rect,
                xRadius: backdrop.rect.height / 2,
                yRadius: backdrop.rect.height / 2
            ).fill()
        case .bar:
            backdrop.rect.fill()
        case .rounded(let radius):
            NSBezierPath(
                roundedRect: backdrop.rect,
                xRadius: radius,
                yRadius: radius
            ).fill()
        }
    }

    /// 1px hairline inset by half its width so it lands fully inside `backdrop`.
    static func stroke(_ backdrop: Backdrop, color: NSColor, opacity: CGFloat) {
        guard backdrop.shape != .none else { return }
        let inset = backdrop.rect.insetBy(dx: 0.5, dy: 0.5)
        guard inset.width > 0, inset.height > 0 else { return }
        color.withAlphaComponent(opacity).setStroke()
        let lineWidth: CGFloat = 1
        let path: NSBezierPath
        switch backdrop.shape {
        case .none:
            return
        case .bar:
            path = NSBezierPath(rect: inset)
        case .capsule:
            path = NSBezierPath(
                roundedRect: inset,
                xRadius: inset.height / 2,
                yRadius: inset.height / 2
            )
        case .rounded(let radius):
            path = NSBezierPath(
                roundedRect: inset,
                xRadius: max(radius - 0.5, 0),
                yRadius: max(radius - 0.5, 0)
            )
        }
        path.lineWidth = lineWidth
        path.stroke()
    }

    /// The subset of `GlyphStripConfig` that changes what segments contain.
    /// Snapshotted once per refresh so segment building never reads config.
    struct Options: Equatable {
        var showSpaceNumbers = true
        var showLayoutSuffix = true
        var showAppIcons = true
        var iconSource: GlyphStripIconSource = .sbarFont
        var dedupeAppsPerSpace = true
        var maxIconsPerSpace = 8
        var showDisplaySeparators = true
        var showAddSpaceButton = true
        var showPlaceholders = true
        var iconSpacing: Double = 3

        init(_ config: GlyphStripConfig) {
            showSpaceNumbers = config.showSpaceNumbers
            showLayoutSuffix = config.showLayoutSuffix
            showAppIcons = config.showAppIcons
            iconSource = config.iconSource
            dedupeAppsPerSpace = config.dedupeAppsPerSpace
            maxIconsPerSpace = max(0, config.maxIconsPerSpace)
            showDisplaySeparators = config.showDisplaySeparators
            showAddSpaceButton = config.showAddSpaceButton
            showPlaceholders = config.showPlaceholders
            iconSpacing = config.iconSpacing
        }
    }

    static let placeholderGlyph = "—"

    /// Layout suffix: bsp draws bare, float and stack get a letter.
    static func layoutSuffix(forSpaceType type: String?) -> String {
        switch type {
        case "float": return "f"
        case "stack": return "s"
        default: return ""
        }
    }

    static func segments(
        for state: GridState,
        options: Options = Options(GlyphStripConfig.default),
        font: AppGlyphFont? = nil
    ) -> [Segment] {
        // Every space from every display goes on the one bar — matching the
        // SketchyBar config this replaces, which set `ignore_association = true`
        // precisely so secondary-display spaces still rendered. Nothing here
        // filters by display.
        //
        // yabai space indexes are global and NOT contiguous — deleting a space
        // leaves a hole — so iterate the spaces yabai actually reported instead
        // of a 1...maxSpaces range, which used to emit a ghost segment for every
        // index past the last real one. Order is by global index, not renumbered
        // per display.
        let spaces = state.spaces.sorted { $0.index < $1.index }
        var segments: [Segment] = []
        var previousSpace: YabaiSpace?

        for space in spaces {
            // Separators compare consecutive RENDERED spaces, never
            // `index + 1`, so a gap in the index sequence cannot shift them.
            if options.showDisplaySeparators,
               let previousSpace,
               space.display != previousSpace.display {
                segments.append(Segment(spaceIndex: nil, runs: [.separator]))
            }
            previousSpace = space
            segments.append(
                Segment(
                    // The real yabai index, so focus/destroy target the space the
                    // user clicked rather than the segment's position in the strip.
                    spaceIndex: space.index,
                    runs: spaceRuns(
                        index: space.index,
                        layoutType: space.type,
                        windows: windows(forSpace: space.index, in: state),
                        options: options,
                        font: font
                    )
                )
            )
        }

        if options.showAddSpaceButton {
            segments.append(Segment(spaceIndex: nil, runs: [.add]))
        }
        return segments
    }

    /// Extra horizontal advance to insert *before* each run, same length as
    /// `runs` so the panel can use one array for both measuring and drawing.
    ///
    /// Two independent gaps, keyed on position within the segment because the
    /// space index and the initials fallback are both `.index` runs:
    /// - `indexPadding` between the leading index run and the first app run or placeholder.
    /// - `iconSpacing` between every later pair of app runs and before `+N` overflow.
    ///
    /// Separators and the add button are their own segments, so neither picks up a gap.
    static func interRunGaps(
        for runs: [Run],
        iconSpacing: CGFloat,
        indexPadding: CGFloat
    ) -> [CGFloat] {
        runs.indices.map { offset in
            guard offset > 0 else { return 0 }
            switch runs[offset] {
            case .separator, .add:
                return 0
            case .placeholder:
                return indexPadding
            case .overflow:
                return iconSpacing
            case .app, .index, .nativeIcon:
                // Only the leading index run gets padded away from. A segment that starts
                // with an icon has no index, so its first gap is plain iconSpacing.
                if offset == 1, case .index = runs[0] { return indexPadding }
                return iconSpacing
            }
        }
    }

    static func windows(forSpace index: Int, in state: GridState) -> [YabaiWindow] {
        let visible = state.windows(forSpace: index).filter {
            $0.shouldDisplay(showExtraWindows: state.config.showExtraWindows)
        }
        return YabaiWindow.inReadingOrder(visible)
    }

    /// Windows reduced to one entry per app when deduping is on, keeping the
    /// first (leftmost) window of each app in reading order.
    static func windowsToShow(_ windows: [YabaiWindow], dedupe: Bool) -> [YabaiWindow] {
        guard dedupe else { return windows }
        var seen = Set<String>()
        return windows.filter { seen.insert($0.app).inserted }
    }

    /// Maps a configured click action onto a concrete command. Returns nil when
    /// the action is disabled or cannot apply to the clicked segment.
    static func command(
        for action: GlyphStripAction,
        spaceIndex: Int?,
        focusedSpaceIndex: Int?
    ) -> Command? {
        switch action {
        case .none:
            return nil
        case .focusSpace:
            guard let spaceIndex else { return nil }
            return .focusSpace(spaceIndex)
        case .destroySpace:
            guard let spaceIndex else { return nil }
            return .destroySpace(spaceIndex)
        case .moveWindowHere:
            guard let spaceIndex else { return nil }
            return .moveFocusedWindowToSpace(spaceIndex)
        case .mergeWindows:
            guard let spaceIndex, let focusedSpaceIndex, spaceIndex != focusedSpaceIndex else { return nil }
            return .mergeIntoSpace(spaceIndex)
        case .toggleFullscreen:
            return .toggleFullscreen
        case .floatWindow:
            return .floatWindow
        case .balanceWindows:
            return .balanceWindows
        }
    }

    private static func spaceRuns(
        index: Int,
        layoutType: String?,
        windows: [YabaiWindow],
        options: Options,
        font: AppGlyphFont?
    ) -> [Run] {
        var runs: [Run] = []
        if options.showSpaceNumbers {
            let suffix = options.showLayoutSuffix ? layoutSuffix(forSpaceType: layoutType) : ""
            runs.append(.index("\(index)\(suffix)"))
        }
        if !options.showAppIcons { return runs }

        let shown = windowsToShow(windows, dedupe: options.dedupeAppsPerSpace)
        if shown.isEmpty {
            if options.showPlaceholders { runs.append(.placeholder) }
            return runs
        }

        // maxIconsPerSpace == 0 means unlimited.
        let limit = options.maxIconsPerSpace == 0 ? shown.count : min(options.maxIconsPerSpace, shown.count)
        for window in shown.prefix(limit) {
            if options.iconSource == .nativeIcons {
                // Native first, sbar glyph then initials as the painted
                // fallback. The panel resolves the image at draw time.
                let fallback: String
                if let glyph = font?.glyph(forApp: window.app), !glyph.isEmpty {
                    fallback = glyph
                } else {
                    fallback = AppGlyphFont.initials(forApp: window.app)
                }
                runs.append(.nativeIcon(
                    app: window.app,
                    pid: window.pid.flatMap { Int32(exactly: $0) },
                    glyph: fallback
                ))
            } else if let glyph = font?.glyph(forApp: window.app), !glyph.isEmpty {
                runs.append(.app(glyph))
            } else {
                // The font is missing or has no ligature for this app; initials
                // keep the segment legible instead of leaving a hole.
                runs.append(.index(AppGlyphFont.initials(forApp: window.app)))
            }
        }
        let overflow = shown.count - limit
        if overflow > 0 { runs.append(.overflow(overflow)) }
        return runs
    }
}
