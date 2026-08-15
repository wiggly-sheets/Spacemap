import SwiftUI

public enum GridLayout {


    static let baseCellWidth: CGFloat = 80
    static let baseCellHeight: CGFloat = 50
    static let baseGap: CGFloat = 6
    static let basePadding: CGFloat = 12


    static func scale(for uiScale: Double) -> CGFloat {
        0.5 + CGFloat(uiScale) * 3.5
    }

    static func cellSize(for uiScale: Double) -> CGSize {
        CGSize(width: baseCellWidth * scale(for: uiScale),
               height: baseCellHeight * scale(for: uiScale))
    }

    static func cellSize(forEffectiveScale effectiveScale: CGFloat) -> CGSize {
        CGSize(width: baseCellWidth * effectiveScale,
               height: baseCellHeight * effectiveScale)
    }

    static func gap(for uiScale: Double) -> CGFloat {
        baseGap * scale(for: uiScale)
    }

    static func padding(for uiScale: Double) -> CGFloat {
        basePadding * scale(for: uiScale)
    }

    static func slotSize(for uiScale: Double) -> CGSize {
        let s = scale(for: uiScale)
        return CGSize(width: baseCellWidth * s + baseGap * s,
                      height: baseCellHeight * s + baseGap * s)
    }

    static func effectiveScale(for uiScale: Double) -> CGFloat { scale(for: uiScale) }
    static func effectiveIconScale(for iconScale: Double) -> CGFloat { 0.2 + CGFloat(iconScale) * 0.8 }


    static func idealSize(visibleIndices: Int, cols: Int, uiScale: Double) -> CGSize {
        let cellW = baseCellWidth * scale(for: uiScale)
        let cellH = baseCellHeight * scale(for: uiScale)
        let gap = baseGap * scale(for: uiScale)
        let pad = basePadding * scale(for: uiScale)
        let rowCount = Int((visibleIndices + cols - 1) / cols)
        let colCount = min(cols, visibleIndices)
        let w = CGFloat(colCount) * (cellW + gap) - gap + pad * 2
        let h = CGFloat(rowCount) * (cellH + gap) - gap + pad * 2
        return CGSize(width: w, height: h)
    }


    static func visibleSpaceIndices(maxSpaces: Int, showMode: ShowMode, activeIndices: Set<Int>) -> [Int] {
        let maxN = min(maxSpaces, 16)
        let all = (1...maxN).map { $0 }
        if showMode == .active {
            return all.filter { activeIndices.contains($0) }
        }
        return all
    }


    static func cellFrame(offset: Int, cols: Int, uiScale: Double) -> CGRect {
        let s = scale(for: uiScale)
        let cellW = baseCellWidth * s
        let cellH = baseCellHeight * s
        let gap = baseGap * s
        let pad = basePadding * s
        let slotW = cellW + gap
        let slotH = cellH + gap
        let col = offset % cols
        let row = offset / cols
        let x = pad + CGFloat(col) * slotW - gap / 2
        let y = pad + CGFloat(row) * slotH - gap / 2
        return CGRect(x: x, y: y, width: slotW, height: slotH)
    }

    static func cellFrames(count: Int, cols: Int, uiScale: Double) -> [CGRect] {
        (0..<count).map { cellFrame(offset: $0, cols: cols, uiScale: uiScale) }
    }

    static func hitTest(point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }


    static func scaledWindowFrame(
        windowFrame: CGRect,
        displayBounds: CGRect,
        cellSize: CGSize
    ) -> CGRect? {
        guard displayBounds.width > 0, displayBounds.height > 0,
              cellSize.width > 0, cellSize.height > 0 else { return nil }
        let scaleX = cellSize.width / displayBounds.width
        let scaleY = cellSize.height / displayBounds.height
        return CGRect(
            x: (windowFrame.minX - displayBounds.minX) * scaleX,
            y: (windowFrame.minY - displayBounds.minY) * scaleY,
            width: max(windowFrame.width * scaleX, 2),
            height: max(windowFrame.height * scaleY, 2)
        )
    }

    static func hybridIconSize(uiScale: CGFloat, windowFrame: CGRect) -> CGFloat {
        guard uiScale > 0, windowFrame.width > 0, windowFrame.height > 0 else { return 0 }
        return min(26.25 * uiScale, min(windowFrame.width, windowFrame.height) * 0.75)
    }

    static func spaceNumberPosition(for uiScale: CGFloat) -> CGPoint {
        CGPoint(x: 8 * uiScale, y: 10 * uiScale)
    }

    static func spaceNamePosition(in cellSize: CGSize) -> CGPoint {
        CGPoint(x: cellSize.width / 2, y: cellSize.height / 2)
    }


    struct WindowIconLayout: Identifiable, Equatable {
        let windowID: Int
        let app: String
        let frame: CGRect
        var id: Int { windowID }
    }

    static func windowIconLayouts(
        windows: [YabaiWindow],
        displayBounds: CGRect,
        cellSize: CGSize
    ) -> [WindowIconLayout] {
        guard !windows.isEmpty,
              displayBounds.width > 0, displayBounds.height > 0,
              cellSize.width > 0, cellSize.height > 0 else { return [] }

        if windows.count == 1, let window = windows.first {
            return [WindowIconLayout(windowID: window.id, app: window.app,
                                    frame: CGRect(origin: .zero, size: cellSize))]
        }

        if windows.count == 2 {
            let horizontal = abs(windows[0].cgFrame.midX - windows[1].cgFrame.midX)
            let vertical = abs(windows[0].cgFrame.midY - windows[1].cgFrame.midY)
            let sorted: [YabaiWindow]
            let frames: [CGRect]

            if horizontal >= vertical {
                sorted = windows.sorted {
                    if $0.cgFrame.midX == $1.cgFrame.midX { return $0.id < $1.id }
                    return $0.cgFrame.midX < $1.cgFrame.midX
                }
                frames = [
                    CGRect(x: 0, y: 0, width: cellSize.width / 2, height: cellSize.height),
                    CGRect(x: cellSize.width / 2, y: 0, width: cellSize.width / 2, height: cellSize.height),
                ]
            } else {
                sorted = windows.sorted {
                    if $0.cgFrame.midY == $1.cgFrame.midY { return $0.id < $1.id }
                    return $0.cgFrame.midY < $1.cgFrame.midY
                }
                frames = [
                    CGRect(x: 0, y: 0, width: cellSize.width, height: cellSize.height / 2),
                    CGRect(x: 0, y: cellSize.height / 2, width: cellSize.width, height: cellSize.height / 2),
                ]
            }

            return zip(sorted, frames).map { window, frame in
                WindowIconLayout(windowID: window.id, app: window.app, frame: frame)
            }
        }

        let scaleX = cellSize.width / displayBounds.width
        let scaleY = cellSize.height / displayBounds.height
        let cellBounds = CGRect(origin: .zero, size: cellSize)

        return windows.compactMap { window in
            let frame = CGRect(
                x: (window.cgFrame.minX - displayBounds.minX) * scaleX,
                y: (window.cgFrame.minY - displayBounds.minY) * scaleY,
                width: window.cgFrame.width * scaleX,
                height: window.cgFrame.height * scaleY
            ).intersection(cellBounds)
            guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
            return WindowIconLayout(windowID: window.id, app: window.app, frame: frame)
        }
    }


    static func thumbnailPixelSize(for uiScale: Double, backingScale: CGFloat) -> CGSize {
        let s = scale(for: uiScale)
        return CGSize(width: baseCellWidth * s * backingScale,
                      height: baseCellHeight * s * backingScale)
    }
}
