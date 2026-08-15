import AppKit

@available(macOS 14.0, *)
final class ThumbnailCacheService {

    private let thumbnailCache = ThumbnailCache()

    func captureRequests(
        for state: GridState,
        spaceIndices: Set<Int>,
        thumbnailPixelSize: CGSize
    ) -> [ThumbnailCache.CaptureRequest] {
        ThumbnailRequestBuilder.captureRequests(
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
