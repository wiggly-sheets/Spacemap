import AppKit
import ApplicationServices
import CoreText

extension GlyphStripPanelController {
    // MARK: - Input

    func handle(_ command: GlyphStrip.Command) {
        switch command {
        case .focusSpace(let index):
            yabaiService.focusSpaceAsync(index)
        case .destroySpace(let index):
            // No confirmation — matches the original SketchyBar behaviour.
            yabaiService.destroySpace(index)
        case .createSpace:
            yabaiService.createSpace()
        case .moveFocusedWindowToSpace(let index):
            yabaiService.moveFocusedWindow(toSpace: index)
        case .mergeIntoSpace(let index):
            guard let focused = focusedSpaceIndex, let state = coordinator.state else { return }
            let ids = GlyphStrip.windows(forSpace: index, in: state).map(\.id)
            yabaiService.moveWindows(ids, toSpace: focused)
        case .toggleFullscreen:
            yabaiService.toggleWindowFullscreen()
        case .floatWindow:
            yabaiService.toggleWindowFloat()
        case .balanceWindows:
            yabaiService.balanceWindows()
        }
    }

    /// Painted run under `point`. Nil when the point is not on a run (padding,
    /// gap, or an empty segment).
    fileprivate func runHit(at point: NSPoint) -> (segment: Int, run: Int)? {
        layout.run(at: point)
    }

    /// Space number run: the strip's first run in a numbered segment. App
    /// initials use the same `.index` case, so position matters.
    fileprivate func isSpaceNumber(segment: Int, run: Int) -> Bool {
        guard segments.indices.contains(segment) else { return false }
        let runs = segments[segment].runs
        return run == 0
            && segments[segment].spaceIndex != nil
            && renderOptions.showSpaceNumbers
            && !runs.isEmpty
            && { if case .index = runs[0] { return true } else { return false } }()
    }

    func spaceNumber(at point: NSPoint) -> Int? {
        guard let hit = runHit(at: point), isSpaceNumber(segment: hit.segment, run: hit.run) else { return nil }
        return segments[hit.segment].spaceIndex
    }

    func draggedWindows(at point: NSPoint) -> (ids: [Int], source: Int)? {
        let layout = self.layout
        guard let hit = layout.run(at: point),
              segments.indices.contains(hit.segment),
              let source = segments[hit.segment].spaceIndex else { return nil }
        let windows = layout.runs[hit.segment][hit.run].windows
        return windows.isEmpty ? nil : (windows.map(\.id), source)
    }

    /// Segment directly under the pointer. Gaps, display separators, and the
    /// add button are not drop targets, so only real spaces highlight.
    func dropSegment(at point: NSPoint) -> Int? {
        let layout = self.layout
        guard let index = layout.segment(at: point), segments.indices.contains(index) else { return nil }
        return segments[index].spaceIndex != nil ? index : nil
    }

    /// The space currently highlighted as the drop destination. Drop uses
    /// this same value so highlight and result cannot diverge. Stored at
    /// targeting time, because a refresh can reorder segment indices mid-drag.
    var dragTargetSpace: Int? { dragTargetSpaceIndex }

    func setDragTarget(_ segment: Int?) {
        let space = segment.flatMap {
            segments.indices.contains($0) ? segments[$0].spaceIndex : nil
        }
        guard dragTargetSegment != segment || dragTargetSpaceIndex != space else { return }
        dragTargetSegment = segment
        dragTargetSpaceIndex = space
        glyphs?.needsDisplay = true
        statusView?.needsDisplay = true
    }

    func performSpaceSwap(from source: Int, to target: Int) {
        // A space can disappear between drag start and drop; do not ask yabai
        // to swap an index that no longer exists.
        let live = Set(segments.compactMap(\.spaceIndex))
        guard source > 0, target > 0, source != target,
              live.contains(source), live.contains(target) else { return }
        yabaiService.swapSpaces(source, target, mode: config.spaceDropMode, focusMode: config.spaceDragFocus)
        refreshAfterDrag()
    }

    func performWindowMove(ids: [Int], to target: Int, source: Int) {
        guard target > 0 else { return }
        yabaiService.moveWindows(ids, toSpace: target, focusMode: config.windowDragFocus, sourceSpace: source)
        refreshAfterDrag()
    }

    fileprivate func refreshAfterDrag() {
        // yabai applies the change asynchronously; a single early repaint can
        // still show the old order. Repaint a few times as the swap settles.
        for delay in [0.15, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
                self?.onDropCompleted?()
            }
        }
    }

    func command(forSegment index: Int, click: GlyphStripClick) -> GlyphStrip.Command? {
        guard segments.indices.contains(index) else { return nil }
        let segment = segments[index]
        if segment.runs == [.add] { return .createSpace }
        return GlyphStrip.command(
            for: action(for: click),
            spaceIndex: segment.spaceIndex,
            focusedSpaceIndex: focusedSpaceIndex
        )
    }

    private func action(for click: GlyphStripClick) -> GlyphStripAction {
        switch click {
        case .left: return config.glyphStrip.leftClickAction
        case .right: return config.glyphStrip.rightClickAction
        case .middle: return config.glyphStrip.middleClickAction
        }
    }

    func segment(at point: NSPoint) -> Int? {
        // Full slot hits; hover highlight stays hover-sized in draw.
        layout.segment(at: point)
    }

    /// Slot of a segment in the view's own coordinates: the menu-bar row, or
    /// one stacked line per space when vertical.
    func segmentRect(_ index: Int) -> CGRect? {
        layout.slot(index)
    }

    /// The drawing layer's own bounds; it fills the panel on every material.
    var viewBounds: CGRect {
        if let glyphs, !glyphs.bounds.isEmpty { return glyphs.bounds }
        return CGRect(origin: .zero, size: panel?.frame.size ?? .zero)
    }

    /// The panel's current frame in screen coordinates, captured by the view
    /// at mouse-down as the starting point for a drag.
    var panelFrame: CGRect? { panel?.frame }

    /// The highlight drawn behind segment `index`, or `nil` when there is nothing
    /// to paint. One definition, shared by the draw loop and the hit test, so the
    /// highlight and the area that arms it cannot disagree.
    ///
    /// Sized from the segment's *content* box — its slot minus `segmentPadding`
    /// on each side — because that padding is the empty space either side of the
    /// glyphs inside the slot. Sizing from the slot instead would subtract
    /// `hoverPadding` from a width that already includes the padding, leaving the
    /// highlight narrower than the glyphs and off-centre.
    ///
    /// Clipped to the painted backdrop (or the plain bounds when no backdrop is
    /// painted), so a wide `hoverPadding` cannot push the highlight past the
    /// strip's ends.
    func hoverBackdrop(_ index: Int) -> GlyphStrip.Backdrop? {
        guard !viewBounds.isEmpty else { return nil }
        // The painted material's rect, or the plain bounds when nothing is
        // painted behind the glyphs.
        let painted: CGRect
        if let backdrop = backdrop(in: viewBounds) {
            painted = backdrop.rect
        } else {
            painted = viewBounds
        }
        return GlyphStrip.hoverFill(
            // `dy: 0` keeps the full row height visible to the run-height clamp.
            segmentRect: segmentRect(index)?.insetBy(dx: Self.segmentPadding, dy: 0),
            runHeight: runHeight(forSegment: index),
            padding: hoverPadding,
            cornerRadius: hoverCornerRadius,
            within: painted.intersection(viewBounds)
        )
    }

    func setHoveredSegment(_ index: Int?) {
        guard hoveredSegment != index else { return }
        hoveredSegment = index
        glyphs?.needsDisplay = true
    }
}
