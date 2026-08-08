import AppKit

/// Pure coordinate transforms shared by HUD rendering and input hit testing.
enum HUDGeometry {
    static func cellFrames(
        for cells: [Int],
        panelFrame: CGRect,
        config: GridConfig,
        quartzMaxY: CGFloat
    ) -> [(spaceIndex: Int, frame: CGRect)] {
        guard !cells.isEmpty else { return [] }
        let cols = max(1, min(config.cols, cells.count))
        let localFrames = GridLayout.cellFrames(count: cells.count, cols: cols, uiScale: config.uiScale)
        let panelMaxY = panelFrame.maxY
        return cells.enumerated().map { offset, spaceIndex in
            var frame = localFrames[offset]
            frame.origin.x += panelFrame.minX
            frame.origin.y = quartzMaxY - panelMaxY + frame.origin.y + frame.height
            return (spaceIndex, frame)
        }
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
}
