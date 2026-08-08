import CoreGraphics
import Foundation

@available(macOS 14.0, *)
enum ThumbnailRequestBuilder {
    private static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
    ]

    static func captureRequests(
        for state: GridState,
        spaceIndices: Set<Int>? = nil,
        thumbnailPixelSize: CGSize = ThumbnailCache.defaultThumbnailPixelSize
    ) -> [ThumbnailCache.CaptureRequest] {
        let knownYabaiWindowIDs = Set(
            state.windows.map { CGWindowID(truncatingIfNeeded: $0.id) }
        )
        return state.spaces.sorted { $0.index < $1.index }.compactMap { space in
            guard spaceIndices?.contains(space.index) ?? true else { return nil }
            let displayFrame = state.displayBounds(forSpace: space.index)
            guard displayFrame.width > 0, displayFrame.height > 0 else { return nil }

            let windows = state.windows(forSpace: space.index)
                .filter {
                    $0.shouldDisplay(showExtraWindows: state.config.showExtraWindows)
                }
                .map {
                    ThumbnailCache.CaptureWindow(
                        windowID: CGWindowID(truncatingIfNeeded: $0.id),
                        frame: $0.cgFrame
                    )
                }
            return ThumbnailCache.CaptureRequest(
                spaceIndex: space.index,
                displayFrame: displayFrame,
                outputSize: ThumbnailCompositor.aspectFillSize(
                    source: displayFrame.size,
                    target: thumbnailPixelSize
                ),
                includeUnmanagedOnScreenWindows:
                    space.isVisible == true ||
                    (space.isVisible == nil && space.hasFocus),
                knownYabaiWindowIDs: knownYabaiWindowIDs,
                windows: windows
            )
        }
    }

    static func shouldIncludeUnmanagedWindow(
        windowID: CGWindowID,
        isOnScreen: Bool,
        windowLayer: Int,
        ownerPID: pid_t?,
        bundleIdentifier: String?,
        frame: CGRect,
        displayFrame: CGRect,
        knownYabaiWindowIDs: Set<CGWindowID>,
        currentPID: pid_t
    ) -> Bool {
        guard isOnScreen, windowLayer >= 0,
              let ownerPID, ownerPID != currentPID,
              !knownYabaiWindowIDs.contains(windowID),
              frame.width >= 16, frame.height >= 16,
              frame.intersects(displayFrame) else {
            return false
        }
        if let bundleIdentifier,
           excludedBundleIdentifiers.contains(bundleIdentifier) {
            return false
        }
        return true
    }
}
