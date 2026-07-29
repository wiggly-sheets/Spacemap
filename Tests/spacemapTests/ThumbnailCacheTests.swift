import XCTest
import CoreGraphics
import AppKit
@testable import spacemap

@available(macOS 14.0, *)
final class ThumbnailCacheTests: XCTestCase {
    func testCaptureRequestsCoverAllSpacesAndTheirDisplays() {
        let requests = ThumbnailCache.captureRequests(for: makeState())

        XCTAssertEqual(requests.map(\.spaceIndex), [1, 2, 3])
        XCTAssertEqual(requests.map(\.displayFrame.width), [1000, 1200, 1000])
        XCTAssertEqual(requests[0].windows.map(\.windowID), [11])
        XCTAssertEqual(requests[1].windows.map(\.windowID), [22])
        XCTAssertTrue(requests[2].windows.isEmpty)
    }

    func testCaptureRequestsExcludeSpacesWithoutDisplayBounds() {
        let requests = ThumbnailCache.captureRequests(
            for: makeState(includeSecondDisplay: false)
        )

        XCTAssertEqual(requests.map(\.spaceIndex), [1, 3])
    }

    func testCaptureRequestsOnlyIncludeVisibleSpaces() {
        let requests = ThumbnailCache.captureRequests(
            for: makeState(),
            spaceIndices: [2, 3]
        )

        XCTAssertEqual(requests.map(\.spaceIndex), [2, 3])
    }

    func testCompositePlacesOnlyRequestedWindowOnTransparentCanvas() throws {
        let request = ThumbnailCache.CaptureRequest(
            spaceIndex: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            windows: [
                .init(
                    windowID: 11,
                    frame: CGRect(x: 10, y: 20, width: 30, height: 40)
                )
            ]
        )
        let windowImage = try XCTUnwrap(solidImage(width: 30, height: 40))
        let composite = try XCTUnwrap(
            ThumbnailCache.composite(request: request, windowImages: [11: windowImage])
        )
        let bitmap = NSBitmapImageRep(cgImage: composite)

        XCTAssertEqual(composite.width, 100)
        XCTAssertEqual(composite.height, 100)
        XCTAssertGreaterThan(bitmap.colorAt(x: 20, y: 50)?.alphaComponent ?? 0, 0.9)
        XCTAssertLessThan(bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0.1)
    }

    private func makeState(includeSecondDisplay: Bool = true) -> GridState {
        let spaces = [
            YabaiSpace(id: 3, index: 3, display: 1, hasFocus: false, label: nil),
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: false, label: nil),
        ]
        let windows = [
            makeWindow(id: 11, space: 1),
            makeWindow(id: 12, space: 1, isHidden: true),
            makeWindow(id: 22, space: 2),
            makeWindow(id: 23, space: 2, isMinimized: true),
        ]
        let displays = [
            YabaiDisplay(
                index: 1,
                frame: .init(x: 0, y: 0, w: 1000, h: 800),
                hasFocus: true
            )
        ] + (includeSecondDisplay ? [
            YabaiDisplay(
                index: 2,
                frame: .init(x: 1000, y: 0, w: 1200, h: 900),
                hasFocus: false
            )
        ] : [])
        return GridState(
            config: .default,
            spaces: spaces,
            windows: windows,
            displayBounds: .zero,
            focusedIndex: 1,
            displays: displays
        )
    }

    private func makeWindow(
        id: Int,
        space: Int,
        isHidden: Bool = false,
        isMinimized: Bool = false
    ) -> YabaiWindow {
        YabaiWindow(
            id: id,
            app: "Test",
            space: space,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: isHidden,
            isMinimized: isMinimized,
            subLayer: "below"
        )
    }

    private func solidImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
