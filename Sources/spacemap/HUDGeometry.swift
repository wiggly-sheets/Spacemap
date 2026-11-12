import AppKit

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
        // GridLayout.cellFrame is top-down from the panel's top edge; Quartz
        // drag points are top-down as well. Convert the panel top into Quartz
        // coordinates once, then add the local top-down offset. Adding
        // frame.height here would shift every hit rect down one slot.
        let panelTopInQuartz = quartzMaxY - panelMaxY
        return cells.enumerated().map { offset, spaceIndex in
            var frame = localFrames[offset]
            frame.origin.x += panelFrame.minX
            frame.origin.y = panelTopInQuartz + frame.origin.y
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
