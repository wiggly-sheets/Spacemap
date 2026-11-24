import AppKit
import ApplicationServices
import CoreText

extension GlyphStripStatusView {
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

    func updateHover(_ event: NSEvent) {
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
    func startHoverWatchdog() {
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

    func stopHoverWatchdog() {
        hoverWatchdog?.invalidate()
        hoverWatchdog = nil
    }
}
