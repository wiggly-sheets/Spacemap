import CoreGraphics

@available(macOS 14.0, *)
enum ThumbnailCompositor {
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

    static func composite(
        request: ThumbnailCache.CaptureRequest,
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
}
