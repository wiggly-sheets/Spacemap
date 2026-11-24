import Foundation
import AppKit
import Carbon
import Combine
import CoreGraphics
import ScreenCaptureKit

@available(macOS 14.0, *)

extension ThumbnailCache {
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
}
