import XCTest
import AppKit
import CoreGraphics
import CoreText
@testable import spacemap


/// Shared fixtures for the glyph strip tests.
class GlyphStripTestCase: XCTestCase {

    func state(
        spaces: [YabaiSpace],
        windows: [YabaiWindow],
        maxSpaces: Int = 16,
        focusedIndex: Int? = nil
    ) -> GridState {
        var config = SpacemapConfig.default
        config.maxSpaces = maxSpaces
        return GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: focusedIndex
        )
    }

    func space(index: Int, display: Int = 1, type: String? = "bsp") -> YabaiSpace {
        var space = YabaiSpace(id: index, index: index, display: display, hasFocus: false, isVisible: true, label: nil)
        space.type = type
        return space
    }

    func window(_ id: Int, _ app: String, x: CGFloat = 0, space: Int = 1) -> YabaiWindow {
        var window = YabaiWindow(
            id: id, app: app, space: space,
            frame: .init(x: x, y: 0, w: 10, h: 10),
            isHidden: false, isMinimized: false, subLayer: "normal"
        )
        window.role = "AXWindow"
        window.subrole = "AXStandardWindow"
        window.isRootWindow = true
        return window
    }

    /// Three windows from two apps: Safari, Safari, Terminal.
    var mixedWindows: [YabaiWindow] {
        [window(1, "Safari", x: 0), window(2, "Safari", x: 100), window(3, "Terminal", x: 200)]
    }

    func singleSegment(_ options: GlyphStrip.Options, windows: [YabaiWindow]) -> GlyphStrip.Segment {
        GlyphStrip.segments(
            for: state(spaces: [space(index: 1)], windows: windows, maxSpaces: 1),
            options: options
        )[0]
    }

    let row = CGRect(x: 0, y: 1085, width: 1728, height: 32)
    let leftArea = CGRect(x: 0, y: 1085, width: 720, height: 32)
    let rightArea = CGRect(x: 1008, y: 1085, width: 720, height: 32)

    func placed(
        width: CGFloat,
        position: GlyphStripPosition,
        margin: CGFloat = 6,
        notched: Bool = true,
        xFraction: Double = 0.5,
        yFraction: Double = 0.5
    ) -> CGRect {
        GlyphStrip.frame(
            contentSize: CGSize(width: width, height: row.height),
            menuBarRow: row,
            leftNotchArea: notched ? leftArea : nil,
            rightNotchArea: notched ? rightArea : nil,
            position: position,
            margin: margin,
            xFraction: xFraction,
            yFraction: yFraction
        )
    }

    func styles(
        for segments: [GlyphStrip.Segment],
        focused: Int?,
        strip: GlyphStripConfig = .default
    ) -> [[GlyphStrip.RunStyle]] {
        segments.map { segment in
            let isCurrent = segment.spaceIndex != nil && segment.spaceIndex == focused
            return segment.runs.map { run in
                GlyphStrip.style(for: run, isCurrent: isCurrent, strip: strip)
            }
        }
    }

    /// One horizontal render: exact slot frames and run frames, plus the
    /// colour policy the paint path resolves from the same segments.

    let stripBounds = CGRect(x: 0, y: 0, width: 400, height: 30)

    var insetHeight: CGFloat { stripBounds.height - GlyphStrip.backdropVerticalInset * 2 }

    func styleStrip(highlight: Bool) -> GlyphStripConfig {
        var strip = GlyphStripConfig.default
        strip.highlightCurrentSpace = highlight
        return strip
    }

    func decodeGlyphStrip(_ toml: String) -> GlyphStripConfig? {
        // `TOMLParser.parse` already normalizes and decodes.
        return (try? TOMLParser.parse(toml))?.config.glyphStrip
    }
}
