import AppKit
import Foundation

extension GlyphStrip {
    // MARK: - Placement

    struct Backdrop: Equatable {
        let rect: CGRect
        /// Already capped to half the rect's height, so a big configured
        /// radius renders as a pill and 0 renders as a square bar.
        let cornerRadius: CGFloat
    }

    /// Placement of the strip inside the menu bar row.
    ///
    /// - Parameters:
    ///   - menuBarRow: the full top row of the target display.
    ///   - leftNotchArea: `NSScreen.auxiliaryTopLeftArea`, or `nil` on a display
    ///     with no notch (AppKit reports an empty rect there).
    ///   - rightNotchArea: `NSScreen.auxiliaryTopRightArea`, likewise `nil`.
    ///   - margin: gap between the strip and the notch edge, in points.
    ///   - screenFrame: the display's whole frame for `.custom`, which may sit
    ///     anywhere on screen. Anchored positions ignore it.
    ///   - xFraction: free-placement X as a fraction of the screen's spare
    ///     width, only used by `.custom`. 0 is the left edge, 1 the right edge;
    ///     the same fraction `HUDPosition.custom` stores for the HUD.
    ///   - yFraction: free-placement Y as the same kind of fraction. AppKit
    ///     grows upward, so 0 is the bottom edge and 1 the top edge.
    ///
    /// Anchored positions centre vertically in the menu bar row. `.custom`
    /// clamps to the whole screen instead, so a dragged strip can reach any
    /// row.
    ///
    /// Overflow: content wider than the row shrinks to the row width,
    /// left-aligned at `menuBarRow.minX`. Clamping x alone would hang the
    /// excess off the right edge.
    static func frame(
        contentSize: CGSize,
        menuBarRow: CGRect,
        screenFrame: CGRect? = nil,
        leftNotchArea: CGRect?,
        rightNotchArea: CGRect?,
        position: GlyphStripPosition,
        margin: CGFloat,
        xFraction: Double = 0.5,
        yFraction: Double = 0.5
    ) -> CGRect {
        // `.custom` may sit anywhere on the display, so it uses the whole
        // screen and measures in fractions of it. Anchored positions stay in
        // the menu bar row.
        let area = position == .custom ? (screenFrame ?? menuBarRow) : menuBarRow
        let height = position == .custom ? min(contentSize.height, area.height) : min(contentSize.height, menuBarRow.height)
        let width = min(max(contentSize.width, 0), area.width)
        let x: CGFloat
        switch position {
        case .leftOfNotch:
            if let left = leftNotchArea, !left.isEmpty {
                // `leftNotchArea` is the unobscured strip to the LEFT of the
                // notch, so its maxX is the notch's left edge. The strip belongs
                // to that side: its right edge goes there, otherwise it renders
                // inside the camera housing.
                x = left.maxX - margin - width
            } else {
                x = menuBarRow.minX + margin
            }
        case .rightOfNotch:
            if let right = rightNotchArea, !right.isEmpty {
                x = right.minX + margin
            } else {
                x = menuBarRow.maxX - margin - width
            }
        case .center:
            let area = notchArea(left: leftNotchArea, right: rightNotchArea, menuBarRow: menuBarRow)
            x = area.midX - width / 2
        case .custom:
            let spare = max(area.width - width, 0)
            x = area.minX + spare * CGFloat(xFraction)
        }
        // Never let the strip hang off the side of its area.
        let clampedX = min(max(x, area.minX), max(area.minX, area.maxX - width))
        let y: CGFloat
        if position == .custom {
            let spare = max(area.height - height, 0)
            let desired = area.minY + spare * CGFloat(yFraction)
            y = min(max(desired, area.minY), max(area.minY, area.maxY - height))
        } else {
            // Vertical centring inside the row.
            y = menuBarRow.minY + (menuBarRow.height - height) / 2
        }
        return CGRect(x: clampedX, y: y, width: width, height: height)
    }

    /// True when the panel must sit above the menu bar window. Anchored
    /// placements live in the row; a custom strip dragged into the row must
    /// also outrank the menu bar or clicks never reach it.
    static func usesMenuBarLevel(
        position: GlyphStripPosition,
        frame: CGRect,
        menuBarRow: CGRect
    ) -> Bool {
        position != .custom || frame.intersects(menuBarRow)
    }

    /// Vertical placement rects, laid out top-down inside `bounds` from the
    /// height of each segment. The first height owns the top slot, so a
    /// vertical strip reads in space order from the top edge.
    static func verticalSlots(heights: [CGFloat], in bounds: CGRect) -> [CGRect] {
        var top = bounds.maxY
        return heights.map { height in
            let slot = CGRect(x: bounds.minX, y: top - height, width: bounds.width, height: height)
            top -= height
            return slot
        }
    }

