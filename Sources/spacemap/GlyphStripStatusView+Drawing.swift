import AppKit
import ApplicationServices
import CoreText

extension GlyphStripStatusView {
    func animateContentChange(segments: [Int]) {
        guard !segments.isEmpty else { return }
        contentAnimationSegments = segments
        contentAnimationStart = CACurrentMediaTime()
        contentAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - (self.contentAnimationStart ?? 0)
            self.needsDisplay = true
            if elapsed >= 0.24 {
                timer.invalidate()
                self.contentAnimationTimer = nil
                self.contentAnimationStart = nil
                self.contentAnimationSegments = []
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        contentAnimationTimer = timer
        needsDisplay = true
    }

    func contentScale(for segment: Int) -> CGFloat {
        guard let start = contentAnimationStart,
              let order = contentAnimationSegments.firstIndex(of: segment) else { return 1 }
        let elapsed = CACurrentMediaTime() - start - Double(order) * 0.015
        let progress = min(max(elapsed / 0.18, 0), 1)
        return 0.9 + 0.1 * (1 - pow(1 - progress, 3))
    }

    /// All painting happens in this child so the view itself can stay empty.
    override func draw(_ dirtyRect: NSRect) {}

    func drawContent(_ dirtyRect: NSRect) {
        guard let controller, !controller.segments.isEmpty else { return }
        if controller.usesSolid, let backdrop = controller.backdrop(in: backdropArea) {
            GlyphStrip.fill(backdrop, color: controller.solidColor, opacity: controller.backgroundOpacity)
            if controller.borderEnabled {
                GlyphStrip.stroke(backdrop, color: controller.strokeColor, opacity: 1)
            }
        } else if controller.usesGlass, let backdrop = controller.backdrop(in: backdropArea) {
            // A status item cannot host a backdrop blur: both
            // `NSGlassEffectView` and behind-window vibrancy flash black when
            // spaces change. Menu-bar mode is solid or transparent only, so
            // glass renders as its solid fill; the floating strip keeps glass.
            GlyphStrip.fill(backdrop, color: controller.solidColor, opacity: controller.backgroundOpacity)
            if controller.borderEnabled {
                GlyphStrip.stroke(backdrop, color: controller.strokeColor, opacity: 1)
            }
        } else if controller.borderEnabled, let border = controller.borderBackdrop(in: backdropArea) {
            GlyphStrip.stroke(border, color: controller.strokeColor, opacity: 1)
        }
        let layout = self.segmentLayout
        drawHighlight(
            for: hoveredSegment.flatMap(layout.slot),
            color: controller.hoverColor,
            opacity: GlyphStrip.hoverHighlightOpacity * hoverProgress
        )
        drawHighlight(
            for: controller.dragTargetSegment.flatMap(layout.slot),
            color: NSColor.controlAccentColor,
            opacity: 0.3
        )

        for (segmentIndex, runs) in controller.attributedRuns.enumerated() {
            guard layout.runs.indices.contains(segmentIndex) else { continue }
            let hoverScale: CGFloat = segmentIndex == hoveredSegment ? 1 + 0.06 * hoverProgress : 1
            let scale = hoverScale * contentScale(for: segmentIndex)
            let context = NSGraphicsContext.current?.cgContext
            let scaled = scale != 1 && context != nil
            if scaled, let context, let slot = layout.slot(segmentIndex) {
                context.saveGState()
                context.translateBy(x: slot.midX, y: slot.midY)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -slot.midX, y: -slot.midY)
            }
            defer { if scaled { context?.restoreGState() } }
            for (runIndex, run) in runs.enumerated() {
                guard layout.runs[segmentIndex].indices.contains(runIndex) else { continue }
                let frame = layout.runs[segmentIndex][runIndex].frame
                if let image = controller.nativeIcon(segment: segmentIndex, run: runIndex) {
                    let side = frame.width
                    image.draw(
                        in: NSRect(x: frame.minX, y: (bounds.height - side) / 2, width: side, height: side),
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1
                    )
                } else {
                    let size = run.size()
                    run.draw(at: NSPoint(x: frame.minX, y: (bounds.height - size.height) / 2))
                }
            }
        }
    }

    func drawHighlight(for rect: CGRect?, color: NSColor, opacity: CGFloat) {
        guard let rect else { return }
        color.withAlphaComponent(opacity).setFill()
        // No horizontal inset: the number's ink starts at the slot edge, and
        // trimming a point left an unhovered sliver beside it.
        NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 3), xRadius: 3, yRadius: 3).fill()
    }
}
