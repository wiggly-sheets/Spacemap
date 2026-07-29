import Foundation
import AppKit
import Combine
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class ThumbnailStore: ObservableObject {
    static let shared = ThumbnailStore()

    @Published private var images: [Int: NSImage] = [:]

    func image(forSpace index: Int) -> NSImage? {
        images[index]
    }

    fileprivate func replace(with images: [Int: NSImage]) {
        self.images = images
    }

    fileprivate func removeAll() {
        images.removeAll()
    }
}

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
        let outputSize: CGSize
        let includeUnmanagedOnScreenWindows: Bool
        let knownYabaiWindowIDs: Set<CGWindowID>
        let windows: [CaptureWindow]
    }

    private struct RefreshJob {
        let generation: Int
        let requests: [CaptureRequest]
    }

    private struct WindowTarget {
        let windowID: CGWindowID
        let window: SCWindow
        let outputSize: CGSize
    }

    static let shared = ThumbnailCache()
    static let maxConcurrentCaptures = 4
    static let duplicateRefreshTTL: TimeInterval = 0.25
    static let defaultThumbnailPixelSize = CGSize(width: 320, height: 200)
    private static let excludedUnmanagedBundleIDs: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
    ]

    private var refreshGeneration = 0
    private var activeRequests: [CaptureRequest]?
    private var pendingRefresh: RefreshJob?
    private var lastCompletedRequests: [CaptureRequest]?
    private var lastCompletedAt: TimeInterval = 0
    private let queue = DispatchQueue(label: "com.spacemap.thumbnailcache")

    /// Capture every requested space and publish one atomic cache update.
    /// A newer refresh supersedes older work; identical bursts are coalesced.
    func refreshSpaces(_ requests: [CaptureRequest], force: Bool = false) {
        let jobToStart: RefreshJob? = queue.sync {
            let now = ProcessInfo.processInfo.systemUptime
            if !force,
               requests == lastCompletedRequests,
               now - lastCompletedAt < Self.duplicateRefreshTTL {
                return nil
            }
            if requests == pendingRefresh?.requests ||
                (requests == activeRequests && pendingRefresh == nil) {
                return nil
            }

            refreshGeneration += 1
            let job = RefreshJob(
                generation: refreshGeneration,
                requests: requests
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

                let knownYabaiWindowIDs = Set(
                    job.requests.flatMap(\.knownYabaiWindowIDs)
                )
                let currentPID = getpid()
                let effectiveRequests = job.requests.map { request in
                    guard request.includeUnmanagedOnScreenWindows else { return request }
                    let unmanagedWindows = content.windows.compactMap { window -> CaptureWindow? in
                        guard Self.shouldIncludeUnmanagedWindow(
                            windowID: window.windowID,
                            isOnScreen: window.isOnScreen,
                            windowLayer: window.windowLayer,
                            ownerPID: window.owningApplication?.processID,
                            bundleIdentifier: window.owningApplication?.bundleIdentifier,
                            frame: window.frame,
                            displayFrame: request.displayFrame,
                            knownYabaiWindowIDs: knownYabaiWindowIDs,
                            currentPID: currentPID
                        ) else {
                            return nil
                        }
                        return CaptureWindow(
                            windowID: window.windowID,
                            frame: window.frame
                        )
                    }
                    return CaptureRequest(
                        spaceIndex: request.spaceIndex,
                        displayFrame: request.displayFrame,
                        outputSize: request.outputSize,
                        includeUnmanagedOnScreenWindows: true,
                        knownYabaiWindowIDs: request.knownYabaiWindowIDs,
                        windows: request.windows + unmanagedWindows
                    )
                }

                var requestedWindows: [CGWindowID: CaptureWindow] = [:]
                var captureSizes: [CGWindowID: CGSize] = [:]
                for request in effectiveRequests {
                    let scaleX = request.outputSize.width / request.displayFrame.width
                    let scaleY = request.outputSize.height / request.displayFrame.height
                    for window in request.windows {
                        requestedWindows[window.windowID] = window
                        captureSizes[window.windowID] = CGSize(
                            width: max(1, window.frame.width * scaleX),
                            height: max(1, window.frame.height * scaleY)
                        )
                    }
                }

                let targets = requestedWindows.keys.sorted().compactMap { windowID -> WindowTarget? in
                    guard let window = shareableWindows[windowID],
                          let outputSize = captureSizes[windowID] else {
                        return nil
                    }
                    return WindowTarget(
                        windowID: windowID,
                        window: window,
                        outputSize: outputSize
                    )
                }
                let windowImages = await Self.captureWindows(targets)

                var captures: [Int: CGImage] = [:]
                for request in effectiveRequests {
                    if let image = Self.composite(
                        request: request,
                        windowImages: windowImages
                    ) {
                        captures[request.spaceIndex] = image
                    }
                }
                let images = captures.mapValues {
                    NSImage(
                        cgImage: $0,
                        size: NSSize(width: $0.width, height: $0.height)
                    )
                }

                let applied = await MainActor.run {
                    queue.sync {
                        guard job.generation == refreshGeneration else { return false }
                        lastCompletedRequests = job.requests
                        lastCompletedAt = ProcessInfo.processInfo.systemUptime
                        ThumbnailStore.shared.replace(with: images)
                        return true
                    }
                }
                if applied {
                    NSLog(
                        "spacemap/ThumbnailCache: refreshed \(captures.count) spaces " +
                        "from \(windowImages.count)/\(requestedWindows.count) windows"
                    )
                }
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
        spaceIndices: Set<Int>? = nil,
        thumbnailPixelSize: CGSize = defaultThumbnailPixelSize
    ) -> [CaptureRequest] {
        let knownYabaiWindowIDs = Set(
            state.windows.map { CGWindowID(truncatingIfNeeded: $0.id) }
        )
        return state.spaces.sorted { $0.index < $1.index }.compactMap { space in
            guard spaceIndices?.contains(space.index) ?? true else { return nil }
            let displayFrame = state.displayBounds(forSpace: space.index)
            guard displayFrame.width > 0, displayFrame.height > 0 else { return nil }

            let windows = state.windows(forSpace: space.index)
                .filter {
                    $0.shouldDisplay(
                        showExtraWindows: state.config.showExtraWindows,
                        ownerIsRegularApplication: IconCache.shared.isRegularApplication(
                            processIdentifier: $0.pid
                        )
                    )
                }
                .map {
                    CaptureWindow(
                        windowID: CGWindowID(truncatingIfNeeded: $0.id),
                        frame: $0.cgFrame
                    )
                }
            return CaptureRequest(
                spaceIndex: space.index,
                displayFrame: displayFrame,
                outputSize: aspectFillSize(
                    source: displayFrame.size,
                    target: thumbnailPixelSize
                ),
                includeUnmanagedOnScreenWindows:
                    space.isVisible == true ||
                    (space.isVisible == nil && space.hasFocus),
                knownYabaiWindowIDs: knownYabaiWindowIDs,
                windows: windows
            )
        }
    }

    static func shouldIncludeUnmanagedWindow(
        windowID: CGWindowID,
        isOnScreen: Bool,
        windowLayer: Int,
        ownerPID: pid_t?,
        bundleIdentifier: String?,
        frame: CGRect,
        displayFrame: CGRect,
        knownYabaiWindowIDs: Set<CGWindowID>,
        currentPID: pid_t
    ) -> Bool {
        guard isOnScreen, windowLayer >= 0,
              let ownerPID, ownerPID != currentPID,
              !knownYabaiWindowIDs.contains(windowID),
              frame.width >= 16, frame.height >= 16,
              frame.intersects(displayFrame) else {
            return false
        }
        if let bundleIdentifier,
           excludedUnmanagedBundleIDs.contains(bundleIdentifier) {
            return false
        }
        return true
    }

    static func aspectFillSize(source: CGSize, target: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0,
              target.width > 0, target.height > 0 else {
            return .zero
        }
        let scale = max(target.width / source.width, target.height / source.height)
        return CGSize(
            width: (source.width * scale).rounded(.up),
            height: (source.height * scale).rounded(.up)
        )
    }

    @MainActor
    func clear() {
        queue.sync {
            refreshGeneration += 1
            pendingRefresh = nil
            lastCompletedRequests = nil
            lastCompletedAt = 0
        }
        ThumbnailStore.shared.removeAll()
    }

    static func composite(
        request: CaptureRequest,
        windowImages: [CGWindowID: CGImage]
    ) -> CGImage? {
        let width = Int(request.outputSize.width.rounded(.up))
        let height = Int(request.outputSize.height.rounded(.up))
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
        let scaleX = request.outputSize.width / request.displayFrame.width
        let scaleY = request.outputSize.height / request.displayFrame.height
        for window in request.windows {
            guard let image = windowImages[window.windowID] else { continue }
            let relativeX = window.frame.minX - request.displayFrame.minX
            let relativeTop = window.frame.minY - request.displayFrame.minY
            let destination = CGRect(
                x: relativeX * scaleX,
                y: request.outputSize.height -
                    (relativeTop + window.frame.height) * scaleY,
                width: window.frame.width * scaleX,
                height: window.frame.height * scaleY
            )
            context.draw(image, in: destination)
        }
        return context.makeImage()
    }

    private static func captureWindows(
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
