import XCTest
import CoreGraphics
import SwiftUI
@testable import spacemap

class CellViewGridViewTestCase: XCTestCase {
    func makeWindow(
        id: Int,
        app: String,
        space: Int = 1,
        subLayer: String = "below",
        isStandard: Bool = true,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> YabaiWindow {
        var window = YabaiWindow(
            id: id,
            app: app,
            space: space,
            frame: .init(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
            isHidden: false,
            isMinimized: false,
            subLayer: subLayer
        )
        window.role = isStandard ? "AXWindow" : "AXUnknown"
        window.subrole = isStandard ? "AXStandardWindow" : "AXUnknown"
        window.isRootWindow = true
        window.hasAXReference = true
        window.isVisible = true
        window.isFloating = false
        return window
    }


}



func makeSpaces(_ indices: ClosedRange<Int>) -> [YabaiSpace] {
    indices.map {
        YabaiSpace(
            id: $0,
            index: $0,
            display: 1,
            hasFocus: $0 == indices.lowerBound,
            isVisible: $0 == indices.lowerBound,
            label: nil
        )
    }
}
