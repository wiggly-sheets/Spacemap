import AppKit

/// Always-visible overlay strip parked in the menu bar row, hugging the notch.
///
/// Borderless `.nonactivatingPanel`, so clicking it never activates Spacemap and
/// yabai's `focus_follows_mouse` keeps the window underneath focused.
final class GlyphStripPanelController: NSObject {

    private static let segmentPadding: CGFloat = 2
    /// Glyph origin drop: y-up coords, so -1 moves ink down 1pt.
    /// Backdrop/glass/hover rects untouched.
    fileprivate static let glyphDrop: CGFloat = 1
    private static let fallbackMenuBarHeight: CGFloat = 24
    /// Notified when displays are added, removed, or resized.
    private static let screenParametersChanged: Notification.Name =
        NSApplication.didChangeScreenParametersNotification

    private let yabaiService: YabaiService
    /// Own coordinator so the strip stays live while the HUD is hidden.
    /// `GridStateCoordinator` already carries the generation guard that stops a
    /// slow older yabai reply from overwriting newer state.
    private let coordinator: GridStateCoordinator
    private lazy var themeService = ThemeService()
    private lazy var font: AppGlyphFont? = {
        let loaded = AppGlyphFont.load()
        if loaded == nil {
            NSLog("spacemap/GlyphStrip: sketchybar-app-font unavailable; falling back to app initials")
        }
        return loaded
    }()

    private var panel: NSPanel?
    /// Drawing layer, retained so refreshes can invalidate it directly.
    private var glyphs: GlyphStripView?
    private var config: GridConfig = .default
    /// Session-only visibility flag driven by the show/hide hotkey. Never
    /// persisted: every launch starts with the strip visible.
    private var hiddenByHotkey = false
    private var segments: [GlyphStrip.Segment] = []
    private var attributedRuns: [[NSAttributedString]] = []
    /// Extra advance before each run, parallel to `attributedRuns`.
    private var runGaps: [[CGFloat]] = []
    private var segmentWidths: [CGFloat] = []
    private var focusedSpaceIndex: Int?
    private var hoveredSegment: Int?
    private var screenObserver: NSObjectProtocol?

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService
        self.coordinator = GridStateCoordinator(yabaiService: yabaiService)
        super.init()
        // A resolution change or a display being unplugged moves the notch and
        // resizes the menu bar row, so the cached frame has to be recomputed.
        screenObserver = NotificationCenter.default.addObserver(
            forName: Self.screenParametersChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyFrame()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - State

    func update(config: GridConfig) {
        self.config = config
        coordinator.config = config
        // Settings changes can carry a new `.smthemes` file or a new effective
        // theme name; reloading here (settings-save frequency, not per refresh)
        // is what keeps this controller's own ThemeService from going stale.
        themeService.reload()
        guard config.glyphStrip.enabled, !hiddenByHotkey else {
            hide()
            return
        }
        // Material/shape/opacity switches keep the same frame, so applyFrame's
        // early-return would leave the old glass/fill on screen. Invalidate
        // both layers here; refresh() then recomputes content.
        panel?.contentView?.needsLayout = true
        panel?.contentView?.layout()
        glyphs?.needsDisplay = true
        refresh()
    }

    /// Toggles the session-only hotkey visibility. Disabled strip: the flag
    /// flips but the strip stays hidden until it is enabled again.
    func toggleVisibilityByHotkey() {
        hiddenByHotkey.toggle()
        if hiddenByHotkey {
            hide()
        } else {
            update(config: config)
        }
    }

    /// Event-driven only — every yabai signal lands here via the shared refresh
    /// path. No polling timer.
    func refresh() {
        guard config.glyphStrip.enabled, !hiddenByHotkey else { return }
        coordinator.refresh { [weak self] in
            guard let self, let state = self.coordinator.state else { return }
            // Single config snapshot for the whole render pass.
            let strip = self.config.glyphStrip
            self.segments = GlyphStrip.segments(
                for: state,
                options: GlyphStrip.Options(strip),
                font: self.font
            )
            self.focusedSpaceIndex = state.focusedIndex
            self.rebuildRuns(strip: strip)
            self.present()
        }
    }

    private func rebuildRuns(strip: GlyphStripConfig) {
        let theme = themeService.named(effectiveThemeName)

        attributedRuns = segments.map { segment in
            let isCurrent = segment.spaceIndex != nil && segment.spaceIndex == focusedSpaceIndex
            return segment.runs.map { run in
                Self.attributedRun(
                    for: run,
                    strip: strip,
                    theme: theme,
                    style: Self.style(for: run, isCurrent: isCurrent, strip: strip, theme: theme)
                )
            }
        }
        // One array drives both the width below and the draw loop, so the frame
        // can never disagree with what is painted.
        runGaps = segments.map {
            GlyphStrip.interRunGaps(
                for: $0.runs,
                iconSpacing: CGFloat(strip.iconSpacing),
                indexPadding: CGFloat(strip.indexPadding)
            )
        }
        segmentWidths = zip(attributedRuns, runGaps).map { runs, gaps in
            let glyphs = zip(runs, gaps).reduce(0) { $0 + $1.0.size().width + $1.1 }
            return glyphs + Self.segmentPadding * 2
        }
    }

    // MARK: - Panel

    /// Creates the panel on first use, then always lays it out. Ordering front
    /// happens only when the panel is not already visible, so steady-state
    /// refreshes do not re-order the panel on every yabai signal.
    private func present() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        applyFrame(to: panel)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = GlyphStripPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Glass floats over the menu bar; the shadow separates its edge.
        panel.hasShadow = true
        // Above the main menu so the strip is never occluded by menu bar items.
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        let container = GlyphStripContainerView(controller: self)
        glyphs = container.glyphs
        panel.contentView = container
        return panel
    }

