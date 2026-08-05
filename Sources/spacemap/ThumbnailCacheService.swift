import AppKit

/// Wraps `ThumbnailCache` to remove the static shared singleton.
/// All window thumbnail capture goes through this service.
@available(macOS 14.0, *)
final class ThumbnailCacheService {

    private let thumbnailCache = ThumbnailCache()

    func captureRequests(
        for state: GridState,
        spaceIndices: Set<Int>,
        thumbnailPixelSize: CGSize
    ) -> [ThumbnailCache.CaptureRequest] {
        ThumbnailCache.captureRequests(
            for: state,
            spaceIndices: spaceIndices,
            thumbnailPixelSize: thumbnailPixelSize
        )
    }

    func refreshSpaces(_ requests: [ThumbnailCache.CaptureRequest], force: Bool = false) {
        thumbnailCache.refreshSpaces(requests, force: force)
    }

    static let maxConcurrentCaptures = ThumbnailCache.maxConcurrentCaptures
    static let defaultThumbnailPixelSize = ThumbnailCache.defaultThumbnailPixelSize
}