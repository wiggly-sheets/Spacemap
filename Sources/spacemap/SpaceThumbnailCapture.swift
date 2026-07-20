import Foundation
import AppKit
import CoreGraphics

/// Captures a screenshot thumbnail of a specific yabai space.
/// Tries ScreenCaptureKit first, then public CGWindowListCreateImage, then private SLS API.
struct SpaceThumbnailCapture {
    
    /// Capture a thumbnail image for the given space index, scaled to fit the cell dimensions.
    static func capture(spaceIndex: Int, displayBounds: CGRect, cellSize: CGSize, windows: [YabaiWindow]) -> NSImage? {
        // Try ScreenCaptureKit first (macOS 14+, can capture off-screen windows)
        if #available(macOS 14.0, *) {
            let semaphore = DispatchSemaphore(value: 0)
            var result: NSImage?
            Task {
                result = await ScreenCaptureKitCapture.capture(spaceIndex: spaceIndex, displayBounds: displayBounds, cellSize: cellSize, windows: windows)
                semaphore.signal()
            }
            semaphore.wait()
            if let img = result { return img }
        }
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
}