    /// Column count needed when a vertical strip is taller than `available`.
    static func verticalColumnCount(totalHeight: CGFloat, available: CGFloat) -> Int {
        guard totalHeight > available, available > 0 else { return 1 }
        return Int(ceil(totalHeight / available))
    }

    /// Slots for a vertical strip that may wrap into several columns. Each
    /// column fills top-down; a segment that would pass the bottom starts the
    /// next column, so the strip grows sideways instead of off screen.
    static func verticalColumnSlots(
        heights: [CGFloat],
        in bounds: CGRect,
        available: CGFloat,
        columnGap: CGFloat
    ) -> [CGRect] {
        guard !heights.isEmpty, available > 0 else { return [] }
        let columns = verticalColumnCount(totalHeight: heights.reduce(0, +), available: available)
        let width = max((bounds.width - columnGap * CGFloat(columns - 1)) / CGFloat(columns), 1)
        var column = 0
        var top = bounds.maxY
        var slots: [CGRect] = []
        for height in heights {
            if top - height < bounds.minY - 0.5, column + 1 < columns {
                column += 1
                top = bounds.maxY
            }
            let x = bounds.minX + CGFloat(column) * (width + columnGap)
            slots.append(CGRect(x: x, y: top - height, width: width, height: height))
            top -= height
        }
        return slots
    }

    /// One rect per stacked line, filled from the top of `slot` downward.
    /// `indexGap` separates the number line from the first icon line;
    /// `iconGap` separates icon lines from each other.
    static func stackedLines(
        count: Int,
        lineHeight: CGFloat,
        indexGap: CGFloat,
        iconGap: CGFloat,
        in slot: CGRect
    ) -> [CGRect] {
        guard count > 0, lineHeight > 0 else { return [] }
        var top = slot.maxY
        return (0..<count).map { index in
            if index > 0 {
                top -= index == 1 ? indexGap : iconGap
            }
            let rect = CGRect(x: slot.minX, y: top - lineHeight, width: slot.width, height: lineHeight)
            top = rect.minY
            return rect
        }
    }

    /// The `.custom` fractions that reproduce `frame` inside `area` — the
    /// inverse of `frame(...)` for the geometry it was given. `area` is the
    /// menu bar row for anchored placements and the whole screen for `.custom`.
    /// Used to turn a dragged panel frame back into config keys.
    ///
    /// Nil when the strip fills the area on an axis (no spare travel), matching
    /// `HUDDisplay.normalizedPosition`: the caller keeps its stored fractions
    /// instead of dividing by zero.
    static func customFractions(for frame: CGRect, area: CGRect) -> (x: Double, y: Double)? {
        let rangeX = area.width - frame.width
        let rangeY = area.height - frame.height
        guard rangeX > 0, rangeY > 0 else { return nil }
        return (
            Double((frame.minX - area.minX) / rangeX),
            Double((frame.minY - area.minY) / rangeY)
        )
    }

    /// Pointer travel, in screen points, that separates a click from a drag.
    static let dragThreshold: CGFloat = 4

    /// True once the pointer has moved `threshold` points from the press — the
    /// strip should follow the pointer instead of firing the press's click.
    static func exceedsDragThreshold(_ delta: CGVector, threshold: CGFloat = dragThreshold) -> Bool {
        max(abs(delta.dx), abs(delta.dy)) >= threshold
    }

    /// A drag only performs a drop when it reaches another space. Ending on the
    /// pressed space or outside every target is a click, so a slight pointer
    /// wobble cannot eat the click.
    static func dragResolvesToDrop(hudTarget: Int?, targetSpace: Int?, sourceSpace: Int?) -> Bool {
        if hudTarget != nil { return true }
        guard let targetSpace, let sourceSpace else { return false }
        return targetSpace != sourceSpace
    }

    /// True when the display has a camera housing: AppKit reports both
    /// unobscured top strips as non-empty rects.
    static func hasNotch(leftNotchArea: CGRect?, rightNotchArea: CGRect?) -> Bool {
        guard let left = leftNotchArea, !left.isEmpty,
              let right = rightNotchArea, !right.isEmpty else {
            return false
        }
        return true
    }

    /// The gap between the two notch areas, or the whole row when the display
    /// has no notch.
    static func notchArea(left: CGRect?, right: CGRect?, menuBarRow: CGRect) -> CGRect {
        guard let left, !left.isEmpty, let right, !right.isEmpty else { return menuBarRow }
        return CGRect(
            x: left.maxX,
            y: menuBarRow.minY,
            width: max(right.minX - left.maxX, 0),
            height: menuBarRow.height
        )
    }
}
