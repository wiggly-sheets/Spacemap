import AppKit
import SwiftUI
class HUDWindowController {
    private var autoHideTimer: Timer?
    private var pollTimer: Timer?
    private var dragHandler: WindowDragHandler
    private var hoveredCell: Int? = nil
    private var currentState: GridState? = nil
    private var lastFocusedSpaceIndex: Int? = nil
    var isVisible = false
    var isPinned = false
    var isToggling = false
    private var isPollingFocusedSpace = false
    private let yabaiService: YabaiService
    private var _config: GridConfig? = nil
    private var config: GridConfig { get { _config ?? Config.load() } set { _config = newValue } }
    var onShowSettings: (() -> Void)?
    private let hudInput: HUDInput
    private let hudDisplay: HUDDisplay
    private let hudStateSync: HUDStateSync
    init(yabaiService: YabaiService = YabaiClientImpl()) {
        self.yabaiService = yabaiService
        self.hudStateSync = DefaultHUDStateSync(coordinator: GridStateCoordinator(yabaiService: yabaiService))
        self.hudDisplay = HUDDisplay(dragHandler: nil, yabaiService: yabaiService)
        self.hudInput = HUDInput(panel: nil)
        self.dragHandler = WindowDragHandler(yabaiService: yabaiService)
        setupDelegates()
    }
    private func setupDelegates() {
        hudInput.delegate = self
        hudDisplay.delegate = self
        hudInput.updateConfig(useArrowKeys: config.useArrowKeys, useVimKeys: config.useVimKeys)
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, isVisible, let state = currentState else { return }
            hoveredCell = cell
            hudDisplay.updateHoveredCell(cell)
            hudDisplay.render(state: state)
            self.resetAutoHideTimer()
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex, modifiers in
            guard let self else { return }
            hoveredCell = nil
            self.resetAutoHideTimer()
            let fd = self.config.focusSpaceOnWindowDrop.shouldFocus(eventFlags: modifiers, requiredModifier: self.config.focusSpaceOnWindowDropModifier)
            self.yabaiService.moveWindowCreatingSpacesIfNeeded(windowID, toSpace: spaceIndex, focusDestination: fd) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result { NSLog("spacemap/HUD: window drop failed: \(error.localizedDescription)") }
                self.refresh()
                self.resetAutoHideTimer()
            }
        }
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
        else { isPinned = true; isVisible ? resetAutoHideTimer() : show() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
    }
    func pin() {
        guard !isToggling, !(isVisible && isPinned) else { return }
        isToggling = true
        isPinned = true
        isVisible ? resetAutoHideTimer() : show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isToggling = false }
    }
    func show() {
        guard !isVisible else { return }
        hudDisplay.hide(); reloadConfig()
        isVisible = true
        if let state = hudStateSync.currentState {
            hudDisplay.updateState(state)
        } else if config.multiMonitorHUDMode == .unified {
            hudDisplay.render(state: GridState(config: config, spaces: [], windows: [], displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440), focusedIndex: nil))
        }
        resetAutoHideTimer()
        startPollTimer()
        hudInput.start()
        if config.multiMonitorHUDMode == .unified, config.unifiedHUDVisibility == .active, case .custom = config.hudPosition { hudInput.startPanelDragMonitor() }
        hudStateSync.fetch { [weak self] in self?.renderRefreshedState(force: true, refreshFocusedWindow: true) }
    }
    func prewarmState() {
        hudStateSync.fetch { [weak self] in
            guard let self, let state = self.hudStateSync.currentState else { return }
            self.hudDisplay.preloadIcons(for: state)
            self.hudDisplay.refreshThumbnails(state: state, force: true)
            if self.isVisible, self.currentState == nil { self.hudDisplay.updateState(state) }
        }
    }
    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.hudInput.reconcileSettingsKeyMonitor()
            guard !self.isPollingFocusedSpace else { return }
            self.isPollingFocusedSpace = true
            self.yabaiService.runOnYabaiQueue { [weak self, yabaiService] in
                let focused = yabaiService.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isPollingFocusedSpace = false
                    guard self.isVisible else { return }
                    if focused != self.lastFocusedSpaceIndex {
                        NSLog("spacemap/HUD: poll detected change last=\(self.lastFocusedSpaceIndex ?? -1) current=\(focused ?? -1)")
                        self.refresh()
                        self.resetAutoHideTimer()
                    }
                }
            }
        }
    }
    private func renderRefreshedState(force: Bool, refreshFocusedWindow: Bool = false) {
        guard isVisible, let state = hudStateSync.currentState else { return }
        currentState = state
        dragHandler.updateInput(WindowDragInput(cellFrames: dragHandler.cellFrames, cachedWindows: state.windows, focusedWindowIDAtOpen: dragHandler.focusedWindowIDAtOpen)); hudDisplay.preloadIcons(for: state)
        hudDisplay.refreshThumbnails(state: state, force: force); hudDisplay.render(state: state); hudDisplay.updateCellFrames(state: state)
        lastFocusedSpaceIndex = state.focusedIndex; dragHandler.start()
        if refreshFocusedWindow {
            yabaiService.runOnYabaiQueue { [weak self, yabaiService] in
                let focusedWindowID = try? yabaiService.queryFocusedWindow()
                DispatchQueue.main.async {
                    guard let self, self.isVisible, let focusedWindowID else { return }
                    self.dragHandler.updateInput(WindowDragInput(cellFrames: self.dragHandler.cellFrames, cachedWindows: self.dragHandler.cachedWindows, focusedWindowIDAtOpen: focusedWindowID))
                }
            }
        }
        NSLog("spacemap/HUD: state refresh complete, focused=\(state.focusedIndex ?? -1), spaces=\(state.spaces.count), windows=\(state.windows.count)")
    }
    func hide() {
        guard isVisible else { return }
        isVisible = false
        isPinned = false; dragHandler.stop()
        autoHideTimer?.invalidate(); autoHideTimer = nil; pollTimer?.invalidate(); pollTimer = nil
        hudDisplay.hide()
        hoveredCell = nil; currentState = nil; isPollingFocusedSpace = false
        hudStateSync.clearPendingFocus(); hudStateSync.cancelPendingFetch()
        dragHandler.updateInput(WindowDragInput(cellFrames: [], cachedWindows: [], focusedWindowIDAtOpen: nil))
        hudInput.stop()
    }
    func refresh() {
        guard isVisible else {
            guard hudStateSync.currentState != nil else { prewarmState(); return }
            yabaiService.runOnYabaiQueue { [weak self, yabaiService] in
                let focusedIndex = yabaiService.queryFocusedSpaceIndex()
                DispatchQueue.main.async {
                    guard let self, !self.isVisible, let focusedIndex else { return }
                    self.hudStateSync.fetch { _ = self.hudStateSync.updateFocusedIndex(focusedIndex) }
                }
            }
            return
        }
        resetAutoHideTimer()
        hudStateSync.refresh { [weak self] in self?.renderRefreshedState(force: false) }
    }
    func reloadConfig() {
        _config = nil
        hudStateSync.reloadConfig()
    }
    private func resetAutoHideTimer() {
        guard !hudInput.panelDragActive else { return }
        autoHideTimer?.invalidate(); autoHideTimer = nil
        guard !isPinned, config.autoHideTimeout > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.autoHideTimeout), repeats: false) { [weak self] _ in self?.hide() }
    }
    private func navigateSpace(_ direction: SpaceNavigationDirection) {
        guard let currentIdx = lastFocusedSpaceIndex, let state = currentState else { return }
        let target: Int?
        switch config.displayNavigationWrap {
        case .within: let ss = state.displayIndex(forSpace: currentIdx).map { state.spaces(forDisplay: $0) } ?? state.spaces
            target = SpaceNavigator.destination(from: currentIdx, visibleSpaceIndices: SpaceNavigator.navigableSpaceIndices(activeSpaceIndices: ss.map(\.index), maxSpaces: config.maxSpaces), columns: config.cols, direction: direction)
        case .between: target = SpaceNavigator.destinationAcrossDisplays(from: currentIdx, displaySpaceIndices: state.populatedDisplayIndices.map { state.spaces(forDisplay: $0).map(\.index) }, maxSpaces: config.maxSpaces, columns: config.cols, direction: direction)
        }
        guard let target else { return }
        NSLog("spacemap/HUD: navigate \(direction) from yabai=\(currentIdx) → target yabai=\(target)")
        yabaiService.focusSpaceAsync(target)
        lastFocusedSpaceIndex = target
        if let optimistic = hudStateSync.updateFocusedIndex(target) {
            currentState = optimistic
            hudDisplay.updateState(optimistic)
        }
        resetAutoHideTimer()
    }
}
extension HUDWindowController: HUDInputDelegate {
    func navigate(direction: SpaceNavigationDirection) { navigateSpace(direction) }
    func showSettings() { hide(); onShowSettings?() }
}
extension HUDWindowController: HUDDisplayDelegate {
    func render(state: GridState) {}
    func updateCellFrames(state: GridState) {
        // HUDDisplay already updates the drag handler via syncDragInput before calling this delegate method
    }
}
