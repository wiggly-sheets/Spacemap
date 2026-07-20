import Foundation
import AppKit
import CoreGraphics

/// Captures a screenshot thumbnail of a specific yabai space.
/// Tries ScreenCaptureKit first, then public CGWindowListCreateImage, then private SLS API.
struct SpaceThumbnailCapture {
    
    /// Capture a thumbnail image for the given space index, scaled to fit the cell dimensions.
    /// Uses synchronous fallbacks only (SLS, CGWindowListCreateImage).
    /// For ScreenCaptureKit, call captureAsync instead.
    static func capture(spaceIndex: Int, displayBounds: CGRect, cellSize: CGSize, windows: [YabaiWindow]) -> NSImage? {
        // Fall back to CGWindowListCreateImage
        if let img = CGWindowThumbnailCapture.capture(spaceIndex: spaceIndex, displayBounds: displayBounds, cellSize: cellSize, windows: windows) {
            return img
        }
        // Fall back to private SLS API
        guard let cgImage = SLSCapture.capture(spaceIndex: spaceIndex, displayBounds: displayBounds) else { return nil }
        let nsImage = NSImage(size: cellSize)
        nsImage.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: cellSize))
        }
        nsImage.unlockFocus()
        return nsImage
    }

    /// Async version that tries ScreenCaptureKit first (macOS 14+).
    @available(macOS 14.0, *)
    static func captureAsync(spaceIndex: Int, displayBounds: CGRect, cellSize: CGSize, windows: [YabaiWindow], completion: @escaping (NSImage?) -> Void) {
        Task {
            if let img = await ScreenCaptureKitCapture.capture(spaceIndex: spaceIndex, displayBounds: displayBounds, cellSize: cellSize, windows: windows) {
                completion(img)
            } else {
                // Fall back to sync methods on background queue
                let fallback = capture(spaceIndex: spaceIndex, displayBounds: displayBounds, cellSize: cellSize, windows: windows)
                completion(fallback)
            }
        }
    }
}


