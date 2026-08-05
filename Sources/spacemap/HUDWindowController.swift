import AppKit
import SwiftUI

class HUDWindowController {
    private var dragHandler: WindowDragHandler
    private var hoveredCell: Int? = nil
    private var currentState: GridState? = nil
    private var lastFocusedSpaceIndex: Int? = nil
    private var focusedWindowIDAtOpen: Int? = nil
    private var previousDragState: DragState = .idle
    var isVisible = false
    var isPinned = false
    var isToggling = false
    private let services: SpacemapServices
    private var _config: GridConfig? = nil
    private var config: GridConfig { get { _config ?? services.appConfig.load() } set { _config = newValue } }
    var onShowSettings: (() -> Void)?
    private let hudInput: HUDInput
    private let hudDisplay: HUDDisplay
    private let hudStateSync: HUDStateSync

    init(services: SpacemapServices) {
        self.services = services
        self.hudStateSync = DefaultHUDStateSync(coordinator: GridStateCoordinator(yabaiService: services.yabaiService))
        self.hudDisplay = HUDDisplay(yabaiService: services.yabaiService)
        self.hudInput = HUDInput(panel: nil)
        self.dragHandler = WindowDragHandler(yabaiService: services.yabaiService)
        setupDelegates()
    }
    private func setupDelegates() {
        hudInput.delegate = self
        hudDisplay.delegate = self
        hudInput.updateConfig(useArrowKeys: config.useArrowKeys, useVimKeys: config.useVimKeys)
        hudInput.yabaiService = services.yabaiService
        hudInput.config = config
    }

    private func checkDragState() {
        let state = dragHandler.dragState
        switch (previousDragState, state) {
        case (.idle, .dragging(_, _, let lastHoveredCell, _)):
            if let cell = lastHoveredCell {
                hoveredCell = cell
                hudDisplay.updateHoveredCell(cell)
                if let currentState { hudDisplay.refreshAndRender(state: currentState, force: false) }
                resetAutoHideTimer()
            }
        case (.dragging(_, _, let prevHoveredCell, _), .dragging(_, _, let currentHoveredCell, _)):
            if currentHoveredCell != prevHoveredCell {
                hoveredCell = currentHoveredCell
                hudDisplay.updateHoveredCell(currentHoveredCell)
                if let currentState { hudDisplay.refreshAndRender(state: currentState, force: false) }
                resetAutoHideTimer()
            }
        case (.dragging(_, let draggedWindowID, let lastHoveredCell, _), .idle):
            if let windowID = draggedWindowID, let cell = lastHoveredCell {
                hoveredCell = nil
                resetAutoHideTimer()
                let modifiers = CGEventFlags(rawValue: UInt64(NSEvent.modifierFlags.rawValue))
                let fd = config.focusSpaceOnWindowDrop.shouldFocus(eventFlags: modifiers, requiredModifier: config.focusSpaceOnWindowDropModifier)
                services.yabaiService.moveWindowCreatingSpacesIfNeeded(windowID, toSpace: cell, focusDestination: fd) { [weak self] result in
                    guard let self else { return }
                    if case .failure(let error) = result { NSLog("spacemap/HUD: window drop failed: \(error.localizedDescription)") }
                    self.refresh()
                    self.resetAutoHideTimer()
                }
            } else if lastHoveredCell != nil {
                hoveredCell = nil
                if let currentState { hudDisplay.refreshAndRender(state: currentState, force: false) }
            }
        default:
            break
        }
        previousDragState = state
    }

