import AppKit
import CoreGraphics

extension HUDInput {
    func startPanelDragMonitor() {
        guard panelDragMonitor == nil, self.panel != nil else { return }
        panelDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let panel = self.panel, self.isVisible else { return event }
            guard let window = panel.contentView?.window else { return event }
            let loc = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            guard panel.contentView?.bounds.contains(loc) == true else { return event }

            switch event.type {
            case .leftMouseDown:
                self.beginPanelDrag(
                    start: NSEvent.mouseLocation,
                    panelOrigin: panel.frame.origin
                )
            case .leftMouseDragged:
                guard let start = self.panelDragStart,
                      let origin = self.panelDragOrigin else { break }
                let current = NSEvent.mouseLocation
                let delta = PanelPresenter.dragDelta(from: start, to: current)
                if let quartzPoint = self.quartzPointConverter?(current) {
                    let overCell = self.dragHandlerCellFrames.contains { $0.frame.contains(quartzPoint) }
                    if !overCell {
                        var newOrigin = origin
                        newOrigin.x += delta.dx
                        newOrigin.y += delta.dy
                        panel.setFrameOrigin(newOrigin)
                        self.panelDragDidMove = true
                    }
                }
            case .leftMouseUp:
                if self.endPanelDrag() {
                    self.onPanelDragEnded?()
                }
            default: break
            }
            return event
        }
    }

    /// Start a panel drag: the armed auto-hide timer must be disarmed while
    /// the mouse is down, otherwise the HUD can vanish mid-drag.
    func beginPanelDrag(start: CGPoint, panelOrigin: CGPoint) {
        panelDragStart = start
        panelDragOrigin = panelOrigin
        panelDragDidMove = false
        isPanelDragging = true
        onPanelDragChanged?(true)
    }

    /// Finish a panel drag and re-arm auto-hide. Returns whether the panel
    /// actually moved (so the caller can persist the new position).
    @discardableResult
    func endPanelDrag() -> Bool {
        let moved = panelDragDidMove
        panelDragStart = nil
        panelDragOrigin = nil
        panelDragDidMove = false
        isPanelDragging = false
        onPanelDragChanged?(false)
        return moved
    }

    func stopPanelDragMonitor() {
        if let monitor = panelDragMonitor {
            NSEvent.removeMonitor(monitor)
            panelDragMonitor = nil
        }
        panelDragStart = nil
        panelDragOrigin = nil
        panelDragDidMove = false
        isPanelDragging = false
        onPanelDragChanged?(false)
    }

    var panelDragActive: Bool { isPanelDragging }
}
