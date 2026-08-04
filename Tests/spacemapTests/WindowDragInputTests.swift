import XCTest
import CoreGraphics
@testable import spacemap

extension WindowDragInput: Equatable {
    public static func == (lhs: WindowDragInput, rhs: WindowDragInput) -> Bool {
        guard lhs.cellFrames.count == rhs.cellFrames.count else { return false }
        for (lhsFrame, rhsFrame) in zip(lhs.cellFrames, rhs.cellFrames) {
            guard lhsFrame.spaceIndex == rhsFrame.spaceIndex &&
                  lhsFrame.frame == rhsFrame.frame else { return false }
        }
        return lhs.cachedWindows == rhs.cachedWindows &&
               lhs.focusedWindowIDAtOpen == rhs.focusedWindowIDAtOpen
    }
}

final class WindowDragInputTests: XCTestCase {

    // MARK: - Creation Tests

    func testWindowDragInputCanBeCreatedWithAllFields() {
        // Given
        let cellFrames = [
            (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (spaceIndex: 1, frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]
        let cachedWindows = [
            YabaiWindow(
                id: 1,
                app: "Finder",
                space: 1,
                frame: .init(x: 0, y: 0, w: 100, h: 100),
                isHidden: false,
                isMinimized: false,
                subLayer: "",
                pid: nil,
                role: nil,
                subrole: nil,
                isRootWindow: nil,
                hasAXReference: nil,
                isVisible: nil,
                isFloating: nil
            )
        ]
        let focusedWindowIDAtOpen = 42

        // When
        let input = WindowDragInput(
            cellFrames: cellFrames,
            cachedWindows: cachedWindows,
            focusedWindowIDAtOpen: focusedWindowIDAtOpen
        )

        // Then
        XCTAssertEqual(input.cellFrames.count, cellFrames.count)
        for (lhs, rhs) in zip(input.cellFrames, cellFrames) {
            XCTAssertEqual(lhs.spaceIndex, rhs.spaceIndex)
            XCTAssertEqual(lhs.frame, rhs.frame)
        }
        XCTAssertEqual(input.cachedWindows, cachedWindows)
        XCTAssertEqual(input.focusedWindowIDAtOpen, focusedWindowIDAtOpen)
    }

    func testWindowDragInputCanBeCreatedWithEmptyArraysAndNilOptional() {
        // When
        let input = WindowDragInput(
            cellFrames: [],
            cachedWindows: [],
            focusedWindowIDAtOpen: nil
        )

        // Then
        XCTAssertTrue(input.cellFrames.isEmpty)
        XCTAssertTrue(input.cachedWindows.isEmpty)
        XCTAssertNil(input.focusedWindowIDAtOpen)
    }

    // MARK: - Property Storage Tests

    func testWindowDragInputPropertiesAreCorrectlyStoredAndRetrievable() {
        // Given
        let cellFrames = [
            (spaceIndex: 3, frame: CGRect(x: 10, y: 20, width: 50, height: 75))
        ]
        let cachedWindows = [
            YabaiWindow(
                id: 7,
                app: "Safari",
                space: 2,
                frame: .init(x: 100, y: 200, w: 800, h: 600),
                isHidden: false,
                isMinimized: false,
                subLayer: "",
                pid: 1234,
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isRootWindow: true,
                hasAXReference: true,
                isVisible: true,
                isFloating: false
            )
        ]
        let focusedWindowIDAtOpen = 7

        // When
        let input = WindowDragInput(
            cellFrames: cellFrames,
            cachedWindows: cachedWindows,
            focusedWindowIDAtOpen: focusedWindowIDAtOpen
        )

        // Then
        XCTAssertEqual(input.cellFrames.count, 1)
        XCTAssertEqual(input.cellFrames[0].spaceIndex, 3)
        XCTAssertEqual(input.cellFrames[0].frame, CGRect(x: 10, y: 20, width: 50, height: 75))
        XCTAssertEqual(input.cachedWindows.count, 1)
        XCTAssertEqual(input.cachedWindows[0].id, 7)
        XCTAssertEqual(input.cachedWindows[0].app, "Safari")
        XCTAssertEqual(input.focusedWindowIDAtOpen, 7)
    }

    // MARK: - Equality Tests

    func testWindowDragInputWithDifferentCellFramesProducesDifferentEqualityResults() {
        // Given
        let inputA = WindowDragInput(
            cellFrames: [
                (spaceIndex: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            ],
            cachedWindows: [],
            focusedWindowIDAtOpen: nil
        )
        let inputB = WindowDragInput(
            cellFrames: [
                (spaceIndex: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            ],
            cachedWindows: [],
            focusedWindowIDAtOpen: nil
        )

        // Then
        XCTAssertNotEqual(inputA, inputB)
    }

    func testWindowDragInputWithDifferentCachedWindowsProducesDifferentEqualityResults() {
        // Given
        let inputA = WindowDragInput(
            cellFrames: [],
            cachedWindows: [
                YabaiWindow(
                    id: 1,
                    app: "Finder",
                    space: 1,
                    frame: .init(x: 0, y: 0, w: 100, h: 100),
                    isHidden: false,
                    isMinimized: false,
                    subLayer: "",
                    pid: nil,
                    role: nil,
                    subrole: nil,
                    isRootWindow: nil,
                    hasAXReference: nil,
                    isVisible: nil,
                    isFloating: nil
                )
            ],
            focusedWindowIDAtOpen: nil
        )
        let inputB = WindowDragInput(
            cellFrames: [],
            cachedWindows: [
                YabaiWindow(
                    id: 2,
                    app: "Safari",
                    space: 1,
                    frame: .init(x: 0, y: 0, w: 100, h: 100),
                    isHidden: false,
                    isMinimized: false,
                    subLayer: "",
                    pid: nil,
                    role: nil,
                    subrole: nil,
                    isRootWindow: nil,
                    hasAXReference: nil,
                    isVisible: nil,
                    isFloating: nil
                )
            ],
            focusedWindowIDAtOpen: nil
        )

        // Then
        XCTAssertNotEqual(inputA, inputB)
    }

    func testWindowDragInputWithDifferentFocusedWindowIDAtOpenProducesDifferentEqualityResults() {
        // Given
        let inputA = WindowDragInput(
            cellFrames: [],
            cachedWindows: [],
            focusedWindowIDAtOpen: 1
        )
        let inputB = WindowDragInput(
            cellFrames: [],
            cachedWindows: [],
            focusedWindowIDAtOpen: 2
        )

        // Then
        XCTAssertNotEqual(inputA, inputB)
    }
}
