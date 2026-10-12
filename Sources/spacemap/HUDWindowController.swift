import AppKit
import SwiftUI

class HUDWindowController {
    private var dragHandler: WindowDragHandler
    private var hoveredCell: Int? = nil
    private var state: GridState? = nil
    private(set) var focusedWindowIDAtOpen: Int? = nil
    private var presentationGeneration = 0
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
    }
    private func setupDelegates() {
        hudInput.delegate = self
        hudDisplay.delegate = self
        hudInput.updateConfig(useArrowKeys: config.useArrowKeys, useVimKeys: config.useVimKeys, useExtendedKeys: config.useExtendedKeys, jumpToSpaceEnabled: config.jumpToSpaceEnabled)
        hudInput.yabaiService = services.yabaiService
        hudInput.config = config
        hudInput.hudStateSync = coordinator
        hudInput.hudDisplay = hudDisplay
        hudInput.onRefresh = { [weak self] in self?.refresh() }
        hudInput.onAutoHide = { [weak self] in self?.hide() }
        hudInput.onNumberEntry = { [weak self] number in self?.hudDisplay.updateDisplayNumber(number) }
        hudInput.onPanelDragEnded = { [weak self] in self?.hudDisplay.savePanelPosition() }
        hudInput.onAccessibilityRevoked = { [weak self] in self?.hide() }
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, self.isVisible, let state = self.state else { return }
            self.hoveredCell = cell
            self.hudDisplay.updateHoveredCell(cell)
            self.hudDisplay.refreshAndRender(state: state, force: false)
            self.resetAutoHideTimer()
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex, modifiers in
            guard let self, self.isVisible else { return }
            self.hoveredCell = nil
            self.hudDisplay.updateHoveredCell(nil)
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
        }
        hudInput.autoHideTimeout = TimeInterval(config.autoHideTimeout)
        hudInput.resetAutoHideTimer()
        hudInput.startPollTimer()
        hudInput.start()
        if config.multiMonitorHUDMode == .unified, config.unifiedHUDVisibility == .active, case .custom = config.hudPosition { hudInput.startPanelDragMonitor() }
        coordinator.fetch { [weak self] in self?.renderRefreshedState(force: true, refreshFocusedWindow: true) }
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
        hudInput.stop()
        hudDisplay.hide()
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
        services.themeService.reload()
        hudInput.config = config
        hudInput.updateConfig(useArrowKeys: config.useArrowKeys, useVimKeys: config.useVimKeys, useExtendedKeys: config.useExtendedKeys, jumpToSpaceEnabled: config.jumpToSpaceEnabled)
        hudDisplay.updateConfig(config)
        coordinator.reloadConfig()
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
        _ = services.yabaiService.focusSpace(target)
    }
    func createSpace() {
        // Chain the refresh after the create lands: poll for the new max
        // index instead of refreshing against the pre-create snapshot.
        // Plain create never steals focus — only createAndFocus does.
        // beforeMax is captured synchronously before the create is enqueued:
        // createSpace() runs async on focusQueue, so reading inside the
        // yabaiQueue block would race it. Pre-capture keeps snapshot pre-create.
        let generation = presentationGeneration
        let beforeMax = (try? services.yabaiService.querySpaces())?.map(\.index).max()
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            self.services.yabaiService.createSpace()
            self.pollForNewestSpace(beforeMax: beforeMax, generation: generation, attempts: 0, shouldFocus: false)
        }
    }
    func createAndFocusNewestSpace() {
        refresh()
        let generation = presentationGeneration
        let beforeMax = (try? services.yabaiService.querySpaces())?.map(\.index).max()
        services.yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
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
        services.yabaiService.destroySpace(focused)
        refresh()
    }
    func setSpaceLayout(_ layout: SpaceLayout) {
        services.yabaiService.setSpaceLayout(layout)
        refresh()
    }
    func showSettings() { hide(); onShowSettings?() }
}
extension HUDWindowController: HUDDisplayDelegate {
    func render(state: GridState) {}
    func updateCellFrames(state: GridState) {
        let frames = hudDisplay.computeCellFrames(state: state)
        hudInput.updateCellFrames(frames)
        dragHandler.updateInput(WindowDragInput(
            cellFrames: frames,
            cachedWindows: state.windows,
            focusedWindowIDAtOpen: focusedWindowIDAtOpen
        ))
    }
}
