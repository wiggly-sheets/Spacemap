import AppKit
import Foundation

extension GlyphStrip {
    // MARK: - Render layout

    /// Segments whose painted content changed. A first build animates nothing;
    /// a count change animates the visible set because indices shifted.
    static func changedSegments(
        previous: [Segment]?,
        current: [Segment]
    ) -> [Int] {
        guard let previous else { return [] }
        guard previous.count == current.count else { return Array(current.indices) }
        return current.indices.filter { previous[$0] != current[$0] }
    }

    /// One slot per segment across `content`, each `widths[index]` wide and as
    /// tall as the content box. Used by both surfaces: the panel insets its
    /// content box, the status item centres the same slots in its button.
    static func horizontalSlots(widths: [CGFloat], in content: CGRect) -> [CGRect] {
        var x = content.minX
        return widths.map { width in
            let slot = CGRect(x: x, y: content.minY, width: width, height: content.height)
            x += width
            return slot
        }
    }

    /// Where runs sit inside their slot for one render.
    enum RunPlacement: Equatable {
        /// Left to right inside the slot, `inset` points from its leading edge.
        case inline(inset: CGFloat)
        /// Every run of a segment on one line, centred on the slot.
        case centered
        /// One run per line from `LayoutInput.lines`.
        case stacked
    }

    /// What only AppKit can measure for one render; `layout(...)` derives the
    /// frames and window mapping from it.
    struct LayoutInput {
        /// Hit slot per segment, in the drawing layer's coordinates.
        var slots: [CGRect]
        /// Measured advance of every run, parallel to the segments and their runs.
        var advances: [[CGFloat]]
        /// Gap before each run, parallel to `advances`.
        var gaps: [[CGFloat]]
        var placement: RunPlacement = .inline(inset: 0)
        /// One line per run for `.stacked`, parallel to `advances`.
        var lines: [[CGRect]] = []
        /// Ink-centre x per run for `.stacked`; nil centres the advance box.
        var inkCenters: [[CGFloat?]] = []
    }

    /// One painted run: its frame and the windows a drag from it carries.
    /// Every draw and hit test reads these instead of re-deriving them.
    struct RunLayout: Equatable {
        let frame: CGRect
        let windows: [YabaiWindow]
    }

    /// The complete description of one render: the hit slot of every segment
    /// and the painted frame and window mapping of every run.
    struct SegmentLayout: Equatable {
        let slots: [CGRect]
        let runs: [[RunLayout]]

        /// Slot of `segment`, or nil when the layout has no such segment.
        func slot(_ segment: Int) -> CGRect? {
            slots.indices.contains(segment) ? slots[segment] : nil
        }

        /// Segment directly under `point`.
        func segment(at point: CGPoint) -> Int? {
            slots.firstIndex { $0.contains(point) }
        }

        /// Run directly under `point`, scanning every segment.
        func run(at point: CGPoint) -> (segment: Int, run: Int)? {
            for (segment, frames) in runs.enumerated() {
                if let run = frames.firstIndex(where: { $0.frame.contains(point) }) {
                    return (segment, run)
                }
            }
            return nil
        }

        /// Run directly under `point` within `segment`; nil outside every run.
        func run(at point: CGPoint, in segment: Int) -> Int? {
            guard runs.indices.contains(segment) else { return nil }
            return runs[segment].firstIndex { $0.frame.contains(point) }
        }
    }

    /// Assembles one render. `input.advances`, `input.gaps`, and the
    /// per-segment `input.lines` are all parallel to `segments` and their runs.
    static func layout(
        segments: [Segment],
        state: GridState?,
        options: Options,
        input: LayoutInput
    ) -> SegmentLayout {
        let runs = segments.enumerated().map { offset, segment -> [RunLayout] in
            // No slot means no paint and no hit area, matching a view that has
            // not been laid out yet.
            guard input.slots.indices.contains(offset) else { return [] }
            let slot = input.slots[offset]
            let frames = runFrames(
                in: slot,
                advances: input.advances.indices.contains(offset) ? input.advances[offset] : [],
                gaps: input.gaps.indices.contains(offset) ? input.gaps[offset] : [],
                placement: input.placement,
                lines: input.lines.indices.contains(offset) ? input.lines[offset] : [],
                inkCenters: input.inkCenters.indices.contains(offset) ? input.inkCenters[offset] : []
            )
            let windows = runWindows(for: segment, in: state, options: options)
            return frames.indices.map { index in
                RunLayout(
                    frame: frames[index],
                    windows: windows.indices.contains(index) ? windows[index] : []
                )
            }
        }
        return SegmentLayout(slots: input.slots, runs: runs)
    }

