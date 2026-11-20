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

    /// VoiceOver label for one painted segment. Pure so the wording can be
    /// asserted without AppKit state; the view supplies the same segments.
    static func accessibilityLabel(
        for segment: Segment,
        focused: Bool,
        spaceName: String? = nil
    ) -> String {
        if segment.runs == [.add] {
            return NSLocalizedString("Add space", comment: "VoiceOver action for the glyph strip add button")
        }
        if segment.runs == [.separator] {
            return NSLocalizedString("Display separator", comment: "VoiceOver label for a display boundary in the glyph strip")
        }

        var parts: [String] = []
        if let index = segment.spaceIndex {
            var space = String(
                format: NSLocalizedString("Space %d", comment: "VoiceOver label for a space number"),
                index
            )
            if let spaceName, !spaceName.isEmpty {
                space += " — \(spaceName)"
            }
            parts.append(space)
        }
        let appNames = segment.runs.compactMap { run -> String? in
            switch run {
            case .app(let name): return name
            case .nativeIcon(let app, _, _): return app
            default: return nil
            }
        }
        if !appNames.isEmpty {
            parts.append(appNames.joined(separator: ", "))
        } else if segment.runs.contains(.placeholder) {
            parts.append(NSLocalizedString("Empty", comment: "VoiceOver label for an empty space"))
        }
        for run in segment.runs {
            if case .overflow(let count) = run {
                parts.append(String(
                    format: NSLocalizedString("%d more windows", comment: "VoiceOver overflow count for a space"),
                    count
                ))
            }
        }
        if focused {
            parts.append(NSLocalizedString("Current space", comment: "VoiceOver label for the focused space"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Placement

    struct Backdrop: Equatable {
        let rect: CGRect
        /// Already capped to half the rect's height, so a big configured
        /// radius renders as a pill and 0 renders as a square bar.
        let cornerRadius: CGFloat
    }

    /// Placement of the strip inside the menu bar row.
    ///
    /// - Parameters:
    ///   - menuBarRow: the full top row of the target display.
    ///   - leftNotchArea: `NSScreen.auxiliaryTopLeftArea`, or `nil` on a display
    ///     with no notch (AppKit reports an empty rect there).
    ///   - rightNotchArea: `NSScreen.auxiliaryTopRightArea`, likewise `nil`.
    ///   - margin: gap between the strip and the notch edge, in points.
    ///   - screenFrame: the display's whole frame for `.custom`, which may sit
    ///     anywhere on screen. Anchored positions ignore it.
    ///   - xFraction: free-placement X as a fraction of the screen's spare
    ///     width, only used by `.custom`. 0 is the left edge, 1 the right edge;
    ///     the same fraction `HUDPosition.custom` stores for the HUD.
    ///   - yFraction: free-placement Y as the same kind of fraction. AppKit
    ///     grows upward, so 0 is the bottom edge and 1 the top edge.
    ///
    /// Anchored positions centre vertically in the menu bar row. `.custom`
    /// clamps to the whole screen instead, so a dragged strip can reach any
    /// row.
    ///
    /// Overflow: content wider than the row shrinks to the row width,
    /// left-aligned at `menuBarRow.minX`. Clamping x alone would hang the
    /// excess off the right edge.
    static func frame(
        contentSize: CGSize,
        menuBarRow: CGRect,
        screenFrame: CGRect? = nil,
        leftNotchArea: CGRect?,
        rightNotchArea: CGRect?,
        position: GlyphStripPosition,
        margin: CGFloat,
        xFraction: Double = 0.5,
        yFraction: Double = 0.5
    ) -> CGRect {
        // `.custom` may sit anywhere on the display, so it uses the whole
        // screen and measures in fractions of it. Anchored positions stay in
        // the menu bar row.
        let area = position == .custom ? (screenFrame ?? menuBarRow) : menuBarRow
        let height = position == .custom ? min(contentSize.height, area.height) : min(contentSize.height, menuBarRow.height)
        let width = min(max(contentSize.width, 0), area.width)
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
            let spare = max(area.width - width, 0)
            x = area.minX + spare * CGFloat(xFraction)
        }
        // Never let the strip hang off the side of its area.
        let clampedX = min(max(x, area.minX), max(area.minX, area.maxX - width))
        let y: CGFloat
        if position == .custom {
            let spare = max(area.height - height, 0)
            let desired = area.minY + spare * CGFloat(yFraction)
            y = min(max(desired, area.minY), max(area.minY, area.maxY - height))
        } else {
            // Vertical centring inside the row.
            y = menuBarRow.minY + (menuBarRow.height - height) / 2
        }
        return CGRect(x: clampedX, y: y, width: width, height: height)
    }

    /// Vertical placement rects, laid out top-down inside `bounds` from the
    /// height of each segment. The first height owns the top slot, so a
    /// vertical strip reads in space order from the top edge.
    static func verticalSlots(heights: [CGFloat], in bounds: CGRect) -> [CGRect] {
        var top = bounds.maxY
        return heights.map { height in
            let slot = CGRect(x: bounds.minX, y: top - height, width: bounds.width, height: height)
            top -= height
            return slot
        }
    }

    /// Column count needed when a vertical strip is taller than `available`.
    static func verticalColumnCount(totalHeight: CGFloat, available: CGFloat) -> Int {
        guard totalHeight > available, available > 0 else { return 1 }
        return Int(ceil(totalHeight / available))
    }

    /// Slots for a vertical strip that may wrap into several columns. Each
    /// column fills top-down; a segment that would pass the bottom starts the
    /// next column, so the strip grows sideways instead of off screen.
    static func verticalColumnSlots(
        heights: [CGFloat],
        in bounds: CGRect,
        available: CGFloat,
        columnGap: CGFloat
    ) -> [CGRect] {
        guard !heights.isEmpty, available > 0 else { return [] }
        let columns = verticalColumnCount(totalHeight: heights.reduce(0, +), available: available)
        let width = max((bounds.width - columnGap * CGFloat(columns - 1)) / CGFloat(columns), 1)
        var column = 0
        var top = bounds.maxY
        var slots: [CGRect] = []
        for height in heights {
            if top - height < bounds.minY - 0.5, column + 1 < columns {
                column += 1
                top = bounds.maxY
            }
            let x = bounds.minX + CGFloat(column) * (width + columnGap)
            slots.append(CGRect(x: x, y: top - height, width: width, height: height))
            top -= height
        }
        return slots
    }

    /// One rect per stacked line, filled from the top of `slot` downward.
    /// `indexGap` separates the number line from the first icon line;
    /// `iconGap` separates icon lines from each other.
    static func stackedLines(
        count: Int,
        lineHeight: CGFloat,
        indexGap: CGFloat,
        iconGap: CGFloat,
        in slot: CGRect
    ) -> [CGRect] {
        guard count > 0, lineHeight > 0 else { return [] }
        var top = slot.maxY
        return (0..<count).map { index in
            if index > 0 {
                top -= index == 1 ? indexGap : iconGap
            }
            let rect = CGRect(x: slot.minX, y: top - lineHeight, width: slot.width, height: lineHeight)
            top = rect.minY
            return rect
        }
    }

    /// The `.custom` fractions that reproduce `frame` inside `area` — the
    /// inverse of `frame(...)` for the geometry it was given. `area` is the
    /// menu bar row for anchored placements and the whole screen for `.custom`.
    /// Used to turn a dragged panel frame back into config keys.
    ///
    /// Nil when the strip fills the area on an axis (no spare travel), matching
    /// `HUDDisplay.normalizedPosition`: the caller keeps its stored fractions
    /// instead of dividing by zero.
    static func customFractions(for frame: CGRect, area: CGRect) -> (x: Double, y: Double)? {
        let rangeX = area.width - frame.width
        let rangeY = area.height - frame.height
        guard rangeX > 0, rangeY > 0 else { return nil }
        return (
            Double((frame.minX - area.minX) / rangeX),
            Double((frame.minY - area.minY) / rangeY)
        )
    }

    /// Pointer travel, in screen points, that separates a click from a drag.
    static let dragThreshold: CGFloat = 4

    /// True once the pointer has moved `threshold` points from the press — the
    /// strip should follow the pointer instead of firing the press's click.
    static func exceedsDragThreshold(_ delta: CGVector, threshold: CGFloat = dragThreshold) -> Bool {
        max(abs(delta.dx), abs(delta.dy)) >= threshold
    }

    /// A drag only performs a drop when it reaches another space. Ending on the
    /// pressed space or outside every target is a click, so a slight pointer
    /// wobble cannot eat the click.
    static func dragResolvesToDrop(hudTarget: Int?, targetSpace: Int?, sourceSpace: Int?) -> Bool {
        if hudTarget != nil { return true }
        guard let targetSpace, let sourceSpace else { return false }
        return targetSpace != sourceSpace
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

    // MARK: - Render layout

    /// Segments whose painted content changed. A first build animates nothing;
    /// a count change animates the visible set because indices shifted.
    static func changedSegments(
        previous: [Segment]?,
        current: [Segment]
    ) -> [Int] {
        guard let previous else { return [] }
        guard previous.count == current.count else { return Array(current.indices) }
        return current.indices.filter { previous[$0] != current[$0] }
    }

    /// One slot per segment across `content`, each `widths[index]` wide and as
    /// tall as the content box. Used by both surfaces: the panel insets its
    /// content box, the status item centres the same slots in its button.
    static func horizontalSlots(widths: [CGFloat], in content: CGRect) -> [CGRect] {
        var x = content.minX
        return widths.map { width in
            let slot = CGRect(x: x, y: content.minY, width: width, height: content.height)
            x += width
            return slot
        }
    }

    /// Where runs sit inside their slot for one render.
    enum RunPlacement: Equatable {
        /// Left to right inside the slot, `inset` points from its leading edge.
        case inline(inset: CGFloat)
        /// Every run of a segment on one line, centred on the slot.
        case centered
        /// One run per line from `LayoutInput.lines`.
        case stacked
    }

    /// What only AppKit can measure for one render; `layout(...)` derives the
    /// frames and window mapping from it.
    struct LayoutInput {
        /// Hit slot per segment, in the drawing layer's coordinates.
        var slots: [CGRect]
        /// Measured advance of every run, parallel to the segments and their runs.
        var advances: [[CGFloat]]
        /// Gap before each run, parallel to `advances`.
        var gaps: [[CGFloat]]
        var placement: RunPlacement = .inline(inset: 0)
        /// One line per run for `.stacked`, parallel to `advances`.
        var lines: [[CGRect]] = []
        /// Ink-centre x per run for `.stacked`; nil centres the advance box.
        var inkCenters: [[CGFloat?]] = []
    }

    /// One painted run: its frame and the windows a drag from it carries.
    /// Every draw and hit test reads these instead of re-deriving them.
    struct RunLayout: Equatable {
        let frame: CGRect
        let windows: [YabaiWindow]
    }

    /// The complete description of one render: the hit slot of every segment
    /// and the painted frame and window mapping of every run.
    struct SegmentLayout: Equatable {
        let slots: [CGRect]
        let runs: [[RunLayout]]

        /// Slot of `segment`, or nil when the layout has no such segment.
        func slot(_ segment: Int) -> CGRect? {
            slots.indices.contains(segment) ? slots[segment] : nil
        }

        /// Segment directly under `point`.
        func segment(at point: CGPoint) -> Int? {
            slots.firstIndex { $0.contains(point) }
        }

        /// Run directly under `point`, scanning every segment.
        func run(at point: CGPoint) -> (segment: Int, run: Int)? {
            for (segment, frames) in runs.enumerated() {
                if let run = frames.firstIndex(where: { $0.frame.contains(point) }) {
                    return (segment, run)
                }
            }
            return nil
        }

        /// Run directly under `point` within `segment`; nil outside every run.
        func run(at point: CGPoint, in segment: Int) -> Int? {
            guard runs.indices.contains(segment) else { return nil }
            return runs[segment].firstIndex { $0.frame.contains(point) }
        }
    }

    /// Assembles one render. `input.advances`, `input.gaps`, and the
    /// per-segment `input.lines` are all parallel to `segments` and their runs.
    static func layout(
        segments: [Segment],
        state: GridState?,
        options: Options,
        input: LayoutInput
    ) -> SegmentLayout {
        let runs = segments.enumerated().map { offset, segment -> [RunLayout] in
            // No slot means no paint and no hit area, matching a view that has
            // not been laid out yet.
            guard input.slots.indices.contains(offset) else { return [] }
            let slot = input.slots[offset]
            let frames = runFrames(
                in: slot,
                advances: input.advances.indices.contains(offset) ? input.advances[offset] : [],
                gaps: input.gaps.indices.contains(offset) ? input.gaps[offset] : [],
                placement: input.placement,
                lines: input.lines.indices.contains(offset) ? input.lines[offset] : [],
                inkCenters: input.inkCenters.indices.contains(offset) ? input.inkCenters[offset] : []
            )
            let windows = runWindows(for: segment, in: state, options: options)
            return frames.indices.map { index in
                RunLayout(
                    frame: frames[index],
                    windows: windows.indices.contains(index) ? windows[index] : []
                )
            }
        }
        return SegmentLayout(slots: input.slots, runs: runs)
    }

    /// Painted frame of every run in `slot`.
    private static func runFrames(
        in slot: CGRect,
        advances: [CGFloat],
        gaps: [CGFloat],
        placement: RunPlacement,
        lines: [CGRect],
        inkCenters: [CGFloat?]
    ) -> [CGRect] {
        if case .stacked = placement {
            guard lines.count == advances.count else { return [] }
            return advances.indices.map { index in
                let line = lines[index]
                let inkCenter = inkCenters.indices.contains(index) ? inkCenters[index] : nil
                let x = inkCenter ?? line.midX - advances[index] / 2
                return CGRect(x: x, y: line.minY, width: advances[index], height: line.height)
            }
        }
        var x: CGFloat
        switch placement {
        case .inline(let inset):
            x = slot.minX + inset
        case .centered, .stacked:
            let inner = advances.indices.reduce(CGFloat(0)) { total, index in
                // Placement skips the gap before run 0, so the centring sum
                // must skip it too.
                let gap = index > 0 && gaps.indices.contains(index) ? gaps[index] : 0
                return total + advances[index] + gap
            }
            x = slot.midX - inner / 2
        }
        return advances.indices.map { index in
            if index > 0, gaps.indices.contains(index) { x += gaps[index] }
            let frame = CGRect(x: x, y: slot.minY, width: advances[index], height: slot.height)
            x += advances[index]
            return frame
        }
    }

    /// Windows behind each run of `segment`: an icon run carries its windows,
    /// every other run none. Dedupe and the icon cap come from `options`, so the
    /// mapping cannot drift from the runs `segments(for:options:font:)` built.
    static func runWindows(
        for segment: Segment,
        in state: GridState?,
        options: Options
    ) -> [[YabaiWindow]] {
        guard let spaceIndex = segment.spaceIndex, let state else {
            return Array(repeating: [], count: segment.runs.count)
        }
        let all = windows(forSpace: spaceIndex, in: state)
        let shown = windowsToShow(all, dedupe: options.dedupeAppsPerSpace)
        let limit = options.maxIconsPerSpace == 0 ? shown.count : min(options.maxIconsPerSpace, shown.count)
        let icons = Array(shown.prefix(limit))
        var iconOffset = 0
        return segment.runs.map { run in
            switch run {
            case .app, .nativeIcon:
                guard icons.indices.contains(iconOffset) else {
                    iconOffset += 1
                    return []
                }
                let icon = icons[iconOffset]
                iconOffset += 1
                return draggedWindows(
                    for: icon,
                    allWindows: all,
                    dedupe: options.dedupeAppsPerSpace
                )
            default:
                return []
            }
        }
    }

    static let placeholderGlyph = "—"

    /// Layout suffix: bsp draws bare, float and stack get a letter.
    static func layoutSuffix(
        forSpaceType type: String?,
        showBSP: Bool = true,
        showStack: Bool = true,
        showFloat: Bool = true
    ) -> String {
        switch type {
        case "float": return showFloat ? "f" : ""
        case "stack": return showStack ? "s" : ""
        case "bsp": return showBSP ? "b" : ""
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

    /// Windows a dragged icon represents. Dedupe means one icon per app, so
    /// the drag carries every window of that app; otherwise it carries the
    /// single window the icon was built from.
    static func draggedWindows(
        for icon: YabaiWindow,
        allWindows: [YabaiWindow],
        dedupe: Bool
    ) -> [YabaiWindow] {
        dedupe ? allWindows.filter { $0.app == icon.app } : [icon]
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

    /// Longest name a strip label shows. Longer names truncate with `…` so one
    /// user-typed name cannot stretch the whole strip.
    private static let spaceNameCharacterLimit = 12

    /// Name to show for one space, or nil when the style hides names, the
    /// space has no entry, or the entry is blank after trimming. The painted
    /// label and the VoiceOver label both read names through here so they
    /// agree on which names exist.
    static func spaceName(for spaceIndex: Int, options: Options) -> String? {
        guard options.spaceLabelStyle != .numbers,
              let name = options.spaceNames[spaceIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Label text for one space's leading run. `.numbers` is exactly today's
    /// index+suffix. `.names` shows the profile name, or the number when the
    /// space has no name. `.both` prefixes the name with the number.
    private static func spaceLabelText(
        index: Int,
        suffix: String,
        options: Options
    ) -> String {
        let number = "\(index)\(suffix)"
        guard let name = spaceName(for: index, options: options) else {
            return number
        }
        let trimmed = name.count > spaceNameCharacterLimit
            ? String(name.prefix(spaceNameCharacterLimit)) + "…"
            : name
        return options.spaceLabelStyle == .both ? "\(number) \(trimmed)" : trimmed
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
            let suffix = options.showLayoutSuffix
                ? layoutSuffix(
                    forSpaceType: layoutType,
                    showBSP: options.showBSPLayoutBadge,
                    showStack: options.showStackLayoutBadge,
                    showFloat: options.showFloatLayoutBadge
                )
                : ""
            runs.append(.index(spaceLabelText(index: index, suffix: suffix, options: options)))
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
                // No glyph font or no ligature: use the app's real Finder
                // icon. Initials remain the text fallback if the image cannot
                // resolve, so the segment never becomes a hole.
                runs.append(.nativeIcon(
                    app: window.app,
                    pid: window.pid.flatMap { Int32(exactly: $0) },
                    glyph: AppGlyphFont.initials(forApp: window.app)
                ))
            }
        }
        let overflow = shown.count - limit
        if overflow > 0 { runs.append(.overflow(overflow)) }
        return runs
    }
}
