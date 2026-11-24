import AppKit
import ApplicationServices
import CoreText

extension GlyphStripPanelController {
    /// Re-applies the background choice without touching content: used when a
    /// system setting changes which glass implementation is allowed.
    func relayoutBackground() {
        panel?.contentView?.needsLayout = true
        panel?.contentView?.layout()
        glyphs?.needsDisplay = true
    }
    // MARK: - State

    func update(config: SpacemapConfig) {
        // The updater drops the cache itself on install, but a version written
        // by another process only shows up here. Unrelated settings saves must
        // not force the next refresh back to disk.
        if config.appFont.installedVersion != self.config.appFont.installedVersion {
            AppGlyphFont.invalidateCache()
        }
        self.config = config
        cachedLayout = nil
        cachedStatusLayout = nil
        // The coordinator cancels any in-flight fetch when its config changes.
        // If that cancellation completes without running our completion (or an
        // older coordinator build did), the latch would stay set and every
        // later refresh would collapse into a follow-up that never runs.
        refreshInFlight = false
        inFlightGeneration = 0
        needsFollowupRefresh = false
        coordinator.updateConfig(config)
        // Settings changes can add or edit a `.smthemes` file; only re-read the
        // directory when an entry actually changed. Theme-name-only changes
        // need no reload (the file is already parsed), and this runs on every
        // save.
        themeStore.reloadIfChanged()
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByFullscreen, !hiddenByMissionControl else {
            hide()
            return
        }
        // Material/shape/opacity switches keep the same frame, so without a
        // layout pass the old glass/fill would stay on screen. Invalidate both
        // layers here; refresh() then recomputes content.
        panel?.contentView?.needsLayout = true
        panel?.contentView?.layout()
        glyphs?.needsDisplay = true
        refresh()
    }

    /// Simulates a fetch cancellation that left the serialization latch set, so
    /// `update(config:)` can be tested for clearing it.
    func markRefreshWedgedForTesting() {
        refreshInFlight = true
        needsFollowupRefresh = true
    }

