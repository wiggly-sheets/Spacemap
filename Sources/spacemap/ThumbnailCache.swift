import Foundation
import AppKit
import Carbon
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
        /// Draw the desktop wallpaper beneath this space's windows.
        var includeWallpaper: Bool = true
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
    /// Reuse a completed capture set for this long. A show after a short
    /// hide reuses pixels instead of recapturing the whole display.
    static let maxStaleness: TimeInterval = 30
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
    private var activeGeneration: Int?
    private var activeRequests: [CaptureRequest]?
    private var activeTask: Task<Void, Never>?
    private var pendingRefresh: RefreshJob?
    private var lastCompletedRequests: [CaptureRequest]?
    private var lastCompletedAt: TimeInterval = 0
    private let queue = DispatchQueue(label: "com.spacemap.thumbnailcache")

    /// Pure staleness/dedupe decision so tests can pin the policy without
    /// invoking ScreenCaptureKit.
    static func shouldSkipRefresh(
        requests: [CaptureRequest],
        lastCompleted: [CaptureRequest]?,
        lastCompletedAt: TimeInterval,
        now: TimeInterval,
        force: Bool,
        maxStaleness: TimeInterval = ThumbnailCache.maxStaleness
    ) -> Bool {
        guard !force, requests == lastCompleted else { return false }
        return now - lastCompletedAt < maxStaleness
    }

    /// An in-flight or queued identical job normally absorbs a repeat call.
    /// `force` must bypass that dedupe so callers can demand fresh pixels.
    static func shouldDedupeActiveJob(
        requests: [CaptureRequest],
        pending: [CaptureRequest]?,
        active: [CaptureRequest]?,
        force: Bool
    ) -> Bool {
        guard !force else { return false }
        return requests == pending || (requests == active && pending == nil)
    }

    func refreshSpaces(_ requests: [CaptureRequest], force: Bool = false) {
        let jobToStart: RefreshJob? = queue.sync {
            let now = ProcessInfo.processInfo.systemUptime
            if Self.shouldSkipRefresh(
                requests: requests,
                lastCompleted: lastCompletedRequests,
                lastCompletedAt: lastCompletedAt,
                now: now,
                force: force
            ) {
                return nil
            }
            if Self.shouldDedupeActiveJob(
                requests: requests,
                pending: pendingRefresh?.requests,
                active: activeRequests,
                force: force
            ) {
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
            activeGeneration = job.generation
            return job
        }
        guard let jobToStart else { return }
        run(jobToStart)
    }

    private func run(_ job: RefreshJob) {
        // Secure input gate before any fetch: never expand unmanaged windows,
        // and force on-screen-only so the fetch itself stays narrow.
        let secureInput = IsSecureEventInputEnabled()
        // Off-space windows are not on screen, but their pixels are what the
        // thumbnails show. Querying only on-screen windows silently dropped
        // most of a strip that previews every space. Secure input still gates
        // unmanaged-window expansion below.
        let onScreenOnly = false
        let task = Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: onScreenOnly
                )
                guard !Task.isCancelled else {
                    finishRefresh(generation: job.generation)
                    return
                }
                var shareableWindows: [CGWindowID: SCWindow] = [:]
                for window in content.windows {
                    shareableWindows[window.windowID] = window
                }

                let knownYabaiWindowIDs = Set(
                    job.requests.flatMap(\.knownYabaiWindowIDs)
                )
                let currentPID = getpid()
                let effectiveRequests = job.requests.map { request in
                    guard request.includeUnmanagedOnScreenWindows, !secureInput else { return request }
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
                async let windowImagesTask = Self.captureWindows(targets)
                let windowImages = await windowImagesTask
                let desktopImages: [CGRect: CGImage]
                if effectiveRequests.contains(where: \.includeWallpaper) {
                    desktopImages = await Self.captureDesktops(
                        requests: effectiveRequests,
                        displays: content.displays,
                        windows: content.windows
                    )
                } else {
                    desktopImages = [:]
                }

                var captures: [Int: CGImage] = [:]
                for request in effectiveRequests {
                    if let image = Self.composite(
                        request: request,
                        windowImages: windowImages,
                        desktopImage: request.includeWallpaper ? desktopImages[request.displayFrame] : nil
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
            finishRefresh(generation: job.generation)
        }
        // Only publish the handle if this job still owns the active slot;
        // cancel() may have run between Task creation and this queue hop.
        let ownsSlot = queue.sync { () -> Bool in
            guard activeGeneration == job.generation else { return false }
            activeTask = task
            return true
        }
        if !ownsSlot {
            task.cancel()
        }
    }

    private func finishRefresh(generation: Int) {
        let nextJob: RefreshJob? = queue.sync {
            // A cancel() or a newer job owns the slot now; do not resurrect
            // stale state or start a pending job that was cleared.
            guard activeGeneration == generation else { return nil }
            activeRequests = nil
            activeGeneration = nil
            activeTask = nil
            guard let pendingRefresh else { return nil }
            self.pendingRefresh = nil
            activeRequests = pendingRefresh.requests
            activeGeneration = pendingRefresh.generation
            return pendingRefresh
        }
        if let nextJob {
            run(nextJob)
        }
    }

    /// Drop in-flight captures (hide) without clearing already-rendered
    /// thumbnails. Any late completion is ignored by generation checks.
    func cancel() {
        queue.sync {
            refreshGeneration += 1
            pendingRefresh = nil
            activeRequests = nil
            activeGeneration = nil
            activeTask?.cancel()
            activeTask = nil
        }
    }

    var currentGeneration: Int { queue.sync { refreshGeneration } }
    var hasActiveRefresh: Bool { queue.sync { activeRequests != nil } }
    var hasPendingRefresh: Bool { queue.sync { pendingRefresh != nil } }

    static func captureRequests(
        for state: GridState,
        spaceIndices: Set<Int>? = nil,
        thumbnailPixelSize: CGSize = defaultThumbnailPixelSize
    ) -> [CaptureRequest] {
        ThumbnailRequestBuilder.captureRequests(
            for: state,
            spaceIndices: spaceIndices,
            thumbnailPixelSize: thumbnailPixelSize
        )
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
        ThumbnailRequestBuilder.shouldIncludeUnmanagedWindow(
            windowID: windowID,
            isOnScreen: isOnScreen,
            windowLayer: windowLayer,
            ownerPID: ownerPID,
            bundleIdentifier: bundleIdentifier,
            frame: frame,
            displayFrame: displayFrame,
            knownYabaiWindowIDs: knownYabaiWindowIDs,
            currentPID: currentPID
        )
    }

    static func aspectFillSize(source: CGSize, target: CGSize) -> CGSize {
        ThumbnailCompositor.aspectFillSize(source: source, target: target)
    }

    /// Synchronous when called on main (the normal HUD path) so a same-turn
    /// `refreshSpaces` cannot be wiped by a deferred clear. Off-main callers
    /// still get a main hop.
    func clear() {
        cancel()
        queue.sync {
            lastCompletedRequests = nil
            lastCompletedAt = 0
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                ThumbnailStore.shared.removeAll()
            }
        } else {
            Task { @MainActor in
                ThumbnailStore.shared.removeAll()
            }
        }
    }

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

    /// One wallpaper-only image per display, drawn beneath the window images.
    /// Every window on the display is excluded, so the capture is desktop
    /// background, not the current space.
    private static func captureDesktops(
        requests: [CaptureRequest],
        displays: [SCDisplay],
        windows: [SCWindow]
    ) async -> [CGRect: CGImage] {
        var seen = Set<CGRect>()
        let jobs: [(CGRect, SCDisplay, CGSize)] = requests.compactMap { request in
            guard seen.insert(request.displayFrame).inserted,
                  let display = displays.first(where: { $0.frame == request.displayFrame }) else {
                return nil
            }
            return (request.displayFrame, display, request.outputSize)
        }
        return await withTaskGroup(
            of: (CGRect, CGImage?).self,
            returning: [CGRect: CGImage].self
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
            var results: [CGRect: CGImage] = [:]
            for await (frame, image) in group {
                if let image { results[frame] = image }
            }
            return results
        }
    }

    private static func captureDesktop(
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
