import AppKit
import ApplicationServices
import CoreText
import QuartzCore

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
    private var lastRefreshAt: TimeInterval = 0
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
    private var statusItem: NSStatusItem?
    fileprivate var statusView: GlyphStripStatusView?
    fileprivate var segments: [GlyphStrip.Segment] = []
    fileprivate var attributedRuns: [[NSAttributedString]] = []
    /// Extra advance before each run, parallel to `attributedRuns`.
    fileprivate var runGaps: [[CGFloat]] = []
    fileprivate var segmentWidths: [CGFloat] = []
    /// Windows behind each painted icon run, parallel to `attributedRuns`.
    /// Empty for the space number, overflow, and non-icon runs. Dedupe expands
    /// an icon to every window of its app.
    fileprivate var runWindows: [[[YabaiWindow]]] = []
    private var lastPaintedSegments: [GlyphStrip.Segment]?

    /// Segments whose painted content changed. A first build animates nothing;
    /// a count change animates the visible set because indices shifted.
    static func changedSegments(
        previous: [GlyphStrip.Segment]?,
        current: [GlyphStrip.Segment]
    ) -> [Int] {
        guard let previous else { return [] }
        guard previous.count == current.count else { return Array(current.indices) }
        return current.indices.filter { previous[$0] != current[$0] }
    }
    /// Painted frame of each run in view coordinates; zero when not drawn.
    /// Drag-and-drop hit-tests these, so it follows the same layout as `draw`.
    private var runFrames: [[CGRect]] = []
    /// Memory-only native icons, parallel to `segments` runs (nil for
    /// non-native runs and cache misses). One array drives measuring and
    /// drawing, so the frame can never disagree with what is painted.
    private var nativeIcons: [[NSImage?]] = []
    /// Names with a background resolve already in flight. Stops a miss from
    /// re-triggering a refresh loop when the app has no bundle at all.
    private var nativeResolveInFlight = Set<String>()
    fileprivate var focusedSpaceIndex: Int?
    private var hoveredSegment: Int?
    fileprivate var dragTargetSegment: Int?
    private var dragTargetSpaceIndex: Int?
    /// Resolves a drop onto a HUD cell in AppKit screen coordinates. Set by
    /// `SpacemapServices`; nil keeps strip-only dragging.
    var hudSpaceAtPoint: ((NSPoint) -> Int?)?
    /// Tells the HUD to hold its auto-hide timer while a strip drag is live.
    var onDragActive: ((Bool) -> Void)?
    /// Space being dragged, so the HUD does not highlight it as its own target.
    var onDragSourceSpace: ((Int?) -> Void)?
    /// Fired after a drop changes space contents or order, so every surface
    /// repaints from fresh yabai state.
    var onDropCompleted: (() -> Void)?
    private var screenObserver: NSObjectProtocol?
    /// Reduce Transparency changes swap the native glass for the legacy
    /// effect view; nothing else reassigns the material while the strip is up.
    private var accessibilityObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

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
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    /// Sleep can freeze a press or hover highlight on the menu-bar view.
    /// Clear both without rebuilding the status item: AppKit is still
    /// restoring the menu bar, and replacing the item steals the first click.
    private func handleWake() {
        // Rebuilding the status item here steals the first post-wake click:
        // AppKit is still restoring the menu bar and the new item is not yet
        // the one under the cursor. Clear any stale press and repaint instead.
        cancelGesture()
        statusView?.refreshHover()
        if let panel, panel.isVisible {
            applyFrame(to: panel)
        }
    }

    private func cancelGesture() {
        statusView?.cancelGesture()
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
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
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
        if let yabaiAnswer = fullscreenWindowOnFocusedSpace() {
            applyFullscreenVisibility(yabaiAnswer)
            return
        }
        // Accessibility can stall while permissions are edited. Never ask on
        // the main thread; fall back to geometry when the probe is unhealthy.
        PermissionProbe.shared.check(provider: { AXIsProcessTrusted() }) { [weak self] trusted in
            guard let self else { return }
            self.applyFullscreenVisibility(Self.hasFullscreenAppInFront(trusted: trusted))
        }
    }

    private func applyFullscreenVisibility(_ shouldHide: Bool) {
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
    static func hasFullscreenAppInFront(trusted: Bool? = nil) -> Bool {
        let isTrusted = trusted ?? (PermissionProbe.shared.isStalled ? false : AXIsProcessTrusted())
        guard isTrusted else { return frontWindowCoversDisplay() }
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
        // Leading edge: react to the first event immediately. Bursts within the
        // coalesce window collapse to one trailing pass instead of adding
        // 32ms to every single signal.
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastRefreshAt
        if elapsed >= Self.refreshCoalesceInterval, !refreshInFlight {
            lastRefreshAt = now
            pendingRefresh = nil
            runRefresh()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.lastRefreshAt = ProcessInfo.processInfo.systemUptime
            self?.runRefresh()
        }
        pendingRefresh = work
        let delay = max(0, Self.refreshCoalesceInterval - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
            if let font = self.glyphFont {
                // The face was parsed once per process. Reuse it instead of
                // hopping to the work queue and back on every movement.
                self.applyRefresh(
                    state: state,
                    options: options,
                    strip: strip,
                    generation: generation,
                    font: font,
                    focused: focused
                )
                return
            }
            Self.stripWorkQueue.async { [weak self] in
                // First pass only: disk IO + parse off-main.
                let loaded = AppGlyphFont.load()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard generation == self.refreshGeneration else {
                        self.finishRefresh(generation: generation)
                        return
                    }
                    let font = self.effectiveFont(from: loaded)
                    self.glyphFont = font
                    self.applyRefresh(
                        state: state,
                        options: options,
                        strip: strip,
                        generation: generation,
                        font: font,
                        focused: focused
                    )
                }
            }
        }
    }

    private func applyRefresh(
        state: GridState,
        options: GlyphStrip.Options,
        strip: GlyphStripConfig,
        generation: Int,
        font: AppGlyphFont?,
        focused: Int?
    ) {
        guard generation == refreshGeneration else {
            finishRefresh(generation: generation)
            return
        }
        let resolved = GlyphStrip.segments(
            for: state,
            options: options,
            font: font
        )
        let previousFocused = focusedSpaceIndex
        segments = resolved
        focusedSpaceIndex = focused
        // Watchdog: a non-empty state must never paint an empty strip from a
        // dropped pass — fall back to initials runs.
        if resolved.isEmpty && !state.spaces.isEmpty {
            NSLog("spacemap/GlyphStrip: empty segments for non-empty state; keeping last good frame")
            finishRefresh(generation: generation)
            return
        }
        // Re-check immediately before painting: the strip may have been
        // disabled or hidden by hotkey while the state work was in flight.
        guard generation == refreshGeneration,
              config.glyphStrip.enabled,
              !hiddenByHotkey else {
            finishRefresh(generation: generation)
            return
        }
        rebuildRuns(strip: strip)
        fitToMaximumLength(strip: strip)
        present()
        if previousFocused != focused, let glyphs {
            NSAccessibility.post(element: glyphs, notification: .valueChanged)
        }
        preloadNativeIcons()
        finishRefresh(generation: generation)
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

    /// Fit the strip to `autoResizeMaxLength` along its layout axis. Sizes grow
    /// when there is spare room and shrink when over, so the setting behaves
    /// like a target length instead of a shrink-only cap. Spacing scales with
    /// the glyphs so fixed gaps cannot leave the strip stuck over the target.
    private func fitToMaximumLength(strip: GlyphStripConfig) {
        let maximum = CGFloat(strip.autoResizeMaxLength)
        guard maximum > 0 else { return }
        var scale: CGFloat = 1
        var fitted = strip
        let baseIcon = CGFloat(strip.iconSize)
        let baseIndex = CGFloat(strip.indexSize)
        let baseIconSpacing = CGFloat(strip.iconSpacing)
        let baseIndexPadding = CGFloat(strip.indexPadding)
        let baseHoverPadding = CGFloat(strip.hoverPadding)
        for _ in 0..<6 {
            let length = stripLength
            guard length > 0 else { return }
            let wanted = min(max(scale * maximum / length, 0.5), 3)
            guard abs(wanted - scale) > 0.01 else { break }
            scale = wanted
            fitted.iconSize = max(baseIcon * scale, 8)
            fitted.indexSize = max(baseIndex * scale, 8)
            fitted.iconSpacing = baseIconSpacing * scale
            fitted.indexPadding = baseIndexPadding * scale
            fitted.hoverPadding = baseHoverPadding * scale
            rebuildRuns(strip: fitted)
        }
    }

    /// Length along the layout axis, including the strip's own padding.
    private var stripLength: CGFloat {
        let glyphs = isVerticalLayout
            ? verticalTotalHeight
            : segmentWidths.reduce(0, +)
        let padding = isVerticalLayout
            ? CGFloat(config.glyphStrip.resolvedVerticalPadding) * 2
            : CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
        return glyphs + padding
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
        let state = coordinator.state
        runWindows = segments.map { segment in
            guard let spaceIndex = segment.spaceIndex, let state else {
                return Array(repeating: [YabaiWindow](), count: segment.runs.count)
            }
            let all = GlyphStrip.windows(forSpace: spaceIndex, in: state)
            let shown = GlyphStrip.windowsToShow(all, dedupe: strip.dedupeAppsPerSpace)
            let limit = strip.maxIconsPerSpace == 0 ? shown.count : min(strip.maxIconsPerSpace, shown.count)
            let icons = Array(shown.prefix(limit))
            var windows: [[YabaiWindow]] = []
            var iconOffset = 0
            for run in segment.runs {
                switch run {
                case .app, .nativeIcon:
                    if icons.indices.contains(iconOffset) {
                        windows.append(GlyphStrip.draggedWindows(
                            for: icons[iconOffset],
                            allWindows: all,
                            dedupe: strip.dedupeAppsPerSpace
                        ))
                    } else {
                        windows.append([])
                    }
                    iconOffset += 1
                default:
                    windows.append([])
                }
            }
            return windows
        }
        runFrames = attributedRuns.map { Array(repeating: .zero, count: $0.count) }
        let changed = Self.changedSegments(previous: lastPaintedSegments, current: segments)
        lastPaintedSegments = segments
        if !changed.isEmpty {
            glyphs?.animateContentChange(segments: changed)
            statusView?.animateContentChange(segments: changed)
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

    private func presentMenuBarItem() {
        panel?.orderOut(nil)
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = ""
            item.button?.imagePosition = .noImage
            let view = GlyphStripStatusView(controller: self)
            view.autoresizingMask = [.width, .height]
            item.button?.addSubview(view)
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            statusView = view
            statusItem = item
        }
        updateStatusItem()
    }

    private func removeStatusItem() {
        statusView?.cancelGesture()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusView = nil
    }

    fileprivate func updateStatusItem() {
        guard let statusItem, let button = statusItem.button else { return }
        guard config.glyphStrip.displayMode == .menuBarItem else { return }
        let horizontal = CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
        let width = min(
            max(segmentWidths.reduce(0, +) + horizontal, 1),
            Self.screenFrame(on: NSScreen.main).width * 0.8
        )
        // Reassigning the length makes the menu bar relayout the whole item.
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
        if statusView?.frame != button.bounds {
            statusView?.frame = button.bounds
        }
        statusView?.refreshHover()
        statusView?.needsDisplay = true
    }

    /// The status-bar button can own the click tracking even when its custom
    /// subview draws the strip. Use the button action as a fallback so a click
    /// that never reaches `GlyphStripStatusView.mouseDown` still focuses.
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent, let view = statusView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        view.handleButtonClick(at: point, eventTime: event.timestamp)
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
        if config.glyphStrip.displayMode == .menuBarItem {
            presentMenuBarItem()
            return
        }
        removeStatusItem()
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        applyFrame(to: panel)
        if !panel.isVisible {
            if config.hudAnimationsEnabled, NSApp != nil, NSApp.isRunning {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = config.hudAnimationStyle.fadeDuration
                    panel.animator().alphaValue = 1
                }
            } else {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
        }
        if let glyphs {
            NSAccessibility.post(element: glyphs, notification: .layoutChanged)
        }
    }

    private func hide() {
        // A menu-bar item is a separate surface; ordering out the panel does
        // not remove it. Drop it before any early return so hotkey, fullscreen,
        // and disabled hides all take effect.
        removeStatusItem()
        // An in-flight refresh must not re-present a strip the user just hid or
        // disabled. Bumping the generation makes every pending reply stale, and
        // cancelling the coalesced work stops a queued pass from starting.
        refreshGeneration += 1
        pendingRefresh?.cancel()
        pendingRefresh = nil
        needsFollowupRefresh = false
        refreshInFlight = false
        inFlightGeneration = 0
        guard let panel, panel.isVisible else {
            panel?.orderOut(nil)
            return
        }
        guard config.hudAnimationsEnabled, NSApp != nil, NSApp.isRunning else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = config.hudAnimationStyle.fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            // A present during the fade animates back to 1; never order out
            // a strip the user just showed again.
            guard panel.alphaValue < 0.01 else {
                panel.alphaValue = 1
                return
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
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
        // Dragging stays free: the pointer can reach any screen edge. The safe
        // area only decides when a tall strip wraps into more columns.
        let area = strip.position == .custom ? Self.screenFrame(on: screen) : row
        let availableHeight = strip.position == .custom
            ? safeScreenFrame(on: screen).height
            : row.height
        panel.level = strip.position == .custom ? .floating : .statusBar
        let frame = GlyphStrip.frame(
            contentSize: stripContentSize(
                rowHeight: row.height,
                availableHeight: availableHeight
            ),
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
    private func stripContentSize(rowHeight: CGFloat, availableHeight: CGFloat) -> CGSize {
        guard isVerticalLayout else {
            let horizontal = CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
            return CGSize(width: max(segmentWidths.reduce(0, +) + horizontal, 1), height: rowHeight)
        }
        var width: CGFloat
        if isStackedVertical {
            // Each line holds one run, so the widest run sets the strip width.
            let widest = attributedRuns
                .map { runs in runs.map { $0.size().width }.max() ?? 0 }
                .max() ?? 0
            width = widest + Self.horizontalPadding * 2
        } else {
            width = segmentWidths.max() ?? 0
        }
        width += CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
        let padding = CGFloat(config.glyphStrip.resolvedVerticalPadding)
        let total = verticalTotalHeight
        let available = max(availableHeight - padding * 2, 1)
        let columns = GlyphStrip.verticalColumnCount(totalHeight: total, available: available)
        let columnsWidth = columns > 1
            ? width * CGFloat(columns) + Self.verticalColumnGap * CGFloat(columns - 1)
            : width
        let height = columns > 1 ? available : total
        return CGSize(width: max(columnsWidth, 1), height: max(height + padding * 2, 1))
    }

    /// Vertical stacking only applies to free placement; anchored positions
    /// stay in the single menu-bar row.
    fileprivate var isVerticalLayout: Bool {
        config.glyphStrip.displayMode == .floating
            && config.glyphStrip.position == .custom
            && config.glyphStrip.orientation == .vertical
    }

    /// Top and bottom breathing room for a vertical strip.
    /// Strip content box. Both axes are inset, so split padding works for
    /// horizontal and vertical layouts alike.
    fileprivate var contentBounds: CGRect {
        // Keep a drawable pixel when padding exceeds the panel dimension.
        let dx = min(CGFloat(config.glyphStrip.resolvedHorizontalPadding), max((viewBounds.width - 1) / 2, 0))
        let dy = min(CGFloat(config.glyphStrip.resolvedVerticalPadding), max((viewBounds.height - 1) / 2, 0))
        return viewBounds.insetBy(dx: dx, dy: dy)
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

    /// Gap between wrapped vertical columns.
    fileprivate static let verticalColumnGap: CGFloat = 8

    /// Usable area for a free-placed strip. Starts from the visible frame, then
    /// gives back space taken by edge-anchored accessory windows such as a
    /// third-party Dock. Menu-bar extras sit above the visible frame, and normal
    /// app windows are ignored.
    private func safeScreenFrame(on screen: NSScreen?) -> CGRect {
        guard let screen else { return .zero }
        let full = screen.frame
        var safe = screen.visibleFrame
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int, owner != Int(ownPID),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 3,
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  rect.intersects(full) else { continue }
            // Only edge furniture: a floating app window in the middle must not
            // push the strip around.
            let touchesBottom = abs(rect.minY - full.minY) <= 2
            let touchesTop = abs(rect.maxY - full.maxY) <= 2
            let touchesLeft = abs(rect.minX - full.minX) <= 2
            let touchesRight = abs(rect.maxX - full.maxX) <= 2
            // Dock-like only: one edge, thin along that edge, long across it.
            let edges = [touchesBottom, touchesTop, touchesLeft, touchesRight].filter { $0 }.count
            guard edges == 1 else { continue }
            let horizontal = touchesBottom || touchesTop
            let thin = horizontal ? rect.height <= full.height * 0.4 : rect.width <= full.width * 0.4
            let long = horizontal ? rect.width >= full.width * 0.25 : rect.height >= full.height * 0.25
            guard thin, long else { continue }
            // Only an obstacle that reaches into the usable area matters. The
            // menu bar itself sits above it, so its extras must not keep
            // shrinking the area.
            if touchesBottom, rect.maxY > safe.minY {
                safe.origin.y = max(safe.minY, rect.maxY + 4)
                safe.size.height = max(safe.maxY - safe.minY, 1)
            }
            if touchesTop, rect.minY < safe.maxY {
                let top = min(safe.maxY, rect.minY - 4)
                safe.size.height = max(top - safe.minY, 1)
            }
            if touchesLeft, rect.maxX > safe.minX {
                safe.origin.x = max(safe.minX, rect.maxX + 4)
                safe.size.width = max(safe.maxX - safe.minX, 1)
            }
            if touchesRight, rect.minX < safe.maxX {
                let right = min(safe.maxX, rect.minX - 4)
                safe.size.width = max(right - safe.minX, 1)
            }
        }
        return safe
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
        if case .focusSpace(let index) = command {
        }
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

    /// Painted run frame recorded by the draw loop. Nil when the point is not
    /// on a run (padding, gap, or an empty segment).
    fileprivate func runHit(at point: NSPoint) -> (segment: Int, run: Int)? {
        for (segment, frames) in runFrames.enumerated() {
            if let run = frames.firstIndex(where: { $0.contains(point) }) {
                return (segment, run)
            }
        }
        return nil
    }

    /// Space number run: the strip's first run in a numbered segment. App
    /// initials use the same `.index` case, so position matters.
    fileprivate func isSpaceNumber(segment: Int, run: Int) -> Bool {
        guard segments.indices.contains(segment) else { return false }
        let runs = segments[segment].runs
        return run == 0
            && segments[segment].spaceIndex != nil
            && config.glyphStrip.showSpaceNumbers
            && !runs.isEmpty
            && { if case .index = runs[0] { return true } else { return false } }()
    }

    fileprivate func spaceNumber(at point: NSPoint) -> Int? {
        guard let hit = runHit(at: point), isSpaceNumber(segment: hit.segment, run: hit.run) else { return nil }
        return segments[hit.segment].spaceIndex
    }

    fileprivate func draggedWindows(at point: NSPoint) -> (ids: [Int], source: Int)? {
        guard let hit = runHit(at: point),
              runWindows.indices.contains(hit.segment),
              runWindows[hit.segment].indices.contains(hit.run),
              let source = segments[hit.segment].spaceIndex else { return nil }
        let windows = runWindows[hit.segment][hit.run]
        return windows.isEmpty ? nil : (windows.map(\.id), source)
    }

    /// Segment directly under the pointer. Gaps, display separators, and the
    /// add button are not drop targets, so only real spaces highlight.
    fileprivate func dropSegment(at point: NSPoint) -> Int? {
        guard viewBounds.contains(point) else { return nil }
        for index in segments.indices where segments[index].spaceIndex != nil {
            guard let rect = segmentRect(index), rect.contains(point) else { continue }
            return index
        }
        return nil
    }

    /// The space currently highlighted as the drop destination. Drop uses
    /// this same value so highlight and result cannot diverge. Stored at
    /// targeting time, because a refresh can reorder segment indices mid-drag.
    fileprivate var dragTargetSpace: Int? { dragTargetSpaceIndex }

    fileprivate func setDragTarget(_ segment: Int?) {
        let space = segment.flatMap {
            segments.indices.contains($0) ? segments[$0].spaceIndex : nil
        }
        guard dragTargetSegment != segment || dragTargetSpaceIndex != space else { return }
        dragTargetSegment = segment
        dragTargetSpaceIndex = space
        glyphs?.needsDisplay = true
        statusView?.needsDisplay = true
    }

    fileprivate func recordRunFrame(_ frame: CGRect, segment: Int, run: Int) {
        guard runFrames.indices.contains(segment), runFrames[segment].indices.contains(run) else { return }
        runFrames[segment][run] = frame
    }

    fileprivate func performSpaceSwap(from source: Int, to target: Int) {
        // A space can disappear between drag start and drop; do not ask yabai
        // to swap an index that no longer exists.
        let live = Set(segments.compactMap(\.spaceIndex))
        guard source > 0, target > 0, source != target,
              live.contains(source), live.contains(target) else { return }
        yabaiService.swapSpaces(source, target, mode: config.spaceDropMode, focusMode: config.spaceDragFocus)
        refreshAfterDrag()
    }

    fileprivate func performWindowMove(ids: [Int], to target: Int, source: Int) {
        guard target > 0 else { return }
        yabaiService.moveWindows(ids, toSpace: target, focusMode: config.windowDragFocus, sourceSpace: source)
        refreshAfterDrag()
    }

    fileprivate func refreshAfterDrag() {
        // yabai applies the change asynchronously; a single early repaint can
        // still show the old order. Repaint a few times as the swap settles.
        for delay in [0.15, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
                self?.onDropCompleted?()
            }
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
            let bounds = contentBounds
            let total = heights.reduce(0, +)
            if total > bounds.height {
                let slots = GlyphStrip.verticalColumnSlots(
                    heights: heights,
                    in: bounds,
                    available: bounds.height,
                    columnGap: Self.verticalColumnGap
                )
                return slots.indices.contains(index) ? slots[index] : nil
            }
            let slots = GlyphStrip.verticalSlots(heights: heights, in: bounds)
            return slots.indices.contains(index) ? slots[index] : nil
        }
        let content = contentBounds
        let x = content.minX + segmentWidths.prefix(index).reduce(0, +)
        // The panel frame can be offset by yOffset, but view bounds stay
        // constant; padding insets both axes so vertical padding also works
        // for a horizontal strip.
        return CGRect(
            x: x,
            y: content.minY,
            width: segmentWidths[index],
            height: content.height
        )
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
    fileprivate var isPositionLocked: Bool { config.glyphStrip.isPositionLocked }
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

/// Compact menu-bar rendering: one horizontal row, no glass, shape or hover.
/// Clicks and the same space/app drag reorder work here; only the floating
/// strip's placement, glass and vertical layouts are unavailable.
private final class GlyphStripStatusView: NSView {
    weak var controller: GlyphStripPanelController?

    private enum Payload {
        case space(Int)
        case windows([Int], source: Int)

        var sourceSpace: Int {
            switch self {
            case .space(let source): return source
            case .windows(_, let source): return source
            }
        }
    }

    private var tracking: NSTrackingArea?
    private var hoveredSegment: Int?
    private var pressSegment: Int?
    private var pressCommand: GlyphStrip.Command?
    private var lastMouseDownTime: TimeInterval = 0
    private var lastHandledClickTime: TimeInterval = 0
    private var pressPoint: NSPoint?
    private var pressScreenLocation: NSPoint?
    private var globalDragMonitor: Any?
    private var payload: Payload?
    private var didDrag = false
    private var dragActivated = false
    private var hoverProgress: CGFloat = 0
    private var hoverTimer: Timer?
    private var hoverWatchdog: Timer?
    private var contentAnimationStart: CFTimeInterval?
    private var contentAnimationSegments: [Int] = []
    private var contentAnimationTimer: Timer?
    init(controller: GlyphStripPanelController) {
        self.controller = controller
        super.init(frame: .zero)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Spacemap spaces")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredSegment = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        stopHoverWatchdog()
        hoverProgress = 0
        needsDisplay = true
    }

    private func updateHover(_ event: NSEvent) {
        let eventPoint = convert(event.locationInWindow, from: nil)
        let segment = segment(at: clickPoint(eventPoint: eventPoint))
        guard segment != hoveredSegment else { return }
        hoveredSegment = segment
        hoverProgress = segment == nil ? 0 : 0
        hoverTimer?.invalidate()
        hoverTimer = nil
        if segment != nil {
            startHoverWatchdog()
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.hoverProgress = min(1, self.hoverProgress + 1.0 / 8.0)
                self.needsDisplay = true
                if self.hoverProgress >= 1 {
                    timer.invalidate()
                    self.hoverTimer = nil
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        }
        needsDisplay = true
    }

    /// Re-hit-tests the resting pointer after a menu-bar reflow, so the
    /// highlight and the next click name the same segment.
    fileprivate func refreshHover() {
        guard let window else {
            hoveredSegment = nil
            hoverProgress = 0
            stopHoverWatchdog()
            needsDisplay = true
            return
        }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let segment = segment(at: point)
        guard segment != hoveredSegment else { return }
        hoveredSegment = segment
        hoverProgress = segment == nil ? 0 : 1
        hoverTimer?.invalidate()
        hoverTimer = nil
        if segment == nil {
            stopHoverWatchdog()
        } else {
            startHoverWatchdog()
        }
        needsDisplay = true
    }

    /// The menu bar can reflow or an overlay can swallow `mouseExited`.
    /// Reconcile a visible hover against the physical pointer until it clears.
    private func startHoverWatchdog() {
        guard hoverWatchdog == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.refreshHover()
            if self.hoveredSegment == nil {
                timer.invalidate()
                self.hoverWatchdog = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverWatchdog = timer
    }

    private func stopHoverWatchdog() {
        hoverWatchdog?.invalidate()
        hoverWatchdog = nil
    }

    fileprivate func animateContentChange(segments: [Int]) {
        guard !segments.isEmpty else { return }
        contentAnimationSegments = segments
        contentAnimationStart = CACurrentMediaTime()
        contentAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - (self.contentAnimationStart ?? 0)
            self.needsDisplay = true
            if elapsed >= 0.24 {
                timer.invalidate()
                self.contentAnimationTimer = nil
                self.contentAnimationStart = nil
                self.contentAnimationSegments = []
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        contentAnimationTimer = timer
        needsDisplay = true
    }

    private func contentScale(for segment: Int) -> CGFloat {
        guard let start = contentAnimationStart,
              let order = contentAnimationSegments.firstIndex(of: segment) else { return 1 }
        let elapsed = CACurrentMediaTime() - start - Double(order) * 0.015
        let progress = min(max(elapsed / 0.18, 0), 1)
        return 0.9 + 0.1 * (1 - pow(1 - progress, 3))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, !controller.segments.isEmpty else { return }
        drawHighlight(
            for: hoveredSegment,
            color: NSColor.selectedContentBackgroundColor,
            opacity: 0.18 * hoverProgress
        )
        drawHighlight(
            for: controller.dragTargetSegment,
            color: NSColor.controlAccentColor,
            opacity: 0.3
        )

        var x = contentOffset
        for (segmentIndex, runs) in controller.attributedRuns.enumerated() {
            let gaps = controller.runGaps[segmentIndex]
            let slotWidth = controller.segmentWidths[segmentIndex]
            let hoverScale: CGFloat = segmentIndex == hoveredSegment ? 1 + 0.06 * hoverProgress : 1
            let scale = hoverScale * contentScale(for: segmentIndex)
            let context = NSGraphicsContext.current?.cgContext
            let scaled = scale != 1 && context != nil
            if scaled, let context, let slot = segmentRect(segmentIndex) {
                context.saveGState()
                context.translateBy(x: slot.midX, y: slot.midY)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -slot.midX, y: -slot.midY)
            }
            defer { if scaled { context?.restoreGState() } }
            var runX = x + 2
            for (runIndex, run) in runs.enumerated() {
                if runIndex > 0 { runX += gaps[runIndex] }
                if let image = controller.nativeIcon(segment: segmentIndex, run: runIndex) {
                    let side = min(run.size().width, bounds.height - 4)
                    image.draw(
                        in: NSRect(x: runX, y: (bounds.height - side) / 2, width: side, height: side),
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1
                    )
                    runX += side
                } else {
                    let size = run.size()
                    run.draw(at: NSPoint(x: runX, y: (bounds.height - size.height) / 2))
                    runX += size.width
                }
            }
            x += slotWidth
        }
    }

    private func pointInView() -> NSPoint? {
        guard let window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(windowPoint, from: nil)
    }

    private func drawHighlight(for segment: Int?, color: NSColor, opacity: CGFloat) {
        guard let segment, let rect = segmentRect(segment) else { return }
        color.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 3), xRadius: 3, yRadius: 3).fill()
    }

    /// The status item can deliver a synthesized center press when another
    /// menu-bar window forwards the click. Prefer the physical pointer, which
    /// still names the segment the user aimed at.
    private func clickPoint(eventPoint: NSPoint) -> NSPoint {
        if let cursor = pointInView(), bounds.contains(cursor) {
            return cursor
        }
        return eventPoint
    }

    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        let eventPoint = convert(event.locationInWindow, from: nil)
        let pressPoint = clickPoint(eventPoint: eventPoint)
        // A lost mouse-up from the previous press would otherwise leave a
        // monitor and a pressed segment behind for this click to inherit.
        removeGlobalDragMonitor()
        pressSegment = nil
        pressCommand = nil
        lastMouseDownTime = event.timestamp
        self.pressPoint = pressPoint
        pressScreenLocation = NSEvent.mouseLocation
        didDrag = false
        dragActivated = false
        payload = nil
        // Menu-bar refreshes can reflow the item under a resting pointer, so
        // the cached hover may name a segment that is no longer under the
        // cursor. Hit-test the press point instead of trusting it.
        let hitSegment = segment(at: pressPoint)
        guard let segment = hitSegment,
              controller.segments.indices.contains(segment) else {
            return
        }
        // The add button has no space index and nothing to drag. It waits for
        // the local mouse-up, which closes the status item's tracking loop.
        if controller.segments[segment].runs == [.add] {
            pressSegment = segment
            pressCommand = .createSpace
            return
        }
        guard let space = controller.segments[segment].spaceIndex else { return }
        pressSegment = segment
        // Capture the command at press time: a refresh between press and
        // release can reorder segments, and the click must still target the
        // space the user pressed.
        pressCommand = controller.command(forSegment: segment, click: .left)
        // Run geometry only matters for a drag. A missing run must not swallow
        // a plain click while the strip is repainting.
        let run = run(at: pressPoint, in: segment)
        if run == 0, controller.segments[segment].runs.first?.isIndex == true {
            payload = .space(space)
        } else if let run,
                  controller.runWindows.indices.contains(segment),
                  controller.runWindows[segment].indices.contains(run),
                  !controller.runWindows[segment][run].isEmpty {
            payload = .windows(controller.runWindows[segment][run].map(\.id), source: space)
        }
        if payload != nil {
            installGlobalDragMonitor()
        }
    }

    /// Fallback for a status-item button that receives a click while its
    /// custom subview does not. The button action fires on mouse-up.
    fileprivate func handleButtonClick(at eventPoint: NSPoint, eventTime: TimeInterval) {
        // A press that reached the view already owns its own release path.
        guard abs(eventTime - lastMouseDownTime) > 0.5 else {
            return
        }
        let point = clickPoint(eventPoint: eventPoint)
        guard lastHandledClickTime != eventTime,
              bounds.contains(point),
              let controller,
              let segment = segment(at: point),
              controller.segments.indices.contains(segment),
              let command = controller.command(forSegment: segment, click: .left) else { return }
        lastHandledClickTime = eventTime
        controller.handle(command)
    }

    /// A status-item view can lose the dragged/up stream while its button
    /// tracks the mouse. The global monitor supplies those events for drags
    /// that begin on a space number or app icon.
    private func installGlobalDragMonitor() {
        removeGlobalDragMonitor()
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDragged {
                self.mouseDragged(with: event)
            } else {
                self.removeGlobalDragMonitor()
                self.mouseUp(with: event)
            }
        }
    }

    private func removeGlobalDragMonitor() {
        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
            self.globalDragMonitor = nil
        }
    }

    /// Drops an in-flight press when the status item is rebuilt or removed, so
    /// a global monitor cannot outlive its view or finish a drag that no longer
    /// has a strip.
    fileprivate func cancelGesture() {
        let activated = dragActivated
        removeGlobalDragMonitor()
        pressSegment = nil
        pressCommand = nil
        pressPoint = nil
        pressScreenLocation = nil
        payload = nil
        didDrag = false
        dragActivated = false
        if activated {
            controller?.onDragSourceSpace?(nil)
            controller?.onDragActive?(false)
            controller?.setDragTarget(nil)
        }
    }

    deinit {
        removeGlobalDragMonitor()
        stopHoverWatchdog()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller, payload != nil else { return }
        if !didDrag {
            guard let start = pressScreenLocation else { return }
            let location = NSEvent.mouseLocation
            let delta = CGVector(dx: location.x - start.x, dy: location.y - start.y)
            guard GlyphStrip.exceedsDragThreshold(delta) else { return }
            didDrag = true
            dragActivated = true
            if let payload {
                activateDragSource(payload, controller: controller)
            }
        }
        guard let point = pointInView(), let target = segment(at: point) else {
            controller.setDragTarget(nil)
            return
        }
        let targetSpace = controller.segments[target].spaceIndex
        controller.setDragTarget(targetSpace == payloadSourceSpace ? nil : target)
    }

    override func mouseUp(with event: NSEvent) {
        // A status item sends its own mouse-up immediately after mouse-down.
        // For a draggable press the real gesture continues in the global
        // monitor, so do not finish until that monitor sees the release.
        if globalDragMonitor != nil && !didDrag && !dragActivated {
            return
        }
        finishGesture()
    }

    private func finishGesture() {
        removeGlobalDragMonitor()
        guard let controller else { return }
        let dragged = didDrag
        let activated = dragActivated
        let currentPayload = payload
        let hudTarget = controller.hudSpaceAtPoint?(NSEvent.mouseLocation)
        let targetSpace = controller.dragTargetSpace
            ?? pointInView().flatMap { segment(at: $0) }
                .flatMap { controller.segments.indices.contains($0) ? controller.segments[$0].spaceIndex : nil }
        let pressedCommand = pressCommand
        pressSegment = nil
        pressCommand = nil
        pressPoint = nil
        pressScreenLocation = nil
        payload = nil
        didDrag = false
        dragActivated = false
        if activated {
            controller.onDragSourceSpace?(nil)
            controller.onDragActive?(false)
            controller.setDragTarget(nil)
        }

        if dragged {
            // A tiny pointer wobble during a click can pass the drag threshold.
            // Only a drag that reached some other space is a drop; otherwise
            // finish it as the click the user made.
            let sourceSpace = currentPayload?.sourceSpace
            if GlyphStrip.dragResolvesToDrop(
                hudTarget: hudTarget,
                targetSpace: targetSpace,
                sourceSpace: sourceSpace
            ) {
                if let currentPayload {
                    performDrop(currentPayload, hudTarget: hudTarget, targetSpace: targetSpace, controller: controller)
                }
            } else if let pressedCommand {
                controller.handle(pressedCommand)
            }
            return
        }

        // The status item can reflow between press and release. Use the
        // command captured at press time, never the new geometry.
        guard let pressedCommand else { return }
        controller.handle(pressedCommand)
    }

    private var payloadSourceSpace: Int? {
        switch payload {
        case .space(let source)?: return source
        case .windows(_, let source)?: return source
        case .none: return nil
        }
    }
    private func activateDragSource(_ payload: Payload, controller: GlyphStripPanelController) {
        switch payload {
        case .space(let source):
            controller.onDragSourceSpace?(source)
        case .windows(_, let source):
            controller.onDragSourceSpace?(source)
        }
        controller.onDragActive?(true)
    }

    private func performDrop(
        _ payload: Payload,
        hudTarget: Int?,
        targetSpace: Int?,
        controller: GlyphStripPanelController
    ) {
        switch payload {
        case .space(let source):
            if let hudTarget {
                controller.performSpaceSwap(from: source, to: hudTarget)
            } else if let targetSpace {
                controller.performSpaceSwap(from: source, to: targetSpace)
            }
        case .windows(let ids, let source):
            if let hudTarget {
                controller.performWindowMove(ids: ids, to: hudTarget, source: source)
            } else if let targetSpace {
                controller.performWindowMove(ids: ids, to: targetSpace, source: source)
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let controller,
              let segment = segment(at: convert(event.locationInWindow, from: nil)),
              let command = controller.command(forSegment: segment, click: .right) else { return }
        controller.handle(command)
    }

    private var contentOffset: CGFloat {
        guard let controller else { return 0 }
        return max((bounds.width - controller.segmentWidths.reduce(0, +)) / 2, 0)
    }

    private func segmentRect(_ index: Int) -> CGRect? {
        guard let controller, controller.segmentWidths.indices.contains(index) else { return nil }
        let x = contentOffset + controller.segmentWidths.prefix(index).reduce(0, +)
        return CGRect(x: x, y: 0, width: controller.segmentWidths[index], height: bounds.height)
    }

    private func segment(at point: NSPoint) -> Int? {
        guard let controller, bounds.contains(point) else { return nil }
        var x = contentOffset
        for (index, width) in controller.segmentWidths.enumerated() {
            if point.x >= x && point.x < x + width { return index }
            x += width
        }
        return nil
    }

    private func run(at point: NSPoint, in segment: Int) -> Int? {
        guard let controller,
              controller.attributedRuns.indices.contains(segment),
              let rect = segmentRect(segment) else { return nil }
        let runs = controller.attributedRuns[segment]
        let gaps = controller.runGaps[segment]
        var x = rect.minX + 2
        for (run, runString) in runs.enumerated() {
            if run > 0 { x += gaps[run] }
            let width = controller.nativeIcon(segment: segment, run: run) == nil
                ? runString.size().width
                : min(runString.size().width, bounds.height - 4)
            if point.x >= x && point.x < x + width { return run }
            x += width
        }
        return 0
    }
}

extension GlyphStrip.Run {
    fileprivate var isIndex: Bool {
        if case .index = self { return true }
        return false
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

    /// Locked strips give up panel dragging: a press on a space number or an
    /// app icon starts a reorder instead.
    private enum DragPayload {
        case space(Int)
        case windows([Int], source: Int)
    }
    private var dragPayload: DragPayload?
    private var dragActivated = false
    /// Hover pop: the segment eases to 1.07 and back. Custom drawing has no
    /// animatable property, so a short timer interpolates the scale.
    private var hoverAnimationTimer: Timer?
    private var hoverScale: CGFloat = 1
    private var scalingSegment: Int?
    /// Content pop after a yabai refresh, so an icon moving between spaces
    /// visibly lands instead of teleporting.
    private var contentAnimationStart: CFTimeInterval?
    private var contentAnimationTimer: Timer?
    private var contentAnimationSegments: [Int] = []

    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        // Screen coordinates, not window ones: the panel moves under the
        // pointer during a drag, and window-space locations drift with it.
        pressScreenLocation = NSEvent.mouseLocation
        pressFrame = controller.panelFrame
        let point = convert(event.locationInWindow, from: nil)
        pressPoint = point
        didDrag = false
        dragPayload = nil
        if controller.isPositionLocked {
            if let space = controller.spaceNumber(at: point) {
                dragPayload = .space(space)
            } else if let dragged = controller.draggedWindows(at: point) {
                dragPayload = .windows(dragged.ids, source: dragged.source)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller,
              let start = pressScreenLocation,
              let startFrame = pressFrame else { return }
        let location = NSEvent.mouseLocation
        let delta = CGVector(dx: location.x - start.x, dy: location.y - start.y)
        if dragPayload != nil {
            guard didDrag || GlyphStrip.exceedsDragThreshold(delta) else { return }
            if !didDrag {
                didDrag = true
                dragActivated = true
                switch dragPayload {
                case .space(let source)?:
                    controller.onDragSourceSpace?(source)
                case .windows(_, let source)?:
                    controller.onDragSourceSpace?(source)
                case .none:
                    break
                }
                controller.onDragActive?(true)
            }
            let point = convert(event.locationInWindow, from: nil)
            guard let target = controller.dropSegment(at: point) else {
                controller.setDragTarget(nil)
                return
            }
            // `setDragTarget` takes a segment index, not a space index.
            var sourceSpace: Int?
            if case .space(let source)? = dragPayload { sourceSpace = source }
            let targetSpace = controller.segments[target].spaceIndex
            controller.setDragTarget(targetSpace == sourceSpace ? nil : target)
            return
        }
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
        let activated = dragActivated
        let point = pressPoint
        let payload = dragPayload
        didDrag = false
        dragActivated = false
        pressPoint = nil
        pressScreenLocation = nil
        pressFrame = nil
        dragPayload = nil
        if payload != nil {
            let hudTarget = controller?.hudSpaceAtPoint?(NSEvent.mouseLocation)
            let target = controller?.dragTargetSpace
            if activated {
                controller?.onDragSourceSpace?(nil)
                controller?.onDragActive?(false)
                controller?.setDragTarget(nil)
            }
            if dragged, target != nil || hudTarget != nil {
                switch payload {
                case .space(let source):
                    if let hudTarget {
                        controller?.performSpaceSwap(from: source, to: hudTarget)
                    } else if let target {
                        controller?.performSpaceSwap(from: source, to: target)
                    }
                case .windows(let ids, let source):
                    if let hudTarget {
                        controller?.performWindowMove(ids: ids, to: hudTarget, source: source)
                    } else if let target {
                        controller?.performWindowMove(ids: ids, to: target, source: source)
                    }
                case .none: break
                }
            }
            if dragged { return }
        }
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

        // Drop target: the same capsule as hover, brighter so it reads as an
        // active drop while the pointer is away from the segment.
        if let target = controller.dragTargetSegment,
           let highlight = controller.hoverBackdrop(target) {
            GlyphStrip.fill(highlight, color: controller.hoverColor, opacity: 0.45)
        }

        // `segmentWidths` charges every segment a leading *and* a trailing
        // `horizontalPadding`, so the pen has to spend both or the drawn content
        // ends up short of the frame and drifts left of the slot centres the
        // hover highlight is anchored to.
        for (offset, runs) in controller.runs.enumerated() {
            // Vertical placement stacks one segment per line; horizontal keeps
            // every segment on the one menu-bar row.
            guard let slot = controller.segmentRect(offset) else { continue }
            let scale = (offset == scalingSegment ? hoverScale : 1) * contentScale(for: offset)
            let context = NSGraphicsContext.current?.cgContext
            let scaled = scale != 1 && context != nil
            if scaled, let context {
                context.saveGState()
                context.translateBy(x: slot.midX, y: slot.midY)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -slot.midX, y: -slot.midY)
            }
            // Restores at the end of this loop iteration, including the
            // stacked branch's `continue`.
            defer { if scaled { context?.restoreGState() } }
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
                    let advance = draw(run, x: x, in: line, controller: controller, segment: offset, index: index)
                    controller.recordRunFrame(
                        CGRect(x: x, y: line.minY, width: advance, height: line.height),
                        segment: offset,
                        run: index
                    )
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
                let advance = draw(run, x: x, in: slot, controller: controller, segment: offset, index: index)
                controller.recordRunFrame(
                    CGRect(x: x, y: slot.minY, width: advance, height: slot.height),
                    segment: offset,
                    run: index
                )
                x += advance
            }
        }
    }

    fileprivate func animateContentChange(segments: [Int]) {
        contentAnimationSegments = segments
        contentAnimationStart = CACurrentMediaTime()
        contentAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - (self.contentAnimationStart ?? 0)
            self.needsDisplay = true
            if elapsed >= 0.24 {
                timer.invalidate()
                self.contentAnimationTimer = nil
                self.contentAnimationStart = nil
                self.contentAnimationSegments = []
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        contentAnimationTimer = timer
        needsDisplay = true
    }

    private func contentScale(for segment: Int) -> CGFloat {
        guard let start = contentAnimationStart,
              let order = contentAnimationSegments.firstIndex(of: segment) else { return 1 }
        let elapsed = CACurrentMediaTime() - start - Double(order) * 0.015
        let progress = min(max(elapsed / 0.18, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        return 0.9 + 0.1 * eased
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
