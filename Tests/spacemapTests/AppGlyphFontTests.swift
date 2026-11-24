import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class AppGlyphFontTests: XCTestCase {

    private func installedFontURL() throws -> URL {
        guard let url = AppGlyphFont.candidateURLs().first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw XCTSkip("sketchybar-app-font is not installed")
        }
        return url
    }

    private func bundledFontData() throws -> Data {
        try Data(contentsOf: try installedFontURL())
    }

    private func loadedFont() throws -> AppGlyphFont {
        guard let font = AppGlyphFont.load() else {
            throw XCTSkip("sketchybar-app-font failed to load")
        }
        return font
    }

    func testInstalledFontHasAppMetadataRecord() throws {
        let data = try bundledFontData()
        let payload = try XCTUnwrap(
            AppGlyphFont.appMetadataPayload(in: data),
            "meta/APPM table not found"
        )
        XCTAssertGreaterThan(payload.count, 0)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: payload))
    }

    func testFaceMatchesParsedFontFile() throws {
        let url = try installedFontURL()
        let font = try XCTUnwrap(AppGlyphFont.parse(data: Data(contentsOf: url), url: url))
        let face = try XCTUnwrap(font.face(size: 11))
        let faceURL = CTFontCopyAttribute(face as CTFont, kCTFontURLAttribute) as? URL
        XCTAssertEqual(faceURL?.standardizedFileURL, url.standardizedFileURL)
    }

    func testKnownLigaturesMapToExpectedAppNames() throws {
        let font = try loadedFont()

        // Finder aliases change between font releases; the stable contract is
        // that the primary name and known aliases resolve.
        let finder = font.appNames(forLigature: ":finder:") ?? []
        XCTAssertTrue(finder.contains("Finder"))
        XCTAssertTrue(finder.contains("访达"))
        XCTAssertTrue(finder.contains("FlowFinder"))
        XCTAssertEqual(font.appNames(forLigature: ":alacritty:"), ["Alacritty"])
        XCTAssertEqual(
            font.appNames(forLigature: ":google_chrome:"),
            ["Chromium", "Google Chrome", "Google Chrome Canary"]
        )
    }

    func testDefaultGlyphIsNonEmptyAndUsedForUnknownApps() throws {
        let font = try loadedFont()

        XCTAssertEqual(font.glyph(forApp: "Totally Unknown App"), font.glyph(forApp: AppGlyphFont.defaultLigature))
        XCTAssertFalse(font.glyph(forApp: "Totally Unknown App").isEmpty)
    }

    func testExactMatchWinsAndPrefixMatchesAreSupported() throws {
        let font = try loadedFont()

        XCTAssertEqual(font.glyph(forApp: "Finder"), font.glyph(forApp: "访达"))
        // Every installed mapping resolves to something other than the default.
        XCTAssertNotEqual(font.glyph(forApp: "Google Chrome"), font.glyph(forApp: "Default"))
    }

    func testInitialsFallbackForMissingFont() {
        XCTAssertEqual(AppGlyphFont.initials(forApp: "Google Chrome"), "GC")
        XCTAssertEqual(AppGlyphFont.initials(forApp: "Safari"), "S")
        XCTAssertEqual(AppGlyphFont.initials(forApp: "some-weird-app"), "SW")
    }
}
