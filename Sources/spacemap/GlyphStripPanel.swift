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
    /// Notified when displays are added, removed, or resized.
    private static let screenParametersChanged: Notification.Name =
        NSApplication.didChangeScreenParametersNotification

    private let yabaiService: YabaiService
    /// Own coordinator so the strip stays live while the HUD is hidden.
    /// `GridStateCoordinator` already carries the generation guard that stops a
    /// slow older yabai reply from overwriting newer state.
    private let coordinator: GridStateCoordinator
    private let themeStore: ThemeStore
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
    /// Panel lifecycle: window construction, alpha fades, drag frame math.
    private let presenter = PanelPresenter(factory: { mask in
        GlyphStripPanel(
            contentRect: .zero,
            styleMask: mask,
            backing: .buffered,
            defer: false
        )
    })
    /// Drawing layer, retained so refreshes can invalidate it directly.
    private var glyphs: GlyphStripView?
    /// Test seam: counts repaint requests made by `applyFrame(to:)`. AppKit may
    /// clear `needsDisplay` synchronously during presentation, so the real
    /// flag cannot be asserted reliably from a unit test.
    private(set) var contentRepaintCount = 0
    private var config: SpacemapConfig = .default
    /// Session-only visibility flag driven by the show/hide hotkey. Never
    /// persisted: every launch starts with the strip visible.
    private var hiddenByHotkey = false
    /// Session-only visibility flag for native fullscreen. Recomputed by a
    /// timer: entering or leaving fullscreen need not produce a yabai signal.
    private var hiddenByFullscreen = false
    /// Session-only visibility flag for Mission Control. Recomputed by the
    /// same timer: the window server sends no Mission Control notification.
    private var hiddenByMissionControl = false
    private var overlayTimer: Timer?
    private var statusItem: NSStatusItem?
    fileprivate var statusView: GlyphStripStatusView?
    fileprivate var segments: [GlyphStrip.Segment] = []
    fileprivate var attributedRuns: [[NSAttributedString]] = []
    /// Extra advance before each run, parallel to `attributedRuns`.
    fileprivate var runGaps: [[CGFloat]] = []
    /// Measured advance of each run, parallel to `attributedRuns`.
    fileprivate var runAdvances: [[CGFloat]] = []
    fileprivate var segmentWidths: [CGFloat] = []
    private var lastPaintedSegments: [GlyphStrip.Segment]?
    /// Segment options the current `segments` were built with, so a config edit
    /// between renders cannot remap drag payloads onto runs it did not build.
    fileprivate var renderOptions = GlyphStrip.Options(.default)
    /// Cached panel render: rebuilt only when the content or the bounds change,
    /// so hover and drag repaints share one layout pass.
    private var cachedLayout: GlyphStrip.SegmentLayout?
    private var cachedLayoutBounds = CGRect.zero
    /// Cached menu-bar render, keyed the same way: the status item draws and
    /// hit-tests far more often than the strip content changes.
    private var cachedStatusLayout: GlyphStrip.SegmentLayout?
    private var cachedStatusLayoutBounds = CGRect.zero
    /// Test seam: counts panel renders built instead of served from the cache.
    private(set) var layoutBuildCount = 0

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
            ) { [weak self] _ in
                self?.reconcileOverlayVisibility()
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

    // MARK: - Panel

    /// Creates the panel on first use, then always lays it out. Ordering front
    /// happens only when the panel is not already visible, so steady-state
    /// refreshes do not re-order the panel on every yabai signal.
    func present() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByFullscreen, !hiddenByMissionControl else {
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
            presenter.present(
                panel,
                duration: config.hudAnimationStyle.fadeDuration,
                animated: PanelPresenter.canAnimate(config.hudAnimationsEnabled)
            )
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
        guard let panel else { return }
        presenter.hide(
            panel,
            duration: config.hudAnimationStyle.fadeDuration,
            animated: PanelPresenter.canAnimate(config.hudAnimationsEnabled)
        )
    }

    private func makePanel() -> NSPanel {
        // Glass floats over the menu bar; the shadow separates its edge. The
        // `.statusBar` level keeps the strip above menu bar items.
        let panel = presenter.makePanel(PanelPresenter.Surface(
            level: .statusBar,
            hasShadow: true,
            collectionBehavior: [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle,
                .fullScreenAuxiliary
            ],
            hidesOnDeactivate: false
        ))
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
        let row = ScreenContext.menuBarRow(on: screen)
        // Free placement can leave the menu bar row, so `presentationFrame`
        // there is the whole display. Anchored positions keep the row.
        // Dragging stays free: the pointer can reach any screen edge. The safe
        // area only decides when a tall strip wraps into more columns.
        let area = strip.position == .custom ? ScreenContext.screenFrame(on: screen) : row
        let availableHeight = strip.position == .custom
            ? ScreenContext.safeScreenFrame(on: screen).height
            : row.height
        panel.level = strip.position == .custom ? .floating : .statusBar
        // A transparent strip draws no backdrop, so its only opaque pixels are
        // the glyphs and the window server would cast their outline as a black
        // shadow. Only shadow a surface that actually paints a shape.
        panel.hasShadow = strip.resolvedBackgroundMaterial(hud: config) != .none
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
            xFraction: strip.customX,
            yFraction: strip.customY
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
            // An anchored strip is pinned to the menu-bar row, so vertical
            // padding can only move the glyphs inside it. A free strip owns
            // its height, so padding grows the panel around the row.
            let vertical = config.glyphStrip.position == .custom
                ? CGFloat(config.glyphStrip.resolvedVerticalPadding) * 2
                : 0
            return CGSize(
                width: max(segmentWidths.reduce(0, +) + horizontal, 1),
                height: rowHeight + vertical
            )
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

    /// Strip content box. Both axes are inset, so split padding works for
    /// horizontal and vertical layouts alike.
    private func contentBounds(in bounds: CGRect) -> CGRect {
        // Keep a drawable pixel when padding exceeds the panel dimension.
        let dx = min(CGFloat(config.glyphStrip.resolvedHorizontalPadding), max((bounds.width - 1) / 2, 0))
        let dy = min(CGFloat(config.glyphStrip.resolvedVerticalPadding), max((bounds.height - 1) / 2, 0))
        return bounds.insetBy(dx: dx, dy: dy)
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

    // MARK: - Render layout

    /// One render for `bounds`: the value every draw and hit test reads.
    ///
    /// `statusItem` centres the slots in the whole button, because a menu-bar
    /// item can be wider than the strip, and shrinks native icons to the row
    /// height, which is what that surface drew and hit-tested before.
    fileprivate func layout(in bounds: CGRect, statusItem: Bool) -> GlyphStrip.SegmentLayout {
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
    fileprivate func statusItemLayout(in bounds: CGRect) -> GlyphStrip.SegmentLayout {
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
    fileprivate static let verticalColumnGap: CGFloat = 8

    // MARK: - Drag

    /// Live follow during a strip drag: `startFrame` is the panel frame
    /// captured at mouse-down and `delta` the pointer travel since, both in
    /// screen coordinates — the panel moves under the pointer, so window
    /// coordinates would stall after the first move.
    ///
    /// Switches the strip to `.custom` and steps the in-memory config along
    /// with the panel, so a refresh landing mid-drag recomputes the frame the
    /// drag already produced instead of snapping back to the old anchor.
    /// Fractions come from the inverse of `GlyphStrip.frame` and the frame
    /// itself comes from `applyFrame(to:)`, so the clamps apply exactly as they
    /// do on every other path.
    fileprivate func dragPanel(from startFrame: CGRect, by delta: CGVector) {
        guard !config.glyphStrip.isPositionLocked, config.glyphStrip.enabled, !hiddenByHotkey, let panel else { return }
        let candidate = PanelPresenter.draggedFrame(from: startFrame, by: delta)
        let screen = panelScreen() ?? targetScreen()
        var strip = config.glyphStrip
        strip.position = .custom
        if let fractions = GlyphStrip.customFractions(
            for: candidate,
            area: ScreenContext.screenFrame(on: screen)
        ) {
            strip.customX = fractions.x
            strip.customY = fractions.y
        }
        strip.customScreen = screen.map(ScreenContext.displayIdentifier(for:)) ?? ""
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
        let fractions = GlyphStrip.customFractions(
            for: panel.frame,
            area: ScreenContext.screenFrame(on: screen)
        )
        let identifier = screen.map(ScreenContext.displayIdentifier(for:)) ?? ""
        ConfigStore.updateConfig { saved in
            var strip = saved.glyphStrip
            strip.position = .custom
            if let fractions {
                strip.customX = fractions.x
                strip.customY = fractions.y
            }
            strip.customScreen = identifier
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
    /// pointer. A free-placed strip first honours the display it was dragged
    /// on, so its saved position survives monitor changes. `NSScreen.main`
    /// follows the key window, which is usually not Spacemap, so it is never
    /// the primary signal.
    private func targetScreen() -> NSScreen? {
        if let stored = Self.storedScreen(for: config.glyphStrip) {
            return stored
        }
        if let state = coordinator.state {
            if let focused = state.focusedIndex,
               let displayIndex = state.displayIndex(forSpace: focused),
               let display = state.displays.first(where: { $0.index == displayIndex }),
               let screen = ScreenContext.screen(containingQuartzFrame: display.frame.cgFrame) {
                return screen
            }
            if let focusedDisplay = state.displays.first(where: \.hasFocus),
               let screen = ScreenContext.screen(containingQuartzFrame: focusedDisplay.frame.cgFrame) {
                return screen
            }
        }
        return panelScreen() ?? ScreenContext.targetScreen()
    }

    /// The display a free-placed strip was saved on, if that display is still
    /// attached. Presets and a missing display return nil so the callers below
    /// pick the target.
    static func storedScreen(
        for strip: GlyphStripConfig,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        guard strip.position == .custom else { return nil }
        return ScreenContext.screen(matchingIdentifier: strip.customScreen, screens: screens)
    }

    /// The display the panel currently sits on, if any. Used by drags so a
    /// strip being moved does not snap back to the focused-space display.
    /// A strip straddling two displays resolves to the one holding most of it,
    /// matching how a HUD panel resolves its display.
    private func panelScreen() -> NSScreen? {
        guard let panel else { return nil }
        let screens = NSScreen.screens
        guard let index = ScreenContext.largestIntersection(
            screenFrames: screens.map(\.frame),
            frame: panel.frame
        ), screens.indices.contains(index) else { return nil }
        return screens[index]
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

    /// Painted run under `point`. Nil when the point is not on a run (padding,
    /// gap, or an empty segment).
    fileprivate func runHit(at point: NSPoint) -> (segment: Int, run: Int)? {
        layout.run(at: point)
    }

    /// Space number run: the strip's first run in a numbered segment. App
    /// initials use the same `.index` case, so position matters.
    fileprivate func isSpaceNumber(segment: Int, run: Int) -> Bool {
        guard segments.indices.contains(segment) else { return false }
        let runs = segments[segment].runs
        return run == 0
            && segments[segment].spaceIndex != nil
            && renderOptions.showSpaceNumbers
            && !runs.isEmpty
            && { if case .index = runs[0] { return true } else { return false } }()
    }

    fileprivate func spaceNumber(at point: NSPoint) -> Int? {
        guard let hit = runHit(at: point), isSpaceNumber(segment: hit.segment, run: hit.run) else { return nil }
        return segments[hit.segment].spaceIndex
    }

    fileprivate func draggedWindows(at point: NSPoint) -> (ids: [Int], source: Int)? {
        let layout = self.layout
        guard let hit = layout.run(at: point),
              segments.indices.contains(hit.segment),
              let source = segments[hit.segment].spaceIndex else { return nil }
        let windows = layout.runs[hit.segment][hit.run].windows
        return windows.isEmpty ? nil : (windows.map(\.id), source)
    }

    /// Segment directly under the pointer. Gaps, display separators, and the
    /// add button are not drop targets, so only real spaces highlight.
    fileprivate func dropSegment(at point: NSPoint) -> Int? {
        let layout = self.layout
        guard let index = layout.segment(at: point), segments.indices.contains(index) else { return nil }
        return segments[index].spaceIndex != nil ? index : nil
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
        // Full slot hits; hover highlight stays hover-sized in draw.
        layout.segment(at: point)
    }

    /// Slot of a segment in the view's own coordinates: the menu-bar row, or
    /// one stacked line per space when vertical.
    fileprivate func segmentRect(_ index: Int) -> CGRect? {
        layout.slot(index)
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
        themeStore.resolvedThemeName(strip: config.glyphStrip, hudTheme: config.theme)
    }

    /// The solid material's fill, at `backgroundOpacity`. Matches the HUD's
    /// `background` role when copying the HUD appearance (the HUD solid fill
    /// uses that role); otherwise the strip's own `cellBg`.
    fileprivate var solidColor: NSColor {
        let role = config.glyphStrip.matchHUDAppearance ? "background" : "cellBg"
        return GlyphStrip.color(for: role, theme: themeStore.named(effectiveThemeName))
            ?? .windowBackgroundColor
    }

    /// The glass layer only exists for `.liquidGlass`.
    fileprivate var usesGlass: Bool { backgroundMaterial == .liquidGlass }

    /// The flat fill only exists for `.solid`, at `backgroundOpacity`.
    fileprivate var usesSolid: Bool { backgroundMaterial == .solid }

    /// No backdrop at all when the material is `.none`. Single source of truth
    /// for `layout()` and `draw()`.
    fileprivate var drawsBackdrop: Bool { backgroundMaterial != .none }

    /// Single resolved backdrop shared by the solid fill and the glass mask so
    /// the two rects cannot disagree. `nil` when nothing is painted, or when
    /// the shape degenerates.
    fileprivate func backdrop(in bounds: CGRect) -> GlyphStrip.Backdrop? {
        guard drawsBackdrop else { return nil }
        let resolved = GlyphStrip.backdrop(bounds: bounds, cornerRadius: cornerRadius, insetForGlass: usesGlass)
        let clipped = resolved.rect.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return GlyphStrip.Backdrop(rect: clipped, cornerRadius: resolved.cornerRadius)
    }

    /// Outline path when no fill painted: the same rounded rect as
    /// `backdrop`, so material `.none` still outlines a pill, bar, or radius.
    fileprivate func borderBackdrop(in bounds: CGRect) -> GlyphStrip.Backdrop? {
        let resolved = GlyphStrip.backdrop(bounds: bounds, cornerRadius: cornerRadius, insetForGlass: usesGlass)
        let clipped = resolved.rect.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return GlyphStrip.Backdrop(rect: clipped, cornerRadius: resolved.cornerRadius)
    }

    fileprivate var strokeColor: NSColor {
        GlyphStrip.glassStrokeColor(theme: themeStore.named(effectiveThemeName))
    }

    /// Native glass tint for the tinted sub-type, `nil` for clear/opaque.
    /// The theme's accent, not its background: tinting with the surface colour
    /// reads as a slightly darker opaque glass instead of a tinted one.
    fileprivate var glassTintColor: NSColor? {
        guard glassStyle == .tinted else { return nil }
        return GlyphStrip.color(for: "focused", theme: themeStore.named(effectiveThemeName)) ?? solidColor
    }

    /// Tinted glass gets the theme-blended hairline; clear/opaque stay neutral.
    fileprivate var glassEdgeColor: NSColor {
        glassStyle == .tinted ? strokeColor : GlyphStrip.neutralGlassStrokeColor()
    }

    /// The hover highlight always uses the theme's `focused` role.
    fileprivate var hoverColor: NSColor {
        GlyphStrip.color(for: "focused", theme: themeStore.named(effectiveThemeName)) ?? .labelColor
    }

    fileprivate static func attributedRun(
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
            glass.cornerRadius = backdrop.cornerRadius
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
    fileprivate static func maskImage(for backdrop: GlyphStrip.Backdrop) -> NSImage? {
        let size = backdrop.rect.size
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: backdrop.cornerRadius,
                yRadius: backdrop.cornerRadius
            ).fill()
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
    private lazy var content = GlyphStripStatusContent(owner: self)
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
        addSubview(content)
    }

    override func layout() {
        super.layout()
        content.frame = bounds
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

    /// All painting happens in this child so the view itself can stay empty.
    override func draw(_ dirtyRect: NSRect) {}

    private var backdropArea: CGRect { bounds.insetBy(dx: 2, dy: 2) }
    fileprivate func drawContent(_ dirtyRect: NSRect) {
        guard let controller, !controller.segments.isEmpty else { return }
        if controller.usesSolid, let backdrop = controller.backdrop(in: backdropArea) {
            GlyphStrip.fill(backdrop, color: controller.solidColor, opacity: controller.backgroundOpacity)
            if controller.borderEnabled {
                GlyphStrip.stroke(backdrop, color: controller.strokeColor, opacity: 1)
            }
        } else if controller.usesGlass, let backdrop = controller.backdrop(in: backdropArea) {
            // A status item cannot host a backdrop blur: both
            // `NSGlassEffectView` and behind-window vibrancy flash black when
            // spaces change. Menu-bar mode is solid or transparent only, so
            // glass renders as its solid fill; the floating strip keeps glass.
            GlyphStrip.fill(backdrop, color: controller.solidColor, opacity: controller.backgroundOpacity)
            if controller.borderEnabled {
                GlyphStrip.stroke(backdrop, color: controller.strokeColor, opacity: 1)
            }
        } else if controller.borderEnabled, let border = controller.borderBackdrop(in: backdropArea) {
            GlyphStrip.stroke(border, color: controller.strokeColor, opacity: 1)
        }
        let layout = self.segmentLayout
        drawHighlight(
            for: hoveredSegment.flatMap(layout.slot),
            color: controller.hoverColor,
            opacity: GlyphStrip.hoverHighlightOpacity * hoverProgress
        )
        drawHighlight(
            for: controller.dragTargetSegment.flatMap(layout.slot),
            color: NSColor.controlAccentColor,
            opacity: 0.3
        )

        for (segmentIndex, runs) in controller.attributedRuns.enumerated() {
            guard layout.runs.indices.contains(segmentIndex) else { continue }
            let hoverScale: CGFloat = segmentIndex == hoveredSegment ? 1 + 0.06 * hoverProgress : 1
            let scale = hoverScale * contentScale(for: segmentIndex)
            let context = NSGraphicsContext.current?.cgContext
            let scaled = scale != 1 && context != nil
            if scaled, let context, let slot = layout.slot(segmentIndex) {
                context.saveGState()
                context.translateBy(x: slot.midX, y: slot.midY)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -slot.midX, y: -slot.midY)
            }
            defer { if scaled { context?.restoreGState() } }
            for (runIndex, run) in runs.enumerated() {
                guard layout.runs[segmentIndex].indices.contains(runIndex) else { continue }
                let frame = layout.runs[segmentIndex][runIndex].frame
                if let image = controller.nativeIcon(segment: segmentIndex, run: runIndex) {
                    let side = frame.width
                    image.draw(
                        in: NSRect(x: frame.minX, y: (bounds.height - side) / 2, width: side, height: side),
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1
                    )
                } else {
                    let size = run.size()
                    run.draw(at: NSPoint(x: frame.minX, y: (bounds.height - size.height) / 2))
                }
            }
        }
    }

    private func pointInView() -> NSPoint? {
        guard let window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(windowPoint, from: nil)
    }

    private func drawHighlight(for rect: CGRect?, color: NSColor, opacity: CGFloat) {
        guard let rect else { return }
        color.withAlphaComponent(opacity).setFill()
        // No horizontal inset: the number's ink starts at the slot edge, and
        // trimming a point left an unhovered sliver beside it.
        NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 3), xRadius: 3, yRadius: 3).fill()
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
        let layout = self.segmentLayout
        let run = layout.run(at: pressPoint, in: segment) ?? 0
        if run == 0, controller.segments[segment].runs.first?.isIndex == true {
            payload = .space(space)
        } else if layout.runs.indices.contains(segment),
                  layout.runs[segment].indices.contains(run),
                  !layout.runs[segment][run].windows.isEmpty {
            payload = .windows(layout.runs[segment][run].windows.map(\.id), source: space)
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

    /// One render for the button: slots centred in the wider button, native
    /// icons shrunk to the row.
    private var segmentLayout: GlyphStrip.SegmentLayout {
        controller?.statusItemLayout(in: bounds)
            ?? GlyphStrip.SegmentLayout(slots: [], runs: [])
    }

    private func segment(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        return segmentLayout.segment(at: point)
    }
}

/// Transparent drawing layer above the status item's glass/backdrop.
private final class GlyphStripStatusContent: NSView {
    weak var owner: GlyphStripStatusView?

    init(owner: GlyphStripStatusView) {
        self.owner = owner
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        owner?.drawContent(dirtyRect)
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
            let options = controller.renderOptions
            // A name reaches VoiceOver only when the strip paints it, and only
            // when it survives the same trim/blank rule, so numbers mode keeps
            // today's labels exactly.
            let spaceName = segment.spaceIndex.flatMap {
                GlyphStrip.spaceName(for: $0, options: options)
            }
            let label = GlyphStrip.accessibilityLabel(
                for: segment,
                focused: segment.spaceIndex != nil && segment.spaceIndex == controller.focusedSpaceIndex,
                spaceName: spaceName
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

        // Every frame comes from the one render value, so the pen, the hover
        // highlight, and the hit tests cannot disagree.
        let layout = controller.layout
        for (offset, runs) in controller.runs.enumerated() {
            guard let slot = layout.slot(offset), layout.runs.indices.contains(offset) else { continue }
            let scale = (offset == scalingSegment ? hoverScale : 1) * contentScale(for: offset)
            let context = NSGraphicsContext.current?.cgContext
            let scaled = scale != 1 && context != nil
            if scaled, let context {
                context.saveGState()
                context.translateBy(x: slot.midX, y: slot.midY)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -slot.midX, y: -slot.midY)
            }
            // Restores at the end of this loop iteration.
            defer { if scaled { context?.restoreGState() } }
            for (index, run) in runs.enumerated() {
                guard layout.runs[offset].indices.contains(index) else { continue }
                let frame = layout.runs[offset][index].frame
                draw(run, x: frame.minX, in: frame, controller: controller, segment: offset, index: index)
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

    /// Draws one run. Native icons fill the fallback advance; text draws on the
    /// line's shared baseline.
    private func draw(
        _ run: NSAttributedString,
        x: CGFloat,
        in line: CGRect,
        controller: GlyphStripPanelController,
        segment: Int,
        index: Int
    ) {
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
            return
        }
        let baseline = controller.contentBaselineY(in: line)
        run.draw(at: NSPoint(
            x: x,
            y: baseline - GlyphStripPanelController.glyphDrop + controller.drawLift(segment: segment, run: index)
        ))
    }

    fileprivate static func font(of run: NSAttributedString) -> NSFont {
        run.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }
}