    private func applyFrame() {
        guard let panel else { return }
        applyFrame(to: panel)
    }

    private func applyFrame(to panel: NSPanel) {
        let screen = Self.targetScreen()
        let strip = config.glyphStrip
        let row = Self.menuBarRow(on: screen)
        let contentWidth = max(segmentWidths.reduce(0, +), 1)
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: contentWidth, height: row.height),
            menuBarRow: row,
            leftNotchArea: screen?.auxiliaryTopLeftArea,
            rightNotchArea: screen?.auxiliaryTopRightArea,
            position: strip.position,
            margin: CGFloat(strip.margin),
            yOffset: CGFloat(strip.yOffset),
            xOffset: CGFloat(strip.xOffset)
        )
        // Steady-state refreshes with an unchanged frame repaint nothing.
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        glyphs?.needsDisplay = true
    }

    // MARK: - Drag

    /// Live follow during a strip drag: `startFrame` is the panel frame
    /// captured at mouse-down and `delta` the pointer travel since, both in
    /// screen coordinates — the panel moves under the pointer, so window
    /// coordinates would stall after the first move.
    ///
    /// Switches the strip to `.custom` and steps the in-memory config along
    /// with the panel, so a refresh landing mid-drag recomputes the frame the
    /// drag already produced instead of snapping back to the old anchor.
    /// Offsets are derived through the inverse of `GlyphStrip.frame` and the
    /// frame itself comes from `applyFrame(to:)`, so the row clamp and the
    /// `clamped()` bounds apply exactly as they do on every other path.
    fileprivate func dragPanel(from startFrame: CGRect, by delta: CGVector) {
        guard config.glyphStrip.enabled, !hiddenByHotkey, let panel else { return }
        let candidate = CGRect(
            x: startFrame.minX + delta.dx,
            y: startFrame.minY + delta.dy,
            width: startFrame.width,
            height: startFrame.height
        )
        let offsets = GlyphStrip.customOffsets(for: candidate, menuBarRow: Self.menuBarRow(on: Self.targetScreen()))
        var strip = config.glyphStrip
        strip.position = .custom
        strip.xOffset = offsets.xOffset
        strip.yOffset = offsets.yOffset
        config.glyphStrip = strip.clamped()
        applyFrame(to: panel)
    }

    /// Persists a finished drag so it survives refreshes and restarts. Same
    /// load-modify-save path `HUDDisplay.savePanelPosition` uses, so config
    /// edits made elsewhere since the last save survive too. The frame the
    /// saved config describes equals the panel's current frame, so the
    /// notification-driven `applyFrame` that follows no-ops on the guard
    /// above rather than looping.
    fileprivate func persistDragPosition() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, let panel else { return }
        applyFrame(to: panel)
        let offsets = GlyphStrip.customOffsets(
            for: panel.frame,
            menuBarRow: Self.menuBarRow(on: Self.targetScreen())
        )
        var saved = Config.load()
        var strip = saved.glyphStrip
        strip.position = .custom
        strip.xOffset = offsets.xOffset
        strip.yOffset = offsets.yOffset
        saved.glyphStrip = strip.clamped()
        Config.saveConfig(saved)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    /// `NSScreen.main` follows the key window, and Spacemap is usually never
    /// active, so anchor the strip to the display the pointer is on — the one
    /// whose menu bar the user is looking at.
    static func targetScreen(mouseLocation: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The top row of the display, derived from the notch-aware safe-area inset
    /// so it is correct on both notched and plain displays.
    static func menuBarRow(on screen: NSScreen?) -> CGRect {
        guard let screen else {
            return CGRect(x: 0, y: 0, width: 0, height: fallbackMenuBarHeight)
        }
        let frame = screen.frame
        let visibleGap = frame.maxY - screen.visibleFrame.maxY
        let height = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : visibleGap
        let resolved = height > 0 ? height : fallbackMenuBarHeight
        return CGRect(x: frame.minX, y: frame.maxY - resolved, width: frame.width, height: resolved)
    }

    // MARK: - Input

    fileprivate func handle(_ command: GlyphStrip.Command) {
        switch command {
        case .focusSpace(let index):
            yabaiService.focusSpaceAsync(index)
        case .destroySpace(let index):
            // No confirmation — matches the original SketchyBar behaviour.
            yabaiService.destroySpace(index)
        case .createSpace:
            yabaiService.createSpace()
        case .moveFocusedWindowToSpace(let index):
            yabaiService.moveFocusedWindow(toSpace: index)
        case .mergeIntoSpace(let index):
            guard let focused = focusedSpaceIndex, let state = coordinator.state else { return }
            let ids = GlyphStrip.windows(forSpace: index, in: state).map(\.id)
            yabaiService.moveWindows(ids, toSpace: focused)
        case .toggleFullscreen:
            yabaiService.toggleWindowFullscreen()
        case .floatWindow:
            yabaiService.toggleWindowFloat()
        case .balanceWindows:
            yabaiService.balanceWindows()
        }
    }

    fileprivate func command(forSegment index: Int, click: GlyphStripClick) -> GlyphStrip.Command? {
        guard segments.indices.contains(index) else { return nil }
        let segment = segments[index]
        if segment.runs == [.add] { return .createSpace }
        return GlyphStrip.command(
            for: action(for: click),
            spaceIndex: segment.spaceIndex,
            focusedSpaceIndex: focusedSpaceIndex
        )
    }

    private func action(for click: GlyphStripClick) -> GlyphStripAction {
        switch click {
        case .left: return config.glyphStrip.leftClickAction
        case .right: return config.glyphStrip.rightClickAction
        case .middle: return config.glyphStrip.middleClickAction
        }
    }

    fileprivate func segment(at point: NSPoint) -> Int? {
        var x: CGFloat = 0
        for (offset, width) in segmentWidths.enumerated() {
            if point.x >= x, point.x < x + width {
                // Full slot hits; hover highlight stays hover-sized in draw.
                return offset
            }
            x += width
        }
        return nil
    }

    /// Horizontal extent of a segment in the view's own coordinates.
    fileprivate func segmentRect(_ index: Int) -> CGRect? {
        guard !viewBounds.isEmpty, segmentWidths.indices.contains(index) else { return nil }
        let x = segmentWidths.prefix(index).reduce(0, +)
        // Use viewBounds height (content height), not panel frame height.
        // The panel frame can be offset by yOffset, but view bounds stay constant.
        return CGRect(x: x, y: 0, width: segmentWidths[index], height: viewBounds.height)
    }

    /// The drawing layer's own bounds. On the native glass path the drawing
    /// layer sits inside the glass (glass-sized), so hit testing and hover
    /// share its coordinates; otherwise it fills the panel.
    fileprivate var viewBounds: CGRect {
        if let glyphs, !glyphs.bounds.isEmpty { return glyphs.bounds }
        return CGRect(origin: .zero, size: panel?.frame.size ?? .zero)
    }

    /// The panel's current frame in screen coordinates, captured by the view
    /// at mouse-down as the starting point for a drag.
    fileprivate var panelFrame: CGRect? { panel?.frame }

    /// The highlight drawn behind segment `index`, or `nil` when there is nothing
    /// to paint. One definition, shared by the draw loop and the hit test, so the
    /// highlight and the area that arms it cannot disagree.
    ///
    /// Sized from the segment's *content* box — its slot minus `segmentPadding`
    /// on each side — because that padding is the empty space either side of the
    /// glyphs inside the slot. Sizing from the slot instead would subtract
    /// `hoverPadding` from a width that already includes the padding, leaving the
    /// highlight narrower than the glyphs and off-centre.
    ///
    /// Clipped to the painted backdrop (or the plain bounds when no backdrop is
    /// painted), so a wide `hoverPadding` cannot push the highlight past the
    /// strip's ends.
    fileprivate func hoverBackdrop(_ index: Int) -> GlyphStrip.Backdrop? {
        guard !viewBounds.isEmpty else { return nil }
        // The painted material's rect, or the plain bounds when nothing is
        // painted behind the glyphs.
        let painted: CGRect
        if let backdrop = backdrop(in: viewBounds) {
            painted = backdrop.rect
        } else {
            painted = viewBounds
        }
        return GlyphStrip.hoverFill(
            // `dy: 0` keeps the full row height visible to the run-height clamp.
            segmentRect: segmentRect(index)?.insetBy(dx: Self.segmentPadding, dy: 0),
            runHeight: runHeight(forSegment: index),
            padding: hoverPadding,
            cornerRadius: hoverCornerRadius,
            within: painted.intersection(viewBounds)
        )
    }

    fileprivate func setHoveredSegment(_ index: Int?) {
        guard hoveredSegment != index else { return }
        hoveredSegment = index
        glyphs?.needsDisplay = true
    }

    // MARK: - Drawing inputs

    fileprivate var runs: [[NSAttributedString]] { attributedRuns }
    fileprivate var gaps: [[CGFloat]] { runGaps }

    /// Per-run y lift over the shared baseline: `appGlyphLift` for icon-font
    /// glyphs, zero for index/placeholder/overflow/separator/add.
    fileprivate func drawLift(segment offset: Int, run index: Int) -> CGFloat {
        guard segments.indices.contains(offset), segments[offset].runs.indices.contains(index) else { return 0 }
        return GlyphStrip.baselineLift(for: segments[offset].runs[index])
    }
    fileprivate var hovered: Int? { hoveredSegment }
    fileprivate var backgroundMaterial: GlyphStripBackgroundMaterial { config.glyphStrip.backgroundMaterial }
    fileprivate var glassAmount: Double { config.glyphStrip.glassAmount }
    fileprivate var useThemeTint: Bool { config.glyphStrip.useThemeTint }
    fileprivate var shape: GlyphStripShape { config.glyphStrip.shape }
    fileprivate var backgroundOpacity: CGFloat { CGFloat(config.glyphStrip.backgroundOpacity) }
    fileprivate var cornerRadius: CGFloat { CGFloat(config.glyphStrip.cornerRadius) }
    fileprivate var hoverPadding: CGFloat { CGFloat(config.glyphStrip.hoverPadding) }
    fileprivate var hoverCornerRadius: CGFloat { CGFloat(config.glyphStrip.hoverCornerRadius) }
    fileprivate var borderEnabled: Bool { config.glyphStrip.borderEnabled }

    /// The resolved text line box for a segment's runs, from real font metrics.
    ///
    /// The hover highlight is sized to this rather than to the menu bar row, so a
    /// 12pt strip does not get a 37.5pt-tall highlight.
    fileprivate func runHeight(forSegment index: Int) -> CGFloat {
        guard attributedRuns.indices.contains(index) else { return 0 }
        let fonts = attributedRuns[index].map { GlyphStripView.font(of: $0) }
        guard !fonts.isEmpty else { return 0 }
        let ascender = fonts.map(\.ascender).max() ?? 0
        let descender = fonts.map(\.descender).min() ?? 0
        return ascender - descender
    }

    /// The content height of the strip — the maximum run height across all segments.
    /// Used to size the solid/glass backdrop to the actual glyph content.
    fileprivate var contentHeight: CGFloat {
        let heights = (0..<attributedRuns.count).map { runHeight(forSegment: $0) }
        return heights.max() ?? viewBounds.height
    }

    /// Tallest ascender across all runs. Pairs with `contentHeight` to place one
    /// shared baseline, so every segment sits on same line.
    fileprivate var contentAscender: CGFloat {
        attributedRuns.flatMap { $0.map { GlyphStripView.font(of: $0).ascender } }.max() ?? 0
    }

    /// Top of content box centered in `bounds`. Feeds `contentBaselineY(in:)`
    /// so glyphs center on the same point as the backdrop.
    fileprivate func contentY(in bounds: CGRect) -> CGFloat {
        bounds.minY + (bounds.height - contentHeight) / 2
    }

    /// Single global baseline for all segments: content box centered in `bounds`,
    /// offset by tallest ascender. Same y-center as backdrop. `NSView` is
    /// y-up here (not flipped), so the baseline sits one ascender *below* the
    /// box top: `contentY + contentHeight - contentAscender`.
    fileprivate func contentBaselineY(in bounds: CGRect) -> CGFloat {
        guard !attributedRuns.isEmpty else { return bounds.minY }
        return contentY(in: bounds) + contentHeight - contentAscender
    }

    /// The theme the strip's colours resolve against: its own `theme` key when
    /// set, otherwise the main HUD's theme.
    private var effectiveThemeName: String {
        config.glyphStrip.theme.isEmpty ? config.theme : config.glyphStrip.theme
    }

    /// The solid material's fill: the theme's `cellBg` at `backgroundOpacity`.
    /// The fill role is fixed, so this never needs a "none" escape hatch.
    fileprivate var backdropColor: NSColor {
        GlyphStrip.color(for: "cellBg", theme: themeService.named(effectiveThemeName)) ?? .windowBackgroundColor
    }

    /// The glass layer only exists for `.liquidGlass`.
    fileprivate var usesGlass: Bool { backgroundMaterial == .liquidGlass }

    /// The flat fill only exists for `.solid`, at `backgroundOpacity`.
    fileprivate var usesSolid: Bool { backgroundMaterial == .solid }

    /// No backdrop at all when the material is `.none` or the shape is `.none`.
    /// Single source of truth for `layout()` and `draw()`.
    fileprivate var drawsBackdrop: Bool { backgroundMaterial != .none && shape != .none }

    /// Single resolved backdrop shared by the solid fill and the glass mask so
    /// the two rects cannot disagree. `nil` when nothing is painted, or when
    /// the shape degenerates.
    fileprivate func backdrop(in bounds: CGRect) -> GlyphStrip.Backdrop? {
        guard drawsBackdrop else { return nil }
        let resolved = GlyphStrip.backdrop(for: shape, bounds: bounds, cornerRadius: cornerRadius, insetForGlass: usesGlass)
        let clipped = resolved.rect.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return GlyphStrip.Backdrop(shape: resolved.shape, rect: clipped)
    }

    /// Outline path when no fill painted: same shape resolution as `backdrop`,
    /// so material `.none` border follows pill/bar/roundedRect. `nil` for
    /// shape `.none` = no outline.
    fileprivate func borderBackdrop(in bounds: CGRect) -> GlyphStrip.Backdrop? {
        guard shape != .none else { return nil }
        let resolved = GlyphStrip.backdrop(for: shape, bounds: bounds, cornerRadius: cornerRadius, insetForGlass: usesGlass)
        let clipped = resolved.rect.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return GlyphStrip.Backdrop(shape: resolved.shape, rect: clipped)
    }

    fileprivate var strokeColor: NSColor {
        GlyphStrip.glassStrokeColor(theme: themeService.named(effectiveThemeName))
    }

    /// The hover highlight always uses the theme's `focused` role.
    fileprivate var hoverColor: NSColor {
        GlyphStrip.color(for: "focused", theme: themeService.named(effectiveThemeName)) ?? .labelColor
    }

    /// How one run is painted: a resolved colour plus the alpha it draws at.
    ///
    /// Pure so the `highlightCurrentSpace` semantics can be asserted without
    /// AppKit state. With the flag off, a focused space resolves exactly like any
    /// other — same colour, same alpha, no separate fill.
    struct RunStyle: Equatable {
        let colorName: String
        let alpha: CGFloat

        /// Every distinguishing bit of a run's appearance, for equality checks.
        static func == (lhs: RunStyle, rhs: RunStyle) -> Bool {
            lhs.colorName == rhs.colorName && lhs.alpha == rhs.alpha
        }
    }

    /// `isCurrent` is ignored entirely when `highlightCurrentSpace` is off, which
    /// is what makes the current space genuinely indistinguishable rather than
    /// merely painted in the dimmed colour.
    ///
    /// Roles are fixed by the theme palette: the current space and the add
    /// button draw in `focused`, everything resting draws in `text`. There are
    /// no per-element colour keys, so `theme` only feeds the caller's colour
    /// lookup downstream.
    static func style(
        for run: GlyphStrip.Run,
        isCurrent: Bool,
        strip: GlyphStripConfig,
        theme: AppTheme
    ) -> RunStyle {
        let highlighted = isCurrent && strip.highlightCurrentSpace
        var isAppGlyph = false
        if case .app = run { isAppGlyph = true }
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

    fileprivate static func attributedRun(
        for run: GlyphStrip.Run,
        strip: GlyphStripConfig,
        theme: AppTheme,
        style: RunStyle
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
            font = appFont(size: CGFloat(strip.iconSize))
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

    fileprivate static var horizontalPadding: CGFloat { segmentPadding }

    fileprivate static func appFont(size: CGFloat) -> NSFont {
        NSFont(name: "sketchybar-app-font", size: size) ?? .systemFont(ofSize: size)
    }
}

enum GlyphStripClick {
    case left, right, middle
}

/// NSPanel subclass so clicks land here without activating Spacemap.
private final class GlyphStripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// Hosts the glass layer for the whole strip.
///
/// macOS 26+: a single `NSGlassEffectView` sized to the shared backdrop rect,
/// with the drawing layer as its `contentView` so the glyphs render inside the
/// glass rather than as a sibling behind it. No mask needed — `cornerRadius`
/// clips the glass.
/// Pre-26 or Reduce Transparency: the legacy `NSVisualEffectView` sibling
/// below the drawing layer, clipped by a shape mask.
private final class GlyphStripContainerView: NSView {

    weak var controller: GlyphStripPanelController?
    let glyphs: GlyphStripView

    private let fallbackGlass = NSVisualEffectView()
    /// `NSGlassEffectView` on macOS 26+, stored untyped. Native-glass code is
    /// additionally gated on `compiler(>=6.0)` (see `useNativeGlass`) because
    /// pre-6.0 SDKs lack the type entirely, so it must not appear in source.
    private var nativeGlass: NSView?

    init(controller: GlyphStripPanelController) {
        self.controller = controller
        self.glyphs = GlyphStripView(controller: controller)
        super.init(frame: .zero)
        // Native menu glass sampling the desktop behind the panel. Tint
        // is applied per `glassAmount` in `layout()` so settings apply live.
        fallbackGlass.blendingMode = .behindWindow
        fallbackGlass.state = .active
        addSubview(fallbackGlass)
        addSubview(glyphs)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Native glass whenever the OS has it, except under Reduce Transparency
    /// where the masked `NSVisualEffectView` stays legible. Also requires a
    /// 6.0+ compiler: the type only exists in post-5.9 SDKs (CI's macos-14
    /// toolchain cannot even name it), so it must be source-excluded there.
    private var useNativeGlass: Bool {
        #if compiler(>=6.0)
        if #available(macOS 26, *) {
            return !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        #endif
        return false
    }

    override func layout() {
        super.layout()
        // Single source of truth with draw(): one flag, one rect. Clearing the
        // mask whenever the fallback glass hides stops a stale mask surviving
        // a switch.
        guard let controller, controller.usesGlass,
              let backdrop = controller.backdrop(in: bounds) else {
            dockGlyphsAsSibling()
            fallbackGlass.isHidden = true
            fallbackGlass.maskImage = nil
            glyphs.insideGlass = false
            glyphs.frame = bounds
            return
        }
        if useNativeGlass {
            layoutNativeGlass(backdrop: backdrop, controller: controller)
        } else {
            layoutFallbackGlass(backdrop: backdrop, controller: controller)
        }
    }

    private func layoutNativeGlass(backdrop: GlyphStrip.Backdrop, controller: GlyphStripPanelController) {
        // Source-gated (not just availability-gated): pre-6.0 SDKs lack
        // `NSGlassEffectView` entirely, so any naming of it fails to compile.
        #if compiler(>=6.0)
        if #available(macOS 26, *) {
            let glass: NSGlassEffectView
            if let existing = nativeGlass as? NSGlassEffectView {
                glass = existing
            } else {
                glass = NSGlassEffectView()
                nativeGlass = glass
                addSubview(glass)
            }
            if glass.contentView !== glyphs {
                glyphs.removeFromSuperview()
                glass.contentView = glyphs
            }
            // Continuous tint: no public blur radius API, so the slider drives
            // tintColor alpha + a fill overlay in draw(), never view alpha.
            glass.style = .regular
            if controller.useThemeTint,
               let tintAlpha = GlyphStrip.glassTintAlpha(for: controller.glassAmount) {
                glass.tintColor = controller.backdropColor.withAlphaComponent(CGFloat(tintAlpha))
            } else {
                glass.tintColor = nil
            }
            glass.cornerRadius = backdrop.glassCornerRadius
            glass.frame = backdrop.rect
            glass.isHidden = false
            // Tint swaps alone do not always repaint the effect cache, so
            // force it: otherwise the slider looks dead until the next resize.
            // The fill overlay lives in glyphs.draw(), so repaint it too.
            glass.needsDisplay = true
            glyphs.needsDisplay = true
            glyphs.insideGlass = true
            glyphs.frame = glass.bounds
        }
        #endif
        fallbackGlass.isHidden = true
        fallbackGlass.maskImage = nil
    }

    private func layoutFallbackGlass(backdrop: GlyphStrip.Backdrop, controller: GlyphStripPanelController) {
        dockGlyphsAsSibling()
        // Tint-on keeps the saturated popover/menu pair; tint-off uses the
        // neutral `.headerView` material at full opacity so no warm menu bar
        // bleeds through the sibling blur view.
        fallbackGlass.material = GlyphStrip.glassFallbackMaterial(
            for: controller.glassAmount,
            useThemeTint: controller.useThemeTint
        )
        fallbackGlass.state = .active
        fallbackGlass.alphaValue = 1.0
        // Size the blur view itself to the backdrop rect — a full-bounds frame
        // leaves a big rectangle whenever the mask is nil or misaligned.
        fallbackGlass.frame = backdrop.rect
        fallbackGlass.maskImage = Self.maskImage(for: backdrop)
        fallbackGlass.isHidden = false
        glyphs.insideGlass = false
        glyphs.frame = bounds
        // Alpha/material swaps alone do not always repaint, so force both
        // layers: otherwise the neutral slider looks dead until resize.
        fallbackGlass.maskImage = nil
        fallbackGlass.needsDisplay = true
        glyphs.needsDisplay = true
    }

    /// Returns the drawing layer to a direct sibling above the fallback glass,
    /// detaching it from the native glass when it was embedded there.
    private func dockGlyphsAsSibling() {
        #if compiler(>=6.0)
        if #available(macOS 26, *) {
            if let native = nativeGlass as? NSGlassEffectView, native.contentView === glyphs {
                native.contentView = nil
            }
        }
        #endif
        nativeGlass?.isHidden = true
        if glyphs.superview !== self {
            glyphs.removeFromSuperview()
            addSubview(glyphs, positioned: .above, relativeTo: fallbackGlass)
        }
    }

    /// Mask in the blur view's own coordinates: transparent background with
    /// the shape filled white at origin zero. Matches the rect the stroke
    /// paints (translated to zero), so mask and edge cannot disagree.
    /// `flipped: false` matches this non-flipped view's y-up coordinates.
    private static func maskImage(for backdrop: GlyphStrip.Backdrop) -> NSImage? {
        let size = backdrop.rect.size
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setFill()
            switch backdrop.shape {
            case .none:
                return false
            case .bar:
                rect.fill()
            case .capsule:
                NSBezierPath(
                    roundedRect: rect,
                    xRadius: rect.height / 2,
                    yRadius: rect.height / 2
                ).fill()
            case .rounded(let radius):
                NSBezierPath(
                    roundedRect: rect,
                    xRadius: radius,
                    yRadius: radius
                ).fill()
            }
            return true
        }
        image.size = size
        return image
    }
}