    /// Painted frame of every run in `slot`.
    static func runFrames(
        in slot: CGRect,
        advances: [CGFloat],
        gaps: [CGFloat],
        placement: RunPlacement,
        lines: [CGRect],
        inkCenters: [CGFloat?]
    ) -> [CGRect] {
        if case .stacked = placement {
            guard lines.count == advances.count else { return [] }
            return advances.indices.map { index in
                let line = lines[index]
                let inkCenter = inkCenters.indices.contains(index) ? inkCenters[index] : nil
                let x = inkCenter ?? line.midX - advances[index] / 2
                return CGRect(x: x, y: line.minY, width: advances[index], height: line.height)
            }
        }
        var x: CGFloat
        switch placement {
        case .inline(let inset):
            x = slot.minX + inset
        case .centered, .stacked:
            let inner = advances.indices.reduce(CGFloat(0)) { total, index in
                // Placement skips the gap before run 0, so the centring sum
                // must skip it too.
                let gap = index > 0 && gaps.indices.contains(index) ? gaps[index] : 0
                return total + advances[index] + gap
            }
            x = slot.midX - inner / 2
        }
        return advances.indices.map { index in
            if index > 0, gaps.indices.contains(index) { x += gaps[index] }
            let frame = CGRect(x: x, y: slot.minY, width: advances[index], height: slot.height)
            x += advances[index]
            return frame
        }
    }

    /// Windows behind each run of `segment`: an icon run carries its windows,
    /// every other run none. Dedupe and the icon cap come from `options`, so the
    /// mapping cannot drift from the runs `segments(for:options:font:)` built.
    static func runWindows(
        for segment: Segment,
        in state: GridState?,
        options: Options
    ) -> [[YabaiWindow]] {
        guard let spaceIndex = segment.spaceIndex, let state else {
            return Array(repeating: [], count: segment.runs.count)
        }
        let all = windows(forSpace: spaceIndex, in: state)
        let shown = windowsToShow(all, dedupe: options.dedupeAppsPerSpace)
        let limit = options.maxIconsPerSpace == 0 ? shown.count : min(options.maxIconsPerSpace, shown.count)
        let icons = Array(shown.prefix(limit))
        var iconOffset = 0
        return segment.runs.map { run in
            switch run {
            case .app, .nativeIcon:
                guard icons.indices.contains(iconOffset) else {
                    iconOffset += 1
                    return []
                }
                let icon = icons[iconOffset]
                iconOffset += 1
                return draggedWindows(
                    for: icon,
                    allWindows: all,
                    dedupe: options.dedupeAppsPerSpace
                )
            default:
                return []
            }
        }
    }

    static let placeholderGlyph = "—"

    /// Layout suffix: bsp draws bare, float and stack get a letter.
    static func layoutSuffix(
        forSpaceType type: String?,
        showBSP: Bool = true,
        showStack: Bool = true,
        showFloat: Bool = true
    ) -> String {
        switch type {
        case "float": return showFloat ? "f" : ""
        case "stack": return showStack ? "s" : ""
        case "bsp": return showBSP ? "b" : ""
        default: return ""
        }
    }

