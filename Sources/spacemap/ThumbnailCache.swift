import Foundation
import CoreGraphics
import ScreenCaptureKit

/// Captures individual yabai windows and composites them into per-space images.
/// Window-only capture prevents Spacemap's own HUD from entering thumbnails and
/// avoids ScreenCaptureKit display-filter leakage between spaces.
@available(macOS 14.0, *)
final class ThumbnailCache {
    struct CaptureWindow: Equatable {
        let windowID: CGWindowID
        let frame: CGRect
    }

    struct CaptureRequest: Equatable {
        let spaceIndex: Int
        let displayFrame: CGRect
        let windows: [CaptureWindow]
    }

    private struct RefreshJob {
        let generation: Int
        let requests: [CaptureRequest]
        let completion: @MainActor @Sendable () -> Void
    }

    static let shared = ThumbnailCache()

    private var cgCache: [Int: CGImage] = [:]
    private var nsCache: [Int: NSImage] = [:]
    private var refreshGeneration = 0
    private var activeRequests: [CaptureRequest]?
    private var pendingRefresh: RefreshJob?
    private let queue = DispatchQueue(label: "com.spacemap.thumbnailcache")

    /// Capture every requested space, then replace the cache in one operation.
    /// A newer refresh invalidates any older in-flight generation.
    func refreshSpaces(
        _ requests: [CaptureRequest],
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let jobToStart: RefreshJob? = queue.sync {
            if requests == pendingRefresh?.requests ||
                (requests == activeRequests && pendingRefresh == nil) {
                return nil
            }
            refreshGeneration += 1
            let job = RefreshJob(
                generation: refreshGeneration,
                requests: requests,
                completion: completion
            )
            if activeRequests != nil {
                pendingRefresh = job
                return nil
            }
            activeRequests = requests
            return job
        }
        guard let jobToStart else { return }
        run(jobToStart)
    }

    private func run(_ job: RefreshJob) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
                var shareableWindows: [CGWindowID: SCWindow] = [:]
                for window in content.windows {
                    shareableWindows[window.windowID] = window
                }

                var requestedWindows: [CGWindowID: CaptureWindow] = [:]
                for request in job.requests {
                    for window in request.windows {
                        requestedWindows[window.windowID] = window
                    }
                }

                let windowImages = await withTaskGroup(
                    of: (CGWindowID, CGImage?).self,
                    returning: [CGWindowID: CGImage].self
                ) { group in
                    for (windowID, requestedWindow) in requestedWindows {
                        guard let window = shareableWindows[windowID] else { continue }
                        group.addTask {
                            let image = await Self.capture(
                                window: window,
                                size: requestedWindow.frame.size
                            )
                            return (windowID, image)
                        }
                    }

                    var results: [CGWindowID: CGImage] = [:]
                    for await (windowID, image) in group {
                        if let image {
                            results[windowID] = image
                        }
                    }
                    return results
                }

                var captures: [Int: CGImage] = [:]
                for request in job.requests {
                    if let image = Self.composite(
                        request: request,
                        windowImages: windowImages
                    ) {
                        captures[request.spaceIndex] = image
                    }
                }

                let applied = queue.sync {
                    guard job.generation == refreshGeneration else { return false }
                    cgCache = captures
                    nsCache = captures.mapValues {
                        NSImage(
                            cgImage: $0,
                            size: NSSize(width: $0.width, height: $0.height)
                        )
                    }
                    return true
                }
                guard applied else { return }

                NSLog(
                    "spacemap/ThumbnailCache: refreshed \(captures.count) spaces " +
                    "from \(windowImages.count)/\(requestedWindows.count) windows"
                )
                DispatchQueue.main.async(execute: job.completion)
            } catch {
                NSLog("spacemap/ThumbnailCache: SCK refresh error: \(error.localizedDescription)")
            }
            finishRefresh()
        }
    }

    private func finishRefresh() {
        let nextJob: RefreshJob? = queue.sync {
            activeRequests = nil
            guard let pendingRefresh else { return nil }
            self.pendingRefresh = nil
            activeRequests = pendingRefresh.requests
            return pendingRefresh
        }
        if let nextJob {
            run(nextJob)
        }
    }

    static func captureRequests(
        for state: GridState,
        spaceIndices: Set<Int>? = nil
    ) -> [CaptureRequest] {
        state.spaces.sorted { $0.index < $1.index }.compactMap { space in
            guard spaceIndices?.contains(space.index) ?? true else { return nil }
            let displayFrame = state.displayBounds(forSpace: space.index)
            guard displayFrame.width > 0, displayFrame.height > 0 else { return nil }

            let windows = state.windows(forSpace: space.index)
                .filter { !$0.isHidden && !$0.isMinimized }
                .map {
                    CaptureWindow(
                        windowID: CGWindowID(truncatingIfNeeded: $0.id),
                        frame: $0.cgFrame
                    )
                }
            return CaptureRequest(
                spaceIndex: space.index,
                displayFrame: displayFrame,
                windows: windows
            )
        }
    }

    /// Get cached thumbnail for a space.
    func thumbnail(forSpace index: Int) -> CGImage? {
        queue.sync { cgCache[index] }
    }

    /// Get cached NSImage for a space.
    func thumbnailNSImage(forSpace index: Int) -> NSImage? {
        queue.sync { nsCache[index] }
    }

    func clear() {
        queue.sync {
            refreshGeneration += 1
            pendingRefresh = nil
            cgCache.removeAll()
            nsCache.removeAll()
        }
    }

    static func composite(
        request: CaptureRequest,
        windowImages: [CGWindowID: CGImage]
    ) -> CGImage? {
        let width = Int(request.displayFrame.width.rounded(.up))
        let height = Int(request.displayFrame.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }
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

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        for window in request.windows {
            guard let image = windowImages[window.windowID] else { continue }
            let relativeX = window.frame.minX - request.displayFrame.minX
            let relativeTop = window.frame.minY - request.displayFrame.minY
            let destination = CGRect(
                x: relativeX,
                y: request.displayFrame.height - relativeTop - window.frame.height,
                width: window.frame.width,
                height: window.frame.height
            )
            context.draw(image, in: destination)
        }
        return context.makeImage()
    }

    private static func capture(window: SCWindow, size: CGSize) async -> CGImage? {
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
