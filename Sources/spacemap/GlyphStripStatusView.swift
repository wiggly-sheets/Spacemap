import AppKit
import ApplicationServices
import CoreText

/// Compact menu-bar rendering: one horizontal row, no glass, shape or hover.
/// Clicks and the same space/app drag reorder work here; only the floating
/// strip's placement, glass and vertical layouts are unavailable.
final class GlyphStripStatusView: NSView {
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
    func refreshHover() {
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

    func animateContentChange(segments: [Int]) {
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
    func handleButtonClick(at eventPoint: NSPoint, eventTime: TimeInterval) {
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
    func cancelGesture() {
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

