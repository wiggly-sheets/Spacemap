import AppKit
import SwiftUI

class HUDWindowController {
    private var dragHandler: WindowDragHandler
    private var hoveredCell: Int? = nil
    private var state: GridState? = nil
    private(set) var focusedWindowIDAtOpen: Int? = nil
    private var presentationGeneration = 0
    private var dragAutoHidePoll: DispatchWorkItem?
    var isVisible = false
    var isPinned: Bool {
        get { hudInput.isPinned }
        set { hudInput.isPinned = newValue }
    }
    var isToggling = false
    // App-lifetime intent: AppDelegate owns SpacemapServices for process
    // lifetime and services owns hud. Both die together at termination,
    // so this strong back-ref never leaks in practice.
    private let services: SpacemapServices
    private var _config: GridConfig? = nil
    private var lastConfigMtime: Date?
    private var didCheckConfigMtime = false
    private var config: GridConfig { get { _config ?? services.appConfig.load() } set { _config = newValue } }
    var onShowSettings: (() -> Void)?
    private let hudInput: HUDInput
    private let hudDisplay: HUDDisplay
    private let coordinator: GridStateCoordinator
    /// Reduce Transparency changes which backing the HUD can use; SwiftUI
    /// reads that only when its body re-evaluates.
    private var accessibilityObserver: NSObjectProtocol?

