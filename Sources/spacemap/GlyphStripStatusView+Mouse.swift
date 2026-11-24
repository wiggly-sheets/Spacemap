import AppKit
import ApplicationServices
import CoreText

extension GlyphStripStatusView {
    func pointInView() -> NSPoint? {
        guard let window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return convert(windowPoint, from: nil)
    }

    /// The status item can deliver a synthesized center press when another
    /// menu-bar window forwards the click. Prefer the physical pointer, which
    /// still names the segment the user aimed at.
    func clickPoint(eventPoint: NSPoint) -> NSPoint {
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

    override func rightMouseDown(with event: NSEvent) {
        guard let controller,
              let segment = segment(at: convert(event.locationInWindow, from: nil)),
              let command = controller.command(forSegment: segment, click: .right) else { return }
        controller.handle(command)
    }

    /// One render for the button: slots centred in the wider button, native
    /// icons shrunk to the row.
    var segmentLayout: GlyphStrip.SegmentLayout {
        controller?.statusItemLayout(in: bounds)
            ?? GlyphStrip.SegmentLayout(slots: [], runs: [])
    }

    func segment(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        return segmentLayout.segment(at: point)
    }
}
