import AppKit
import ApplicationServices
import CoreText

/// Always-visible overlay strip parked in the menu bar row, hugging the notch.
///
/// Borderless `.nonactivatingPanel`, so clicking it never activates Spacemap and
/// yabai's `focus_follows_mouse` keeps the window underneath focused.
final class GlyphStripPanelController: NSObject {

    static let segmentPadding: CGFloat = 2
    /// Glyph origin drop: y-up coords, so -1 moves ink down 1pt.
    /// Backdrop/glass/hover rects untouched.
    static let glyphDrop: CGFloat = 1
    /// Notified when displays are added, removed, or resized.
    private static let screenParametersChanged: Notification.Name =
        NSApplication.didChangeScreenParametersNotification
    /// A menu-bar overlay joins every space, so it survives a space switch
    /// without being re-ordered.
    static let stripCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .stationary,
        .ignoresCycle,
        .fullScreenAuxiliary
    ]

    let yabaiService: YabaiService
    /// Own coordinator so the strip stays live while the HUD is hidden.
    /// `GridStateCoordinator` already carries the generation guard that stops a
    /// slow older yabai reply from overwriting newer state.
    let coordinator: GridStateCoordinator
    let themeStore: ThemeStore
    /// Background work queue: font load (disk IO + parse) runs here. Only
    /// the attributed-run apply, frame, and draw run on main.
    private static let stripWorkQueue = DispatchQueue(label: "com.spacemap.glyphstrip", qos: .userInitiated)
    /// Coalescing window for rapid space-change bursts: every refresh()
    /// cancels the pending one, so a burst paints once.
    private static let refreshCoalesceInterval: TimeInterval = 0.032
    private var lastRefreshAt: TimeInterval = 0
    /// Generation so a stale background reply never overwrites newer state.
    /// Read-only to tests so hiding can be asserted without exposing writes.
    var refreshGeneration = 0
    var pendingRefresh: DispatchWorkItem?
    /// Serializes refresh bodies: a refresh landing mid-pass sets
    /// `needsFollowupRefresh` for one bounded follow-up instead of recursing.
    var refreshInFlight = false
    var needsFollowupRefresh = false
    /// Generation that owns the in-flight latch; stale completions must not
    /// clear it for a refresh that replaced them.
    var inFlightGeneration = 0
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

    var panel: NSPanel?
    /// Panel lifecycle: window construction, alpha fades, drag frame math.
    let presenter = PanelPresenter(factory: { mask in
        GlyphStripPanel(
            contentRect: .zero,
            styleMask: mask,
            backing: .buffered,
            defer: false
        )
    })
    /// Drawing layer, retained so refreshes can invalidate it directly.
    var glyphs: GlyphStripView?
    /// Test seam: counts repaint requests made by `applyFrame(to:)`. AppKit may
    /// clear `needsDisplay` synchronously during presentation, so the real
    /// flag cannot be asserted reliably from a unit test.
    var contentRepaintCount = 0
    var config: SpacemapConfig = .default
    /// Session-only visibility flag driven by the show/hide hotkey. Never
    /// persisted: every launch starts with the strip visible.
    var hiddenByHotkey = false
    /// Session-only visibility flag for native fullscreen. Recomputed by a
    /// timer: entering or leaving fullscreen need not produce a yabai signal.
    var hiddenByFullscreen = false
    /// Session-only visibility flag for Mission Control. Recomputed by the
    /// same timer: the window server sends no Mission Control notification.
    var hiddenByMissionControl = false
    private var overlayTimer: Timer?
    private var statusItem: NSStatusItem?
    var statusView: GlyphStripStatusView?
    var segments: [GlyphStrip.Segment] = []
    var attributedRuns: [[NSAttributedString]] = []
    /// Extra advance before each run, parallel to `attributedRuns`.
    var runGaps: [[CGFloat]] = []
    /// Measured advance of each run, parallel to `attributedRuns`.
    var runAdvances: [[CGFloat]] = []
    var segmentWidths: [CGFloat] = []
    private var lastPaintedSegments: [GlyphStrip.Segment]?
    /// Segment options the current `segments` were built with, so a config edit
    /// between renders cannot remap drag payloads onto runs it did not build.
    var renderOptions = GlyphStrip.Options(.default)
    /// Cached panel render: rebuilt only when the content or the bounds change,
    /// so hover and drag repaints share one layout pass.
    var cachedLayout: GlyphStrip.SegmentLayout?
    var cachedLayoutBounds = CGRect.zero
    /// Cached menu-bar render, keyed the same way: the status item draws and
    /// hit-tests far more often than the strip content changes.
    var cachedStatusLayout: GlyphStrip.SegmentLayout?
    var cachedStatusLayoutBounds = CGRect.zero
    /// Test seam: counts panel renders built instead of served from the cache.
    var layoutBuildCount = 0

    /// Memory-only native icons, parallel to `segments` runs (nil for
    /// non-native runs and cache misses). One array drives measuring and
    /// drawing, so the frame can never disagree with what is painted.
    var nativeIcons: [[NSImage?]] = []
    /// Names with a background resolve already in flight. Stops a miss from
    /// re-triggering a refresh loop when the app has no bundle at all.
    private var nativeResolveInFlight = Set<String>()
    var focusedSpaceIndex: Int?
    var hoveredSegment: Int?
    var dragTargetSegment: Int?
    var dragTargetSpaceIndex: Int?
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

    init(yabaiService: YabaiService, themeStore: ThemeStore) {
        self.yabaiService = yabaiService
        self.themeStore = themeStore
        self.coordinator = GridStateCoordinator(yabaiService: yabaiService)
        super.init()
        // 0.25s keeps the Mission Control hide ahead of its snapshot animation.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.reconcileOverlayVisibility()
        }
        RunLoop.main.add(timer, forMode: .common)
        overlayTimer = timer
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
            ) { [weak self] note in
                self?.reconcileOverlayVisibility()
                if note.name == NSWorkspace.activeSpaceDidChangeNotification {
                    self?.reattachPanelToActiveSpace()
                }
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
        overlayTimer?.invalidate()
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

    func update(config: SpacemapConfig) {
        // The updater drops the cache itself on install, but a version written
        // by another process only shows up here. Unrelated settings saves must
        // not force the next refresh back to disk.
        if config.appFont.installedVersion != self.config.appFont.installedVersion {
            AppGlyphFont.invalidateCache()
        }
        self.config = config
        cachedLayout = nil
        cachedStatusLayout = nil
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
        themeStore.reloadIfChanged()
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByFullscreen, !hiddenByMissionControl else {
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

    /// Hides the strip while another app owns a native fullscreen window or
    /// Mission Control is up, and brings it back afterwards. Polled because
    /// the window server gives no notification for either; yabai signals alone
    /// miss the green-button case.
    private func reconcileOverlayVisibility() {
        // Mission Control copies every visible window into each space
        // thumbnail, so the strip hides there regardless of the fullscreen
        // setting.
        applyMissionControlVisibility(ScreenContext.isMissionControlActive())
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
            self.applyFullscreenVisibility(ScreenContext.hasFullscreenAppInFront(trusted: trusted))
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

    private func applyMissionControlVisibility(_ shouldHide: Bool) {
        guard shouldHide != hiddenByMissionControl else { return }
        hiddenByMissionControl = shouldHide
        if shouldHide {
            hide()
        } else {
            update(config: config)
        }
    }

    /// Native fullscreen on the focused space, from yabai's window or space flag.
    /// A fullscreen window on another space is invisible to the user, so the
    /// window-server and Accessibility checks alone cannot tell them apart.
    /// `nil` when the focused space or the field is unavailable.
    private func fullscreenWindowOnFocusedSpace() -> Bool? {
        guard let state = coordinator.state, let focused = state.focusedIndex else { return nil }
        return state.isFullscreen(spaceIndex: focused)
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
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByMissionControl else { return }
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
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByMissionControl else { return }
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
        coordinator.refresh { [weak self] in
            guard let self else { return }
            guard generation == self.refreshGeneration,
                  let state = self.coordinator.state else {
                // Stale reply or no state: drop it, never paint over newer state.
                self.finishRefresh(generation: generation)
                return
            }
            // Auto naming reads the space windows, so options wait for the state.
            let options = Self.segmentOptions(for: self.config, state: state)
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
        // A stopped daemon reports no spaces. Painting that would replace a
        // live strip with a lone add button and drop the focus highlight until
        // the next space change, so keep the last painted frame instead. Still
        // present it: a strip hidden by hotkey or fullscreen and re-shown during
        // downtime has kept segments but no frame on screen.
        if state.spaces.isEmpty, !segments.isEmpty {
            present()
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
              !hiddenByHotkey,
              !hiddenByMissionControl else {
            finishRefresh(generation: generation)
            return
        }
        rebuildRuns(strip: strip, options: options)
        fitToMaximumLength(strip: strip, options: options)
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
    private func fitToMaximumLength(strip: GlyphStripConfig, options: GlyphStrip.Options) {
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
            rebuildRuns(strip: fitted, options: options)
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

    private func rebuildRuns(strip: GlyphStripConfig, options: GlyphStrip.Options) {
        let theme = themeStore.named(effectiveThemeName)
        renderOptions = options
        cachedLayout = nil
        cachedStatusLayout = nil

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
                    style: GlyphStrip.style(for: run, isCurrent: isCurrent, strip: strip),
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
        runAdvances = attributedRuns.map { $0.map { $0.size().width } }
        let changed = GlyphStrip.changedSegments(previous: lastPaintedSegments, current: segments)
        lastPaintedSegments = segments
        if !changed.isEmpty {
            glyphs?.animateContentChange(segments: changed)
            statusView?.animateContentChange(segments: changed)
        }
        segmentWidths = runAdvances.indices.map { offset in
            let advances = runAdvances[offset]
            let gaps = runGaps[offset]
            // Resolved native icons fill their fallback's advance: the same
            // cell an `.app` run measures at this iconSize, side bearings
            // included. Hit and miss share one width, so resolving an icon
            // never reflows the strip.
            let glyphs = advances.indices.reduce(CGFloat(0)) { total, index in
                total + advances[index] + gaps[index]
            }
            return glyphs + Self.segmentPadding * 2
        }
    }

    /// The one place app config becomes segment options, so a new strip key is
    /// wired once for every render path.
    static func segmentOptions(for config: SpacemapConfig, state: GridState) -> GlyphStrip.Options {
        GlyphStrip.Options(config.glyphStrip, spaceNames: state.resolvedSpaceNames)
    }

    func presentMenuBarItem() {
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

    func removeStatusItem() {
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
            ScreenContext.screenFrame(on: NSScreen.main).width * 0.8
        )
        // Reassigning the length makes the menu bar relayout the whole item.
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
        if statusView?.frame != button.bounds {
            statusView?.frame = button.bounds
        }
        statusView?.refreshHover()
        statusView?.needsLayout = true
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

}
