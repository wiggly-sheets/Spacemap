import AppKit

/// Panel lifecycle shared by the HUD and the glyph strip: window construction,
/// alpha fades, and the drag frame math. Content and entrance styles stay with
/// each surface.
final class PanelPresenter {
    /// Per-surface window configuration. The strip changes `level` per frame
    /// (`.statusBar` anchored, `.floating` free-placed), so it stays a
    /// parameter rather than baked into the presenter.
    struct Surface {
        var level: NSWindow.Level
        var hasShadow: Bool
        var collectionBehavior: NSWindow.CollectionBehavior
        /// `nil` keeps AppKit's default (HUD); the strip opts out so it
        /// survives another app becoming frontmost.
        var hidesOnDeactivate: Bool?
    }

    typealias PanelFactory = (NSWindow.StyleMask) -> NSPanel

    static let defaultPanelFactory: PanelFactory = { mask in
        NSPanel(
            contentRect: .zero,
            styleMask: mask,
            backing: .buffered,
            defer: false
        )
    }

    private let factory: PanelFactory

    /// `factory` is the test seam, mirroring `HUDDisplay.screenFramesOverride`:
    /// tests can build panels without a running app.
    init(factory: @escaping PanelFactory = PanelPresenter.defaultPanelFactory) {
        self.factory = factory
    }

    func makePanel(_ surface: Surface) -> NSPanel {
        let panel = factory([.borderless, .nonactivatingPanel])
        panel.isOpaque = false
        panel.backgroundColor = .clear
        if let hidesOnDeactivate = surface.hidesOnDeactivate {
            panel.hidesOnDeactivate = hidesOnDeactivate
        }
        panel.hasShadow = surface.hasShadow
        panel.level = surface.level
        panel.collectionBehavior = surface.collectionBehavior
        return panel
    }

    /// NSAnimationContext needs a running app; unit tests create windows but do
    /// not spin an app event loop, so animate only in the real app.
    static func canAnimate(_ enabled: Bool) -> Bool {
        enabled && NSApp != nil && NSApp.isRunning
    }

    /// Order a panel in, fading alpha when animations run. Callers check
    /// `isVisible` first so repeated state renders do not re-animate it.
    func present(_ panel: NSPanel, duration: TimeInterval, animated: Bool) {
        guard animated else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 1
        }
    }

    /// Whether an animated hide should finish. A present that races the fade can
    /// raise alpha back above the threshold, and the panel must stay visible.
    static func shouldCompleteHide(currentAlpha: CGFloat) -> Bool {
        currentAlpha < 0.01
    }

    /// Fade a visible panel out, then order it out. When a present raced the
    /// fade, the completion restores the panel and keeps it visible instead.
    func hide(_ panel: NSPanel, duration: TimeInterval, animated: Bool) {
        guard panel.isVisible, animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: {
            guard Self.shouldCompleteHide(currentAlpha: panel.alphaValue) else {
                panel.alphaValue = 1
                return
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    /// Pointer travel in screen coordinates: the panel moves under the pointer,
    /// so window coordinates would stall after the first move.
    static func dragDelta(from start: CGPoint, to current: CGPoint) -> CGVector {
        CGVector(dx: current.x - start.x, dy: current.y - start.y)
    }

    /// Frame a panel occupies after pointer travel `delta` from `startFrame`.
    static func draggedFrame(from startFrame: CGRect, by delta: CGVector) -> CGRect {
        startFrame.offsetBy(dx: delta.dx, dy: delta.dy)
    }
}
