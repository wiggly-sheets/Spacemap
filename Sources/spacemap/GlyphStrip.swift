import AppKit
import Foundation

/// Compact menu-bar strip: one segment per yabai space plus an optional `+`.
///
/// Pure model — the panel and its view live in `GlyphStripPanel.swift`.
enum GlyphStrip {

    /// What a click on a segment resolves to. `focusSpace` and `destroySpace`
    /// carry an index; the window-scoped commands do not.
    enum Command: Equatable {
        case focusSpace(Int)
        case destroySpace(Int)
        case moveFocusedWindowToSpace(Int)
        case mergeIntoSpace(Int)
        case toggleFullscreen
        case floatWindow
        case balanceWindows
        case createSpace
    }

    enum Run: Equatable {
        /// `index`, `overflow` and `separator` text use the system font; app
        /// glyphs use sketchybar-app-font.
        case index(String)
        case app(String)
        /// Native app icon: `app` (+`pid` fast path) resolves the NSImage via
        /// IconCache, `glyph` is the sbar fallback painted on a miss.
        case nativeIcon(app: String, pid: Int32?, glyph: String)
        case overflow(Int)
        case placeholder
        case separator
        case add
    }

    struct Segment: Equatable {
        /// nil for the separator and add segments, which have no space.
        let spaceIndex: Int?
        let runs: [Run]
    }

    /// VoiceOver label for one painted segment. Pure so the wording can be
    /// asserted without AppKit state; the view supplies the same segments.
    static func accessibilityLabel(
        for segment: Segment,
        focused: Bool,
        spaceName: String? = nil
    ) -> String {
        if segment.runs == [.add] {
            return NSLocalizedString("Add space", comment: "VoiceOver action for the glyph strip add button")
        }
        if segment.runs == [.separator] {
            return NSLocalizedString("Display separator", comment: "VoiceOver label for a display boundary in the glyph strip")
        }

        var parts: [String] = []
        if let index = segment.spaceIndex {
            var space = String(
                format: NSLocalizedString("Space %d", comment: "VoiceOver label for a space number"),
                index
            )
            if let spaceName, !spaceName.isEmpty {
                space += " — \(spaceName)"
            }
            parts.append(space)
        }
        let appNames = segment.runs.compactMap { run -> String? in
            switch run {
            case .app(let name): return name
            case .nativeIcon(let app, _, _): return app
            default: return nil
            }
        }
        if !appNames.isEmpty {
            parts.append(appNames.joined(separator: ", "))
        } else if segment.runs.contains(.placeholder) {
            parts.append(NSLocalizedString("Empty", comment: "VoiceOver label for an empty space"))
        }
        for run in segment.runs {
            if case .overflow(let count) = run {
                parts.append(String(
                    format: NSLocalizedString("%d more windows", comment: "VoiceOver overflow count for a space"),
                    count
                ))
            }
        }
        if focused {
            parts.append(NSLocalizedString("Current space", comment: "VoiceOver label for the focused space"))
        }
        return parts.joined(separator: ", ")
    }
}
