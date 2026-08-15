import Foundation

enum SpaceNavigationDirection {
    case left
    case right
    case up
    case down
}

enum SpaceNavigator {
    static func navigableSpaceIndices(activeSpaceIndices: [Int], maxSpaces: Int) -> [Int] {
        let limit = min(max(maxSpaces, 0), 16)
        return Array(Set(activeSpaceIndices))
            .filter { $0 >= 1 && $0 <= limit }
            .sorted()
    }

    static func destination(
        from currentSpaceIndex: Int,
        visibleSpaceIndices: [Int],
        columns: Int,
        direction: SpaceNavigationDirection
    ) -> Int? {
        guard !visibleSpaceIndices.isEmpty else { return nil }

        let columnCount = max(columns, 1)
        guard let currentPosition = visibleSpaceIndices.firstIndex(of: currentSpaceIndex) else {
            return visibleSpaceIndices.first
        }

        let rowStart = (currentPosition / columnCount) * columnCount
        let rowEnd = min(rowStart + columnCount, visibleSpaceIndices.count)

        switch direction {
        case .left:
            let targetPosition = currentPosition == rowStart ? rowEnd - 1 : currentPosition - 1
            return visibleSpaceIndices[targetPosition]

        case .right:
            let targetPosition = currentPosition + 1 == rowEnd ? rowStart : currentPosition + 1
            return visibleSpaceIndices[targetPosition]

        case .up, .down:
            let column = currentPosition % columnCount
            let positionsInColumn = stride(
                from: column,
                to: visibleSpaceIndices.count,
                by: columnCount
            ).map { $0 }

            guard let positionInColumn = positionsInColumn.firstIndex(of: currentPosition) else {
                return nil
            }

            let targetOffset: Int
            switch direction {
            case .up:
                targetOffset = (positionInColumn - 1 + positionsInColumn.count) % positionsInColumn.count
            case .down:
                targetOffset = (positionInColumn + 1) % positionsInColumn.count
            case .left, .right:
                preconditionFailure("Handled before column navigation")
            }
            return visibleSpaceIndices[positionsInColumn[targetOffset]]
        }
    }

    static func destinationAcrossDisplays(
        from currentSpaceIndex: Int,
        displaySpaceIndices: [[Int]],
        maxSpaces: Int,
        columns: Int,
        direction: SpaceNavigationDirection
    ) -> Int? {
        let displays = displaySpaceIndices
            .map { navigableSpaceIndices(activeSpaceIndices: $0, maxSpaces: maxSpaces) }
            .filter { !$0.isEmpty }
        guard !displays.isEmpty else { return nil }
        guard let currentDisplayPosition = displays.firstIndex(where: { $0.contains(currentSpaceIndex) }) else {
            return displays.first?.first
        }

        let currentDisplay = displays[currentDisplayPosition]
        guard let localTarget = destination(
            from: currentSpaceIndex,
            visibleSpaceIndices: currentDisplay,
            columns: columns,
            direction: direction
        ) else {
            return nil
        }
        guard wrapsWithinGrid(
            from: currentSpaceIndex,
            visibleSpaceIndices: currentDisplay,
            columns: columns,
            direction: direction
        ), displays.count > 1 else {
            return localTarget
        }

        let step: Int
        switch direction {
        case .left, .up: step = -1
        case .right, .down: step = 1
        }
        let targetDisplayPosition = (currentDisplayPosition + step + displays.count) % displays.count
        let targetDisplay = displays[targetDisplayPosition]
        return step > 0 ? targetDisplay.first : targetDisplay.last
    }

    private static func wrapsWithinGrid(
        from currentSpaceIndex: Int,
        visibleSpaceIndices: [Int],
        columns: Int,
        direction: SpaceNavigationDirection
    ) -> Bool {
        let columnCount = max(columns, 1)
        guard let currentPosition = visibleSpaceIndices.firstIndex(of: currentSpaceIndex) else {
            return false
        }

        switch direction {
        case .left:
            return currentPosition % columnCount == 0
        case .right:
            let rowEnd = min(((currentPosition / columnCount) + 1) * columnCount, visibleSpaceIndices.count)
            return currentPosition + 1 == rowEnd
        case .up, .down:
            let column = currentPosition % columnCount
            let positionsInColumn = stride(
                from: column,
                to: visibleSpaceIndices.count,
                by: columnCount
            ).map { $0 }
            guard let positionInColumn = positionsInColumn.firstIndex(of: currentPosition) else {
                return false
            }
            switch direction {
            case .up:
                return positionInColumn == 0
            case .down:
                return positionInColumn + 1 == positionsInColumn.count
            case .left, .right:
                preconditionFailure("Handled before column navigation")
            }
        }
    }
}