    /// Event-driven only — every yabai signal lands here via the shared refresh
    /// path. No polling timer. Debounced (~32ms): rapid space-change bursts
    /// coalesce to one pass. Font IO + segment model build run on the work
    /// queue; only the attributed-run apply + frame runs on main.
    func refresh() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByMissionControl else { return }
        refreshGeneration += 1
        pendingRefresh?.cancel()
        // Leading edge: react to the first event immediately. Bursts within the
        // coalesce window collapse to one trailing pass instead of adding
        // 32ms to every single signal.
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastRefreshAt
        if elapsed >= Self.refreshCoalesceInterval, !refreshInFlight {
            lastRefreshAt = now
            pendingRefresh = nil
            runRefresh()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.lastRefreshAt = ProcessInfo.processInfo.systemUptime
            self?.runRefresh()
        }
        pendingRefresh = work
        let delay = max(0, Self.refreshCoalesceInterval - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func runRefresh() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, !hiddenByMissionControl else { return }
        // Re-entrant guard: a refresh landing mid-pass (e.g. an icon resolve
        // landing one) collapses to a single bounded follow-up.
        guard !refreshInFlight else {
            needsFollowupRefresh = true
            return
        }
        refreshInFlight = true
        let generation = refreshGeneration
        inFlightGeneration = generation
        // Single config snapshot for the whole render pass.
        let strip = config.glyphStrip
        coordinator.refresh { [weak self] in
            guard let self else { return }
            guard generation == self.refreshGeneration,
                  let state = self.coordinator.state else {
                // Stale reply or no state: drop it, never paint over newer state.
                self.finishRefresh(generation: generation)
                return
            }
            // Auto naming reads the space windows, so options wait for the state.
            let options = Self.segmentOptions(for: self.config, state: state)
            let focused = state.focusedIndex
            if let font = self.glyphFont {
                // The face was parsed once per process. Reuse it instead of
                // hopping to the work queue and back on every movement.
                self.applyRefresh(
                    state: state,
                    options: options,
                    strip: strip,
                    generation: generation,
                    font: font,
                    focused: focused
                )
                return
            }
            Self.stripWorkQueue.async { [weak self] in
                // First pass only: disk IO + parse off-main.
                let loaded = AppGlyphFont.load()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard generation == self.refreshGeneration else {
                        self.finishRefresh(generation: generation)
                        return
                    }
                    let font = self.effectiveFont(from: loaded)
                    self.glyphFont = font
                    self.applyRefresh(
                        state: state,
                        options: options,
                        strip: strip,
                        generation: generation,
                        font: font,
                        focused: focused
                    )
                }
            }
        }
    }

    func applyRefresh(
        state: GridState,
        options: GlyphStrip.Options,
        strip: GlyphStripConfig,
        generation: Int,
        font: AppGlyphFont?,
        focused: Int?
    ) {
        guard generation == refreshGeneration else {
            finishRefresh(generation: generation)
            return
        }
        // A stopped daemon reports no spaces. Painting that would replace a
        // live strip with a lone add button and drop the focus highlight until
        // the next space change, so keep the last painted frame instead. Still
        // present it: a strip hidden by hotkey or fullscreen and re-shown during
        // downtime has kept segments but no frame on screen.
        if state.spaces.isEmpty, !segments.isEmpty {
            present()
            finishRefresh(generation: generation)
            return
        }
        let resolved = GlyphStrip.segments(
            for: state,
            options: options,
            font: font
        )
        let previousFocused = focusedSpaceIndex
        segments = resolved
        focusedSpaceIndex = focused
        // Watchdog: a non-empty state must never paint an empty strip from a
        // dropped pass — fall back to initials runs.
        if resolved.isEmpty && !state.spaces.isEmpty {
            NSLog("spacemap/GlyphStrip: empty segments for non-empty state; keeping last good frame")
            finishRefresh(generation: generation)
            return
        }
        // Re-check immediately before painting: the strip may have been
        // disabled or hidden by hotkey while the state work was in flight.
        guard generation == refreshGeneration,
              config.glyphStrip.enabled,
              !hiddenByHotkey,
              !hiddenByMissionControl else {
            finishRefresh(generation: generation)
            return
        }
        rebuildRuns(strip: strip, options: options)
        fitToMaximumLength(strip: strip, options: options)
        present()
        if previousFocused != focused, let glyphs {
            NSAccessibility.post(element: glyphs, notification: .valueChanged)
        }
        preloadNativeIcons()
        finishRefresh(generation: generation)
    }

    /// Clears the in-flight flag and runs one collapsed follow-up when a
    /// refresh landed mid-pass. Stale generations never trigger follow-ups.
    func finishRefresh(generation: Int) {
        guard generation == inFlightGeneration else { return }
        refreshInFlight = false
        inFlightGeneration = 0
        if needsFollowupRefresh {
            needsFollowupRefresh = false
            refresh()
        }
    }

    /// Off-main miss resolution for native icons: cache hits paint this pass,
    /// misses repaint via one follow-up refresh once the image lands.
    /// In-flight names are skipped so an unresolvable app cannot loop.
    func preloadNativeIcons() {
        guard config.glyphStrip.iconSource == .nativeIcons else { return }
        for (segmentOffset, segment) in segments.enumerated() {
            for (runOffset, run) in segment.runs.enumerated() {
                guard case .nativeIcon(let app, _, _) = run,
                      nativeIcons.indices.contains(segmentOffset),
                      nativeIcons[segmentOffset].indices.contains(runOffset),
                      nativeIcons[segmentOffset][runOffset] == nil,
                      !nativeResolveInFlight.contains(app) else { continue }
                nativeResolveInFlight.insert(app)
                IconCache.shared.resolveInBackground(appName: app) { [weak self] image in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.nativeResolveInFlight.remove(app)
                        // Nil (no bundle anywhere) must not re-trigger: the
                        // fallback glyph is the final answer for this launch.
                        if image != nil { self.refresh() }
                    }
                }
            }
        }
    }

    /// Fit the strip to `autoResizeMaxLength` along its layout axis. Sizes grow
    /// when there is spare room and shrink when over, so the setting behaves
    /// like a target length instead of a shrink-only cap. Spacing scales with
    /// the glyphs so fixed gaps cannot leave the strip stuck over the target.
    func fitToMaximumLength(strip: GlyphStripConfig, options: GlyphStrip.Options) {
        let maximum = CGFloat(strip.autoResizeMaxLength)
        guard maximum > 0 else { return }
        var scale: CGFloat = 1
        var fitted = strip
        let baseIcon = CGFloat(strip.iconSize)
        let baseIndex = CGFloat(strip.indexSize)
        let baseIconSpacing = CGFloat(strip.iconSpacing)
        let baseIndexPadding = CGFloat(strip.indexPadding)
        let baseHoverPadding = CGFloat(strip.hoverPadding)
        for _ in 0..<6 {
            let length = stripLength
            guard length > 0 else { return }
            let wanted = min(max(scale * maximum / length, 0.5), 3)
            guard abs(wanted - scale) > 0.01 else { break }
            scale = wanted
            fitted.iconSize = max(baseIcon * scale, 8)
            fitted.indexSize = max(baseIndex * scale, 8)
            fitted.iconSpacing = baseIconSpacing * scale
            fitted.indexPadding = baseIndexPadding * scale
            fitted.hoverPadding = baseHoverPadding * scale
            rebuildRuns(strip: fitted, options: options)
        }
    }

    /// Length along the layout axis, including the strip's own padding.
    var stripLength: CGFloat {
        let glyphs = isVerticalLayout
            ? verticalTotalHeight
            : segmentWidths.reduce(0, +)
        let padding = isVerticalLayout
            ? CGFloat(config.glyphStrip.resolvedVerticalPadding) * 2
            : CGFloat(config.glyphStrip.resolvedHorizontalPadding) * 2
        return glyphs + padding
    }

    func rebuildRuns(strip: GlyphStripConfig, options: GlyphStrip.Options) {
        let theme = themeStore.named(effectiveThemeName)
        renderOptions = options
        cachedLayout = nil
        cachedStatusLayout = nil

        // Memory-only hits; misses keep nil and paint the fallback glyph
        // until preloadNativeIcons lands them. Never blocks on icon(forFile:).
        nativeIcons = segments.map { segment in
            segment.runs.map { run in
                guard case .nativeIcon(let app, _, _) = run else { return nil }
                return IconCache.shared.cachedIcon(for: app)
            }
        }
        attributedRuns = segments.map { segment in
            let isCurrent = segment.spaceIndex != nil && segment.spaceIndex == focusedSpaceIndex
            return segment.runs.map { run in
                Self.attributedRun(
                    for: run,
                    strip: strip,
                    theme: theme,
                    style: GlyphStrip.style(for: run, isCurrent: isCurrent, strip: strip),
                    face: glyphFont
                )
            }
        }
        // One array drives both the width below and the draw loop, so the frame
        // can never disagree with what is painted.
        runGaps = segments.map {
            GlyphStrip.interRunGaps(
                for: $0.runs,
                iconSpacing: CGFloat(strip.iconSpacing),
                indexPadding: CGFloat(strip.indexPadding)
            )
        }
        runAdvances = attributedRuns.map { $0.map { $0.size().width } }
        let changed = GlyphStrip.changedSegments(previous: lastPaintedSegments, current: segments)
        lastPaintedSegments = segments
        if !changed.isEmpty {
            glyphs?.animateContentChange(segments: changed)
            statusView?.animateContentChange(segments: changed)
        }
        segmentWidths = runAdvances.indices.map { offset in
            let advances = runAdvances[offset]
            let gaps = runGaps[offset]
            // Resolved native icons fill their fallback's advance: the same
            // cell an `.app` run measures at this iconSize, side bearings
            // included. Hit and miss share one width, so resolving an icon
            // never reflows the strip.
            let glyphs = advances.indices.reduce(CGFloat(0)) { total, index in
                total + advances[index] + gaps[index]
            }
            return glyphs + Self.segmentPadding * 2
        }
    }

    /// The one place app config becomes segment options, so a new strip key is
    /// wired once for every render path.
    static func segmentOptions(for config: SpacemapConfig, state: GridState) -> GlyphStrip.Options {
        GlyphStrip.Options(config.glyphStrip, spaceNames: state.resolvedSpaceNames)
    }
}
