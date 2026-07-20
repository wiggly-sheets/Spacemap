import AppKit
import ScreenCaptureKit

/// Captures space thumbnails using ScreenCaptureKit (macOS 14+).
/// Can capture windows on non-active spaces since it queries the window server directly.
@available(macOS 14.0, *)
struct ScreenCaptureKitCapture {

    private static var cachedShareableContent: SCShareableContent?
    private static var lastRefreshTime: Date?

    /// Capture a thumbnail for the given space by finding matching SCWindows.
    static func capture(spaceIndex: Int, displayBounds: CGRect, cellSize: CGSize, windows: [YabaiWindow]) async -> NSImage? {
        guard !windows.isEmpty else { return nil }

        let shareableContent = await getShareableContent()
        guard let content = shareableContent else {
            NSLog("spacemap/SCK: failed to get SCShareableContent")
            return nil
        }

        // Match yabai windows to SCWindows by app name
        var matchedWindows: [SCWindow] = []
        for yabaiWin in windows {
            guard !yabaiWin.isHidden, !yabaiWin.isMinimized else { continue }
            if let match = findMatchingSCWindow(yabaiWin, in: content.windows) {
                matchedWindows.append(match)
            }
        }

        guard !matchedWindows.isEmpty else {
            NSLog("spacemap/SCK: no SCWindows matched for space \(spaceIndex)")
            return nil
        }

        NSLog("spacemap/SCK: space \(spaceIndex) matched \(matchedWindows.count)/\(windows.count) windows")

        // Capture each window individually and composite
        let pixelWidth = Int(cellSize.width * 2)
        let pixelHeight = Int(cellSize.height * 2)

        return await withCheckedContinuation { continuation in
            let group = DispatchGroup()
            var results: [(SCWindow, CGImage)] = []

            for scWin in matchedWindows {
                let filter = SCContentFilter(desktopIndependentWindow: scWin)

                let config = SCStreamConfiguration()
                config.width = pixelWidth
                config.height = pixelHeight
                config.showsCursor = false
                config.pixelFormat = kCVPixelFormatType_32BGRA

                group.enter()
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                    if let image = image {
                        results.append((scWin, image))
                    } else if let error = error {
                        NSLog("spacemap/SCK: capture failed for window: \(error.localizedDescription)")
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                guard !results.isEmpty else {
                    NSLog("spacemap/SCK: no windows captured")
                    continuation.resume(returning: nil)
                    return
                }

                // Composite all captured windows into one bitmap
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Compute union of all SCWindow frames
                var unionFrame = CGRect.null
                for (scWin, _) in results {
                    unionFrame = unionFrame.union(scWin.frame)
                }
                guard unionFrame.width > 0, unionFrame.height > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let scaleX = cellSize.width / unionFrame.width
                let scaleY = cellSize.height / unionFrame.height
                let scale = min(scaleX, scaleY)

                for (scWin, cgImage) in results {
                    let winFrame = scWin.frame
                    let destX = (winFrame.minX - unionFrame.minX) * scale * 2
                    let destY = unionFrame.height * 2 - (winFrame.maxY - unionFrame.minY) * scale * 2
                    let destW = winFrame.width * scale * 2
                    let destH = winFrame.height * scale * 2

                    context.draw(cgImage, in: CGRect(x: destX, y: destY, width: destW, height: destH))
                }

                guard let outputCGImage = context.makeImage() else {
                    continuation.resume(returning: nil)
                    return
                }
                NSLog("spacemap/SCK: captured \(results.count) windows, composite \(outputCGImage.width)x\(outputCGImage.height)")

                let nsImage = NSImage(size: cellSize)
                nsImage.lockFocus()
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.interpolationQuality = .high
                    ctx.draw(outputCGImage, in: CGRect(origin: .zero, size: cellSize))
                }
                nsImage.unlockFocus()
                continuation.resume(returning: nsImage)
            }
        }
    }

    private static func getShareableContent() async -> SCShareableContent? {
        if let cached = cachedShareableContent, let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < 2.0 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            SCShareableContent.getWithCompletionHandler { content, error in
                if let error = error {
                    NSLog("spacemap/SCK: SCShareableContent error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                cachedShareableContent = content
                lastRefreshTime = Date()
                continuation.resume(returning: content)
            }
        }
    }

    private static func findMatchingSCWindow(_ yabaiWin: YabaiWindow, in scWindows: [SCWindow]) -> SCWindow? {
        let yabaiFrame = yabaiWin.cgFrame

        var bestMatch: (window: SCWindow, score: Double)?
        for scWin in scWindows {
            guard scWin.isOnScreen else { continue }

            let ownerName = scWin.owningApplication?.applicationName ?? ""
            guard ownerName.lowercased() == yabaiWin.app.lowercased() else { continue }

            let scFrame = scWin.frame
            let overlap = yabaiFrame.intersection(scFrame)
            let overlapArea = max(overlap.width, 0) * max(overlap.height, 0)
            let yabaiArea = yabaiFrame.width * yabaiFrame.height
            let scArea = scFrame.width * scFrame.height
            let maxArea = max(yabaiArea, scArea, 1)
            let score = overlapArea / maxArea

            if score > 0.1, (bestMatch == nil || score > bestMatch!.score) {
                bestMatch = (scWin, Double(score))
            }
        }

        return bestMatch?.window
    }
}
