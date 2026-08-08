import AppKit

enum MenuBarPreviewRenderer {
    private static let previewHeight: CGFloat = 18
    private static let gap: CGFloat = 2

    static func spaceIndices(
        mode: MenuBarDisplayMode,
        nearbyCount: Int,
        spaces: [YabaiSpace],
        focusedIndex: Int?
    ) -> [Int] {
        let active = spaces.map(\.index).sorted()
        guard !active.isEmpty else { return [] }
        let focused = focusedIndex.flatMap { active.contains($0) ? $0 : nil } ?? active[0]

        switch mode {
        case .icon:
            return []
        case .dots:
            return active
        case .current:
            return [focused]
        case .all:
            return active
        case .nearby:
            let count = min(max(nearbyCount, 1), active.count)
            guard let focusedOffset = active.firstIndex(of: focused) else {
                return Array(active.prefix(count))
            }
            var lower = focusedOffset - ((count - 1) / 2)
            lower = min(max(lower, 0), active.count - count)
            return Array(active[lower..<(lower + count)])
        }
    }

    static func image(for state: GridState) -> NSImage? {
        let mode = state.config.menuBarDisplayMode
        if mode == .dots {
            return dotGridImage(for: state)
        }
        let indices = spaceIndices(
            mode: mode,
            nearbyCount: state.config.menuBarNearbyCount,
            spaces: state.spaces,
            focusedIndex: state.focusedIndex
        )
        guard !indices.isEmpty else { return nil }

        let rows = 1
        let columns = Int(ceil(Double(indices.count) / Double(rows)))
        let cellWidth: CGFloat = mode == .nearby ? 26 : 34
        let cellHeight = (previewHeight - CGFloat(rows - 1) * gap) / CGFloat(rows)
        let size = CGSize(
            width: CGFloat(columns) * cellWidth + CGFloat(max(columns - 1, 0)) * gap,
            height: previewHeight
        )
        let image = NSImage(size: size, flipped: false) { bounds in
            for (offset, spaceIndex) in indices.enumerated() {
                let row = offset / columns
                let column = offset % columns
                let cell = CGRect(
                    x: CGFloat(column) * (cellWidth + gap),
                    y: bounds.maxY - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap,
                    width: cellWidth,
                    height: cellHeight
                )
                drawSpace(spaceIndex, in: cell, state: state)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = NSLocalizedString("Spacemap workspace preview", comment: "")
        return image
    }

    private static func dotGridImage(for state: GridState) -> NSImage {
        let maxSpaces = max(1, min(state.config.maxSpaces, 16))
        let columns = max(1, min(state.config.cols, maxSpaces))
        let rows = max(1, Int(ceil(Double(maxSpaces) / Double(columns))))
        let active = Set(state.spaces.map(\.index))
        let imageHeight: CGFloat = 20
        let padding: CGFloat = 2
        let horizontalGap: CGFloat = columns > 1 ? 1.5 : 0
        let availableHeight = imageHeight - padding * 2
        let verticalGap: CGFloat = rows > 1
            ? (rows <= 4 ? 1.5 : max(0.25, min(1, availableHeight / CGFloat(rows * 3))))
            : 0
        let diameter = min(
            4,
            (availableHeight - CGFloat(rows - 1) * verticalGap) / CGFloat(rows)
        )
        let gridWidth = CGFloat(columns) * diameter + CGFloat(columns - 1) * horizontalGap
        let gridHeight = CGFloat(rows) * diameter + CGFloat(rows - 1) * verticalGap
        let size = CGSize(width: max(20, gridWidth + padding * 2), height: imageHeight)
        let origin = CGPoint(
            x: (size.width - gridWidth) / 2,
            y: (size.height - gridHeight) / 2
        )

        let image = NSImage(size: size, flipped: false) { _ in
            for offset in 0..<maxSpaces {
                let spaceIndex = offset + 1
                let row = offset / columns
                let column = offset % columns
                let dotRect = CGRect(
                    x: origin.x + CGFloat(column) * (diameter + horizontalGap),
                    y: origin.y + CGFloat(rows - row - 1) * (diameter + verticalGap),
                    width: diameter,
                    height: diameter
                )
                let color: NSColor
                if spaceIndex == state.focusedIndex {
                    color = .controlAccentColor
                } else if active.contains(spaceIndex) {
                    color = .labelColor.withAlphaComponent(0.75)
                } else {
                    color = .labelColor.withAlphaComponent(0.18)
                }
                color.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = NSLocalizedString("Spacemap workspace dots", comment: "")
        return image
    }

    private static func drawSpace(_ spaceIndex: Int, in rect: CGRect, state: GridState) {
        let focused = spaceIndex == state.focusedIndex
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
        (focused ? NSColor.controlAccentColor.withAlphaComponent(0.25) : NSColor.labelColor.withAlphaComponent(0.08)).setFill()
        path.fill()
        (focused ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.45)).setStroke()
        path.lineWidth = focused ? 1.25 : 0.75
        path.stroke()

        let content = rect.insetBy(dx: 2, dy: 2)
        guard content.width > 0, content.height > 0 else { return }
        let displayBounds = state.displayBounds(forSpace: spaceIndex)
        let windows = state.windows(forSpace: spaceIndex).filter {
            $0.shouldDisplay(showExtraWindows: state.config.showExtraWindows)
        }

        for window in windows {
            guard let scaled = GridLayout.scaledWindowFrame(
                windowFrame: window.cgFrame,
                displayBounds: displayBounds,
                cellSize: content.size
            ) else { continue }
            let windowRect = CGRect(
                x: content.minX + scaled.minX,
                y: content.maxY - scaled.maxY,
                width: scaled.width,
                height: scaled.height
            ).intersection(content)
            guard let separatedRect = separatedWindowFrame(windowRect) else { continue }
            NSColor.labelColor.withAlphaComponent(focused ? 0.8 : 0.6).setFill()
            NSBezierPath(roundedRect: separatedRect, xRadius: 0.6, yRadius: 0.6).fill()
        }
    }

    static func separatedWindowFrame(_ frame: CGRect, inset: CGFloat = 0.55) -> CGRect? {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
        let horizontalInset = min(inset, max(0, (frame.width - 1) / 2))
        let verticalInset = min(inset, max(0, (frame.height - 1) / 2))
        return frame.insetBy(dx: horizontalInset, dy: verticalInset)
    }
}
