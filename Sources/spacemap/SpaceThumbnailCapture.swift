import Foundation
import AppKit
import CoreGraphics

/// Captures a screenshot thumbnail of a specific yabai space using private SLS API.
struct SpaceThumbnailCapture {
    
    /// Capture a thumbnail image for the given space index, scaled to fit the cell dimensions.
    static func capture(spaceIndex: Int, displayBounds: CGRect, cellSize: CGSize, windows: [YabaiWindow]) -> NSImage? {
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


