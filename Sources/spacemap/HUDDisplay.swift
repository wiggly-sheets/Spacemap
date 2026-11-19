import AppKit
import SwiftUI

protocol HUDDisplayDelegate: AnyObject {
    func render(state: GridState)
    func updateCellFrames(state: GridState)
    func show()
    func hide()
}

final class HUDDisplay {
    weak var delegate: HUDDisplayDelegate?

    private var panel: NSPanel?
    private var displayPanels: [Int: NSPanel] = [:]
    private var hostingView: NSHostingView<AnyView>?
    private var displayHostingViews: [Int: NSHostingView<AnyView>] = [:]
    private var currentConfig: SpacemapConfig = .default
    private(set) var hoveredCell: Int? = nil
    /// Typed-number readout channel. Separate from the rendered grid so a
    /// digit repaints the overlay only.
    private let numberState = HUDNumberState()
    private let noticeState = HUDNoticeState()
    private(set) var renderedState: GridState?
    private var yabaiService: YabaiService
    private let themeStore: ThemeStore
    /// Panel lifecycle: window construction and the non-motion ordering path.
    /// Entrance motion stays here because the frames are HUD-style policy.
    private let presenter = PanelPresenter()
    /// Shared, cheap hover channel for the rendered grid. Hover changes only
    /// mutate this observable, so SwiftUI repaints the border/background of
    /// the affected cells without icon/thumbnail work or panel resizing.
    let hoverState = HUDHoverState()
    private var showingThumbnails = false

    /// Test-visible work counters: hover must not bump these.
    private(set) var fullRenderCount = 0
    private(set) var iconPreloadCount = 0
    private(set) var thumbnailRefreshCount = 0

    var unifiedPanel: NSPanel? { panel }
    var displayPanelIndices: Set<Int> { Set(displayPanels.keys) }
    /// Test seam: when set, display matching uses these frames instead of the
    /// host's `NSScreen.screens`, so panel tests do not depend on the CI
    /// machine's monitor count.
    var screenFramesOverride: [CGRect]?
    /// Supplied by the controller: true while the user is dragging the panel.
    /// A signal-driven render mid-drag must not snap it back.
    var isPanelDragging: (() -> Bool)?
    /// Drag feedback owned by the controller: suppress auto-hide, and resolve
    /// a drop onto a space cell.
    var onDragActive: ((Bool) -> Void)?
    var onSpaceDrop: ((Int, NSPoint) -> Void)?
    var onWindowDrop: (([Int], Int, NSPoint) -> Void)?
    var onSpaceDragStart: ((Int) -> Void)?
    var onWindowDragStart: ((Int) -> Void)?

    init(yabaiService: YabaiService, themeStore: ThemeStore) {
        self.yabaiService = yabaiService
        self.themeStore = themeStore
    }

    func updateConfig(_ config: SpacemapConfig) {
        let wasShowingThumbnails = currentConfig.cellStyle == .thumbnails
        currentConfig = config
        panel?.hasShadow = config.hudShadow
        displayPanels.values.forEach { $0.hasShadow = config.hudShadow }
        if wasShowingThumbnails, config.cellStyle != .thumbnails {
            clearThumbnailsIfNeeded()
        }
    }

    /// Highlight the cell a drag would drop onto. Separate from pointer hover:
    /// external drags own the highlight until they end.
    func setExternalDropTarget(_ spaceIndex: Int?) {
        guard hoverState.cell != spaceIndex else { return }
        hoverState.cell = spaceIndex
    }

    func updateDisplayNumber(_ feedback: HUDNumberFeedback?, clearAfter delay: TimeInterval? = nil) {
        // A clear must always land: the setting can flip off mid-hold, and a
        // dropped nil would leave stale text in the overlay.
        guard feedback == nil || currentConfig.showHUDInteractionFeedback else { return }
        numberState.update(feedback, clearAfter: delay)
    }

    /// Typed letters for a fuzzy space-name jump, gated like digit feedback and
    /// drawn by the same overlay.
    func updateDisplayTypedText(_ text: String?) {
        guard text == nil || currentConfig.showHUDInteractionFeedback else { return }
        numberState.updateTypedText(text)
    }

    /// Action feedback is optional; the action itself never depends on it.
    func showNotice(_ text: String) {
        guard currentConfig.showHUDInteractionFeedback else { return }
        noticeState.show(text)
    }

    private var thumbnailClearWorkItem: DispatchWorkItem?

