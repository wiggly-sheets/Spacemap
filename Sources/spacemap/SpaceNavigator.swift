import Foundation

/// The four directions supported by HUD keyboard navigation.
enum SpaceNavigationDirection {
    case left
    case right
    case up
    case down
}

/// Calculates keyboard navigation targets for the HUD's visible space grid.
///
/// Rows and columns wrap independently. This means a short final row still
/// participates correctly: horizontal navigation stays in that row, while
/// vertical navigation only cycles through cells that actually exist in the
/// current column.
enum SpaceNavigator {
    /// Returns the spaces yabai can actually focus. The HUD may display empty
    /// placeholder cells in `showMode == .all`, but navigation must skip them.
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

        // Config validation normally guarantees this, but treating invalid
        // values as a one-column grid prevents navigation from crashing.
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
}
