import AppKit
import CoreGraphics

/// Captures space thumbnails using public CGWindowListCreateImage API.
/// Falls back to nil if windows can't be matched or capture fails.
struct CGWindowThumbnailCapture {

    /// Attempt to capture a thumbnail for the given space by finding CGWindowIDs
    /// that match the yabai windows on that space, then using CGWindowListCreateImage.
    static func capture(spaceIndex: Int, displayBounds: CGRect, cellSize: CGSize, windows: [YabaiWindow]) -> NSImage? {
        guard !windows.isEmpty else {
            NSLog("spacemap/CGWindowThumb: no windows for space \(spaceIndex)")
            return nil
        }

        // Get all on-screen window info from the window server
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            NSLog("spacemap/CGWindowThumb: failed to get window info list")
            return nil
        }

        NSLog("spacemap/CGWindowThumb: space \(spaceIndex) has \(windows.count) yabai windows, \(windowInfoList.count) CG windows")

        // Match yabai windows to CGWindowIDs by app name + approximate position
        var cgWindowIDs: [CGWindowID] = []
        for yabaiWin in windows {
            guard !yabaiWin.isHidden, !yabaiWin.isMinimized else { continue }
            if let match = findMatchingCGWindow(yabaiWin, in: windowInfoList) {
                cgWindowIDs.append(match)
                NSLog("spacemap/CGWindowThumb: matched '\(yabaiWin.app)' → CGWindowID \(match)")
            } else {
                NSLog("spacemap/CGWindowThumb: no match for '\(yabaiWin.app)' frame=(\(Int(yabaiWin.cgFrame.minX)),\(Int(yabaiWin.cgFrame.minY)),\(Int(yabaiWin.cgFrame.width)),\(Int(yabaiWin.cgFrame.height)))")
            }
        }

        guard !cgWindowIDs.isEmpty else {
            NSLog("spacemap/CGWindowThumb: no CGWindowIDs matched for space \(spaceIndex)")
            return nil
        }

        // Compute union rect of all matched windows (in screen coordinates)
        var unionRect = CGRect.null
        for windowID in cgWindowIDs {
            guard let info = windowInfoList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }),
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }
            let rect = CGRect(x: x, y: y, width: w, height: h)
            unionRect = unionRect.union(rect)
        }

        guard !unionRect.isNull, unionRect.width > 0, unionRect.height > 0 else { return nil }

        // Render each window individually and composite into a shared bitmap
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = Int(cellSize.width)
        let height = Int(cellSize.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let scaleX = cellSize.width / unionRect.width
        let scaleY = cellSize.height / unionRect.height
        let scale = min(scaleX, scaleY)

        for windowID in cgWindowIDs {
            guard let info = windowInfoList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }),
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }

            let windowRect = CGRect(x: x, y: y, width: w, height: h)
            guard let windowImage = CGWindowListCreateImage(windowRect, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]) else {
                NSLog("spacemap/CGWindowThumb: CGWindowListCreateImage failed for CGWindowID \(windowID)")
                continue
            }

            NSLog("spacemap/CGWindowThumb: captured CGWindowID \(windowID) \(windowImage.width)x\(windowImage.height)")

            // Map from screen coordinates to cell coordinates
            // CGWindowListCreateImage returns image in the rect's coordinate space (origin top-left in CG)
            // Cell coordinates: origin top-left
            let destX = (windowRect.minX - unionRect.minX) * scale
            let destY = unionRect.height - (windowRect.maxY - unionRect.minY) * scale
            let destW = windowRect.width * scale
            let destH = windowRect.height * scale

            context.draw(windowImage, in: CGRect(x: destX, y: destY, width: destW, height: destH))
        }

        guard let outputCGImage = context.makeImage() else {
            NSLog("spacemap/CGWindowThumb: failed to make output image")
            return nil
        }
        NSLog("spacemap/CGWindowThumb: success! \(outputCGImage.width)x\(outputCGImage.height)")
        let nsImage = NSImage(size: cellSize)
        nsImage.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.interpolationQuality = .high
            ctx.draw(outputCGImage, in: CGRect(origin: .zero, size: cellSize))
        }
        nsImage.unlockFocus()
        return nsImage
    }

    /// Try to match a yabai window to a CGWindow by app name and approximate frame overlap.
    private static func findMatchingCGWindow(_ yabaiWin: YabaiWindow, in windowInfoList: [[String: Any]]) -> CGWindowID? {
        let yabaiFrame = yabaiWin.cgFrame

        var bestMatch: (id: CGWindowID, score: Double)?
        for info in windowInfoList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }

            guard ownerName.lowercased() == yabaiWin.app.lowercased() else { continue }

            let cgFrame = CGRect(x: x, y: y, width: w, height: h)
            let overlap = yabaiFrame.intersection(cgFrame)
            let overlapArea = max(overlap.width, 0) * max(overlap.height, 0)
            let yabaiArea = yabaiFrame.width * yabaiFrame.height
            let cgArea = cgFrame.width * cgFrame.height
            let maxArea = max(yabaiArea, cgArea, 1)
            let score = overlapArea / maxArea

            NSLog("spacemap/CGWindowThumb: candidate '\(ownerName)' CGID=\(windowID) cgFrame=(\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))) score=\(String(format: "%.2f", score))")

            if score > 0.3, (bestMatch == nil || score > bestMatch!.score) {
                bestMatch = (windowID, Double(score))
            }
        }

        return bestMatch?.id
    }
}
