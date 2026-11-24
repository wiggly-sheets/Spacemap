import AppKit
import ApplicationServices
import CoreText

extension GlyphStripStatusView {
    /// A status-item view can lose the dragged/up stream while its button
    /// tracks the mouse. The global monitor supplies those events for drags
    /// that begin on a space number or app icon.
    func installGlobalDragMonitor() {
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

    func removeGlobalDragMonitor() {
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

    func finishGesture() {
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

    func activateDragSource(_ payload: Payload, controller: GlyphStripPanelController) {
        switch payload {
        case .space(let source):
            controller.onDragSourceSpace?(source)
        case .windows(_, let source):
            controller.onDragSourceSpace?(source)
        }
        controller.onDragActive?(true)
    }

    func performDrop(
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
}
