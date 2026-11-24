import XCTest
import CoreGraphics
@testable import spacemap

class ModelTestCase: XCTestCase {
    func standard(_ window: YabaiWindow) -> YabaiWindow {
        var window = window
        window.role = "AXWindow"
        window.subrole = "AXStandardWindow"
        window.isRootWindow = true
        return window
    }

    /// Auto naming: each space takes its leftmost visible window's app, hidden
    /// and minimized windows never name a space, and an empty space has none.
}
