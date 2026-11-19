import AppKit
import ApplicationServices
import CoreGraphics

/// Screen geometry shared by the HUD and the glyph strip: screen lookup, the
/// Quartz/AppKit flip, the menu-bar row, safe-area/dock detection, and
/// fullscreen detection. Pure functions unless the window server is the only
/// source of truth.
enum ScreenContext {
    static let fallbackMenuBarHeight: CGFloat = 24
    /// Tolerance for a yabai display frame vs. an AppKit screen frame. Sum of
    /// origin/size deltas; bigger than this is a stale or scaled-away display.
    static let screenMatchTolerance: CGFloat = 200

    // MARK: - Screen lookup

    static func screenFrame(on screen: NSScreen?) -> CGRect {
        screen?.frame ?? NSScreen.main?.frame ?? .zero
    }

    /// Pointer-based fallback for the first paint before any yabai state exists.
    static func targetScreen(mouseLocation: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The display a panel currently sits on, if any.
    static func screen(containing frame: CGRect, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { $0.frame.intersects(frame) }
    }

    /// Index of the screen frame that holds the most of `frame`. A panel or
    /// strip straddling two displays belongs to the one it covers most, so a
    /// saved position replays on that display instead of jumping back.
    static func largestIntersection(screenFrames: [CGRect], frame: CGRect) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screenFrame) in screenFrames.enumerated() {
            let overlap = screenFrame.intersection(frame)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Stable-ish display identity written to config with a custom panel
    /// position: the CGDisplay UUID, or the localized name when the display has
    /// no UUID. Survives monitor changes because it never depends on order or
    /// geometry.
    static func displayIdentifier(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuid) as String
            }
        }
        return screen.localizedName
    }

    /// The screen a stored identity still names. Nil when that display is gone,
    /// so callers fall back to their usual target screen.
    static func screen(
        matchingIdentifier identifier: String,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        guard !identifier.isEmpty else { return nil }
        return screens.first { displayIdentifier(for: $0) == identifier }
    }

    /// yabai reports Quartz display frames (top-left origin); `NSScreen.frame`
    /// is AppKit (bottom-left). Flip through the main screen's maxY before
    /// matching, otherwise vertically stacked displays never resolve.
    static func screen(
        containingQuartzFrame frame: CGRect,
        screens: [NSScreen] = NSScreen.screens,
        quartzMaxY: CGFloat? = nil
    ) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        let maxY = quartzMaxY ?? mainScreenFrame(screens: screens).maxY
        let appKit = appKitFrame(forQuartzFrame: frame, quartzMaxY: maxY)
        guard let index = bestScreenIndex(for: appKit, screenFrames: screens.map(\.frame)) else {
            return nil
        }
        return screens[index]
    }

    /// Screen frames for display matching. Tests inject frames so panel layout
    /// does not depend on the host's monitor count.
    static func availableScreenFrames(override: [CGRect]? = nil) -> [CGRect] {
        override ?? NSScreen.screens.map(\.frame)
    }

    static func bestScreenIndex(
        for targetFrame: CGRect,
        screenFrames: [CGRect],
        tolerance: CGFloat = ScreenContext.screenMatchTolerance
    ) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        var bestIndex = 0
        var bestScore = CGFloat.greatestFiniteMagnitude
        for (index, frame) in screenFrames.enumerated() {
            let score = screenMatchScore(frame, targetFrame: targetFrame)
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestScore <= tolerance ? bestIndex : nil
    }

    static func screenMatchScore(_ screenFrame: CGRect, targetFrame: CGRect) -> CGFloat {
        abs(screenFrame.minX - targetFrame.minX) +
            abs(screenFrame.minY - targetFrame.minY) +
            abs(screenFrame.width - targetFrame.width) +
            abs(screenFrame.height - targetFrame.height)
    }

    /// AppKit frame of a yabai display, resolved against `frames`.
    static func screenFrame(
        forDisplay displayIndex: Int,
        in state: GridState,
        frames: [CGRect],
        quartzMaxY: CGFloat
    ) -> CGRect? {
        guard !frames.isEmpty else { return nil }
        guard let yabaiDisplay = state.displays.first(where: { $0.index == displayIndex }) else {
            // No yabai topology yet: positional fallback, but never clamp a
            // nonexistent display onto the main screen (that stacked panels).
            let fallbackIndex = displayIndex - 1
            return frames.indices.contains(fallbackIndex) ? frames[fallbackIndex] : nil
        }
        let appKit = appKitFrame(forQuartzFrame: yabaiDisplay.frame.cgFrame, quartzMaxY: quartzMaxY)
        guard let index = bestScreenIndex(for: appKit, screenFrames: frames) else { return nil }
        return frames[index]
    }

    /// Resolve display indices to physical screen frames, dropping duplicate
    /// frames (mirrored/stale yabai topology) so two logical displays can
    /// never stack two HUD panels on one screen. If nothing matches, keep the
    /// HUD usable with a single main-screen panel rather than painting nothing.
    static func screenAssignments(
        for displayIndices: [Int],
        in state: GridState,
        frames: [CGRect],
        quartzMaxY: CGFloat,
        mainFrame: CGRect?
    ) -> [(displayIndex: Int, frame: CGRect)] {
        // Array + equality instead of Set: CGRect's Hashable conformance is
        // macOS 15+, and this deployment target is macOS 13.
        var seenFrames: [CGRect] = []
        var assignments: [(displayIndex: Int, frame: CGRect)] = []
        for displayIndex in displayIndices {
            guard let frame = screenFrame(
                forDisplay: displayIndex,
                in: state,
                frames: frames,
                quartzMaxY: quartzMaxY
            ) else { continue }
            guard !seenFrames.contains(frame) else { continue }
            seenFrames.append(frame)
            assignments.append((displayIndex, frame))
        }
        if assignments.isEmpty, let mainFrame, let first = displayIndices.first {
            assignments.append((first, mainFrame))
        }
        return assignments
    }

    // MARK: - Quartz flip

    static func appKitFrame(forQuartzFrame frame: CGRect, quartzMaxY: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: quartzMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func quartzPoint(fromAppKit point: CGPoint, quartzMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: quartzMaxY - point.y)
    }

    static func mainScreenFrame(screens: [NSScreen] = NSScreen.screens) -> CGRect {
        let mainDisplayID = CGMainDisplayID()
        return screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainDisplayID
        }?.frame ?? screens.first?.frame ?? .zero
    }

    /// Quartz hit rects for the HUD cells inside `panelFrame`.
    static func cellFrames(
        for cells: [Int],
        panelFrame: CGRect,
        config: SpacemapConfig,
        quartzMaxY: CGFloat
    ) -> [(spaceIndex: Int, frame: CGRect)] {
        guard !cells.isEmpty else { return [] }
        let cols = max(1, min(config.cols, cells.count))
        let localFrames = GridLayout.cellFrames(count: cells.count, cols: cols, uiScale: config.uiScale)
        let panelMaxY = panelFrame.maxY
        // GridLayout.cellFrame is top-down from the panel's top edge; Quartz
        // drag points are top-down as well. Convert the panel top into Quartz
        // coordinates once, then add the local top-down offset. Adding
        // frame.height here would shift every hit rect down one slot.
        let panelTopInQuartz = quartzMaxY - panelMaxY
        return cells.enumerated().map { offset, spaceIndex in
            var frame = localFrames[offset]
            frame.origin.x += panelFrame.minX
            frame.origin.y = panelTopInQuartz + frame.origin.y
            return (spaceIndex, frame)
        }
    }

    // MARK: - Menu-bar row

    /// The top row of the display, derived from the notch-aware safe-area inset
    /// so it is correct on both notched and plain displays.
    static func menuBarRow(on screen: NSScreen?) -> CGRect {
        guard let screen else {
            return CGRect(x: 0, y: 0, width: 0, height: fallbackMenuBarHeight)
        }
        return menuBarRow(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top
        )
    }

    /// Pure geometry for `menuBarRow(on:)`: notched displays expose the row as
    /// the top safe-area inset, plain displays as the gap above `visibleFrame`.
    static func menuBarRow(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat
    ) -> CGRect {
        let visibleGap = screenFrame.maxY - visibleFrame.maxY
        let height = safeAreaTop > 0 ? safeAreaTop : visibleGap
        let resolved = height > 0 ? height : fallbackMenuBarHeight
        return CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - resolved,
            width: screenFrame.width,
            height: resolved
        )
    }

    // MARK: - Safe area

    /// Usable area for a free-placed panel.
    static func safeScreenFrame(on screen: NSScreen?) -> CGRect {
        guard let screen else { return .zero }
        return safeScreenFrame(
            visibleFrame: screen.visibleFrame,
            screenFrame: screen.frame,
            obstacles: edgeObstacles(intersecting: screen.frame)
        )
    }

    /// Pure clamp: starts from the visible frame, then gives back space taken
    /// by edge-anchored accessory windows such as a third-party Dock.
    /// Menu-bar extras sit above the visible frame, and normal app windows are
    /// ignored.
    static func safeScreenFrame(
        visibleFrame: CGRect,
        screenFrame full: CGRect,
        obstacles: [CGRect]
    ) -> CGRect {
        var safe = visibleFrame
        for rect in obstacles {
            guard rect.intersects(full) else { continue }
            // Only edge furniture: a floating app window in the middle must not
            // push the strip around.
            let touchesBottom = abs(rect.minY - full.minY) <= 2
            let touchesTop = abs(rect.maxY - full.maxY) <= 2
            let touchesLeft = abs(rect.minX - full.minX) <= 2
            let touchesRight = abs(rect.maxX - full.maxX) <= 2
            // Dock-like only: one edge, thin along that edge, long across it.
            let edges = [touchesBottom, touchesTop, touchesLeft, touchesRight].filter { $0 }.count
            guard edges == 1 else { continue }
            let horizontal = touchesBottom || touchesTop
            let thin = horizontal ? rect.height <= full.height * 0.4 : rect.width <= full.width * 0.4
            let long = horizontal ? rect.width >= full.width * 0.25 : rect.height >= full.height * 0.25
            guard thin, long else { continue }
            // Only an obstacle that reaches into the usable area matters. The
            // menu bar itself sits above it, so its extras must not keep
            // shrinking the area.
            if touchesBottom, rect.maxY > safe.minY {
                safe.origin.y = max(safe.minY, rect.maxY + 4)
                safe.size.height = max(safe.maxY - safe.minY, 1)
            }
            if touchesTop, rect.minY < safe.maxY {
                let top = min(safe.maxY, rect.minY - 4)
                safe.size.height = max(top - safe.minY, 1)
            }
            if touchesLeft, rect.maxX > safe.minX {
                safe.origin.x = max(safe.minX, rect.maxX + 4)
                safe.size.width = max(safe.maxX - safe.minX, 1)
            }
            if touchesRight, rect.minX < safe.maxX {
                let right = min(safe.maxX, rect.minX - 4)
                safe.size.width = max(right - safe.minX, 1)
            }
        }
        return safe
    }

    /// Window-server rects at or above the Dock layer that touch `frame`.
    private static func edgeObstacles(intersecting frame: CGRect) -> [CGRect] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? Int, owner != Int(ownPID),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 3,
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  rect.intersects(frame) else { return nil }
            return rect
        }
    }

    // MARK: - Fullscreen detection

    /// True when the app the user sees has a native fullscreen window.
    ///
    /// Accessibility reports this directly, so it survives the window resizes
    /// of the fullscreen animation. Falls back to window geometry when
    /// Accessibility is not granted. A menu-bar app can report itself as
    /// frontmost, so that case resolves the app from the front layer-0 window.
    static func hasFullscreenAppInFront(trusted: Bool? = nil) -> Bool {
        let isTrusted = trusted ?? (PermissionProbe.shared.isStalled ? false : AXIsProcessTrusted())
        guard isTrusted else { return frontWindowCoversDisplay() }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if pid == nil || pid == ownPID {
            pid = frontWindowOwner(excluding: ownPID)
        }
        guard let pid, pid != ownPID else { return false }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &window
        ) == .success, let window else {
            return frontWindowCoversDisplay()
        }
        var fullscreen: CFTypeRef?
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return frontWindowCoversDisplay() }
        let axWindow = unsafeDowncast(window, to: AXUIElement.self)
        guard AXUIElementCopyAttributeValue(
            axWindow,
            "AXFullScreen" as CFString,
            &fullscreen
        ) == .success else {
            return frontWindowCoversDisplay()
        }
        guard (fullscreen as? Bool) == true else { return false }
        // `AXFocusedWindow` can still be the fullscreen window while the user
        // looks at a different space of the same app. Only hide when that app
        // also has a fullscreen-sized window on screen now.
        return windowCoversDisplay(owner: pid)
    }

    /// Does `owner` have an on-screen layer-0 window as large as a display?
    private static func windowCoversDisplay(owner pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  owner == Int(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else {
                continue
            }
            // Accessibility already said the window is fullscreen, so this is a
            // space-membership check, not a shape test: accept the small height
            // differences of the fullscreen animation and a hidden menu bar.
            if NSScreen.screens.contains(where: {
                abs($0.frame.width - bounds.width) <= 2 && bounds.height >= $0.frame.height - 60
            }) {
                return true
            }
        }
        return false
    }

    /// Owner of the frontmost layer-0 window that is not Spacemap's own.
    private static func frontWindowOwner(excluding ownPID: pid_t) -> pid_t? {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  owner != Int(ownPID),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            return pid_t(owner)
        }
        return nil
    }

    /// Geometry fallback: does the frontmost normal window cover a display?
    /// Fullscreen windows cover the display; zoomed windows stop below the menu
    /// bar.
    private static func frontWindowCoversDisplay() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int, owner != Int(ownPID),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else {
                continue
            }
            return NSScreen.screens.contains {
                abs($0.frame.width - bounds.width) <= 2 && abs($0.frame.height - bounds.height) <= 2
            }
        }
        return false
    }
}