    static func segments(
        for state: GridState,
        options: Options = Options(GlyphStripConfig.default),
        font: AppGlyphFont? = nil
    ) -> [Segment] {
        // Every space from every display goes on the one bar — matching the
        // SketchyBar config this replaces, which set `ignore_association = true`
        // precisely so secondary-display spaces still rendered. Nothing here
        // filters by display.
        //
        // yabai space indexes are global and NOT contiguous — deleting a space
        // leaves a hole — so iterate the spaces yabai actually reported instead
        // of a 1...maxSpaces range, which used to emit a ghost segment for every
        // index past the last real one. Order is by global index, not renumbered
        // per display.
        let spaces = state.spaces.sorted { $0.index < $1.index }
        var segments: [Segment] = []
        var previousSpace: YabaiSpace?

        for space in spaces {
            // Separators compare consecutive RENDERED spaces, never
            // `index + 1`, so a gap in the index sequence cannot shift them.
            if options.showDisplaySeparators,
               let previousSpace,
               space.display != previousSpace.display {
                segments.append(Segment(spaceIndex: nil, runs: [.separator]))
            }
            previousSpace = space
            segments.append(
                Segment(
                    // The real yabai index, so focus/destroy target the space the
                    // user clicked rather than the segment's position in the strip.
                    spaceIndex: space.index,
                    runs: spaceRuns(
                        index: space.index,
                        layoutType: space.type,
                        windows: windows(forSpace: space.index, in: state),
                        options: options,
                        font: font
                    )
                )
            )
        }

        if options.showAddSpaceButton {
            segments.append(Segment(spaceIndex: nil, runs: [.add]))
        }
        return segments
    }

    /// Extra horizontal advance to insert *before* each run, same length as
    /// `runs` so the panel can use one array for both measuring and drawing.
    ///
    /// Two independent gaps, keyed on position within the segment because the
    /// space index and the initials fallback are both `.index` runs:
    /// - `indexPadding` between the leading index run and the first app run or placeholder.
    /// - `iconSpacing` between every later pair of app runs and before `+N` overflow.
    ///
    /// Separators and the add button are their own segments, so neither picks up a gap.
    static func interRunGaps(
        for runs: [Run],
        iconSpacing: CGFloat,
        indexPadding: CGFloat
    ) -> [CGFloat] {
        runs.indices.map { offset in
            guard offset > 0 else { return 0 }
            switch runs[offset] {
            case .separator, .add:
                return 0
            case .placeholder:
                return indexPadding
            case .overflow:
                return iconSpacing
            case .app, .index, .nativeIcon:
                // Only the leading index run gets padded away from. A segment that starts
                // with an icon has no index, so its first gap is plain iconSpacing.
                if offset == 1, case .index = runs[0] { return indexPadding }
                return iconSpacing
            }
        }
    }

    static func windows(forSpace index: Int, in state: GridState) -> [YabaiWindow] {
        let visible = state.windows(forSpace: index).filter {
            $0.shouldDisplay(showExtraWindows: state.config.showExtraWindows)
        }
        return YabaiWindow.inReadingOrder(visible)
    }

    /// Windows reduced to one entry per app when deduping is on, keeping the
    /// first (leftmost) window of each app in reading order.
    static func windowsToShow(_ windows: [YabaiWindow], dedupe: Bool) -> [YabaiWindow] {
        guard dedupe else { return windows }
        var seen = Set<String>()
        return windows.filter { seen.insert($0.app).inserted }
    }

    /// Windows a dragged icon represents. Dedupe means one icon per app, so
    /// the drag carries every window of that app; otherwise it carries the
    /// single window the icon was built from.
    static func draggedWindows(
        for icon: YabaiWindow,
        allWindows: [YabaiWindow],
        dedupe: Bool
    ) -> [YabaiWindow] {
        dedupe ? allWindows.filter { $0.app == icon.app } : [icon]
    }

