import Foundation
import AppKit
import Carbon
import Combine
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class ThumbnailStore: ObservableObject {
    static let shared = ThumbnailStore()

    @Published private var images: [Int: NSImage] = [:]

    func image(forSpace index: Int) -> NSImage? {
        images[index]
    }

    func replace(with images: [Int: NSImage]) {
        self.images = images
    }

    func removeAll() {
        images.removeAll()
    }
}

@available(macOS 14.0, *)
final class ThumbnailCache {
    struct CaptureWindow: Equatable {
        let windowID: CGWindowID
        let frame: CGRect
    }

    struct CaptureRequest: Equatable {
        let spaceIndex: Int
        let displayFrame: CGRect
        let outputSize: CGSize
        let includeUnmanagedOnScreenWindows: Bool
        let knownYabaiWindowIDs: Set<CGWindowID>
        let windows: [CaptureWindow]
        /// Draw the desktop wallpaper beneath this space's windows.
        var includeWallpaper: Bool = true
    }

    struct RefreshJob {
        let generation: Int
        let requests: [CaptureRequest]
    }

    struct WindowTarget {
        let windowID: CGWindowID
        let window: SCWindow
        let outputSize: CGSize
    }

    static let shared = ThumbnailCache()
    static let maxConcurrentCaptures = 4
    /// Reuse a completed capture set for this long. A show after a short
    /// hide reuses pixels instead of recapturing the whole display.
    static let maxStaleness: TimeInterval = 30
    static let defaultThumbnailPixelSize = CGSize(width: 320, height: 200)
    static let excludedUnmanagedBundleIDs: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
    ]

    var refreshGeneration = 0
    var activeGeneration: Int?
    var activeRequests: [CaptureRequest]?
    var activeTask: Task<Void, Never>?
    var pendingRefresh: RefreshJob?
    var lastCompletedRequests: [CaptureRequest]?
    var lastCompletedAt: TimeInterval = 0
    let queue = DispatchQueue(label: "com.spacemap.thumbnailcache")

    /// One wallpaper-only image per display, drawn beneath the window images.
    /// Every window on the display is excluded, so the capture is desktop
    /// background, not the current space.
    /// CGRect gains Hashable only in macOS 15; deployment target is 13,
    /// so the cache keys displays on their four components instead.
    struct FrameKey: Hashable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ frame: CGRect) {
            x = frame.minX
            y = frame.minY
            width = frame.width
            height = frame.height
        }
    }

}
