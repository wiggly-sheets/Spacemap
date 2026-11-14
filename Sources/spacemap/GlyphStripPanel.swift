import AppKit
import ApplicationServices
import CoreText

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
    private lazy var themeService = ThemeManager.shared
    /// Background work queue: font load (disk IO + parse) runs here. Only
    /// the attributed-run apply, frame, and draw run on main.
    private static let stripWorkQueue = DispatchQueue(label: "com.spacemap.glyphstrip", qos: .userInitiated)
    /// Coalescing window for rapid space-change bursts: every refresh()
    /// cancels the pending one, so a burst paints once.
    private static let refreshCoalesceInterval: TimeInterval = 0.032
    /// Generation so a stale background reply never overwrites newer state.
    /// Read-only to tests so hiding can be asserted without exposing writes.
    private(set) var refreshGeneration = 0
    private(set) var pendingRefresh: DispatchWorkItem?
    /// Serializes refresh bodies: a refresh landing mid-pass sets
    /// `needsFollowupRefresh` for one bounded follow-up instead of recursing.
    private(set) var refreshInFlight = false
    private(set) var needsFollowupRefresh = false
    /// Generation that owns the in-flight latch; stale completions must not
    /// clear it for a refresh that replaced them.
    private var inFlightGeneration = 0
    /// Resolved per refresh on the work queue and passed through — never
    /// held, since the updater invalidates the shared cache after install.
    private var didLogMissingFont = false
    /// Face owner for the last painted pass. Drawing reads the face from the
    /// same file the codepoints came from.
    private var glyphFont: AppGlyphFont?
    /// Availability gate for an already-loaded font: metadata parses but the
    /// face must resolve, else initials instead of tofu.
    private func effectiveFont(from loaded: AppGlyphFont?) -> AppGlyphFont? {
        guard let loaded else {
            if !didLogMissingFont {
                didLogMissingFont = true
                NSLog("spacemap/GlyphStrip: sketchybar-app-font unavailable; falling back to app initials")
            }
            return nil
        }
        guard loaded.face(size: 11) != nil else {
            if !didLogMissingFont {
                didLogMissingFont = true
                NSLog("spacemap/GlyphStrip: sketchybar-app-font metadata parses but face unavailable; falling back to app initials")
            }
            return nil
        }
        return loaded
    }

    private(set) var panel: NSPanel?
    /// Drawing layer, retained so refreshes can invalidate it directly.
    private var glyphs: GlyphStripView?
    /// Test seam: counts repaint requests made by `applyFrame(to:)`. AppKit may
    /// clear `needsDisplay` synchronously during presentation, so the real
    /// flag cannot be asserted reliably from a unit test.
    private(set) var contentRepaintCount = 0
    private var config: GridConfig = .default
    /// Session-only visibility flag driven by the show/hide hotkey. Never
    /// persisted: every launch starts with the strip visible.
    private var hiddenByHotkey = false
    /// Session-only visibility flag for native fullscreen. Recomputed by a
    /// timer: entering or leaving fullscreen need not produce a yabai signal.
    private var hiddenByFullscreen = false
    private var fullscreenTimer: Timer?
    fileprivate var segments: [GlyphStrip.Segment] = []
    private var attributedRuns: [[NSAttributedString]] = []
    /// Extra advance before each run, parallel to `attributedRuns`.
    private var runGaps: [[CGFloat]] = []
    private var segmentWidths: [CGFloat] = []
    /// Memory-only native icons, parallel to `segments` runs (nil for
    /// non-native runs and cache misses). One array drives measuring and
    /// drawing, so the frame can never disagree with what is painted.
    private var nativeIcons: [[NSImage?]] = []
    /// Names with a background resolve already in flight. Stops a miss from
    /// re-triggering a refresh loop when the app has no bundle at all.
    private var nativeResolveInFlight = Set<String>()
    fileprivate var focusedSpaceIndex: Int?
    private var hoveredSegment: Int?
    private var screenObserver: NSObjectProtocol?
    /// Reduce Transparency changes swap the native glass for the legacy
    /// effect view; nothing else reassigns the material while the strip is up.
    private var accessibilityObserver: NSObjectProtocol?

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService
        self.coordinator = GridStateCoordinator(yabaiService: yabaiService)
        super.init()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.reconcileFullscreenVisibility()
        }
        RunLoop.main.add(timer, forMode: .common)
        fullscreenTimer = timer
        // A resolution change or a display being unplugged moves the notch and
        // resizes the menu bar row, so the cached frame has to be recomputed.
        screenObserver = NotificationCenter.default.addObserver(
            forName: Self.screenParametersChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyFrame()
        }
        // Polling alone leaves the strip visible for up to a tick after an app
        // switch or fullscreen exit. These land the same pass immediately.
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reconcileFullscreenVisibility()
            }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.relayoutBackground()
        }
    }

    deinit {
        pendingRefresh?.cancel()
        fullscreenTimer?.invalidate()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    /// Re-applies the background choice without touching content: used when a
    /// system setting changes which glass implementation is allowed.
    private func relayoutBackground() {
        panel?.contentView?.needsLayout = true
        panel?.contentView?.layout()
        glyphs?.needsDisplay = true
    }

    // MARK: - State

    func update(config: GridConfig) {
        // The updater drops the cache itself on install, but a version written
        // by another process only shows up here. Unrelated settings saves must
        // not force the next refresh back to disk.
        if config.appFont.installedVersion != self.config.appFont.installedVersion {
            AppGlyphFont.invalidateCache()
        }
        self.config = config
        // The coordinator cancels any in-flight fetch when its config changes.
        // If that cancellation completes without running our completion (or an
        // older coordinator build did), the latch would stay set and every
        // later refresh would collapse into a follow-up that never runs.
        refreshInFlight = false
        inFlightGeneration = 0
        needsFollowupRefresh = false
        coordinator.updateConfig(config)
        // Settings changes can add or edit a `.smthemes` file; only re-read the
        // directory when an entry actually changed. Theme-name-only changes
        // need no reload (the file is already parsed), and this runs on every
        // save.
        themeService.reloadIfChanged()
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByFullscreen else {
            hide()
            return
        }
        // Material/shape/opacity switches keep the same frame, so without a
        // layout pass the old glass/fill would stay on screen. Invalidate both
        // layers here; refresh() then recomputes content.
        panel?.contentView?.needsLayout = true
        panel?.contentView?.layout()
        glyphs?.needsDisplay = true
        refresh()
    }

    /// Simulates a fetch cancellation that left the serialization latch set, so
    /// `update(config:)` can be tested for clearing it.
    func markRefreshWedgedForTesting() {
        refreshInFlight = true
        needsFollowupRefresh = true
    }

    /// Hides the strip while another app owns a native fullscreen window, and
    /// brings it back when that app leaves fullscreen. Polled because the
    /// window server gives no fullscreen notification; yabai signals alone miss
    /// the green-button case.
    private func reconcileFullscreenVisibility() {
        guard config.glyphStrip.enabled, config.glyphStrip.hideInFullscreen else {
            guard hiddenByFullscreen else { return }
            hiddenByFullscreen = false
            update(config: config)
            return
        }
        let shouldHide = fullscreenWindowOnFocusedSpace() ?? Self.hasFullscreenAppInFront()
        guard shouldHide != hiddenByFullscreen else { return }
        hiddenByFullscreen = shouldHide
        if shouldHide {
            hide()
        } else {
            update(config: config)
        }
    }

    /// Native fullscreen on the focused space, from yabai's own space model.
    /// A fullscreen window on another space is invisible to the user, so the
    /// window-server and Accessibility checks alone cannot tell them apart.
    /// `nil` when the focused space or the field is unavailable.
    private func fullscreenWindowOnFocusedSpace() -> Bool? {
        guard let state = coordinator.state, let focused = state.focusedIndex else { return nil }
        let windows = state.windows(forSpace: focused)
        guard windows.contains(where: { $0.isNativeFullscreen != nil }) else { return nil }
        return windows.contains { $0.isNativeFullscreen == true }
    }

    /// True when the app the user sees has a native fullscreen window.
    ///
    /// Accessibility reports this directly, so it survives the window resizes
    /// of the fullscreen animation. Falls back to window geometry when
    /// Accessibility is not granted. A menu-bar app can report itself as
    /// frontmost, so that case resolves the app from the front layer-0 window.
    static func hasFullscreenAppInFront() -> Bool {
        guard AXIsProcessTrusted() else { return frontWindowCoversDisplay() }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if pid == nil || pid == ownPID {
            pid = frontWindowOwner(excluding: ownPID)
        }
        guard let pid, pid != ownPID else { return false }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &window
        ) == .success, let window else {
            return frontWindowCoversDisplay()
        }
        var fullscreen: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            "AXFullScreen" as CFString,
            &fullscreen
        ) == .success else {
            return frontWindowCoversDisplay()
        }
        guard (fullscreen as? Bool) == true else { return false }
        // `AXFocusedWindow` can still be the fullscreen window while the user
        // looks at a different space of the same app. Only hide when that app
        // also has a fullscreen-sized window on screen now.
        return windowCoversDisplay(owner: pid)
    }

    /// Does `owner` have an on-screen layer-0 window as large as a display?
    private static func windowCoversDisplay(owner pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  owner == Int(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else {
                continue
            }
            // Accessibility already said the window is fullscreen, so this is a
            // space-membership check, not a shape test: accept the small height
            // differences of the fullscreen animation and a hidden menu bar.
            if NSScreen.screens.contains(where: {
                abs($0.frame.width - bounds.width) <= 2 && bounds.height >= $0.frame.height - 60
            }) {
                return true
            }
        }
        return false
    }

    /// Owner of the frontmost layer-0 window that is not Spacemap's own.
    private static func frontWindowOwner(excluding ownPID: pid_t) -> pid_t? {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  owner != Int(ownPID),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            return pid_t(owner)
        }
        return nil
    }

    /// Geometry fallback: does the frontmost normal window cover a display?
    /// Fullscreen windows cover the display; zoomed windows stop below the menu
    /// bar.
    private static func frontWindowCoversDisplay() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int, owner != Int(ownPID),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else {
                continue
            }
            return NSScreen.screens.contains {
                abs($0.frame.width - bounds.width) <= 2 && abs($0.frame.height - bounds.height) <= 2
            }
        }
        return false
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
    /// path. No polling timer. Debounced (~32ms): rapid space-change bursts
    /// coalesce to one pass. Font IO + segment model build run on the work
    /// queue; only the attributed-run apply + frame runs on main.
    func refresh() {
        guard config.glyphStrip.enabled, !hiddenByHotkey else { return }
        refreshGeneration += 1
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runRefresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshCoalesceInterval, execute: work)
    }

    private func runRefresh() {
        guard config.glyphStrip.enabled, !hiddenByHotkey else { return }
        // Re-entrant guard: a refresh landing mid-pass (e.g. an icon resolve
        // landing one) collapses to a single bounded follow-up.
        guard !refreshInFlight else {
            needsFollowupRefresh = true
            return
        }
        refreshInFlight = true
        let generation = refreshGeneration
        inFlightGeneration = generation
        // Single config snapshot for the whole render pass.
        let strip = config.glyphStrip
        let options = GlyphStrip.Options(strip)
        coordinator.refresh { [weak self] in
            guard let self else { return }
            guard generation == self.refreshGeneration,
                  let state = self.coordinator.state else {
                // Stale reply or no state: drop it, never paint over newer state.
                self.finishRefresh(generation: generation)
                return
            }
            let focused = state.focusedIndex
            Self.stripWorkQueue.async { [weak self] in
                // Disk IO + parse only; the gated face check and the pure
                // segment build stay on main below.
                let loaded = AppGlyphFont.load()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard generation == self.refreshGeneration else {
                        self.finishRefresh(generation: generation)
                        return
                    }
                    let font = self.effectiveFont(from: loaded)
                    self.glyphFont = font
                    let resolved = GlyphStrip.segments(
                        for: state,
                        options: options,
                        font: font
                    )
                    let previousFocused = self.focusedSpaceIndex
                    self.segments = resolved
                    self.focusedSpaceIndex = focused
                    // Watchdog: a non-empty state must never paint an empty
                    // strip from a dropped pass — fall back to initials runs.
                    if resolved.isEmpty && !state.spaces.isEmpty {
                        NSLog("spacemap/GlyphStrip: empty segments for non-empty state; keeping last good frame")
                        self.finishRefresh(generation: generation)
                        return
                    }
                    // Re-check immediately before painting: the strip may have
                    // been disabled or hidden by hotkey while the font/state
                    // work was in flight.
                    guard generation == self.refreshGeneration,
                          self.config.glyphStrip.enabled,
                          !self.hiddenByHotkey else {
                        self.finishRefresh(generation: generation)
                        return
                    }
                    self.rebuildRuns(strip: strip)
                    self.present()
                    if previousFocused != focused, let glyphs = self.glyphs {
                        NSAccessibility.post(element: glyphs, notification: .valueChanged)
                    }
                    self.preloadNativeIcons()
                    self.finishRefresh(generation: generation)
                }
            }
        }
    }

    /// Clears the in-flight flag and runs one collapsed follow-up when a
    /// refresh landed mid-pass. Stale generations never trigger follow-ups.
    private func finishRefresh(generation: Int) {
        guard generation == inFlightGeneration else { return }
        refreshInFlight = false
        inFlightGeneration = 0
        if needsFollowupRefresh {
            needsFollowupRefresh = false
            refresh()
        }
    }

    /// Off-main miss resolution for native icons: cache hits paint this pass,
    /// misses repaint via one follow-up refresh once the image lands.
    /// In-flight names are skipped so an unresolvable app cannot loop.
    private func preloadNativeIcons() {
        guard config.glyphStrip.iconSource == .nativeIcons else { return }
        for (segmentOffset, segment) in segments.enumerated() {
            for (runOffset, run) in segment.runs.enumerated() {
                guard case .nativeIcon(let app, _, _) = run,
                      nativeIcons.indices.contains(segmentOffset),
                      nativeIcons[segmentOffset].indices.contains(runOffset),
                      nativeIcons[segmentOffset][runOffset] == nil,
                      !nativeResolveInFlight.contains(app) else { continue }
                nativeResolveInFlight.insert(app)
                IconCache.shared.resolveInBackground(appName: app) { [weak self] image in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.nativeResolveInFlight.remove(app)
                        // Nil (no bundle anywhere) must not re-trigger: the
                        // fallback glyph is the final answer for this launch.
                        if image != nil { self.refresh() }
                    }
                }
            }
        }
    }

    private func rebuildRuns(strip: GlyphStripConfig) {
        let theme = themeService.named(effectiveThemeName)

        // Memory-only hits; misses keep nil and paint the fallback glyph
        // until preloadNativeIcons lands them. Never blocks on icon(forFile:).
        nativeIcons = segments.map { segment in
            segment.runs.map { run in
                guard case .nativeIcon(let app, _, _) = run else { return nil }
                return IconCache.shared.cachedIcon(for: app)
            }
        }
        attributedRuns = segments.map { segment in
            let isCurrent = segment.spaceIndex != nil && segment.spaceIndex == focusedSpaceIndex
            return segment.runs.map { run in
                Self.attributedRun(
                    for: run,
                    strip: strip,
                    theme: theme,
                    style: Self.style(for: run, isCurrent: isCurrent, strip: strip, theme: theme),
                    face: glyphFont
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
        segmentWidths = segments.indices.map { offset in
            let runs = attributedRuns[offset]
            let gaps = runGaps[offset]
            // Resolved native icons fill their fallback's advance: the same
            // cell an `.app` run measures at this iconSize, side bearings
            // included. Hit and miss share one width, so resolving an icon
            // never reflows the strip.
            let glyphs = runs.indices.reduce(CGFloat(0)) { total, index in
                total + runs[index].size().width + gaps[index]
            }
            return glyphs + Self.segmentPadding * 2
        }
    }

    // MARK: - Panel

    /// Creates the panel on first use, then always lays it out. Ordering front
    /// happens only when the panel is not already visible, so steady-state
    /// refreshes do not re-order the panel on every yabai signal.
    func present() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByFullscreen else {
            hide()
            return
        }
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        applyFrame(to: panel)
        if !panel.isVisible { panel.orderFrontRegardless() }
        if let glyphs {
            NSAccessibility.post(element: glyphs, notification: .layoutChanged)
        }
    }

    private func hide() {
        // An in-flight refresh must not re-present a strip the user just hid or
        // disabled. Bumping the generation makes every pending reply stale, and
        // cancelling the coalesced work stops a queued pass from starting.
        refreshGeneration += 1
        pendingRefresh?.cancel()
        pendingRefresh = nil
        needsFollowupRefresh = false
        refreshInFlight = false
        inFlightGeneration = 0
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
        // NSPanel hides itself when the app deactivates by default. The strip
        // must survive focus leaving Spacemap (Settings closed, another app
        // frontmost), so opt out explicitly.
        panel.hidesOnDeactivate = false
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

    private func applyFrame(to panel: NSPanel, screen explicitScreen: NSScreen? = nil) {
        let screen = explicitScreen ?? targetScreen()
        let strip = config.glyphStrip
        let row = Self.menuBarRow(on: screen)
        // Free placement can leave the menu bar row, so `presentationFrame`
        // there is the whole display. Anchored positions keep the row.
        let area = strip.position == .custom ? Self.screenFrame(on: screen) : row
        panel.level = strip.position == .custom ? .floating : .statusBar
        let frame = GlyphStrip.frame(
            contentSize: stripContentSize(rowHeight: row.height),
            menuBarRow: row,
            screenFrame: area,
            leftNotchArea: screen?.auxiliaryTopLeftArea,
            rightNotchArea: screen?.auxiliaryTopRightArea,
            position: strip.position,
            margin: CGFloat(strip.margin),
            yOffset: CGFloat(strip.yOffset),
            xOffset: CGFloat(strip.xOffset)
        )
        // Only move the window when the frame changed, but always repaint:
        // content can change (new glyphs, focus, theme) at an identical frame.
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        contentRepaintCount += 1
        glyphs?.needsDisplay = true
    }

    /// Slot size for the panel: one horizontal row in the menu bar, or one
    /// stacked block per space when `.custom` renders vertically.
    private func stripContentSize(rowHeight: CGFloat) -> CGSize {
        guard isVerticalLayout else {
            return CGSize(width: max(segmentWidths.reduce(0, +), 1), height: rowHeight)
        }
        let width: CGFloat
        if isStackedVertical {
            // Each line holds one run, so the widest run sets the strip width.
            let widest = attributedRuns
                .map { runs in runs.map { $0.size().width }.max() ?? 0 }
                .max() ?? 0
            width = widest + Self.horizontalPadding * 2
        } else {
            width = segmentWidths.max() ?? 0
        }
        let height = max(verticalTotalHeight, 1)
        return CGSize(width: max(width, 1), height: height)
    }

    /// Vertical stacking only applies to free placement; anchored positions
    /// stay in the single menu-bar row.
    fileprivate var isVerticalLayout: Bool {
        config.glyphStrip.position == .custom && config.glyphStrip.orientation == .vertical
    }

    /// Icons under the number, one per line, instead of beside it.
    fileprivate var isStackedVertical: Bool {
        isVerticalLayout && config.glyphStrip.verticalLayout == .stacked
    }

    /// Height of one glyph line: the tallest glyph box.
    fileprivate var contentLineHeight: CGFloat { max(contentHeight, 1) }

    /// Slot height for an inline vertical space, with hover breathing room.
    fileprivate var verticalLineHeight: CGFloat {
        contentLineHeight + hoverPadding * 2
    }

    /// Number of drawn lines in a vertical segment. Inline vertical is always
    /// one line; stacked vertical spends one line per run.
    fileprivate func verticalLineCount(_ index: Int) -> Int {
        guard isStackedVertical, attributedRuns.indices.contains(index) else { return 1 }
        return max(attributedRuns[index].count, 1)
    }

    /// Gap before stacked line `index`: `indexPadding` once between the number
    /// and the first icon, `iconSpacing` between icons after that.
    fileprivate func stackedGap(before index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        return CGFloat(index == 1 ? config.glyphStrip.indexPadding : config.glyphStrip.iconSpacing)
    }

    fileprivate func verticalSegmentHeight(_ index: Int) -> CGFloat {
        guard isStackedVertical else { return verticalLineHeight }
        let lines = verticalLineCount(index)
        let gaps = (1..<max(lines, 1)).reduce(CGFloat(0)) { $0 + stackedGap(before: $1) }
        return CGFloat(lines) * contentLineHeight + gaps + hoverPadding * 2
    }

    private var verticalTotalHeight: CGFloat {
        guard !attributedRuns.isEmpty else { return verticalLineHeight }
        return attributedRuns.indices.reduce(0) { $0 + verticalSegmentHeight($1) }
    }

    static func screenFrame(on screen: NSScreen?) -> CGRect {
        screen?.frame ?? NSScreen.main?.frame ?? .zero
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
        guard !config.glyphStrip.isPositionLocked, config.glyphStrip.enabled, !hiddenByHotkey, let panel else { return }
        let candidate = CGRect(
            x: startFrame.minX + delta.dx,
            y: startFrame.minY + delta.dy,
            width: startFrame.width,
            height: startFrame.height
        )
        let screen = panelScreen() ?? targetScreen()
        let offsets = GlyphStrip.customOffsets(
            for: candidate,
            area: Self.screenFrame(on: screen)
        )
        var strip = config.glyphStrip
        strip.position = .custom
        strip.xOffset = offsets.xOffset
        strip.yOffset = offsets.yOffset
        config.glyphStrip = strip.clamped()
        applyFrame(to: panel, screen: screen)
    }

    /// Persists a finished drag so it survives refreshes and restarts. Same
    /// load-modify-save path `HUDDisplay.savePanelPosition` uses, so config
    /// edits made elsewhere since the last save survive too. Posts only the
    /// dedicated position notification (not `.settingsChanged`, which would
    /// drop the font cache and reload themes).
    fileprivate func persistDragPosition() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, let panel else { return }
        let screen = panelScreen() ?? targetScreen()
        let offsets = GlyphStrip.customOffsets(
            for: panel.frame,
            area: Self.screenFrame(on: screen)
        )
        AppConfig.updateConfig { saved in
            var strip = saved.glyphStrip
            strip.position = .custom
            strip.xOffset = offsets.xOffset
            strip.yOffset = offsets.yOffset
            saved.glyphStrip = strip.clamped()
        }
        applyFrame(to: panel, screen: screen)
        // Position-only change: notify an open Settings window so its stale
        // `glyphStrip` state cannot write the old position back on the next
        // save. Deliberately not `.settingsChanged` (that would reload themes
        // and drop the font cache).
        NotificationCenter.default.post(name: .glyphStripPositionChanged, object: nil)
    }

    /// The strip follows the display that owns yabai's focused space, falling
    /// back to the display it is currently parked on, and only then to the
    /// pointer. `NSScreen.main` follows the key window, which is usually not
    /// Spacemap, so it is never the primary signal.
    private func targetScreen() -> NSScreen? {
        if let state = coordinator.state {
            if let focused = state.focusedIndex,
               let displayIndex = state.displayIndex(forSpace: focused),
               let display = state.displays.first(where: { $0.index == displayIndex }),
               let screen = Self.screen(containingQuartzFrame: display.frame.cgFrame) {
                return screen
            }
            if let focusedDisplay = state.displays.first(where: \.hasFocus),
               let screen = Self.screen(containingQuartzFrame: focusedDisplay.frame.cgFrame) {
                return screen
            }
        }
        return panelScreen() ?? Self.targetScreen()
    }

    /// The display the panel currently sits on, if any. Used by drags so a
    /// strip being moved does not snap back to the focused-space display.
    private func panelScreen() -> NSScreen? {
        guard let panel else { return nil }
        return NSScreen.screens.first { $0.frame.intersects(panel.frame) }
    }

    /// Pointer-based fallback for the first refresh before any state exists.
    static func targetScreen(mouseLocation: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// yabai reports Quartz display frames (top-left origin); `NSScreen.frame`
    /// is AppKit (bottom-left). Flip through the main screen's maxY before
    /// matching, otherwise vertically stacked displays never resolve.
    static func appKitFrame(forQuartzFrame frame: CGRect, quartzMaxY: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: quartzMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func bestScreenIndex(for targetFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        HUDDisplay.bestScreenIndex(for: targetFrame, screenFrames: screenFrames)
    }

    static func screen(
        containingQuartzFrame frame: CGRect,
        screens: [NSScreen] = NSScreen.screens,
        quartzMaxY: CGFloat? = nil
    ) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        let maxY = quartzMaxY ?? HUDGeometry.mainScreenFrame(screens: screens).maxY
        let appKitFrame = appKitFrame(forQuartzFrame: frame, quartzMaxY: maxY)
        guard let index = bestScreenIndex(for: appKitFrame, screenFrames: screens.map(\.frame)) else {
            return nil
        }
        return screens[index]
    }

    /// The top row of the display, derived from the notch-aware safe-area inset
    /// so it is correct on both notched and plain displays.
    static func menuBarRow(on screen: NSScreen?) -> CGRect {
        guard let screen else {
            return CGRect(x: 0, y: 0, width: 0, height: fallbackMenuBarHeight)
        }
        return menuBarRow(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top
        )
    }

    /// Pure geometry for `menuBarRow(on:)`: notched displays expose the row as
    /// the top safe-area inset, plain displays as the gap above `visibleFrame`.
    static func menuBarRow(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat
    ) -> CGRect {
        let visibleGap = screenFrame.maxY - visibleFrame.maxY
        let height = safeAreaTop > 0 ? safeAreaTop : visibleGap
        let resolved = height > 0 ? height : fallbackMenuBarHeight
        return CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - resolved,
            width: screenFrame.width,
            height: resolved
        )
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
        for index in segmentWidths.indices where segmentRect(index)?.contains(point) == true {
            // Full slot hits; hover highlight stays hover-sized in draw.
            return index
        }
        return nil
    }

    /// Slot of a segment in the view's own coordinates: the menu-bar row, or
    /// one stacked line per space when vertical.
    fileprivate func segmentRect(_ index: Int) -> CGRect? {
        guard !viewBounds.isEmpty, segmentWidths.indices.contains(index) else { return nil }
        if isVerticalLayout {
            let heights = segmentWidths.indices.map { verticalSegmentHeight($0) }
            let slots = GlyphStrip.verticalSlots(heights: heights, in: viewBounds)
            return slots.indices.contains(index) ? slots[index] : nil
        }
        let x = segmentWidths.prefix(index).reduce(0, +)
        // Use viewBounds height (content height), not panel frame height.
        // The panel frame can be offset by yOffset, but view bounds stay constant.
        return CGRect(x: x, y: 0, width: segmentWidths[index], height: viewBounds.height)
    }

    /// The drawing layer's own bounds; it fills the panel on every material.
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
    /// and native-icon runs, zero for index/placeholder/overflow/separator/add.
    fileprivate func drawLift(segment offset: Int, run index: Int) -> CGFloat {
        guard segments.indices.contains(offset), segments[offset].runs.indices.contains(index) else { return 0 }
        return GlyphStrip.baselineLift(for: segments[offset].runs[index])
    }
    fileprivate var hovered: Int? { hoveredSegment }
    fileprivate var backgroundMaterial: GlyphStripBackgroundMaterial {
        config.glyphStrip.resolvedBackgroundMaterial(hud: config)
    }
    fileprivate var glassStyle: HUDGlassStyle {
        config.glyphStrip.resolvedGlassStyle(hud: config)
    }
    fileprivate var glassVariant: Int {
        config.glyphStrip.resolvedGlassVariant(hud: config)
    }
    fileprivate var glassTintedMaterial: HUDGlassMaterial {
        config.glyphStrip.resolvedGlassTintedMaterial(hud: config)
    }
    fileprivate var shape: GlyphStripShape { config.glyphStrip.shape }
    fileprivate var backgroundOpacity: CGFloat {
        CGFloat(config.glyphStrip.resolvedBackgroundOpacity(hud: config))
    }
    fileprivate var cornerRadius: CGFloat { CGFloat(config.glyphStrip.cornerRadius) }
    fileprivate var hoverPadding: CGFloat { CGFloat(config.glyphStrip.hoverPadding) }
    fileprivate var hoverCornerRadius: CGFloat { CGFloat(config.glyphStrip.hoverCornerRadius) }
    fileprivate var borderEnabled: Bool { config.glyphStrip.borderEnabled }

    /// The resolved text line box for a segment's runs, from real font metrics.
    ///
    /// The hover highlight is sized to this rather than to the menu bar row, so a
    /// 12pt strip does not get a 37.5pt-tall highlight.
    fileprivate func runHeight(forSegment index: Int) -> CGFloat {
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
    fileprivate var contentHeight: CGFloat {
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
        config.glyphStrip.resolvedThemeName(hud: config)
    }

    /// The solid material's fill, at `backgroundOpacity`. Matches the HUD's
    /// `background` role when copying the HUD appearance (the HUD solid fill
    /// uses that role); otherwise the strip's own `cellBg`.
    fileprivate var solidColor: NSColor {
        let role = config.glyphStrip.matchHUDAppearance ? "background" : "cellBg"
        return GlyphStrip.color(for: role, theme: themeService.named(effectiveThemeName))
            ?? .windowBackgroundColor
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

    /// Native glass tint for the tinted sub-type, `nil` for clear/opaque.
    /// The theme's accent, not its background: tinting with the surface colour
    /// reads as a slightly darker opaque glass instead of a tinted one.
    fileprivate var glassTintColor: NSColor? {
        guard glassStyle == .tinted else { return nil }
        return GlyphStrip.color(for: "focused", theme: themeService.named(effectiveThemeName)) ?? solidColor
    }

    /// Tinted glass gets the theme-blended hairline; clear/opaque stay neutral.
    fileprivate var glassEdgeColor: NSColor {
        glassStyle == .tinted ? strokeColor : GlyphStrip.neutralGlassStrokeColor()
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
        if GlyphStrip.isNativeIcon(run) { isAppGlyph = true }
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
        style: RunStyle,
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

    fileprivate static var horizontalPadding: CGFloat { segmentPadding }

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
    fileprivate func nativeIcon(segment offset: Int, run index: Int) -> NSImage? {
        guard nativeIcons.indices.contains(offset),
              nativeIcons[offset].indices.contains(index) else { return nil }
        return nativeIcons[offset][index]
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
///
/// In both cases the flat fill is painted by the drawing layer over the
/// material, because a glass material samples the window backdrop rather than
/// sibling views below it.
private final class GlyphStripContainerView: NSView {

    weak var controller: GlyphStripPanelController?
    let glyphs: GlyphStripView

    private let fallbackGlass = NSVisualEffectView()
    /// `NSGlassEffectView` on macOS 26+, stored untyped. Native-glass code is
    /// additionally gated on `compiler(>=6.2)` (see `useNativeGlass`) because
    /// pre-6.2 SDKs lack the type entirely, so it must not appear in source.
    private var nativeGlass: NSView?

    init(controller: GlyphStripPanelController) {
        self.controller = controller
        self.glyphs = GlyphStripView(controller: controller)
        super.init(frame: .zero)
        // Native menu glass sampling the desktop behind the panel. The style
        // and backing are applied in `layout()`/`draw()` so settings apply live.
        fallbackGlass.blendingMode = .behindWindow
        fallbackGlass.state = .active
        addSubview(fallbackGlass)
        addSubview(glyphs)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        NSLog("spacemap/GlyphStripContainerView: init(coder:) unsupported")
        return nil
    }

    // The container is a transparent grouping wrapper, not an element itself;
    // VoiceOver should descend to the drawing layer's segment children.
    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityChildren() -> [Any]? { [glyphs] }

    /// Native glass whenever the OS has it, except under Reduce Transparency
    /// where the masked `NSVisualEffectView` stays legible. Also requires a
    /// 6.0+ compiler: the type only exists in post-5.9 SDKs (CI's macos-14
    /// toolchain cannot even name it), so it must be source-excluded there.
    private var useNativeGlass: Bool {
        #if compiler(>=6.2)
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
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let style: NSGlassEffectView.Style =
                controller.glassStyle.material(tintedMaterial: controller.glassTintedMaterial) == .clear ? .clear : .regular
            let glass: NSGlassEffectView
            // `NSGlassEffectView` caches its effect; `needsDisplay` does not
            // rebuild it. A material swap needs a fresh view.
            if let existing = nativeGlass as? NSGlassEffectView, existing.style == style {
                glass = existing
            } else {
                nativeGlass?.removeFromSuperview()
                glass = NSGlassEffectView()
                glass.style = style
                nativeGlass = glass
            }
            // Glass below the drawing layer, not its `contentView`: the view's
            // alpha then carries the opacity without fading the glyphs, the way
            // macOS menu-bar overlays do it.
            addSubview(glass, positioned: .below, relativeTo: glyphs)
            GlassVariant.apply(controller.glassVariant, to: glass)
            glass.tintColor = controller.glassTintColor
            glass.cornerRadius = backdrop.glassCornerRadius
            glass.frame = backdrop.rect
            glass.alphaValue = CGFloat(controller.backgroundOpacity)
            glass.isHidden = false
            glass.needsDisplay = true
            glyphs.needsDisplay = true
            glyphs.frame = bounds
        }
        #endif
        fallbackGlass.isHidden = true
        fallbackGlass.maskImage = nil
    }

    private func layoutFallbackGlass(backdrop: GlyphStrip.Backdrop, controller: GlyphStripPanelController) {
        dockGlyphsAsSibling()
        // One material per sub-type, so clear and opaque stay distinct.
        fallbackGlass.material = GlyphStrip.glassFallbackMaterial(
            for: controller.glassStyle,
            tintedMaterial: controller.glassTintedMaterial
        )
        fallbackGlass.state = .active
        fallbackGlass.alphaValue = 1.0
        // Size the blur view itself to the backdrop rect — a full-bounds frame
        // leaves a big rectangle whenever the mask is nil or misaligned.
        fallbackGlass.frame = backdrop.rect
        fallbackGlass.maskImage = Self.maskImage(for: backdrop)
        fallbackGlass.isHidden = false
        glyphs.frame = bounds
        // Alpha/material swaps alone do not always repaint, so force both
        // layers: otherwise the neutral slider looks dead until resize.
        fallbackGlass.needsDisplay = true
        glyphs.needsDisplay = true
    }

    /// Returns the drawing layer to a direct sibling above the effect view.
    private func dockGlyphsAsSibling() {
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

/// One VoiceOver child per painted segment; pressing it runs the same command
/// as a left click on that segment.
private final class GlyphStripAccessibilityElement: NSAccessibilityElement {
    weak var controller: GlyphStripPanelController?
    var segmentIndex = 0

    override func accessibilityActionNames() -> [NSAccessibility.Action] { [.press] }

    override func accessibilityPerformPress() -> Bool {
        guard let controller,
              let command = controller.command(forSegment: segmentIndex, click: .left) else {
            return false
        }
        controller.handle(command)
        return true
    }
}

private final class GlyphStripView: NSView {

    weak var controller: GlyphStripPanelController?
    private var tracking: NSTrackingArea?
    /// VoiceOver expects the vendor to keep its elements alive between
    /// queries, so the last-built children are retained here.
    private var accessibilitySegments: [GlyphStripAccessibilityElement] = []

    init(controller: GlyphStripPanelController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        NSLog("spacemap/GlyphStripView: init(coder:) unsupported")
        return nil
    }

    /// The panel is normally never key, so the first click must not be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Accessibility

    /// Exposes the strip as a group of button-like segments. Without this the
    /// whole overlay is invisible to VoiceOver: it is custom-drawn and never
    /// becomes key.
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? {
        NSLocalizedString("Glyph strip", comment: "VoiceOver label for the menu-bar glyph strip")
    }

    override func accessibilityChildren() -> [Any]? {
        guard let controller else { return nil }
        accessibilitySegments = controller.segments.indices.compactMap { index in
            let segment = controller.segments[index]
            let label = GlyphStrip.accessibilityLabel(
                for: segment,
                focused: segment.spaceIndex != nil && segment.spaceIndex == controller.focusedSpaceIndex
            )
            guard !label.isEmpty else { return nil }
            let element = GlyphStripAccessibilityElement()
            element.controller = controller
            element.segmentIndex = index
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(label)
            if let rect = controller.segmentRect(index) {
                let windowRect = convert(rect, to: nil)
                element.setAccessibilityFrame(window?.convertToScreen(windowRect) ?? rect)
            }
            return element
        }
        return accessibilitySegments
    }

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

        // `.liquidGlass` paints only its edge here. The view's alpha carries the
        // opacity, so there is no fill to wash out the material.
        if controller.usesGlass, let backdrop = controller.backdrop(in: bounds) {
            if controller.borderEnabled {
                GlyphStrip.stroke(backdrop, color: controller.glassEdgeColor, opacity: 1)
            }
        } else if controller.usesSolid, let backdrop = controller.backdrop(in: bounds) {
            // Solid never blurs; opacity simply lets the desktop show through.
            GlyphStrip.fill(backdrop, color: controller.solidColor, opacity: controller.backgroundOpacity)
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
        for (offset, runs) in controller.runs.enumerated() {
            // Vertical placement stacks one segment per line; horizontal keeps
            // every segment on the one menu-bar row.
            guard let slot = controller.segmentRect(offset) else { continue }
            if controller.isStackedVertical {
                // Number on top, one icon per line underneath, each centred.
                let lines = GlyphStrip.stackedLines(
                    count: runs.count,
                    lineHeight: controller.contentLineHeight,
                    indexGap: controller.stackedGap(before: 1),
                    iconGap: controller.stackedGap(before: 2),
                    in: slot.insetBy(dx: 0, dy: controller.hoverPadding)
                )
                for (index, run) in runs.enumerated() where lines.indices.contains(index) {
                    let line = lines[index]
                    let x = controller.nativeIcon(segment: offset, run: index) == nil
                        ? Self.inkCenteredX(for: run, in: line)
                        : line.midX - run.size().width / 2
                    draw(run, x: x, in: line, controller: controller, segment: offset, index: index)
                }
                continue
            }
            let gaps = controller.gaps[offset]
            // Inline vertical centres the space's single line in the strip;
            // horizontal already has an exact slot.
            let inner = runs.indices.reduce(CGFloat(0)) { $0 + runs[$1].size().width + gaps[$1] }
            var x = controller.isVerticalLayout
                ? slot.midX - inner / 2
                : slot.minX + GlyphStripPanelController.horizontalPadding
            for (index, run) in runs.enumerated() {
                if index > 0 { x += gaps[index] }
                x += draw(run, x: x, in: slot, controller: controller, segment: offset, index: index)
            }
        }
    }

    /// Pen x that centres the run's **ink**, not its advance box. App-font
    /// glyphs carry asymmetric side bearings, so centring by advance leaves the
    /// visible glyph off-centre under its space number. Native icons fill their
    /// advance box exactly and keep the plain advance centring.
    fileprivate static func inkCenteredX(for run: NSAttributedString, in line: CGRect) -> CGFloat {
        let lineRef = CTLineCreateWithAttributedString(run)
        let ink = CTLineGetBoundsWithOptions(lineRef, .useGlyphPathBounds)
        guard ink.width > 0 else { return line.midX - run.size().width / 2 }
        return line.midX - ink.midX
    }

    /// Draws one run and returns its advance. Native icons fill the fallback
    /// advance; text draws on the line's shared baseline.
    @discardableResult
    private func draw(
        _ run: NSAttributedString,
        x: CGFloat,
        in line: CGRect,
        controller: GlyphStripPanelController,
        segment: Int,
        index: Int
    ) -> CGFloat {
        // Native icon: square image filling the fallback advance, the same
        // width the measuring path charged, centred on the content with the
        // `.app` lift so it sits where a font glyph would.
        if let image = controller.nativeIcon(segment: segment, run: index) {
            let advance = run.size().width
            let y = controller.contentY(in: line) + (controller.contentHeight - advance) / 2
                + controller.drawLift(segment: segment, run: index)
            // Fraction honors style() dimming (0.55 on resting runs).
            let fraction = (run.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.alphaComponent ?? 1.0
            image.draw(in: NSRect(x: x, y: y, width: advance, height: advance), from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: fraction)
            return advance
        }
        let baseline = controller.contentBaselineY(in: line)
        run.draw(at: NSPoint(
            x: x,
            y: baseline - GlyphStripPanelController.glyphDrop + controller.drawLift(segment: segment, run: index)
        ))
        return run.size().width
    }

    fileprivate static func font(of run: NSAttributedString) -> NSFont {
        run.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }
}
