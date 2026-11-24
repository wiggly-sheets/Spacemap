import Cocoa

extension WindowDragHandler {
    func findDraggedWindowID(atCG cgPoint: CGPoint) -> Int? {
        let candidates = windowsForFrontmostApp()
        guard !candidates.isEmpty else {
            // A known app/pid with no cached window is not evidence. Falling
            // back to the focused window here can move a different app's
            // overlapping window.
            return hasKnownFrontmostIdentity ? nil : focusedWindowIDAtOpen
        }

        // Prefer the exact window the WindowServer reported under the click.
        if let sample = mouseDownCGWindow,
           let matching = candidates.first(where: {
               framesApproximatelyMatch($0.cgFrame, sample.bounds)
           }) {
            return matching.id
        }

        if let focused = focusedWindowIDAtOpen,
           let focusedWindow = candidates.first(where: { $0.id == focused }),
           focusedWindow.cgFrame.contains(cgPoint) {
            return focused
        }

        if let containing = candidates.first(where: { $0.cgFrame.contains(cgPoint) }) {
            return containing.id
        }

        // AX and CGEvent coordinates share Quartz's top-left origin.
        return candidates.min {
            hypot($0.cgFrame.minX - cgPoint.x, $0.cgFrame.minY - cgPoint.y) <
            hypot($1.cgFrame.minX - cgPoint.x, $1.cgFrame.minY - cgPoint.y)
        }?.id
    }

    /// Drop resolution is more permissive than evidence: a focused window that
    /// contains the drag start can still receive the drop.
    func resolveDraggedWindowID(atCG cgPoint: CGPoint) -> Int? {
        if let windowID = findDraggedWindowID(atCG: cgPoint) { return windowID }
        if let focused = focusedWindowIDAtOpen,
           let window = cachedWindows.first(where: { $0.id == focused }),
           window.cgFrame.contains(cgPoint) {
            return focused
        }
        return nil
    }

    var hasKnownFrontmostIdentity: Bool {
        mouseDownCGWindow != nil || frontmostPIDAtMouseDown != nil || frontmostAppAtMouseDown != nil
    }

    var effectiveFrontmostPID: Int32? {
        mouseDownCGWindow?.ownerPID ?? frontmostPIDAtMouseDown
    }

    func windowsForFrontmostApp() -> [YabaiWindow] {
        if let pid = effectiveFrontmostPID {
            let matches = cachedWindows.filter { $0.pid == Int(pid) }
            if !matches.isEmpty { return matches }
            // The WindowServer pid is authoritative; do not fall back to a
            // stale frontmost localized name when it does not match.
            if mouseDownCGWindow != nil { return [] }
        }
        guard let appName = frontmostAppAtMouseDown else { return [] }
        return cachedWindows.filter { $0.app == appName }
    }

    func framesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 4 &&
            abs(lhs.minY - rhs.minY) <= 4 &&
            abs(lhs.width - rhs.width) <= 4 &&
            abs(lhs.height - rhs.height) <= 4
    }

    func sampleCGWindows(force: Bool = false) -> [CGWindowSample] {
        let now = ProcessInfo.processInfo.systemUptime
        if force || lastCGWindowSample.isEmpty
            || now - lastCGWindowSampleTime >= cgWindowSampleInterval {
            lastCGWindowSample = cgWindowListProvider()
            lastCGWindowSampleTime = now
        }
        return lastCGWindowSample
    }

    func cgWindowMoved() -> Bool {
        guard let before = mouseDownCGWindow else { return false }
        guard let after = sampleCGWindows().first(where: { $0.windowID == before.windowID }) else {
            return false
        }
        let moved = abs(after.bounds.minX - before.bounds.minX) > Self.dragThreshold
            || abs(after.bounds.minY - before.bounds.minY) > Self.dragThreshold
        // An edge-resize changes the origin too; only count movement when the
        // window kept its size.
        let resized = abs(after.bounds.width - before.bounds.width) > Self.dragThreshold
            || abs(after.bounds.height - before.bounds.height) > Self.dragThreshold
        return moved && !resized
    }

    static func onScreenWindows() -> [CGWindowSample] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
                  ownerPID != Int(ownPID),
                  let windowID = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else {
                return nil
            }
            return CGWindowSample(
                windowID: CGWindowID(windowID),
                ownerPID: pid_t(ownerPID),
                bounds: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }
}
