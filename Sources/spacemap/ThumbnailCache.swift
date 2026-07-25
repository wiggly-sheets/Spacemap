import Foundation
import CoreGraphics
import ScreenCaptureKit

/// Caches CGImage thumbnails per space. Captures the active display on each space visit.
/// Until a space is visited, its cell shows empty.
@available(macOS 14.0, *)
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cgCache: [Int: CGImage] = [:]
    private var nsCache: [Int: NSImage] = [:]
    private let queue = DispatchQueue(label: "com.spacemap.thumbnailcache")

    /// Capture the currently active display (the current space) and pin it to its cell.
    func captureActiveSpace(spaceIndex: Int) {
        Task {
            guard let cgImage = await captureDisplay() else {
                NSLog("spacemap/ThumbnailCache: failed to capture display for space \(spaceIndex)")
                return
            }
            queue.sync {
                cgCache[spaceIndex] = cgImage
                nsCache[spaceIndex] = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            NSLog("spacemap/ThumbnailCache: captured space \(spaceIndex) (\(cgImage.width)x\(cgImage.height))")
        }
    }

    /// Get cached thumbnail for a space. Returns nil if not yet visited.
    func thumbnail(forSpace index: Int) -> CGImage? {
        queue.sync { cgCache[index] }
    }

    /// Get cached NSImage for a space. Returns nil if not yet visited.
    func thumbnailNSImage(forSpace index: Int) -> NSImage? {
        queue.sync { nsCache[index] }
    }

    /// Clear all cached thumbnails.
    func clear() {
        queue.sync {
            cgCache.removeAll()
            nsCache.removeAll()
        }
    }

    private func captureDisplay() async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return nil }

            let selfWindows = content.windows.filter {
                $0.owningApplication?.applicationName == "spacemap"
            }

            let filter = SCContentFilter(display: display, excludingWindows: selfWindows)
            let config = SCStreamConfiguration()
            config.width = Int(display.width * 2)
            config.height = Int(display.height * 2)
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            NSLog("spacemap/ThumbnailCache: SCK error: \(error.localizedDescription)")
            return nil
        }
    }
}
