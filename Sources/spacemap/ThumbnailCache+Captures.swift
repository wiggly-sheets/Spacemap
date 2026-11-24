import Foundation
import AppKit
import Carbon
import Combine
import CoreGraphics
import ScreenCaptureKit

@available(macOS 14.0, *)

extension ThumbnailCache {
    static func composite(
        request: CaptureRequest,
        windowImages: [CGWindowID: CGImage],
        desktopImage: CGImage? = nil
    ) -> CGImage? {
        ThumbnailCompositor.composite(
            request: request,
            windowImages: windowImages,
            desktopImage: desktopImage
        )
    }

    static func captureWindows(
        _ targets: [WindowTarget]
    ) async -> [CGWindowID: CGImage] {
        await withTaskGroup(
            of: (CGWindowID, CGImage?).self,
            returning: [CGWindowID: CGImage].self
        ) { group in
            var iterator = targets.makeIterator()
            for _ in 0..<min(maxConcurrentCaptures, targets.count) {
                guard let target = iterator.next() else { break }
                group.addTask {
                    (
                        target.windowID,
                        await capture(window: target.window, size: target.outputSize)
                    )
                }
            }

            var results: [CGWindowID: CGImage] = [:]
            while let (windowID, image) = await group.next() {
                if let image {
                    results[windowID] = image
                }
                if let target = iterator.next() {
                    group.addTask {
                        (
                            target.windowID,
                            await capture(window: target.window, size: target.outputSize)
                        )
                    }
                }
            }
            return results
        }
    }

    static func captureDesktops(
        requests: [CaptureRequest],
        displays: [SCDisplay],
        windows: [SCWindow]
    ) async -> [FrameKey: CGImage] {
        var seen = Set<FrameKey>()
        let jobs: [(FrameKey, SCDisplay, CGSize)] = requests.compactMap { request in
            guard seen.insert(FrameKey(request.displayFrame)).inserted,
                  let display = displays.first(where: { $0.frame == request.displayFrame }) else {
                return nil
            }
            return (FrameKey(request.displayFrame), display, request.outputSize)
        }
        return await withTaskGroup(
            of: (FrameKey, CGImage?).self,
            returning: [FrameKey: CGImage].self
        ) { group in
            for job in jobs {
                group.addTask {
                    (
                        job.0,
                        await captureDesktop(
                            display: job.1,
                            size: job.2,
                            excluding: windows
                        )
                    )
                }
            }
            var results: [FrameKey: CGImage] = [:]
            for await (frame, image) in group {
                if let image { results[frame] = image }
            }
            return results
        }
    }

    static func captureDesktop(
        display: SCDisplay,
        size: CGSize,
        excluding windows: [SCWindow]
    ) async -> CGImage? {
        do {
            let filter = SCContentFilter(display: display, excludingWindows: windows)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(size.width.rounded(.up)))
            config.height = max(1, Int(size.height.rounded(.up)))
            config.showsCursor = false
            config.shouldBeOpaque = true
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            NSLog(
                "spacemap/ThumbnailCache: desktop capture error: " +
                error.localizedDescription
            )
            return nil
        }
    }

    static func capture(window: SCWindow, size: CGSize) async -> CGImage? {
        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(size.width.rounded(.up)))
            config.height = max(1, Int(size.height.rounded(.up)))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            config.shouldBeOpaque = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            NSLog(
                "spacemap/ThumbnailCache: window \(window.windowID) capture error: " +
                error.localizedDescription
            )
            return nil
        }
    }
}
