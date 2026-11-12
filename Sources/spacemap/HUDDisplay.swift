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
    private var currentConfig: GridConfig = .default
    private(set) var hoveredCell: Int? = nil
    private var displayNumber: Int?
    private(set) var renderedState: GridState?
    private var yabaiService: YabaiService
    private let themeService: ThemeManager
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

    init(yabaiService: YabaiService, themeService: ThemeManager = .shared) {
        self.yabaiService = yabaiService
        self.themeService = themeService
    }

    func updateConfig(_ config: GridConfig) {
        let wasShowingThumbnails = currentConfig.cellStyle == .thumbnails
        currentConfig = config
        panel?.hasShadow = config.hudShadow
        displayPanels.values.forEach { $0.hasShadow = config.hudShadow }
        if wasShowingThumbnails, config.cellStyle != .thumbnails {
            clearThumbnailsIfNeeded()
        }
    }

    func updateDisplayNumber(_ number: Int?) {
        displayNumber = number
        if let renderedState { updateState(renderedState) }
    }

    func updateHoveredCell(_ cell: Int?) {
        guard hoveredCell != cell || hoverState.cell != cell else { return }
        hoveredCell = cell
        hoverState.cell = cell
    }

    func show() {
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
        }
        panel?.orderOut(nil)
        for displayPanel in displayPanels.values {
            displayPanel.orderOut(nil)
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

    static func shouldPreloadIcons(config: GridConfig) -> Bool {
        config.cellStyle == .icons || config.cellStyle == .hybrid || config.showIconStrip
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
            thumbnailPixelSize: thumbnailPixelSize
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

    static let customScreenDefaultsKey = "spacemap.hudCustomScreenIdentifier"
    static let hudPositionChangedNotification = Notification.Name("hudPositionChanged")

    /// Stable-ish display identity used to restore a custom position on the
    /// screen it was dragged on. Falls back to the localized name.
    static func displayIdentifier(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuid) as String
            }
        }
        return screen.localizedName
    }

    static func screen(
        matchingIdentifier identifier: String,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        screens.first { displayIdentifier(for: $0) == identifier }
    }

    private func restoredCustomScreenFrame() -> CGRect? {
        guard case .custom = currentConfig.hudPosition,
              let identifier = UserDefaults.standard.string(forKey: Self.customScreenDefaultsKey)
        else { return nil }
        return Self.screen(matchingIdentifier: identifier)?.frame
    }

    func savePanelPosition() {
        guard let panel = unifiedPanel ?? displayPanels.first?.value else { return }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        guard let normalized = Self.normalizedPosition(panelFrame: panel.frame, screenFrame: screen.frame) else { return }
        let x = Double(normalized.x)
        let y = Double(normalized.y)
        // Atomic read-modify-write so a concurrent AppFontUpdater save cannot
        // be clobbered by this load+save pair. Only persist the screen pairing
        // when the fraction actually landed, otherwise the next restore would
        // combine a new screen with an old fraction.
        let saved = AppConfig.updateConfig { config in
            config.hudPosition = .custom(x: x, y: y)
            config.customHUDX = x
            config.customHUDY = y
        }
        guard saved else {
            NSLog("spacemap/HUDDisplay: failed to persist custom position x=%.2f y=%.2f", x, y)
            return
        }
        UserDefaults.standard.set(
            Self.displayIdentifier(for: screen),
            forKey: Self.customScreenDefaultsKey
        )
        NSLog("spacemap/HUDDisplay: saved custom position x=%.2f y=%.2f", x, y)
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
                    panel.contentView = existing
                } else {
                    let hostingView = NSHostingView(rootView: AnyView(gridView))
                    hostingView.frame = NSRect(origin: .zero, size: size)
                    panel.contentView = hostingView
                    displayHostingViews[displayIndex] = hostingView
                }
                panel.setContentSize(size)
                positionPanel(panel, size: size, screenFrame: screenFrame)
                panel.orderFrontRegardless()
            }
            return
        }

        closeDisplayPanels()
        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        if let hostingView {
            hostingView.rootView = AnyView(gridView)
            hostingView.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hostingView
        } else {
            let hostingView = NSHostingView(rootView: AnyView(gridView))
            hostingView.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hostingView
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
        panel.orderFrontRegardless()
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
                panel.contentView = existing
            } else {
                let hostingView = NSHostingView(rootView: AnyView(gridView))
                hostingView.frame = NSRect(origin: .zero, size: size)
                panel.contentView = hostingView
                displayHostingViews[displayIndex] = hostingView
            }
            panel.setContentSize(size)
            positionPanel(panel, size: size, screenFrame: screenFrame)
            panel.orderFrontRegardless()
        }
    }

    private func makeGridView(
        state: GridState,
        hoveredCell: Int?,
        spaceIndices: [Int]? = nil
    ) -> GridView {
        GridView(state: state, hoveredCell: hoveredCell, hoverState: hoverState, displayNumber: displayNumber, onSelect: { [weak self] index in
            self?.yabaiService.focusSpaceAsync(index)
            self?.delegate?.hide()
        }, uiScale: currentConfig.uiScale, theme: currentConfig.theme,
           resolvedTheme: themeService.named(currentConfig.theme), spaceIndices: spaceIndices)
    }

    private func cellFrames(for cells: [Int], in panel: NSPanel) -> [(spaceIndex: Int, frame: CGRect)] {
        HUDGeometry.cellFrames(
            for: cells,
            panelFrame: panel.frame,
            config: currentConfig,
            quartzMaxY: quartzMainScreenFrame.maxY
        )
    }

    private var availableScreenFrames: [CGRect] {
        screenFramesOverride ?? NSScreen.screens.map(\.frame)
    }

    private func screenFrame(forDisplay displayIndex: Int, in state: GridState) -> CGRect? {
        let frames = availableScreenFrames
        guard !frames.isEmpty else { return nil }
        guard let yabaiDisplay = state.displays.first(where: { $0.index == displayIndex }) else {
            // No yabai topology yet: positional fallback, but never clamp a
            // nonexistent display onto the main screen (that stacked panels).
            let fallbackIndex = displayIndex - 1
            return frames.indices.contains(fallbackIndex) ? frames[fallbackIndex] : nil
        }

        let yabaiFrame = yabaiDisplay.frame.cgFrame
        let appKitFrame = CGRect(
            x: yabaiFrame.minX,
            y: quartzMainScreenFrame.maxY - yabaiFrame.maxY,
            width: yabaiFrame.width,
            height: yabaiFrame.height
        )
        guard let index = Self.bestScreenIndex(
            for: appKitFrame,
            screenFrames: frames
        ) else { return nil }
        return frames[index]
    }

    /// Resolve display indices to physical screen frames, dropping duplicate
    /// frames (mirrored/stale yabai topology) so two logical displays can
    /// never stack two HUD panels on one screen. If nothing matches, keep the
    /// HUD usable with a single main-screen panel rather than painting nothing.
    private func screenAssignments(
        for displayIndices: [Int],
        in state: GridState
    ) -> [(displayIndex: Int, frame: CGRect)] {
        // Array + equality instead of Set: CGRect's Hashable conformance is
        // macOS 15+, and this deployment target is macOS 13.
        var seenFrames: [CGRect] = []
        var assignments: [(displayIndex: Int, frame: CGRect)] = []
        for displayIndex in displayIndices {
            guard let frame = screenFrame(forDisplay: displayIndex, in: state) else { continue }
            guard !seenFrames.contains(frame) else { continue }
            seenFrames.append(frame)
            assignments.append((displayIndex, frame))
        }
        if assignments.isEmpty,
           let mainFrame = screenFramesOverride?.first ?? NSScreen.main?.frame,
           let first = displayIndices.first {
            assignments.append((first, mainFrame))
        }
        return assignments
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

    /// Tolerance for a yabai display frame vs. an AppKit screen frame. Sum of
    /// origin/size deltas; bigger than this is a stale or scaled-away display.
    static let screenMatchTolerance: CGFloat = 200

    static func bestScreenIndex(
        for targetFrame: CGRect,
        screenFrames: [CGRect],
        tolerance: CGFloat = HUDDisplay.screenMatchTolerance
    ) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        var bestIndex = 0
        var bestScore = CGFloat.greatestFiniteMagnitude
        for (index, frame) in screenFrames.enumerated() {
            let score = screenMatchScore(frame, targetFrame: targetFrame)
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestScore <= tolerance ? bestIndex : nil
    }

    static func screenMatchScore(_ screenFrame: CGRect, targetFrame: CGRect) -> CGFloat {
        abs(screenFrame.minX - targetFrame.minX) +
            abs(screenFrame.minY - targetFrame.minY) +
            abs(screenFrame.width - targetFrame.width) +
            abs(screenFrame.height - targetFrame.height)
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
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hasShadow = currentConfig.hudShadow
        return p
    }

    private var quartzMainScreenFrame: CGRect {
        HUDGeometry.mainScreenFrame()
    }

    func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
        HUDGeometry.quartzPoint(fromAppKit: point, quartzMaxY: quartzMainScreenFrame.maxY)
    }
}
