import XCTest
import CoreGraphics
import AppKit
@testable import spacemap

@available(macOS 14.0, *)
final class ThumbnailCacheTests: XCTestCase {
    func testCaptureRequestsCoverAllSpacesAndTheirDisplays() {
        let requests = ThumbnailRequestBuilder.captureRequests(for: makeState())

        XCTAssertEqual(requests.map(\.spaceIndex), [1, 2, 3])
        XCTAssertEqual(requests.map(\.displayFrame.width), [1000, 1200, 1000])
        XCTAssertEqual(requests.map(\.outputSize.width), [320, 320, 320])
        XCTAssertEqual(requests.map(\.outputSize.height), [256, 240, 256])
        XCTAssertEqual(
            requests.map(\.includeUnmanagedOnScreenWindows),
            [true, true, false]
        )
        XCTAssertEqual(requests[0].windows.map(\.windowID), [11])
        XCTAssertEqual(requests[1].windows.map(\.windowID), [22])
        XCTAssertTrue(requests[2].windows.isEmpty)
    }

    func testCaptureRequestsExcludeSpacesWithoutDisplayBounds() {
        let requests = ThumbnailRequestBuilder.captureRequests(
            for: makeState(includeSecondDisplay: false)
        )

        XCTAssertEqual(requests.map(\.spaceIndex), [1, 3])
    }

    func testCaptureRequestsOnlyIncludeVisibleSpaces() {
        let requests = ThumbnailRequestBuilder.captureRequests(
            for: makeState(),
            spaceIndices: [2, 3]
        )

        XCTAssertEqual(requests.map(\.spaceIndex), [2, 3])
    }

    func testCompositePlacesOnlyRequestedWindowOnTransparentCanvas() throws {
        let request = ThumbnailCache.CaptureRequest(
            spaceIndex: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            outputSize: CGSize(width: 50, height: 50),
            includeUnmanagedOnScreenWindows: false,
            knownYabaiWindowIDs: [11],
            windows: [
                .init(
                    windowID: 11,
                    frame: CGRect(x: 10, y: 20, width: 30, height: 40)
                )
            ]
        )
        let windowImage = try XCTUnwrap(solidImage(width: 30, height: 40))
        let composite = try XCTUnwrap(
            ThumbnailCompositor.composite(request: request, windowImages: [11: windowImage])
        )
        let bitmap = NSBitmapImageRep(cgImage: composite)

        XCTAssertEqual(composite.width, 50)
        XCTAssertEqual(composite.height, 50)
        XCTAssertGreaterThan(bitmap.colorAt(x: 10, y: 25)?.alphaComponent ?? 0, 0.9)
        XCTAssertLessThan(bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0.1)
    }

    func testAspectFillSizePreservesDisplayAspectRatio() {
        let size = ThumbnailCompositor.aspectFillSize(
            source: CGSize(width: 2560, height: 1440),
            target: CGSize(width: 320, height: 200)
        )

        XCTAssertEqual(size, CGSize(width: 356, height: 200))
        XCTAssertEqual(ThumbnailCache.maxConcurrentCaptures, 4)
        XCTAssertEqual(ThumbnailCache.duplicateRefreshTTL, 0.25)
    }

    func testCaptureRequestsIncludeHelperWindowsOnlyWhenConfigured() {
        let requests = ThumbnailRequestBuilder.captureRequests(
            for: makeState(showExtraWindows: true)
        )

        XCTAssertEqual(requests[0].windows.map(\.windowID), [11, 13])
    }

    func testUnmanagedOnScreenWindowFilterIncludesRaycastButRejectsSystemAndManagedWindows() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let raycastFrame = CGRect(x: 300, y: 200, width: 400, height: 300)

        XCTAssertTrue(ThumbnailRequestBuilder.shouldIncludeUnmanagedWindow(
            windowID: 50,
            isOnScreen: true,
            windowLayer: 3,
            ownerPID: 500,
            bundleIdentifier: "com.raycast.macos",
            frame: raycastFrame,
            displayFrame: display,
            knownYabaiWindowIDs: [11],
            currentPID: 999
        ))
        XCTAssertFalse(ThumbnailRequestBuilder.shouldIncludeUnmanagedWindow(
            windowID: 50,
            isOnScreen: true,
            windowLayer: 3,
            ownerPID: 999,
            bundleIdentifier: "com.spacemap.app",
            frame: raycastFrame,
            displayFrame: display,
            knownYabaiWindowIDs: [],
            currentPID: 999
        ))
        XCTAssertFalse(ThumbnailRequestBuilder.shouldIncludeUnmanagedWindow(
            windowID: 50,
            isOnScreen: true,
            windowLayer: 0,
            ownerPID: 500,
            bundleIdentifier: "com.apple.controlcenter",
            frame: raycastFrame,
            displayFrame: display,
            knownYabaiWindowIDs: [],
            currentPID: 999
        ))
        XCTAssertFalse(ThumbnailRequestBuilder.shouldIncludeUnmanagedWindow(
            windowID: 11,
            isOnScreen: true,
            windowLayer: 0,
            ownerPID: 500,
            bundleIdentifier: "com.example.app",
            frame: raycastFrame,
            displayFrame: display,
            knownYabaiWindowIDs: [11],
            currentPID: 999
        ))
    }

    private func makeState(
        includeSecondDisplay: Bool = true,
        showExtraWindows: Bool = false
    ) -> GridState {
        let spaces = [
            YabaiSpace(id: 3, index: 3, display: 1, hasFocus: false, isVisible: false, label: nil),
            YabaiSpace(id: 1, index: 1, display: 1, hasFocus: true, isVisible: true, label: nil),
            YabaiSpace(id: 2, index: 2, display: 2, hasFocus: false, isVisible: true, label: nil),
        ]
        let windows = [
            makeWindow(id: 11, space: 1),
            makeWindow(id: 12, space: 1, isHidden: true),
            makeWindow(id: 13, space: 1, isStandard: false),
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
        var config = GridConfig.default
        config.showExtraWindows = showExtraWindows
        return GridState(
            config: config,
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
        isMinimized: Bool = false,
        subLayer: String = "below",
        isStandard: Bool = true
    ) -> YabaiWindow {
        var window = YabaiWindow(
            id: id,
            app: "Test",
            space: space,
            frame: .init(x: 0, y: 0, w: 100, h: 100),
            isHidden: isHidden,
            isMinimized: isMinimized,
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
