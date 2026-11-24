import Cocoa

extension WindowDragHandler {
    static func shouldRecoverEventTap(for type: CGEventType) -> Bool {
        shouldRecoverWindowDragEventTap(for: type)
    }

    func recoverEventTap() {
        _ = recoverEventTap(expectedGeneration: nil)
    }

    @discardableResult
    func recoverEventTap(expectedGeneration: Int?) -> Bool {
        guard wantsEventTap else { return false }
        if let expectedGeneration, expectedGeneration != eventTapGeneration {
            NSLog("Spacemap/Drag: ignoring stale event tap recovery")
            return false
        }
        if eventTapHost.tapIsValid {
            eventTapHost.enableTap()
            if eventTapHost.tapIsEnabled { return true }
        }
        cancelHoverForTeardown()
        invalidateQueuedDelivery()
        eventTapHost.tearDown()
        reset()
        reconcileEventTap()
        return true
    }

    /// Installs, re-enables, or retries the drag tap. Exposed for the health
    /// timer and for tests; keeps retrying on a bounded cadence.
    func reconcileEventTap() {
        guard wantsEventTap else { return }

        let isPermitted = permissionIsGranted()
        if lastPermissionState != isPermitted {
            NSLog(isPermitted
                ? "Spacemap/Drag: window drag event tap active"
                : "Spacemap/Drag: input monitoring unavailable; will retry")
            lastPermissionState = isPermitted
        }
        guard isPermitted else {
            // Permission can disappear mid-drag; do not leave a highlight or
            // a half-finished drag behind.
            cancelHoverForTeardown()
            eventTapHost.tearDown()
            reset()
            return
        }

        let installs = eventTapHost.installCount
        eventTapHost.reconcile(consumer: self)
        if eventTapHost.installCount != installs { eventTapGeneration += 1 }
    }

    func permissionIsGranted() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedPermission, now - lastPermissionCheckTime < permissionCacheInterval {
            return cachedPermission
        }
        lastPermissionCheckTime = now
        let permitted = permissionCheck()
        cachedPermission = permitted
        return permitted
    }

    func startHealthTimer() {
        eventTapHost.startHealthTimer { [weak self] in
            self?.probePermissionAndReconcile()
        }
    }

    /// Timer path: the permission check can block while TCC is being edited,
    /// so run it off-main and only touch the tap here.
    func probePermissionAndReconcile() {
        let provider = permissionCheck
        PermissionProbe.shared.check(provider: provider) { [weak self] permitted in
            guard let self else { return }
            self.lastPermissionCheckTime = ProcessInfo.processInfo.systemUptime
            self.cachedPermission = permitted
            self.reconcileEventTap()
        }
    }

    func reset() {
        dragSnapshotGeneration += 1
        dragSnapshotReady = true
        isDragging = false
        draggedWindowID = nil
        dragStartPoint = nil
        lastHoveredCell = nil
        frontmostAppAtMouseDown = nil
        frontmostPIDAtMouseDown = nil
        mouseDownCGWindow = nil
        lastCGWindowSample = []
    }
}
