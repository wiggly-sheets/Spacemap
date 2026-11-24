import XCTest
import CoreGraphics
@testable import spacemap

class WindowDragHandlerTestCase: XCTestCase {
    var handler: WindowDragHandler!

    override func setUp() {
        super.setUp()
        handler = WindowDragHandler(
            frontmostApplicationName: { "Finder" },
            cgWindowListProvider: { [] }
        )
    }

    override func tearDown() {
        handler?.stop()
        handler = nil
        super.tearDown()
    }


    func makeWindow(
        id: Int,
        app: String,
        pid: Int? = nil,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> YabaiWindow {
        YabaiWindow(
            id: id,
            app: app,
            space: 1,
            frame: .init(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
            isHidden: false,
            isMinimized: false,
            subLayer: "normal",
            pid: pid
        )
    }
}
