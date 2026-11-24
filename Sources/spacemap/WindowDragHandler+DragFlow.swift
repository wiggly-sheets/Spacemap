import Cocoa

extension WindowDragHandler {
    func handleMouseDown(at cgPoint: CGPoint) {
        dragSnapshotGeneration += 1
        let snapshotGeneration = dragSnapshotGeneration
        dragStartPoint = cgPoint
        isDragging = false
        draggedWindowID = nil
        frontmostAppAtMouseDown = frontmostApplicationName()
        frontmostPIDAtMouseDown = frontmostApplicationPID()
        // The WindowServer is authoritative for which app owns the window
        // under the click, even when the frontmost-app snapshot is stale.
        mouseDownCGWindow = sampleCGWindows(force: true).first { $0.bounds.contains(cgPoint) }
        if let onRequestDragSnapshot {
            dragSnapshotReady = false
            onRequestDragSnapshot(snapshotGeneration)
        } else {
            dragSnapshotReady = true
        }
    }

    func applyDragSnapshot(
        focusedWindowID: Int?,
        windows: [YabaiWindow],
        generation: Int
    ) {
        guard generation == dragSnapshotGeneration else { return }
        dragSnapshotReady = true
        guard dragStartPoint != nil else { return }
        focusedWindowIDAtOpen = focusedWindowID
        cachedWindows = windows
        if isDragging, draggedWindowID == nil, let start = dragStartPoint {
            draggedWindowID = findDraggedWindowID(atCG: start)
        }
    }

    func handleDrag(at cgPoint: CGPoint) {
        guard !cellFrames.isEmpty else { return }

        if !isDragging {
            guard let start = dragStartPoint,
                  hypot(cgPoint.x - start.x, cgPoint.y - start.y) > Self.dragThreshold,
                  hasWindowDragEvidence(at: start) else {
                return
            }
            isDragging = true
        }
        if draggedWindowID == nil, dragSnapshotReady, let start = dragStartPoint {
            draggedWindowID = findDraggedWindowID(atCG: start)
        }

        let cell = cellSpaceIndex(forCG: cgPoint)
        if cell != lastHoveredCell {
            lastHoveredCell = cell
            enqueueDelivery(.hover(cell))
        }
    }

    func handleMouseUp(at cgPoint: CGPoint, modifiers: CGEventFlags) {
        let wasDragging = isDragging
        let start = dragStartPoint
        let snapshotWasPending = !dragSnapshotReady
        let trackedWindowID = draggedWindowID
        let cell = cellSpaceIndex(forCG: cgPoint)
        defer { reset() }

        guard wasDragging else {
            if lastHoveredCell != nil {
                lastHoveredCell = nil
                enqueueDelivery(.hover(nil))
            }
            return
        }

        let windowID = trackedWindowID ?? resolveDraggedWindowID(atCG: start ?? cgPoint)
        guard let cell, let windowID else {
            if cell == nil {
                NSLog("Spacemap/Drag: drop cancelled; released outside all cells")
            } else {
                NSLog("Spacemap/Drag: drop abandoned; no window identified")
            }
            if lastHoveredCell != nil {
                lastHoveredCell = nil
                enqueueDelivery(.hover(nil))
            }
            return
        }

        if trackedWindowID == nil {
            NSLog("Spacemap/Drag: drop used cached window fallback (snapshot pending: \(snapshotWasPending))")
        }
        lastHoveredCell = nil
        enqueueDelivery(.drop(windowID: windowID, cell: cell, modifiers: modifiers))
    }

    func cellSpaceIndex(forCG cgPoint: CGPoint) -> Int? {
        for entry in cellFrames where entry.frame.contains(cgPoint) {
            return entry.spaceIndex
        }
        return nil
    }

    func hasWindowDragEvidence(at cgPoint: CGPoint) -> Bool {
        if let windowID = findDraggedWindowID(atCG: cgPoint),
           let window = cachedWindows.first(where: { $0.id == windowID }) {
            let frame = window.cgFrame
            if frame.contains(cgPoint),
               cgPoint.y - frame.minY <= Self.titleBarHeight {
                return true
            }
        }
        // Toolbar, borderless, and background drags may start below the title
        // bar. The WindowServer tells us cheaply whether the window under the
        // cursor actually moved; text selection and sliders do not move it.
        return cgWindowMoved()
    }
}