    func updateHoveredCell(_ cell: Int?) {
        guard hoveredCell != cell || hoverState.cell != cell else { return }
        hoveredCell = cell
        hoverState.cell = cell
    }

    func show() {
        thumbnailClearWorkItem?.cancel()
        thumbnailClearWorkItem = nil
        delegate?.show()
    }

    func hide() {
        // Clear hover before hiding: no drop-target border may survive into
        // the next presentation. Panels/hosting views stay alive so the next
        // show does not rebuild the whole window tree.
        hoveredCell = nil
        hoverState.cell = nil
        renderedState = nil
        if #available(macOS 14.0, *) {
            ThumbnailCache.shared.cancel()
            // Captures are cancelled now, but the last frames are useful if the
            // HUD reopens soon. Drop them after a delay to bound retention.
            thumbnailClearWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let visible = (self.panel?.isVisible ?? false) ||
                    self.displayPanels.values.contains { $0.isVisible }
                if !visible { ThumbnailCache.shared.clear() }
                self.thumbnailClearWorkItem = nil
            }
            thumbnailClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        }
        if let panel { dismiss(panel) }
        for displayPanel in displayPanels.values {
            dismiss(displayPanel)
        }
        delegate?.hide()
    }

    /// Single panel-sync path: a state update is a full render. Panels are
    /// created, removed, positioned and rooted exactly like `render`, so an
    /// async icon landing or focus change cannot leave stale panels behind.
    func updateState(_ state: GridState) {
        render(state: state)
    }

    func render(state: GridState) {
        currentConfig = state.config
        renderedState = state
        fullRenderCount += 1
        switch state.config.multiMonitorHUDMode {
        case .unified:
            renderUnifiedState(state)
        case .separate:
            renderSeparateStates(state)
        }
        updateCellFrames(state: state)
    }

    func computeCellFrames(state: GridState) -> [(spaceIndex: Int, frame: CGRect)] {
        var frames: [(spaceIndex: Int, frame: CGRect)] = []
        switch currentConfig.multiMonitorHUDMode {
        case .unified:
            let cells = GridLayout.visibleSpaceIndices(
                maxSpaces: currentConfig.maxSpaces,
                showMode: currentConfig.showMode,
                activeIndices: Set(state.spaces.map(\.index))
            )
            if let panel {
                frames.append(contentsOf: cellFrames(for: cells, in: panel))
            } else {
                for panel in displayPanels.values {
                    frames.append(contentsOf: cellFrames(for: cells, in: panel))
                }
            }
        case .separate:
            for (displayIndex, panel) in displayPanels {
                frames.append(contentsOf: cellFrames(
                    for: state.spaces(forDisplay: displayIndex).map(\.index),
                    in: panel
                ))
            }
        }
        return frames
    }

    func updateCellFrames(state: GridState) {
        delegate?.updateCellFrames(state: state)
    }

    func preloadIcons(for state: GridState) {
        guard Self.shouldPreloadIcons(config: currentConfig) else { return }
        iconPreloadCount += 1
        let visibleWindows = state.windows.filter {
            $0.shouldDisplay(showExtraWindows: currentConfig.showExtraWindows)
        }
        // Misses repaint via one follow-up updateState once the image lands,
        // same pattern as the strip's preloadNativeIcons. Hits skip, nils
        // (no bundle anywhere) never re-trigger, and updateState never
        // preloads, so this terminates after one follow-up per resolved app.
        for name in Set(visibleWindows.map(\.app)) {
            guard IconCache.shared.cachedIcon(for: name) == nil else { continue }
            IconCache.shared.resolveInBackground(appName: name) { [weak self] image in
                guard let self, image != nil, let current = self.renderedState else { return }
                guard self.hostingView != nil || !self.displayHostingViews.isEmpty else { return }
                self.updateState(current)
            }
        }
    }

    static func shouldPreloadIcons(config: SpacemapConfig) -> Bool {
        guard config.hudIconSource == .nativeIcons else { return false }
        return config.cellStyle == .icons || config.cellStyle == .hybrid || config.showIconStrip
    }

    func refreshThumbnails(state: GridState, force: Bool = false) {
        guard #available(macOS 14.0, *) else { return }
        guard currentConfig.cellStyle == .thumbnails else {
            clearThumbnailsIfNeeded()
            return
        }
        thumbnailRefreshCount += 1
        showingThumbnails = true

        let visibleSpaceIndices: Set<Int>
        switch currentConfig.multiMonitorHUDMode {
        case .unified:
            visibleSpaceIndices = Set(GridLayout.visibleSpaceIndices(
                maxSpaces: currentConfig.maxSpaces,
                showMode: currentConfig.showMode,
                activeIndices: Set(state.spaces.map(\.index))
            ))
        case .separate:
            visibleSpaceIndices = Set(state.spaces.map(\.index))
        }

        let backingScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let thumbnailPixelSize = GridLayout.thumbnailPixelSize(for: currentConfig.uiScale, backingScale: backingScale)
        let requests = ThumbnailRequestBuilder.captureRequests(
            for: state,
            spaceIndices: visibleSpaceIndices,
            thumbnailPixelSize: thumbnailPixelSize,
            includeWallpaper: currentConfig.showThumbnailWallpaper
        )
        guard !requests.isEmpty else {
            clearThumbnailsIfNeeded()
            return
        }

        ThumbnailCache.shared.refreshSpaces(requests, force: force)
    }

    /// Thumbnails are only meaningful while the style is active and at least
    /// one space is visible; drop the store so a later style switch cannot
    /// paint stale captures, and so an empty topology leaves no residue.
    private func clearThumbnailsIfNeeded() {
        guard showingThumbnails else { return }
        showingThumbnails = false
        guard #available(macOS 14.0, *) else { return }
        // Both sides are main in the HUD path; clear synchronously so a new
        // refresh queued in the same turn cannot be cancelled by a late task.
        ThumbnailCache.shared.clear()
    }

    /// Panel-position normalization shared with `HUDPosition.custom.point`:
    /// fraction 0 sits at the screen origin, fraction 1 fully right/bottom.
    /// Storing a mid-panel fraction (the old code) made the round trip move
    /// the panel by half its size on the next show.
    static func normalizedPosition(panelFrame: CGRect, screenFrame: CGRect) -> CGPoint? {
        let rangeX = screenFrame.width - panelFrame.width
        let rangeY = screenFrame.height - panelFrame.height
        guard rangeX > 0, rangeY > 0 else { return nil }
        return CGPoint(
            x: (panelFrame.minX - screenFrame.minX) / rangeX,
            y: (panelFrame.minY - screenFrame.minY) / rangeY
        )
    }

    static let hudPositionChangedNotification = Notification.Name("hudPositionChanged")

    /// The custom position a panel frame represents on `screen`: the same
    /// fraction `normalizedPosition` computes plus that display's identity.
    /// Nil when the panel is larger than the screen, so no fraction exists.
    /// Fractions are clamped: a drag can push the panel past a screen edge,
    /// and the decoder rejects out-of-range values, which would reset the
    /// position to Center.
    static func customPosition(
        panelFrame: CGRect,
        screenFrame: CGRect,
        screen: NSScreen
    ) -> HUDPosition? {
        guard let normalized = normalizedPosition(panelFrame: panelFrame, screenFrame: screenFrame) else {
            return nil
        }
        return .custom(
            x: Double(min(max(normalized.x, 0), 1)),
            y: Double(min(max(normalized.y, 0), 1)),
            screen: ScreenContext.displayIdentifier(for: screen)
        )
    }

    private func restoredCustomScreenFrame() -> CGRect? {
        guard let identifier = currentConfig.hudPosition.screenIdentifier,
              let screen = ScreenContext.screen(matchingIdentifier: identifier)
        else { return nil }
        return screen.frame
    }

    func savePanelPosition() {
        guard let panel = unifiedPanel ?? displayPanels.first?.value else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        guard let position = Self.customPosition(
            panelFrame: panel.frame,
            screenFrame: screen.frame,
            screen: screen
        ) else { return }
        // Atomic read-modify-write so a concurrent AppFontUpdater save cannot
        // be clobbered by this load+save pair. Fractions and the display
        // identity land in the same key, so a restore can never combine a new
        // screen with an old fraction.
        let saved = ConfigStore.updateConfig { config in
            config.hudPosition = position
        }
        guard saved else {
            NSLog("spacemap/HUDDisplay: failed to persist custom position %@", String(describing: position))
            return
        }
        NSLog("spacemap/HUDDisplay: saved custom position %@", String(describing: position))
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        NotificationCenter.default.post(name: Self.hudPositionChangedNotification, object: nil)
    }


    func prewarm(state: GridState) {
        // Launch warmup: icons only. Thumbnail captures must never run before
        // the HUD is first shown — they are expensive and can prompt for
        // screen-recording permission from a background launch.
        preloadIcons(for: state)
    }

    func refreshAndRender(state: GridState, force: Bool) {
        preloadIcons(for: state)
        refreshThumbnails(state: state, force: force)
        // render() already ends with updateCellFrames; no explicit call here.
        render(state: state)
    }


    private func renderUnifiedState(_ state: GridState) {
        let gridView = makeGridView(state: state, hoveredCell: hoveredCell)
        let size = gridView.idealSize

        if currentConfig.unifiedHUDVisibility == .all {
            if let panel {
                panel.orderOut(nil)
                panel.close()
                self.panel = nil
                hostingView = nil
            }

            // Empty spaces (pre-fetch placeholder) yield no indices: fall
            // back to one main-screen panel so the HUD still paints.
            let displayIndices = state.populatedDisplayIndices.isEmpty ? [1] : state.populatedDisplayIndices
            let assignments = screenAssignments(for: displayIndices, in: state)
            let activeIndices = Set(assignments.map(\.displayIndex))
            let staleIndices = Set(displayPanels.keys).subtracting(activeIndices)
            for index in staleIndices {
                displayPanels[index]?.orderOut(nil)
                displayPanels[index]?.close()
                displayPanels[index] = nil
                displayHostingViews[index] = nil
            }

            for (displayIndex, screenFrame) in assignments {
                let panel: NSPanel
                if let existing = displayPanels[displayIndex] {
                    panel = existing
                } else {
                    panel = makePanel()
                    displayPanels[displayIndex] = panel
                }

                if let existing = displayHostingViews[displayIndex] {
                    existing.rootView = AnyView(gridView)
                    existing.frame = NSRect(origin: .zero, size: size)
                    installContent(existing, in: panel, size: size)
                } else {
                    let hostingView = NSHostingView(rootView: AnyView(gridView))
                    hostingView.frame = NSRect(origin: .zero, size: size)
                    installContent(hostingView, in: panel, size: size)
                    displayHostingViews[displayIndex] = hostingView
                }
                panel.setContentSize(size)
                positionPanel(panel, size: size, screenFrame: screenFrame)
                present(panel)
            }
            return
        }

        closeDisplayPanels()
        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        if let hostingView {
            hostingView.rootView = AnyView(gridView)
            hostingView.frame = NSRect(origin: .zero, size: size)
            installContent(hostingView, in: panel, size: size)
        } else {
            let hostingView = NSHostingView(rootView: AnyView(gridView))
            hostingView.frame = NSRect(origin: .zero, size: size)
            installContent(hostingView, in: panel, size: size)
            self.hostingView = hostingView
        }

        panel.setContentSize(size)
        let focusedScreenFrame = state.focusedIndex
            .flatMap { state.displayIndex(forSpace: $0) }
            .flatMap { screenFrame(forDisplay: $0, in: state) }
        if let frame = restoredCustomScreenFrame()
            ?? focusedScreenFrame
            ?? NSScreen.main?.frame
            ?? availableScreenFrames.first {
            positionPanel(panel, size: size, screenFrame: frame)
        }
        present(panel)
    }

    private func renderSeparateStates(_ state: GridState) {
        if let panel {
            panel.orderOut(nil)
            panel.close()
            self.panel = nil
            hostingView = nil
        }

        var displayIndices: [Int]
        if currentConfig.separateHUDVisibility == .active,
           let focusedIndex = state.focusedIndex,
           let focusedDisplayIndex = state.displayIndex(forSpace: focusedIndex) {
            displayIndices = [focusedDisplayIndex]
        } else {
            displayIndices = state.populatedDisplayIndices
        }
        // Empty spaces (pre-fetch placeholder) yield no indices: fall back
        // to one main-screen panel so the HUD still paints.
        if displayIndices.isEmpty { displayIndices = [1] }
        // A display with no spaces while others have them is not shown;
        // filtered before resolution so it cannot claim a physical screen.
        displayIndices = displayIndices.filter { index in
            !(state.spaces(forDisplay: index).isEmpty && !state.spaces.isEmpty)
        }
        let assignments = screenAssignments(for: displayIndices, in: state)
        let activeIndices = Set(assignments.map(\.displayIndex))
        let staleIndices = Set(displayPanels.keys).subtracting(activeIndices)
        for index in staleIndices {
            displayPanels[index]?.orderOut(nil)
            displayPanels[index]?.close()
            displayPanels[index] = nil
            displayHostingViews[index] = nil
        }

        for (displayIndex, screenFrame) in assignments {
            let spaces = state.spaces(forDisplay: displayIndex).map(\.index)

            let panel: NSPanel
            if let existing = displayPanels[displayIndex] {
                panel = existing
            } else {
                panel = makePanel()
                displayPanels[displayIndex] = panel
            }

            let gridView = makeGridView(state: state, hoveredCell: hoveredCell, spaceIndices: spaces.isEmpty ? nil : spaces)
            let size = gridView.idealSize
            if let existing = displayHostingViews[displayIndex] {
                existing.rootView = AnyView(gridView)
                existing.frame = NSRect(origin: .zero, size: size)
                installContent(existing, in: panel, size: size)
            } else {
                let hostingView = NSHostingView(rootView: AnyView(gridView))
                hostingView.frame = NSRect(origin: .zero, size: size)
                installContent(hostingView, in: panel, size: size)
                displayHostingViews[displayIndex] = hostingView
            }
            panel.setContentSize(size)
            positionPanel(panel, size: size, screenFrame: screenFrame)
            present(panel)
        }
    }

    /// Installs the SwiftUI grid in the panel's glass container. The container
    /// keeps a native glass sibling below the content so the effect samples the
    /// window backdrop, as it does in System Settings and the glyph strip.
    /// Fades the panel in only on a fresh presentation, so repeated state
    /// renders do not re-animate it. Respects the global animation switch.
    private func present(_ panel: NSPanel) {
        guard !panel.isVisible else {
            panel.orderFrontRegardless()
            return
        }
        // NSAnimationContext needs a running app; unit tests create windows but
        // do not spin an app event loop, so animate only in the real app.
        guard PanelPresenter.canAnimate(currentConfig.hudAnimationsEnabled) else {
            presenter.present(panel, duration: 0, animated: false)
            return
        }
        let target = panel.frame
        let start = entranceFrame(currentConfig.hudEntranceStyle, for: panel) ?? target
        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = currentConfig.hudAnimationStyle.fadeDuration
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func dismiss(_ panel: NSPanel) {
        guard panel.isVisible, currentConfig.hudAnimationsEnabled, NSApp != nil, NSApp.isRunning else {
            panel.orderOut(nil)
            return
        }
        let target = panel.frame
        let end = entranceFrame(currentConfig.hudEntranceStyle, for: panel) ?? target
        NSAnimationContext.runAnimationGroup { context in
            context.duration = currentConfig.hudAnimationStyle.fadeDuration
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.setFrame(target, display: false)
            panel.alphaValue = 1
        }
    }

    /// Frame the panel animates from or to for an entrance style. `nil` means
    /// a plain fade. Slides leave the screen from a chosen edge; scale grows
    /// from a slightly smaller frame.
    private func entranceFrame(_ style: HUDEntranceStyle, for panel: NSPanel) -> CGRect? {
        guard let screen = panel.screen ?? NSScreen.main else { return nil }
        let frame = panel.frame
        let area = screen.frame
        switch style {
        case .fade:
            return nil
        case .slideFromLeft:
            return frame.offsetBy(dx: area.minX - frame.maxX, dy: 0)
        case .slideFromRight:
            return frame.offsetBy(dx: area.maxX - frame.minX, dy: 0)
        case .slideFromTop:
            return frame.offsetBy(dx: 0, dy: area.maxY - frame.minY)
        case .slideFromBottom:
            return frame.offsetBy(dx: 0, dy: area.minY - frame.maxY)
        case .scale:
            return frame.insetBy(dx: frame.width * 0.04, dy: frame.height * 0.04)
        }
    }

    private func installContent(_ hostingView: NSView, in panel: NSPanel, size: CGSize) {
        let container: HUDGlassContainerView
        if let existing = panel.contentView as? HUDGlassContainerView {
            container = existing
        } else {
            container = HUDGlassContainerView()
            panel.contentView = container
        }
        container.configure(hosting: hostingView, size: size, appearance: hudGlassAppearance)
    }

    /// Native glass is only possible when the compiler, OS, and accessibility
    /// settings all allow it; otherwise SwiftUI draws its own material.
    private static var nativeGlassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return GlassSupport.isAvailable }
        #endif
        return false
    }

    private var hudGlassAppearance: HUDGlassContainerView.Appearance {
        HUDGlassContainerView.Appearance(
            enabled: currentConfig.backgroundStyle == .glass && Self.nativeGlassAvailable,
            style: currentConfig.glassStyle,
            tintedMaterial: currentConfig.glassTintedMaterial,
            opacity: CGFloat(currentConfig.effectiveBackgroundOpacity(for: .glass)),
            tint: GlyphStrip.color(for: "focused", theme: themeStore.named(currentConfig.theme))
                ?? .controlAccentColor,
            cornerRadius: CGFloat(currentConfig.hudCornerRadius),
            variant: currentConfig.glassStyle == .clear
                ? currentConfig.glassClearVariant
                : (currentConfig.glassStyle == .regular
                    ? currentConfig.glassRegularVariant
                    : currentConfig.glassTintedVariant)
        )
    }

    private func makeGridView(
        state: GridState,
        hoveredCell: Int?,
        spaceIndices: [Int]? = nil
    ) -> GridView {
        GridView(state: state, hoveredCell: hoveredCell, hoverState: hoverState, numberState: numberState, noticeState: noticeState, onSelect: { [weak self] index in
            self?.yabaiService.focusSpaceAsync(index)
            self?.delegate?.hide()
        }, uiScale: currentConfig.uiScale, theme: currentConfig.theme,
           resolvedTheme: themeStore.named(currentConfig.theme), spaceIndices: spaceIndices,
           usesNativeGlass: Self.nativeGlassAvailable && currentConfig.backgroundStyle == .glass,
           hudAnimation: currentConfig.hudAnimationsEnabled ? currentConfig.hudAnimationStyle : nil,
           onSpaceDrop: onSpaceDrop,
           onWindowDrop: onWindowDrop,
           onDragActive: onDragActive,
           onSpaceDragStart: onSpaceDragStart,
           onWindowDragStart: onWindowDragStart)
    }

    private func cellFrames(for cells: [Int], in panel: NSPanel) -> [(spaceIndex: Int, frame: CGRect)] {
        ScreenContext.cellFrames(
            for: cells,
            panelFrame: panel.frame,
            config: currentConfig,
            quartzMaxY: quartzMainScreenFrame.maxY
        )
    }

    private var availableScreenFrames: [CGRect] {
        ScreenContext.availableScreenFrames(override: screenFramesOverride)
    }

    private func screenFrame(forDisplay displayIndex: Int, in state: GridState) -> CGRect? {
        ScreenContext.screenFrame(
            forDisplay: displayIndex,
            in: state,
            frames: availableScreenFrames,
            quartzMaxY: quartzMainScreenFrame.maxY
        )
    }

    /// Resolve display indices to physical screen frames, dropping duplicate
    /// frames (mirrored/stale yabai topology) so two logical displays can
    /// never stack two HUD panels on one screen.
    private func screenAssignments(
        for displayIndices: [Int],
        in state: GridState
    ) -> [(displayIndex: Int, frame: CGRect)] {
        ScreenContext.screenAssignments(
            for: displayIndices,
            in: state,
            frames: availableScreenFrames,
            quartzMaxY: quartzMainScreenFrame.maxY,
            mainFrame: screenFramesOverride?.first ?? NSScreen.main?.frame
        )
    }

    static func deduplicatedAssignments(
        _ assignments: [(displayIndex: Int, screenFrame: CGRect)]
    ) -> [(displayIndex: Int, screenFrame: CGRect)] {
        var seenFrames: [CGRect] = []
        return assignments.filter { assignment in
            guard !seenFrames.contains(assignment.screenFrame) else { return false }
            seenFrames.append(assignment.screenFrame)
            return true
        }
    }

    private func closeDisplayPanels() {
        for panel in displayPanels.values {
            panel.orderOut(nil)
            panel.close()
        }
        displayPanels.removeAll()
        displayHostingViews.removeAll()
    }

    private func positionPanel(_ panel: NSPanel, size: CGSize, screenFrame: CGRect) {
        // A render can be triggered by a yabai signal while the user is
        // dragging the panel; leave the live drag position alone.
        guard isPanelDragging?() != true else { return }
        panel.setFrameOrigin(currentConfig.hudPosition.point(for: size, screen: screenFrame))
    }

    private func makePanel() -> NSPanel {
        presenter.makePanel(PanelPresenter.Surface(
            level: .floating,
            hasShadow: currentConfig.hudShadow,
            collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ))
    }

    private var quartzMainScreenFrame: CGRect {
        ScreenContext.mainScreenFrame()
    }

    func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
        ScreenContext.quartzPoint(fromAppKit: point, quartzMaxY: quartzMainScreenFrame.maxY)
    }
}
