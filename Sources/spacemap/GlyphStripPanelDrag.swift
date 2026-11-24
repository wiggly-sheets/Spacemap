import AppKit
import ApplicationServices
import CoreText

extension GlyphStripPanelController {
    // MARK: - Drag

    /// Live follow during a strip drag: `startFrame` is the panel frame
    /// captured at mouse-down and `delta` the pointer travel since, both in
    /// screen coordinates — the panel moves under the pointer, so window
    /// coordinates would stall after the first move.
    ///
    /// Switches the strip to `.custom` and steps the in-memory config along
    /// with the panel, so a refresh landing mid-drag recomputes the frame the
    /// drag already produced instead of snapping back to the old anchor.
    /// Fractions come from the inverse of `GlyphStrip.frame` and the frame
    /// itself comes from `applyFrame(to:)`, so the clamps apply exactly as they
    /// do on every other path.
    func dragPanel(from startFrame: CGRect, by delta: CGVector) {
        guard !isPositionLocked, config.glyphStrip.enabled, !hiddenByHotkey, let panel else { return }
        let candidate = PanelPresenter.draggedFrame(from: startFrame, by: delta)
        let screen = panelScreen() ?? targetScreen()
        let hasNotch = screen.map(Self.hasNotch) ?? true
        let identifier = screen.map(ScreenContext.displayIdentifier(for:)) ?? ""
        var strip = config.glyphStrip
        markCustomPlacement(&strip, hasNotch: hasNotch)
        if let fractions = GlyphStrip.customFractions(
            for: candidate,
            area: ScreenContext.screenFrame(on: screen)
        ) {
            strip.setCustomPlacement(
                hasNotch: hasNotch,
                x: fractions.x,
                y: fractions.y,
                screen: identifier
            )
        } else {
            strip.setCustomScreen(identifier, hasNotch: hasNotch)
        }
        config.glyphStrip = strip.clamped()
        applyFrame(to: panel, screen: screen)
    }

    /// Persists a finished drag so it survives refreshes and restarts. Same
    /// load-modify-save path `HUDDisplay.savePanelPosition` uses, so config
    /// edits made elsewhere since the last save survive too. Posts only the
    /// dedicated position notification (not `.settingsChanged`, which would
    /// drop the font cache and reload themes).
    func persistDragPosition() {
        guard config.glyphStrip.enabled, !hiddenByHotkey, let panel else { return }
        let screen = panelScreen() ?? targetScreen()
        let fractions = GlyphStrip.customFractions(
            for: panel.frame,
            area: ScreenContext.screenFrame(on: screen)
        )
        let identifier = screen.map(ScreenContext.displayIdentifier(for:)) ?? ""
        let hasNotch = screen.map(Self.hasNotch) ?? true
        ConfigStore.updateConfig { saved in
            var strip = saved.glyphStrip
            markCustomPlacement(&strip, hasNotch: hasNotch)
            if let fractions {
                strip.setCustomPlacement(
                    hasNotch: hasNotch,
                    x: fractions.x,
                    y: fractions.y,
                    screen: identifier
                )
            } else {
                strip.setCustomScreen(identifier, hasNotch: hasNotch)
            }
            saved.glyphStrip = strip.clamped()
        }
        applyFrame(to: panel, screen: screen)
        // Position-only change: notify an open Settings window so its stale
        // `glyphStrip` state cannot write the old position back on the next
        // save. Deliberately not `.settingsChanged` (that would reload themes
        // and drop the font cache).
        NotificationCenter.default.post(name: .glyphStripPositionChanged, object: nil)
    }

    /// Placement and margin for a display. A notched display uses the notch
    /// anchors; a plain display uses its own position and margin, so a notch
    /// anchor never parks the strip against a screen edge on a display with no
    /// housing to anchor to.
    private func placement(on screen: NSScreen?) -> (position: GlyphStripPosition, margin: CGFloat) {
        config.glyphStrip.placement(hasNotch: screen.map(Self.hasNotch) ?? false)
    }

