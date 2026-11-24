import AppKit
import ApplicationServices
import CoreText

/// Compact menu-bar rendering: one horizontal row, no glass, shape or hover.
/// Clicks and the same space/app drag reorder work here; only the floating
/// strip's placement, glass and vertical layouts are unavailable.
final class GlyphStripStatusView: NSView {
    weak var controller: GlyphStripPanelController?

    enum Payload {
        case space(Int)
        case windows([Int], source: Int)

        var sourceSpace: Int {
            switch self {
            case .space(let source): return source
            case .windows(_, let source): return source
            }
        }
    }

    var tracking: NSTrackingArea?
    var hoveredSegment: Int?
    lazy var content = GlyphStripStatusContent(owner: self)
    var pressSegment: Int?
    var pressCommand: GlyphStrip.Command?
    var lastMouseDownTime: TimeInterval = 0
    var lastHandledClickTime: TimeInterval = 0
    var pressPoint: NSPoint?
    var pressScreenLocation: NSPoint?
    var globalDragMonitor: Any?
    var payload: Payload?
    var didDrag = false
    var dragActivated = false
    var hoverProgress: CGFloat = 0
    var hoverTimer: Timer?
    var hoverWatchdog: Timer?
    var contentAnimationStart: CFTimeInterval?
    var contentAnimationSegments: [Int] = []
    var contentAnimationTimer: Timer?
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

    var backdropArea: CGRect { bounds.insetBy(dx: 2, dy: 2) }
    deinit {
        removeGlobalDragMonitor()
        stopHoverWatchdog()
    }

    var payloadSourceSpace: Int? {
        switch payload {
        case .space(let source)?: return source
        case .windows(_, let source)?: return source
        case .none: return nil
        }
    }
}

/// Transparent drawing layer above the status item's glass/backdrop.
final class GlyphStripStatusContent: NSView {
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
