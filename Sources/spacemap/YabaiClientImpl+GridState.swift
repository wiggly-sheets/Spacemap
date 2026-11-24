import Foundation
import AppKit

extension YabaiClientImpl {
    func buildGridState(config: SpacemapConfig, focusedIndex: Int? = nil) -> GridState {
        // NSScreen.main is main-only: capture on main, pass in.
        let displayBounds = Self.mainDisplayBounds()
        // Callers already run off-main (yabai queue / utility queue), so query
        // directly instead of fanning out and blocking on group.wait.
        guard isYabaiRunning() else {
            return GridState(config: config, spaces: [], windows: [], displayBounds: displayBounds, focusedIndex: nil)
        }
        // Cached snapshots keep the last good result when a query fails, so a
        // transient timeout never publishes an empty grid and blanks the HUD.
        let spaces = (try? cachedSpaces()) ?? []
        let displays = cachedDisplays()
        let windows = (try? cachedWindows()) ?? []
        let resolvedFocus = focusedIndex ?? spaces.first { $0.hasFocus }?.index
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: resolvedFocus, displays: displays)
    }

    static let boundsLock = NSLock()
    static var cachedMainBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    static func mainDisplayBounds() -> CGRect {
        let fallback = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        if Thread.isMainThread {
            let bounds = NSScreen.main?.frame ?? fallback
            boundsLock.lock()
            cachedMainBounds = bounds
            boundsLock.unlock()
            return bounds
        }
        // Never main.sync: buildGridState runs off-main and main may wait
        // on it. Refresh cache async, return last known bounds now.
        DispatchQueue.main.async {
            let bounds = NSScreen.main?.frame ?? fallback
            boundsLock.lock()
            cachedMainBounds = bounds
            boundsLock.unlock()
        }
        boundsLock.lock()
        defer { boundsLock.unlock() }
        return cachedMainBounds
    }

}