    /// Placement resolved for the display the strip is on or headed to.
    var resolvedPlacement: (position: GlyphStripPosition, margin: CGFloat) {
        placement(on: panelScreen() ?? targetScreen())
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        GlyphStrip.hasNotch(
            leftNotchArea: screen.auxiliaryTopLeftArea,
            rightNotchArea: screen.auxiliaryTopRightArea
        )
    }

    /// Marks the placement custom for one screen type. The saved point stays
    /// separate: notch displays use `customX`/`customY`/`customScreen`,
    /// plain displays use the `plainCustom*` keys.
    private func markCustomPlacement(_ strip: inout GlyphStripConfig, hasNotch: Bool) {
        if hasNotch {
            strip.position = .custom
        } else {
            strip.plainPosition = .custom
        }
    }

    /// The strip follows the display that owns yabai's focused space, falling
    /// back to the display it is currently parked on, and only then to the
    /// pointer. A free-placed strip first honours the display it was dragged
    /// on, so its saved position survives monitor changes. `NSScreen.main`
    /// follows the key window, which is usually not Spacemap, so it is never
    /// the primary signal.
    func targetScreen() -> NSScreen? {
        if let focused = focusedScreen() {
            let hasNotch = Self.hasNotch(focused)
            // A free placement only claims its saved display for its own
            // screen type; a notch point must not drag a plain-focused strip
            // onto another monitor.
            if config.glyphStrip.placement(hasNotch: hasNotch).position == .custom,
               let stored = Self.storedScreen(
                   for: config.glyphStrip,
                   hasNotch: hasNotch
               ) {
                return stored
            }
            return focused
        }
        if let stored = Self.storedScreen(for: config.glyphStrip) {
            return stored
        }
        return panelScreen() ?? ScreenContext.targetScreen()
    }

    /// The display that owns yabai's focused space, or the display flagged
    /// focused. Nil before the first topology arrives.
    private func focusedScreen() -> NSScreen? {
        guard let state = coordinator.state else { return nil }
        if let focused = state.focusedIndex,
           let displayIndex = state.displayIndex(forSpace: focused),
           let display = state.displays.first(where: { $0.index == displayIndex }),
           let screen = ScreenContext.screen(containingQuartzFrame: display.frame.cgFrame) {
            return screen
        }
        if let focusedDisplay = state.displays.first(where: \.hasFocus),
           let screen = ScreenContext.screen(containingQuartzFrame: focusedDisplay.frame.cgFrame) {
            return screen
        }
        return nil
    }

    /// The display a free-placed strip was saved on, if that display is still
    /// attached. Presets and a missing display return nil so the callers below
    /// pick the target.
    /// The display a free placement was saved on for one screen type, if that
    /// display is still attached.
    static func storedScreen(
        for strip: GlyphStripConfig,
        hasNotch: Bool,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        guard strip.placement(hasNotch: hasNotch).position == .custom else { return nil }
        return ScreenContext.screen(
            matchingIdentifier: strip.customPlacement(hasNotch: hasNotch).screen,
            screens: screens
        )
    }

    /// The display a free-placed strip was saved on, preferring the notch
    /// point. Callers that know the target screen type pass `hasNotch`.
    static func storedScreen(
        for strip: GlyphStripConfig,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        storedScreen(for: strip, hasNotch: true, screens: screens)
            ?? storedScreen(for: strip, hasNotch: false, screens: screens)
    }

    /// The display the panel currently sits on, if any. Used by drags so a
    /// strip being moved does not snap back to the focused-space display.
    /// A strip straddling two displays resolves to the one holding most of it,
    /// matching how a HUD panel resolves its display.
    func panelScreen() -> NSScreen? {
        guard let panel else { return nil }
        let screens = NSScreen.screens
        guard let index = ScreenContext.largestIntersection(
            screenFrames: screens.map(\.frame),
            frame: panel.frame
        ), screens.indices.contains(index) else { return nil }
        return screens[index]
    }
}