    /// Maps a configured click action onto a concrete command. Returns nil when
    /// the action is disabled or cannot apply to the clicked segment.
    static func command(
        for action: GlyphStripAction,
        spaceIndex: Int?,
        focusedSpaceIndex: Int?
    ) -> Command? {
        switch action {
        case .none:
            return nil
        case .focusSpace:
            guard let spaceIndex else { return nil }
            return .focusSpace(spaceIndex)
        case .destroySpace:
            guard let spaceIndex else { return nil }
            return .destroySpace(spaceIndex)
        case .moveWindowHere:
            guard let spaceIndex else { return nil }
            return .moveFocusedWindowToSpace(spaceIndex)
        case .mergeWindows:
            guard let spaceIndex, let focusedSpaceIndex, spaceIndex != focusedSpaceIndex else { return nil }
            return .mergeIntoSpace(spaceIndex)
        case .toggleFullscreen:
            return .toggleFullscreen
        case .floatWindow:
            return .floatWindow
        case .balanceWindows:
            return .balanceWindows
        }
    }

    /// Longest name a strip label shows. Longer names truncate with `…` so one
    /// user-typed name cannot stretch the whole strip.
    static let spaceNameCharacterLimit = 12

    /// Name to show for one space, or nil when the style hides names, the
    /// space has no entry, or the entry is blank after trimming. The painted
    /// label and the VoiceOver label both read names through here so they
    /// agree on which names exist.
    static func spaceName(for spaceIndex: Int, options: Options) -> String? {
        guard options.spaceLabelStyle != .numbers,
              let name = options.spaceNames[spaceIndex]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Label text for one space's leading run. `.numbers` is exactly today's
    /// index+suffix. `.names` shows the profile name, or the number when the
    /// space has no name. `.both` prefixes the name with the number.
    static func spaceLabelText(
        index: Int,
        suffix: String,
        options: Options
    ) -> String {
        let number = "\(index)\(suffix)"
        guard let name = spaceName(for: index, options: options) else {
            return number
        }
        let trimmed = name.count > spaceNameCharacterLimit
            ? String(name.prefix(spaceNameCharacterLimit)) + "…"
            : name
        return options.spaceLabelStyle == .both ? "\(number) \(trimmed)" : trimmed
    }

    static func spaceRuns(
        index: Int,
        layoutType: String?,
        windows: [YabaiWindow],
        options: Options,
        font: AppGlyphFont?
    ) -> [Run] {
        var runs: [Run] = []
        if options.showSpaceNumbers {
            let suffix = options.showLayoutSuffix
                ? layoutSuffix(
                    forSpaceType: layoutType,
                    showBSP: options.showBSPLayoutBadge,
                    showStack: options.showStackLayoutBadge,
                    showFloat: options.showFloatLayoutBadge
                )
                : ""
            runs.append(.index(spaceLabelText(index: index, suffix: suffix, options: options)))
        }
        if !options.showAppIcons { return runs }

        let shown = windowsToShow(windows, dedupe: options.dedupeAppsPerSpace)
        if shown.isEmpty {
            if options.showPlaceholders { runs.append(.placeholder) }
            return runs
        }

        // maxIconsPerSpace == 0 means unlimited.
        let limit = options.maxIconsPerSpace == 0 ? shown.count : min(options.maxIconsPerSpace, shown.count)
        for window in shown.prefix(limit) {
            if options.iconSource == .nativeIcons {
                // Native first, sbar glyph then initials as the painted
                // fallback. The panel resolves the image at draw time.
                let fallback: String
                if let glyph = font?.glyph(forApp: window.app), !glyph.isEmpty {
                    fallback = glyph
                } else {
                    fallback = AppGlyphFont.initials(forApp: window.app)
                }
                runs.append(.nativeIcon(
                    app: window.app,
                    pid: window.pid.flatMap { Int32(exactly: $0) },
                    glyph: fallback
                ))
            } else if let glyph = font?.glyph(forApp: window.app), !glyph.isEmpty {
                runs.append(.app(glyph))
            } else {
                // No glyph font or no ligature: use the app's real Finder
                // icon. Initials remain the text fallback if the image cannot
                // resolve, so the segment never becomes a hole.
                runs.append(.nativeIcon(
                    app: window.app,
                    pid: window.pid.flatMap { Int32(exactly: $0) },
                    glyph: AppGlyphFont.initials(forApp: window.app)
                ))
            }
        }
        let overflow = shown.count - limit
        if overflow > 0 { runs.append(.overflow(overflow)) }
        return runs
    }
}
