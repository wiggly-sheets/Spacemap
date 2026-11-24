import Foundation
import AppKit
import Carbon
import Combine
import CoreGraphics
import ScreenCaptureKit

@available(macOS 14.0, *)

extension ThumbnailCache {
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

    func run(_ job: RefreshJob) {
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
                var desktopImages: [FrameKey: CGImage]
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
                        desktopImage: request.includeWallpaper ? desktopImages[FrameKey(request.displayFrame)] : nil
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

    func finishRefresh(generation: Int) {
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
}
