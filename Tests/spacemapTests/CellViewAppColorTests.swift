import XCTest
import CoreGraphics
import SwiftUI
@testable import spacemap

final class CellViewAppColorTests: CellViewGridViewTestCase {
    func testAppColorFewWindowsReturnsBaseRectColor() {
        let theme = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0xff0000, rect2: 0x00ff00, rect3: 0x0000ff)
        let palette = [theme.rect1, theme.rect2, theme.rect3]
        let expected = palette[Int(CellView.stableAppHash("Firefox") % 3)]
        let c1 = CellView.appColor("Firefox", theme: theme)
        XCTAssertEqual(String(describing: c1), String(describing: Color(hex: expected)))
        XCTAssertEqual(String(describing: c1), String(describing: CellView.appColor("Firefox", theme: theme)))

        let other = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0x111111, rect2: 0x222222, rect3: 0x333333)
        let otherPalette = [other.rect1, other.rect2, other.rect3]
        let otherExpected = otherPalette[Int(CellView.stableAppHash("Firefox") % 3)]
        XCTAssertEqual(
            String(describing: CellView.appColor("Firefox", theme: other)),
            String(describing: Color(hex: otherExpected))
        )
    }

    func testAppColorManyWindowsHSLVariation() {
        let theme = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0xff0000, rect2: 0x00ff00, rect3: 0x0000ff)
        let other = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0x111111, rect2: 0x222222, rect3: 0x333333)
        let palette = [theme.rect1, theme.rect2, theme.rect3]
        let otherPalette = [other.rect1, other.rect2, other.rect3]
        for name in ["Firefox", "Safari", "Terminal"] {
            let expected = palette[Int(CellView.stableAppHash(name) % 3)]
            XCTAssertEqual(
                String(describing: CellView.appColor(name, theme: theme)),
                String(describing: Color(hex: expected)),
                "\(name) left palette"
            )
            let otherExpected = otherPalette[Int(CellView.stableAppHash(name) % 3)]
            XCTAssertEqual(
                String(describing: CellView.appColor(name, theme: other)),
                String(describing: Color(hex: otherExpected)),
                "\(name) index unstable across themes"
            )
        }
    }

    func testAppColorUsesStableFNVHash() {
        XCTAssertEqual(CellView.stableAppHash(""), 14_695_981_039_346_656_037)
        XCTAssertEqual(CellView.stableAppHash("a"), 12_638_187_200_555_641_996)
    }

    func testAppColorLightnessActuallyVariesByApp() {
        let variations = ["Firefox", "Safari", "Terminal", "VSCode", "Slack", "Notes"]
            .map(CellView.appColorVariation(for:))
        let lightnesses = Set(variations.map(\.lightness))

        XCTAssertGreaterThan(lightnesses.count, 1)
        for variation in variations {
            XCTAssertTrue((0.42...0.58).contains(variation.lightness))
            XCTAssertTrue((0.35...0.69).contains(variation.saturation))
        }
    }

    func testAppColorReturnsValidThemeColor() {
        let theme = AppTheme(background: 0, focused: 0, text: 0, dropTarget: 0, cellBg: 0, cellBgFocused: 0,
                             rect1: 0xff0000, rect2: 0x00ff00, rect3: 0x0000ff)
        let names = ["Firefox", "Safari", "Terminal", "VSCode", "Slack", "Notes"]
        let validColors: Set<String> = ["#FF0000FF", "#00FF00FF", "#0000FFFF"]
        for name in names {
            let c = CellView.appColor(name, theme: theme)
            XCTAssertTrue(validColors.contains(String(describing: c)),
                          "\(name) returned unexpected color \(c)")
        }
    }


}