private final class GlyphStripView: NSView {

    weak var controller: GlyphStripPanelController?
    /// True while embedded as the native glass `contentView`: `bounds` are
    /// then the shared backdrop rect, so the border outlines them directly.
    var insideGlass = false

    private var tracking: NSTrackingArea?

    init(controller: GlyphStripPanelController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The panel is normally never key, so the first click must not be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            // `.activeAlways`, not `.activeInKeyWindow`: Spacemap runs with a
            // `.prohibited` activation policy and is almost never key, which
            // would leave the hover highlight permanently dead.
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard let controller else { return }
        controller.setHoveredSegment(controller.segment(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        controller?.setHoveredSegment(nil)
    }

    /// Set on every left press and held until mouse-up: screen coordinates,
    /// the panel frame, and the view-space point the click dispatches at. A
    /// press resolves to a click OR a drag once the button comes back up.
    private var pressScreenLocation: NSPoint?
    private var pressFrame: CGRect?
    private var pressPoint: NSPoint?
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        // Screen coordinates, not window ones: the panel moves under the
        // pointer during a drag, and window-space locations drift with it.
        pressScreenLocation = NSEvent.mouseLocation
        pressFrame = controller.panelFrame
        pressPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller,
              let start = pressScreenLocation,
              let startFrame = pressFrame else { return }
        let location = NSEvent.mouseLocation
        let delta = CGVector(dx: location.x - start.x, dy: location.y - start.y)
        if !didDrag {
            guard GlyphStrip.exceedsDragThreshold(delta) else { return }
            didDrag = true
            // The pressed segment's highlight would otherwise pin itself
            // wherever the drag started.
            controller.setHoveredSegment(nil)
        }
        controller.dragPanel(from: startFrame, by: delta)
    }

    override func mouseUp(with event: NSEvent) {
        let dragged = didDrag
        let point = pressPoint
        didDrag = false
        pressPoint = nil
        pressScreenLocation = nil
        pressFrame = nil
        if dragged {
            controller?.persistDragPosition()
            return
        }
        // Below the threshold it is a click, dispatched at the press point.
        guard let point else { return }
        dispatch(.left, at: point)
    }

    override func rightMouseDown(with event: NSEvent) {
        dispatch(.right, at: convert(event.locationInWindow, from: nil))
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        dispatch(.middle, at: convert(event.locationInWindow, from: nil))
    }

    private func dispatch(_ click: GlyphStripClick, at point: NSPoint) {
        guard let controller,
              let index = controller.segment(at: point),
              let command = controller.command(forSegment: index, click: click) else { return }
        controller.handle(command)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }

        // `.liquidGlass` tints via the glass tintColor plus this fill overlay —
        // view alpha stays 1.0. Same backdrop rect as layout(). Tint off:
        // pure frost, no fill overlay.
        if controller.usesGlass, let backdrop = controller.backdrop(in: bounds) {
            // Inside native glass `bounds` already are the shared backdrop
            // rect, so paint them directly instead of insetting twice.
            let base = insideGlass
                ? GlyphStrip.Backdrop(shape: backdrop.shape, rect: bounds)
                : backdrop
            if controller.useThemeTint {
                GlyphStrip.fill(
                    base,
                    color: controller.backdropColor,
                    opacity: CGFloat(GlyphStrip.glassFillOpacity(for: controller.glassAmount))
                )
            } else {
                // Tint off: pure neutral `.headerView` frost. No fill overlay.
            }
            if controller.borderEnabled {
                GlyphStrip.stroke(
                    base,
                    color: controller.useThemeTint
                        ? controller.strokeColor
                        : GlyphStrip.neutralGlassStrokeColor(),
                    opacity: 1
                )
            }
        } else if controller.usesSolid, let backdrop = controller.backdrop(in: bounds) {
            // Opacity applies to the solid fill only; glass uses system material.
            GlyphStrip.fill(backdrop, color: controller.backdropColor, opacity: controller.backgroundOpacity)
            if controller.borderEnabled {
                GlyphStrip.stroke(backdrop, color: controller.strokeColor, opacity: 1)
            }
        } else if controller.borderEnabled, let border = controller.borderBackdrop(in: bounds) {
            // No fill painted — material `.none`. Border follows selected shape.
            GlyphStrip.stroke(border, color: controller.strokeColor, opacity: 1)
        }

        // Hover composes on top of whichever base is active, in every material.
        // With a `.pill` shape this capsule is the entire background, but it is
        // still sized to the glyphs rather than to the menu bar row.
        if let hovered = controller.hovered,
           let hover = controller.hoverBackdrop(hovered) {
            GlyphStrip.fill(
                hover,
                color: controller.hoverColor,
                opacity: GlyphStrip.hoverHighlightOpacity
            )
        }

        // `segmentWidths` charges every segment a leading *and* a trailing
        // `horizontalPadding`, so the pen has to spend both or the drawn content
        // ends up short of the frame and drifts left of the slot centres the
        // hover highlight is anchored to.
        var x: CGFloat = 0
        // One global baseline from contentHeight, same center as backdrop,
        // so all segments share a line.
        let baselineY = controller.contentBaselineY(in: bounds)
        for (offset, runs) in controller.runs.enumerated() {
            let gaps = controller.gaps[offset]
            x += GlyphStripPanelController.horizontalPadding
            for (index, run) in runs.enumerated() {
                if index > 0 { x += gaps[index] }
                run.draw(at: NSPoint(x: x, y: baselineY - GlyphStripPanelController.glyphDrop + controller.drawLift(segment: offset, run: index)))
                x += run.size().width
            }
            x += GlyphStripPanelController.horizontalPadding
        }
    }

    fileprivate static func font(of run: NSAttributedString) -> NSFont {
        run.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }
}
