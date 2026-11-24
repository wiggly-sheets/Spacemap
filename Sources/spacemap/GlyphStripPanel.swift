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
    static let screenParametersChanged: Notification.Name =
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
    static let stripWorkQueue = DispatchQueue(label: "com.spacemap.glyphstrip", qos: .userInitiated)
    /// Coalescing window for rapid space-change bursts: every refresh()
    /// cancels the pending one, so a burst paints once.
    static let refreshCoalesceInterval: TimeInterval = 0.032
    var lastRefreshAt: TimeInterval = 0
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
    var didLogMissingFont = false
    /// Face owner for the last painted pass. Drawing reads the face from the
    /// same file the codepoints came from.
    var glyphFont: AppGlyphFont?
    /// Availability gate for an already-loaded font: metadata parses but the
    /// face must resolve, else initials instead of tofu.
    func effectiveFont(from loaded: AppGlyphFont?) -> AppGlyphFont? {
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
    var overlayTimer: Timer?
    var statusItem: NSStatusItem?
    var statusView: GlyphStripStatusView?
    var segments: [GlyphStrip.Segment] = []
    var attributedRuns: [[NSAttributedString]] = []
    /// Extra advance before each run, parallel to `attributedRuns`.
    var runGaps: [[CGFloat]] = []
    /// Measured advance of each run, parallel to `attributedRuns`.
    var runAdvances: [[CGFloat]] = []
    var segmentWidths: [CGFloat] = []
    var lastPaintedSegments: [GlyphStrip.Segment]?
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
    var nativeResolveInFlight = Set<String>()
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
    var screenObserver: NSObjectProtocol?
    /// Reduce Transparency changes swap the native glass for the legacy
    /// effect view; nothing else reassigns the material while the strip is up.
    var accessibilityObserver: NSObjectProtocol?
    var wakeObserver: NSObjectProtocol?

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

}