    init(services: SpacemapServices, coordinator: GridStateCoordinator? = nil) {
        self.services = services
        let appConfig = services.appConfig
        self.coordinator = coordinator ?? GridStateCoordinator(yabaiService: services.yabaiService, configLoader: { appConfig.load() })
        self.hudDisplay = HUDDisplay(
            yabaiService: services.yabaiService,
            themeService: services.themeService
        )
        self.hudInput = HUDInput(panel: nil)
        self.dragHandler = WindowDragHandler()
        setupDelegates()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.refresh()
        }
    }

    deinit {
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }
    private func setupDelegates() {
        hudInput.delegate = self
        hudDisplay.delegate = self
        hudDisplay.isPanelDragging = { [weak hudInput = self.hudInput] in
            hudInput?.panelDragActive ?? false
        }
        hudInput.quartzPointConverter = { [weak hudDisplay = self.hudDisplay] point in
            hudDisplay?.quartzPoint(fromAppKit: point) ?? point
        }
        hudInput.updateConfig(useArrowKeys: config.useArrowKeys, useVimKeys: config.useVimKeys, useExtendedKeys: config.useExtendedKeys, jumpToSpaceEnabled: config.jumpToSpaceEnabled)
        hudInput.yabaiService = services.yabaiService
        hudInput.config = config
        hudInput.hudStateSync = coordinator
        hudInput.hudDisplay = hudDisplay
        hudInput.onRefresh = { [weak self] in self?.refresh() }
        hudInput.onAutoHide = { [weak self] in self?.hide() }
        hudInput.onNumberEntry = { [weak self] feedback in self?.hudDisplay.updateDisplayNumber(feedback) }
        hudInput.onPanelDragEnded = { [weak self] in self?.hudDisplay.savePanelPosition() }
        hudInput.onAccessibilityRevoked = { [weak self] in self?.hide() }
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, self.isVisible, self.state != nil else { return }
            self.handleHoverCell(cell)
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex, modifiers in
            guard let self, self.isVisible else { return }
            self.hoveredCell = nil
            self.hudDisplay.updateHoveredCell(nil)
            hudInput.setAutoHideSuppressed(false)
            let focusDestination = self.config.focusSpaceOnWindowDrop.shouldFocus(
                eventFlags: modifiers,
                requiredModifier: self.config.focusSpaceOnWindowDropModifier
            )
            self.services.yabaiService.moveWindowCreatingSpacesIfNeeded(
                windowID,
                toSpace: spaceIndex,
                focusDestination: focusDestination
            ) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result { NSLog("spacemap/HUD: window drop failed: \(error.localizedDescription)") }
                self.refresh()
                self.resetAutoHideTimer()
            }
        }
        dragHandler.onRequestDragSnapshot = { [weak self] requestGeneration in
            guard let self else { return }
            let presentationGeneration = self.presentationGeneration
            self.services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self else { return }
                let focusedWindowID = try? self.services.yabaiService.queryFocusedWindow()
                let windows = (try? self.services.yabaiService.queryWindows()) ?? []
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.isVisible,
                          self.presentationGeneration == presentationGeneration else { return }
                    self.dragHandler.applyDragSnapshot(
                        focusedWindowID: focusedWindowID,
                        windows: windows,
                        generation: requestGeneration
                    )
                }
            }
        }
    }

    /// Cell-crossing hover: only mutate the observable hover channel and
    /// auto-hide state. No icons, thumbnails, rendering or panel resizing.
    func handleHoverCell(_ cell: Int?) {
        guard hoveredCell != cell else { return }
        hoveredCell = cell
        hudDisplay.updateHoveredCell(cell)
        hudInput.setAutoHideSuppressed(cell != nil || dragHandler.isDragging)
        guard cell == nil else { return }
        guard dragHandler.isDragging else {
            hudInput.setAutoHideSuppressed(false)
            resetAutoHideTimer()
            return
        }
        // handleMouseUp clears the hover before WindowDragHandler.reset() runs
        // its deferred isDragging reset, and a drag that ends over panel
        // padding produces no final hover callback at all. Poll briefly until
        // the drag is genuinely over, then re-arm auto-hide.
        releaseAutoHideAfterDrag()

    }

    private func releaseAutoHideAfterDrag(attempt: Int = 0) {
        dragAutoHidePoll?.cancel()
        // Bounded: a drag under 20s is re-checked every 200ms; after that
        // give up and re-arm auto-hide rather than polling forever.
        guard attempt < 100 else {
            dragAutoHidePoll = nil
            hudInput.setAutoHideSuppressed(false)
            resetAutoHideTimer()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            guard !self.dragHandler.isDragging else {
                self.releaseAutoHideAfterDrag(attempt: attempt + 1)
                return
            }
            self.dragAutoHidePoll = nil
            self.hudInput.setAutoHideSuppressed(false)
            self.resetAutoHideTimer()
        }
        dragAutoHidePoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Test seam: the input's drag target must be the live HUD panel.
    var inputPanel: NSPanel? { hudInput.currentPanel }
    var inputQuartzPointConverter: ((CGPoint) -> CGPoint)? { hudInput.quartzPointConverter }
    var hudDisplayForTesting: HUDDisplay { hudDisplay }
    var seededFocusedSpaceIndex: Int? { hudInput.lastFocusedSpaceIndex }

    func toggle() {
        debouncedToggle { [weak self] in
            guard let self else { return }
            self.isPinned = false
            self.isVisible ? self.hide() : self.show()
        }
    }

    func togglePinned() {
        debouncedToggle { [weak self] in
            guard let self else { return }
            if self.isVisible, self.isPinned { self.hide() }
            else { self.isPinned = true; self.isVisible ? self.hudInput.resetAutoHideTimer() : self.show() }
        }
    }
    func pin() {
        guard !(isVisible && isPinned) else { return }
        debouncedToggle { [weak self] in
            guard let self else { return }
            self.isPinned = true
            self.isVisible ? self.hudInput.resetAutoHideTimer() : self.show()
        }
    }
    private func debouncedToggle(_ action: @escaping () -> Void) {
        guard !isToggling else { return }
        isToggling = true
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
    }
    func show() {
        guard !isVisible else { return }
        hudDisplay.hide(); reloadConfigIfChanged()
        presentationGeneration += 1
        isVisible = true
        hudInput.updateVisibility(true)
        if let state = coordinator.state {
            hudDisplay.updateState(state)
            hudInput.currentState = state
            hudInput.lastFocusedSpaceIndex = state.focusedIndex
        } else {
            // Fail-usable placeholder: empty grid still paints cells and
            // seeds input state, so navigation works once fetch lands.
            // Placeholder forces .all: active mode with no spaces paints
            // nothing (GridLayout filters on active indices).
            var placeholderConfig = config
            placeholderConfig.showMode = .all
            let placeholder = GridState(config: placeholderConfig, spaces: [], windows: [], displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440), focusedIndex: nil)
            hudDisplay.updateState(placeholder)
            hudInput.currentState = placeholder
            hudInput.lastFocusedSpaceIndex = placeholder.focusedIndex
        }
        hudInput.autoHideTimeout = TimeInterval(config.autoHideTimeout)
        hudInput.resetAutoHideTimer()
        hudInput.startPollTimer()
        hudInput.start()
        reconcilePanelDragMonitor()
        coordinator.fetch { [weak self] in self?.renderRefreshedState(force: false, refreshFocusedWindow: true) }
    }
    func prewarmState() {
        coordinator.fetch { [weak self] in
            guard let self, let state = self.coordinator.state else { return }
            self.hudDisplay.prewarm(state: state)
            if self.isVisible, self.state == nil { self.hudDisplay.updateState(state) }
        }
    }
    func startPollTimer() {
        hudInput.startPollTimer()
    }
    private func renderRefreshedState(force: Bool, refreshFocusedWindow: Bool = false) {
        guard isVisible, let state = coordinator.state else { return }
        self.state = state
        hudInput.currentState = state
        hudDisplay.refreshAndRender(state: state, force: force)
        hudInput.lastFocusedSpaceIndex = state.focusedIndex
        dragHandler.start()
        if refreshFocusedWindow {
            let generation = presentationGeneration
            services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self = self else { return }
                let focusedWindowID = try? services.yabaiService.queryFocusedWindow()
                DispatchQueue.main.async {
                    guard self.isVisible, self.presentationGeneration == generation else { return }
                    self.focusedWindowIDAtOpen = focusedWindowID
                    let cellFrames = self.hudDisplay.computeCellFrames(state: state)
                    self.dragHandler.updateInput(WindowDragInput(cellFrames: cellFrames, cachedWindows: state.windows, focusedWindowIDAtOpen: focusedWindowID))
                }
            }
        }
    }
    func hide() {
        guard isVisible else { return }
        presentationGeneration += 1
        isVisible = false
        hudInput.updateVisibility(false)
        isPinned = false; dragHandler.stop()
        // Hide the display first: hudInput.stop() clears number entry, whose
        // callback triggers updateDisplayNumber → a full render if the display
        // still considers itself rendered. Ordering avoids a transient re-show.
        dragAutoHidePoll?.cancel()
        dragAutoHidePoll = nil
        hudDisplay.hide()
        hudInput.stop()
        hoveredCell = nil; self.state = nil; hudInput.currentState = nil
        focusedWindowIDAtOpen = nil
        hudInput.isPollingFocusedSpace = false
        hudInput.lastFocusedSpaceIndex = nil
        coordinator.clearPendingFocus(); coordinator.cancelPendingFetch()
        dragHandler.updateInput(WindowDragInput(cellFrames: [], cachedWindows: [], focusedWindowIDAtOpen: nil))
    }
    func refresh() {
        guard isVisible else {
            guard coordinator.state != nil else { prewarmState(); return }
            services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self = self else { return }
                let focusedIndex = services.yabaiService.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isVisible, let focusedIndex = focusedIndex else { return }
                    self.coordinator.fetch { _ = self.coordinator.updateFocusedIndex(focusedIndex) }
                }
            }
            return
        }
        hudInput.resetAutoHideTimer()
        coordinator.refresh { [weak self] in self?.renderRefreshedState(force: false) }
    }
    func reloadConfig() {
        _config = nil
        services.themeService.reloadIfChanged()
        hudInput.config = config
        hudInput.updateConfig(useArrowKeys: config.useArrowKeys, useVimKeys: config.useVimKeys, useExtendedKeys: config.useExtendedKeys, jumpToSpaceEnabled: config.jumpToSpaceEnabled)
        hudDisplay.updateConfig(config)
        coordinator.reloadConfig()
        reconcilePanelDragMonitor()
    }
    private func reloadConfigIfChanged() {
        let mtime: Date? = (try? FileManager.default.attributesOfItem(atPath: services.appConfig.configPath))?[.modificationDate] as? Date
        guard !didCheckConfigMtime || mtime != lastConfigMtime else { return }
        didCheckConfigMtime = true
        lastConfigMtime = mtime
        reloadConfig()
    }
    private func resetAutoHideTimer() {
        hudInput.resetAutoHideTimer()
    }
    /// Panel-drag positioning only applies to the single unified active
    /// panel; reconcile on show and on config reload so toggling the custom
    /// position takes effect without a hide/show cycle.
    private func reconcilePanelDragMonitor() {
        let current = config
        if isVisible,
           current.multiMonitorHUDMode == .unified,
           current.unifiedHUDVisibility == .active,
           case .custom = current.hudPosition {
            hudInput.startPanelDragMonitor()
        } else {
            hudInput.stopPanelDragMonitor()
        }
    }
    private func navigateSpace(_ direction: SpaceNavigationDirection) {
        hudInput.navigate(direction: direction)
    }
}
extension HUDWindowController: HUDInputDelegate {
    func navigate(direction: SpaceNavigationDirection) { navigateSpace(direction) }
    func navigateToFirst() { hudInput.navigateToFirst() }
    func navigateToLast() { hudInput.navigateToLast() }
    func closeHUD() { hide() }
    func focusRecent() {
        // "recent" is a named selector; SpaceFocusTarget never fails for it.
        guard let target = SpaceFocusTarget(argument: "recent") else { return }
        // focusSpaceAsync only accepts numeric indices, so run the target
        // form on yabaiQueue instead: yabai can block up to 10s and must
        // never stall the main thread (same as every other entry point).
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            _ = self.services.yabaiService.focusSpace(target)
            // Pull the new focus back immediately so the highlight and the
            // next arrow key operate on the actual current space.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isVisible else { return }
                self.refresh()
            }
        }
    }
    func createSpace() {
        // Chain the refresh after the create lands: poll for the new max
        // index instead of refreshing against the pre-create snapshot.
        // Plain create never steals focus — only createAndFocus does.
        // beforeMax is read on yabaiQueue before the create is enqueued:
        // createSpace() runs async on focusQueue, so the snapshot is still
        // pre-create without blocking the main thread on a yabai query.
        let generation = presentationGeneration
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            let beforeMax = (try? self.services.yabaiService.querySpaces())?.map(\.index).max()
            self.services.yabaiService.createSpace()
            self.pollForNewestSpace(beforeMax: beforeMax, generation: generation, attempts: 0, shouldFocus: false)
        }
    }
    func createAndFocusNewestSpace() {
        refresh()
        let generation = presentationGeneration
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            let beforeMax = (try? self.services.yabaiService.querySpaces())?.map(\.index).max()
            self.services.yabaiService.createSpace()
            self.pollForNewestSpace(beforeMax: beforeMax, generation: generation, attempts: 0)
        }
    }
    private func pollForNewestSpace(beforeMax: Int?, generation: Int, attempts: Int, shouldFocus: Bool = true) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self else { return }
                if let maxNow = (try? self.services.yabaiService.querySpaces())?.map(\.index).max(),
                   beforeMax.map({ maxNow > $0 }) ?? true {
                    // Async: sync focus blocks yabai queue up to 10s.
                    // Same focusQueue as createSpace keeps focus ordered after create.
                    if shouldFocus { self.services.yabaiService.focusSpaceAsync(maxNow) }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.presentationGeneration == generation else { return }
                        self.hudDisplay.showNotice("Space \(maxNow) Created")
                        self.refresh()
                    }
                    return
                }
                guard attempts + 1 < 20 else {
                    NSLog("spacemap/HUD: createAndFocus timed out waiting for new space")
                    return
                }
                self.pollForNewestSpace(beforeMax: beforeMax, generation: generation, attempts: attempts + 1, shouldFocus: shouldFocus)
            }
        }
    }
    func destroyCurrentSpace() {
        guard let focused = state?.focusedIndex else { return }
        // yabai itself falls back to the first space after a destroy. Keep the
        // user's place instead: focus the space just before it once the destroy
        // has landed, so the quick auto-jump is corrected.
        let previous = state?.spaces.map(\.index).filter { $0 < focused }.max()
        let generation = presentationGeneration
        services.yabaiService.destroySpace(focused)
        hudDisplay.showNotice("Space \(focused) Deleted")
        waitForDestroy(focused, previous: previous, generation: generation, attempts: 0)
    }

    /// Polls until the destroyed space is gone, then focuses the previous space.
    /// Retries because yabai applies the destroy asynchronously.
    private func waitForDestroy(_ destroyed: Int, previous: Int?, generation: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self else { return }
                let indices = (try? self.services.yabaiService.querySpaces())?.map(\.index) ?? []
                if !indices.contains(destroyed) {
                    if let previous, indices.contains(previous) {
                        self.services.yabaiService.focusSpaceAsync(previous)
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.presentationGeneration == generation else { return }
                        self.refresh()
                    }
                    return
                }
                guard attempts + 1 < 20 else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.presentationGeneration == generation else { return }
                        self.refresh()
                    }
                    return
                }
                self.waitForDestroy(destroyed, previous: previous, generation: generation, attempts: attempts + 1)
            }
        }
    }
    func setSpaceLayout(_ layout: SpaceLayout) {
        services.yabaiService.setSpaceLayout(layout)
        hudDisplay.showNotice(Self.layoutNotice(layout))
        refresh()
    }
    private static func layoutNotice(_ layout: SpaceLayout) -> String {
        switch layout {
        case .bsp: return "BSP Layout"
        case .stack: return "Stack Layout"
        case .float: return "Float Layout"
        }
    }
    func showSettings() { hide(); onShowSettings?() }
}
extension HUDWindowController: HUDDisplayDelegate {
    func render(state: GridState) {}
    func updateCellFrames(state: GridState) {
        let frames = hudDisplay.computeCellFrames(state: state)
        hudInput.updateCellFrames(frames)
        // Panels are created/replaced during render; keep the drag monitor's
        // target pointed at the live unified panel or custom positioning dies.
        hudInput.updatePanel(hudDisplay.unifiedPanel)
        dragHandler.updateInput(WindowDragInput(
            cellFrames: frames,
            cachedWindows: state.windows,
            focusedWindowIDAtOpen: focusedWindowIDAtOpen
        ))
    }
}
