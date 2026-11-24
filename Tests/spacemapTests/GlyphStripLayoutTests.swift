import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


final class GlyphStripLayoutTests: GlyphStripTestCase {

    // MARK: - Vertical layout


    func testOnlyChangedSegmentsAnimate() {
        let a = GlyphStrip.Segment(spaceIndex: 1, runs: [.index("1"), .app("Safari")])
        let b = GlyphStrip.Segment(spaceIndex: 2, runs: [.index("2")])
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: nil, current: [a, b]),
            []
        )
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [a, b]),
            []
        )
        let moved = GlyphStrip.Segment(spaceIndex: 2, runs: [.index("1"), .app("Safari")])
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [moved, b]),
            [0]
        )
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [a]),
            [0]
        )
        let iconAdded = GlyphStrip.Segment(spaceIndex: 2, runs: [.index("2"), .app("Safari")])
        XCTAssertEqual(
            GlyphStrip.changedSegments(previous: [a, b], current: [a, iconAdded]),
            [1],
            "a changed second segment must animate even when the first is identical"
        )
    }

    // MARK: - Render layout

    func testHorizontalLayoutPinsSlotRunFramesAndStyles() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A"), .overflow(2)]),
            .init(spaceIndex: 2, runs: [.index("2"), .placeholder])
        ]
        let slots = [
            CGRect(x: 10, y: 0, width: 50, height: 24),
            CGRect(x: 60, y: 0, width: 40, height: 24)
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: slots,
                advances: [[8, 10, 6], [8, 5]],
                gaps: [[0, 3, 3], [0, 6]],
                placement: .inline(inset: 2)
            )
        )

        XCTAssertEqual(layout.slots, slots)
        XCTAssertEqual(layout.runs.map { $0.map(\.frame) }, [
            [
                CGRect(x: 12, y: 0, width: 8, height: 24),
                CGRect(x: 23, y: 0, width: 10, height: 24),
                CGRect(x: 36, y: 0, width: 6, height: 24)
            ],
            [
                CGRect(x: 62, y: 0, width: 8, height: 24),
                CGRect(x: 76, y: 0, width: 5, height: 24)
            ]
        ])
        let policy = styles(for: segments, focused: 1)
        XCTAssertEqual(policy[0].map(\.colorName), ["focused", "focused", "focused"])
        XCTAssertEqual(policy[1].map(\.colorName), ["text", "text"])
        XCTAssertEqual(policy[1].map(\.alpha), [1, 1])
    }

    /// Vertical inline layout centres the segment's single line in its slot.
    func testVerticalLayoutCentresTheLineInItsSlot() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A")])
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: [CGRect(x: 0, y: 0, width: 60, height: 30)],
                advances: [[8, 10]],
                gaps: [[0, 3]],
                placement: .centered
            )
        )

        XCTAssertEqual(layout.runs[0].map(\.frame), [
            CGRect(x: 19.5, y: 0, width: 8, height: 30),
            CGRect(x: 30.5, y: 0, width: 10, height: 30)
        ])
    }

    /// Stacked vertical layout puts one run per line and centres each by its
    /// ink centre, falling back to the advance box for nil centres.
    func testStackedLayoutCentresEachRunOnItsLine() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A")])
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: [CGRect(x: 0, y: 0, width: 40, height: 50)],
                advances: [[10, 12]],
                gaps: [[0, 0]],
                placement: .stacked,
                lines: [[
                    CGRect(x: 0, y: 40, width: 40, height: 10),
                    CGRect(x: 0, y: 20, width: 40, height: 10)
                ]],
                inkCenters: [[nil, 15]]
            )
        )

        XCTAssertEqual(layout.runs[0].map(\.frame), [
            CGRect(x: 15, y: 40, width: 10, height: 10),
            CGRect(x: 15, y: 20, width: 12, height: 10)
        ])
    }

    func testLayoutHitTestsNameTheSegmentAndRunUnderThePoint() {
        let segments: [GlyphStrip.Segment] = [
            .init(spaceIndex: 1, runs: [.index("1"), .app("A"), .overflow(2)]),
            .init(spaceIndex: 2, runs: [.index("2"), .placeholder])
        ]
        let layout = GlyphStrip.layout(
            segments: segments,
            state: nil,
            options: GlyphStrip.Options(.default),
            input: GlyphStrip.LayoutInput(
                slots: [
                    CGRect(x: 10, y: 0, width: 50, height: 24),
                    CGRect(x: 60, y: 0, width: 40, height: 24)
                ],
                advances: [[8, 10, 6], [8, 5]],
                gaps: [[0, 3, 3], [0, 6]],
                placement: .inline(inset: 2)
            )
        )

        XCTAssertEqual(layout.segment(at: CGPoint(x: 12, y: 10)), 0)
        XCTAssertEqual(layout.segment(at: CGPoint(x: 59, y: 10)), 0)
        XCTAssertEqual(layout.segment(at: CGPoint(x: 60, y: 10)), 1)
        XCTAssertNil(layout.segment(at: CGPoint(x: 5, y: 10)))

        XCTAssertEqual(layout.run(at: CGPoint(x: 12, y: 10))?.segment, 0)
        XCTAssertEqual(layout.run(at: CGPoint(x: 12, y: 10))?.run, 0)
        XCTAssertEqual(layout.run(at: CGPoint(x: 23, y: 10), in: 0), 1)
        XCTAssertEqual(layout.run(at: CGPoint(x: 76, y: 10), in: 1), 1)
        XCTAssertNil(layout.run(at: CGPoint(x: 21, y: 10), in: 0), "the gap between two runs is not a run")
        XCTAssertNil(layout.run(at: CGPoint(x: 5, y: 10), in: 0))
    }

    /// Drag payloads must follow the same dedupe and icon cap as the runs.
    func testLayoutMapsWindowsFromSegmentOptions() {
        var deduped = GlyphStrip.Options(.default)
        deduped.dedupeAppsPerSpace = true
        deduped.maxIconsPerSpace = 0
        var capped = GlyphStrip.Options(.default)
        capped.dedupeAppsPerSpace = false
        capped.maxIconsPerSpace = 1
        let gridState = state(spaces: [space(index: 1)], windows: mixedWindows, maxSpaces: 1)

        func layout(for options: GlyphStrip.Options) -> GlyphStrip.SegmentLayout {
            let segment = singleSegment(options, windows: mixedWindows)
            return GlyphStrip.layout(
                segments: [segment],
                state: gridState,
                options: options,
                input: GlyphStrip.LayoutInput(
                    slots: [CGRect(x: 0, y: 0, width: 40, height: 20)],
                    advances: [Array(repeating: 5, count: segment.runs.count)],
                    gaps: [Array(repeating: 0, count: segment.runs.count)],
                    placement: .inline(inset: 0)
                )
            )
        }

        // Dedupe: one Safari icon carries every Safari window.
        let dedupedLayout = layout(for: deduped)
        XCTAssertEqual(dedupedLayout.runs[0].count, 3)
        XCTAssertTrue(dedupedLayout.runs[0][0].windows.isEmpty, "the number run carries no windows")
        XCTAssertEqual(dedupedLayout.runs[0][1].windows.map(\.id), [1, 2])
        XCTAssertEqual(dedupedLayout.runs[0][2].windows.map(\.id), [3])

        // Cap: the kept icon carries its window, the overflow indicator none.
        let cappedLayout = layout(for: capped)
        XCTAssertEqual(cappedLayout.runs[0].count, 3)
        XCTAssertEqual(cappedLayout.runs[0][1].windows.map(\.id), [1])
        XCTAssertTrue(cappedLayout.runs[0][2].windows.isEmpty)
    }

    func testVerticalSlotsStackFromTheTopInSpaceOrder() {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 120)
        let slots = GlyphStrip.verticalSlots(heights: [50, 30, 40], in: bounds)

        XCTAssertEqual(slots.map(\.height), [50, 30, 40])
        XCTAssertEqual(slots[0].maxY, bounds.maxY, "first space owns the top slot")
        XCTAssertEqual(slots[0].minY, slots[1].maxY)
        XCTAssertEqual(slots[1].minY, slots[2].maxY)
        XCTAssertEqual(slots[2].minY, bounds.minY)
        XCTAssertTrue(slots.allSatisfy { $0.width == bounds.width && $0.minX == bounds.minX })
    }

    func testAutoResizeMaxLengthDefaultsOffAndDecodes() {
        var strip = GlyphStripConfig.default
        XCTAssertEqual(strip.autoResizeMaxLength, 0)

        strip.autoResizeMaxLength = 6000
        XCTAssertEqual(strip.clamped().autoResizeMaxLength, 4000)
        strip.autoResizeMaxLength = -10
        XCTAssertEqual(strip.clamped().autoResizeMaxLength, 0)

        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nautoResizeMaxLength = 420")?.autoResizeMaxLength, 420)
    }

    func testVerticalColumnSlotsWrapInsteadOfOverflowing() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let slots = GlyphStrip.verticalColumnSlots(
            heights: [20, 20, 20],
            in: bounds,
            available: 50,
            columnGap: 8
        )
        XCTAssertEqual(GlyphStrip.verticalColumnCount(totalHeight: 60, available: 50), 2)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots[0].maxY, 50)
        XCTAssertEqual(slots[1].maxY, 30)
        XCTAssertEqual(slots[2].maxY, 50)
        XCTAssertGreaterThan(slots[2].minX, slots[0].minX)
        XCTAssertEqual(slots[0].width, 46)
    }

    func testVerticalColumnCountStaysOneWhenItFits() {
        XCTAssertEqual(GlyphStrip.verticalColumnCount(totalHeight: 40, available: 50), 1)
        XCTAssertEqual(GlyphStrip.verticalColumnCount(totalHeight: 50, available: 50), 1)
    }

    func testStackedLinesFillTheSlotTopDown() {
        let slot = CGRect(x: 4, y: 10, width: 40, height: 96)
        let lines = GlyphStrip.stackedLines(
            count: 3,
            lineHeight: 30,
            indexGap: 4,
            iconGap: 2,
            in: slot
        )

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].maxY, slot.maxY)
        XCTAssertEqual(lines[1].maxY, lines[0].minY - 4, "index padding separates the number line")
        XCTAssertEqual(lines[2].maxY, lines[1].minY - 2, "icon spacing separates icon lines")
        XCTAssertEqual(lines[2].minY, slot.minY)
        XCTAssertTrue(lines.allSatisfy { $0.width == slot.width && $0.minX == slot.minX })
    }

    func testVerticalLayoutDefaultsToInlineAndDecodesBothModes() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.verticalLayout, .inline)
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nverticalLayout = \"stacked\"")?.verticalLayout,
            .stacked
        )
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\nverticalLayout = \"nonsense\"")?.verticalLayout,
            .inline
        )
    }

    func testLayoutSuffixFiltersEachSpaceType() {
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "bsp"), "b")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "bsp", showBSP: false), "")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "stack", showStack: false), "")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "float", showFloat: false), "")
        XCTAssertEqual(GlyphStrip.layoutSuffix(forSpaceType: "float", showStack: false), "f")

        var strip = GlyphStripConfig.default
        XCTAssertTrue(strip.showBSPLayoutBadge)
        strip.showBSPLayoutBadge = false
        strip.verticalPadding = 99
        XCTAssertFalse(GlyphStrip.Options(strip.clamped()).showBSPLayoutBadge)
        XCTAssertEqual(strip.clamped().verticalPadding, 40)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nverticalPadding = 12")?.verticalPadding, 12)
    }

    func testHideInFullscreenDefaultsOffAndDecodes() {
        XCTAssertEqual(GlyphStripConfig.default.hideInFullscreen, false)
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nhideInFullscreen = true")?.hideInFullscreen, true)
    }

    func testPaddingLocksByDefaultAndDecodesDisplayMode() {
        let defaults = GlyphStripConfig.default
        XCTAssertTrue(defaults.lockPadding)
        XCTAssertEqual(defaults.resolvedHorizontalPadding, 4)
        XCTAssertEqual(defaults.resolvedVerticalPadding, 4)

        var unlocked = defaults
        unlocked.lockPadding = false
        unlocked.horizontalPadding = 12
        unlocked.verticalPadding = 2
        XCTAssertEqual(unlocked.resolvedHorizontalPadding, 12)
        XCTAssertEqual(unlocked.resolvedVerticalPadding, 2)

        let decoded = decodeGlyphStrip("""
        [glyphStrip]
        displayMode = "menuBarItem"
        padding = 9
        lockPadding = false
        horizontalPadding = 7
        """)
        XCTAssertEqual(decoded?.displayMode, .menuBarItem)
        XCTAssertEqual(decoded?.resolvedHorizontalPadding, 7)
        XCTAssertEqual(decoded?.padding, 9)
    }

    func testOrientationDefaultsToHorizontalAndDecodesBothDirections() {
        XCTAssertEqual(decodeGlyphStrip("[glyphStrip]\nenabled = true")?.orientation, .horizontal)
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\norientation = \"vertical\"")?.orientation,
            .vertical
        )
        XCTAssertEqual(
            decodeGlyphStrip("[glyphStrip]\norientation = \"sideways\"")?.orientation,
            .horizontal
        )
    }

    func testDragThresholdSeparatesClickFromDrag() {
        XCTAssertFalse(GlyphStrip.exceedsDragThreshold(CGVector(dx: 3.9, dy: 0)))
        XCTAssertFalse(GlyphStrip.exceedsDragThreshold(CGVector(dx: 0, dy: -3.9)))
        XCTAssertTrue(GlyphStrip.exceedsDragThreshold(CGVector(dx: 4, dy: 0)))
        XCTAssertTrue(GlyphStrip.exceedsDragThreshold(CGVector(dx: -4, dy: 4)))
    }

    func testDragOnlyDropsOnAnotherSpace() {
        XCTAssertTrue(GlyphStrip.dragResolvesToDrop(hudTarget: 3, targetSpace: nil, sourceSpace: 2))
        XCTAssertTrue(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: 3, sourceSpace: 2))
        XCTAssertFalse(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: 2, sourceSpace: 2))
        XCTAssertFalse(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: nil, sourceSpace: 2))
        XCTAssertFalse(GlyphStrip.dragResolvesToDrop(hudTarget: nil, targetSpace: 3, sourceSpace: nil))
    }

    func testTallContentIsClampedToTheRowHeight() {
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 200, height: 900),
            menuBarRow: row,
            leftNotchArea: leftArea,
            rightNotchArea: rightArea,
            position: .leftOfNotch,
            margin: 6
        )
        XCTAssertEqual(frame.height, row.height)
        XCTAssertEqual(frame.midY, row.midY, accuracy: 0.001)
    }

    /// Geometry captured from this machine with /tmp/notchprobe: a 14" MacBook
    /// Pro at 2x reporting a 1710x1112 frame, a 37.5pt safe-area top inset and
    /// a notch occupying x 751...959. The strip used to be placed at x=751 with
    /// the notch edge as its LEFT anchor, which put its whole body inside the
    /// camera housing. This asserts what the old code got wrong.
    func testRealNotchDisplayKeepsTheStripOutOfTheCameraHousing() {
        let realRow = CGRect(x: 0, y: 1074.5, width: 1710, height: 37.5)
        let realLeft = CGRect(x: 0, y: 1074.5, width: 751, height: 37.5)
        let realRight = CGRect(x: 959, y: 1074.5, width: 751, height: 37.5)
        let notch = CGRect(x: realLeft.maxX, y: 1074.5, width: realRight.minX - realLeft.maxX, height: 37.5)
        // The widest strip the live app actually produced was 220.6pt.
        let width: CGFloat = 220.627453125

        let left = GlyphStrip.frame(
            contentSize: CGSize(width: width, height: 37.5),
            menuBarRow: realRow,
            leftNotchArea: realLeft,
            rightNotchArea: realRight,
            position: .leftOfNotch,
            margin: 0
        )
        XCTAssertFalse(left.intersects(notch), "leftOfNotch landed in the notch: \(left)")
        XCTAssertEqual(left.maxX, 751, "should sit flush against the notch's left edge")
        XCTAssertTrue(realRow.contains(left))

        let right = GlyphStrip.frame(
            contentSize: CGSize(width: width, height: 37.5),
            menuBarRow: realRow,
            leftNotchArea: realLeft,
            rightNotchArea: realRight,
            position: .rightOfNotch,
            margin: 0
        )
        XCTAssertFalse(right.intersects(notch), "rightOfNotch landed in the notch: \(right)")
        XCTAssertEqual(right.minX, 959, "should sit flush against the notch's right edge")
        XCTAssertTrue(realRow.contains(right))
    }

    /// The notch cutout on this display is only 208pt wide, so `.center` cannot
    /// hold a full strip. Documented ceiling rather than a silent clamp.
    func testCenterOnTheRealDisplayIsWiderThanTheNotchGap() {
        let realRow = CGRect(x: 0, y: 1074.5, width: 1710, height: 37.5)
        let realLeft = CGRect(x: 0, y: 1074.5, width: 751, height: 37.5)
        let realRight = CGRect(x: 959, y: 1074.5, width: 751, height: 37.5)
        let notchGap = realRight.minX - realLeft.maxX
        XCTAssertEqual(notchGap, 208)
        // `.center` centres on the gap midpoint, which is under the camera.
        let frame = GlyphStrip.frame(
            contentSize: CGSize(width: 220.627453125, height: 37.5),
            menuBarRow: realRow,
            leftNotchArea: realLeft,
            rightNotchArea: realRight,
            position: .center,
            margin: 0
        )
        XCTAssertEqual(frame.midX, 855, accuracy: 0.001)
        XCTAssertGreaterThan(
            frame.width, notchGap,
            "known limitation: a full strip cannot fit the notch gap, so .center is partly occluded"
        )
    }
}
