import AppKit
import ApplicationServices
import CoreText

extension GlyphStrip.Run {
    var isIndex: Bool {
        if case .index = self { return true }
        return false
    }
}

final class GlyphStripView: NSView {

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

    func animateContentChange(segments: [Int]) {
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
    static func inkCenteredX(for run: NSAttributedString, in line: CGRect) -> CGFloat {
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

    static func font(of run: NSAttributedString) -> NSFont {
        run.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }
}