    func toggle() {
        guard !isToggling else { return }
        isToggling = true
        isPinned = false
        isVisible ? hide() : show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
    }
    func togglePinned() {
        guard !isToggling else { return }
        isToggling = true
        if isVisible, isPinned { hide() }
        else { isPinned = true; isVisible ? hudInput.resetAutoHideTimer() : show() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
    }
    func pin() {
        guard !isToggling, !(isVisible && isPinned) else { return }
        isToggling = true
        isPinned = true
        isVisible ? hudInput.resetAutoHideTimer() : show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
    }
    func show() {
        guard !isVisible else { return }
        hudDisplay.hide(); reloadConfig()
        isVisible = true
        if let state = hudStateSync.currentState {
            hudDisplay.updateState(state)
            hudInput.currentState = state
        } else if config.multiMonitorHUDMode == .unified {
            hudDisplay.render(state: GridState(config: config, spaces: [], windows: [], displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440), focusedIndex: nil))
        }
        hudInput.isPinned = isPinned
        hudInput.autoHideTimeout = TimeInterval(config.autoHideTimeout)
        hudInput.resetAutoHideTimer()
        hudInput.startPollTimer()
        hudInput.start()
        if config.multiMonitorHUDMode == .unified, config.unifiedHUDVisibility == .active, case .custom = config.hudPosition { hudInput.startPanelDragMonitor() }
        hudStateSync.fetch { [weak self] in self?.renderRefreshedState(force: true, refreshFocusedWindow: true) }
    }
    func prewarmState() {
        hudStateSync.fetch { [weak self] in
            guard let self, let state = self.hudStateSync.currentState else { return }
            self.hudDisplay.prewarm(state: state)
            if self.isVisible, self.currentState == nil { self.hudDisplay.updateState(state) }
        }
    }
    func startPollTimer() {
        hudInput.startPollTimer()
    }
    private func renderRefreshedState(force: Bool, refreshFocusedWindow: Bool = false) {
        guard isVisible, let state = hudStateSync.currentState else { return }
        currentState = state
        hudInput.currentState = state
        checkDragState()
        let cellFrames = hudDisplay.computeCellFrames(state: state)
        dragHandler.updateInput(WindowDragInput(cellFrames: cellFrames, cachedWindows: state.windows, focusedWindowIDAtOpen: focusedWindowIDAtOpen))
        hudDisplay.refreshAndRender(state: state, force: force)
        lastFocusedSpaceIndex = state.focusedIndex
        hudInput.lastFocusedSpaceIndex = state.focusedIndex
        dragHandler.start()
        if refreshFocusedWindow {
            services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self = self else { return }
                let focusedWindowID = try? services.yabaiService.queryFocusedWindow()
                DispatchQueue.main.async {
                    guard let focusedWindowID = focusedWindowID else { return }
                    let cellFrames = self.hudDisplay.computeCellFrames(state: state)
                    self.dragHandler.updateInput(WindowDragInput(cellFrames: cellFrames, cachedWindows: state.windows, focusedWindowIDAtOpen: focusedWindowID))
                }
            }
        }
        NSLog("spacemap/HUD: state refresh complete, focused=\(state.focusedIndex ?? -1), spaces=\(state.spaces.count), windows=\(state.windows.count)")
    }
    func hide() {
        guard isVisible else { return }
        isVisible = false
        isPinned = false; dragHandler.stop()
        hudInput.stop()
        hudDisplay.hide()
        hoveredCell = nil; currentState = nil; hudInput.currentState = nil
        hudInput.isPollingFocusedSpace = false
        hudInput.lastFocusedSpaceIndex = nil
        hudStateSync.clearPendingFocus(); hudStateSync.cancelPendingFetch()
        dragHandler.updateInput(WindowDragInput(cellFrames: [], cachedWindows: [], focusedWindowIDAtOpen: nil))
    }
    func refresh() {
        guard isVisible else {
            guard hudStateSync.currentState != nil else { prewarmState(); return }
            services.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self = self else { return }
                let focusedIndex = services.yabaiService.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isVisible, let focusedIndex = focusedIndex else { return }
                    self.hudStateSync.fetch { _ = self.hudStateSync.updateFocusedIndex(focusedIndex) }
                }
            }
            return
        }
        hudInput.resetAutoHideTimer()
        hudStateSync.refresh { [weak self] in self?.renderRefreshedState(force: false) }
    }
    func reloadConfig() {
        _config = nil
        hudInput.config = config
        hudStateSync.reloadConfig()
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
    func showSettings() { hide(); onShowSettings?() }
}
extension HUDWindowController: HUDDisplayDelegate {
    func render(state: GridState) {}
    func updateCellFrames(state: GridState) {
    }
}