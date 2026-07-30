import AppKit
import XCTest
@testable import spacemap

final class AboutWindowControllerTests: XCTestCase {
    @MainActor
    func testLicenseScrollViewContainsVisibleMITLicenseText() throws {
        let scroll = AboutWindowController.makeLicenseScrollView()
        let textView = try XCTUnwrap(scroll.documentView as? NSTextView)

        XCTAssertTrue(textView.string.hasPrefix("MIT License"))
        XCTAssertTrue(textView.string.contains("Permission is hereby granted"))
        XCTAssertEqual(textView.textColor, .labelColor)
        XCTAssertTrue(textView.isVerticallyResizable)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView == true)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertTrue(
            scroll.constraints.contains {
                $0.firstAttribute == .width && $0.constant == 520
            }
        )
        XCTAssertTrue(
            scroll.constraints.contains {
                $0.firstAttribute == .height && $0.constant == 220
            }
        )
    }
}
