import AppKit
import SwiftUI

class HUDWindowController {
    // Unified mode owns one panel; separate mode owns one panel per yabai display.
    private var panel: NSPanel?
    private var displayPanels: [Int: NSPanel] = [:]
    private var isVisible = false
    private var isPinned = false
    private var _config: GridConfig? = nil
    private var config: GridConfig {
        get {
            if let c = _config {
                return c
            } else {
                _config = ConfigReader.load()
                return _config!
            }
        }
        set {
            _config = newValue
        }
    }
    private var hoveredCell: Int? = nil
    // Snapshot of grid state taken when HUD opens; reused for hover rerenders so
    // the thumbnail layout doesn't flicker during a drag and cachedWindows stays stable.
    private var currentState: GridState? = nil
    // Persists while the HUD is hidden, allowing the next show to render its
    // complete grid immediately while yabai supplies a fresh snapshot.
    private var latestState: GridState? = nil
    private var autoHideTimer: Timer?
    private var pollTimer: Timer?
    private let dragHandler = WindowDragHandler()
    private var lastFocusedSpaceIndex: Int? = nil
    private var isToggling = false   // prevents re-entry during toggle animations
    private var hostingView: NSHostingView<AnyView>?
    private var displayHostingViews: [Int: NSHostingView<AnyView>] = [:]
    var onShowSettings: (() -> Void)?
    private var keyboardEventTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?
    // Panel drag state for custom position mode
    private var panelDragMonitor: Any?
    private var panelDragStart: CGPoint?   // initial mouse location on drag start
    private var panelDragDidMove = false
    private var panelDragOffset: CGPoint?  // not used maybe
    private var panelDragOrigin: CGPoint?  // initial panel origin on drag start
    private var isPanelDragging = false
    private var refreshWorkItem: DispatchWorkItem?
    private var isFetching = false  // prevents concurrent fetches
    private var isPollingFocusedSpace = false
    private var pendingFocusedSpaceIndex: Int?
    private var pendingFocusDeadline: Date?
    
    init() {
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, isVisible, let state = currentState else { return }
            hoveredCell = cell
            renderState(state)
            self.resetAutoHideTimer()
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex, modifiers in
            guard let self else { return }
            hoveredCell = nil
            resetAutoHideTimer()
            let focusDestination = config.focusSpaceOnWindowDrop.shouldFocus(
                eventFlags: modifiers,
                requiredModifier: config.focusSpaceOnWindowDropModifier
            )
            YabaiClient.moveWindowCreatingSpacesIfNeeded(
                windowID,
                toSpace: spaceIndex,
                focusDestination: focusDestination
            ) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    NSLog("spacemap/HUD: window drop failed: \(error.localizedDescription)")
                }
                refreshState()
                resetAutoHideTimer()
            }
        }
    }
    
    func toggle() {
        guard !isToggling else { 
            NSLog("spacemap/HUD: toggle ignored, isToggling=\(isToggling)")
            return 
        }
        NSLog("spacemap/HUD: toggle called, isVisible=\(isVisible)")
        isToggling = true
        isPinned = false
        if isVisible { hide() } else { show() }
        // Reset isToggling after a short delay to allow for animation settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggling = false
        }
    }

    func togglePinned() {
        guard !isToggling else { return }
        isToggling = true
        if isVisible, isPinned {
            hide()
        } else {
            isPinned = true
            if isVisible {
                resetAutoHideTimer()
            } else {
                show()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggling = false
        }
    }

    func pin() {
        guard !isToggling, !(isVisible && isPinned) else { return }
        isToggling = true
        isPinned = true
        if isVisible {
            resetAutoHideTimer()
        } else {
            show()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggling = false
        }
    }
    
    func show() {
        guard !isVisible else { return }
        tearDownPanels()
        NSLog("spacemap/HUD: show() called")
        reloadConfig()
        
        isVisible = true
        if let latestState {
            displayCachedState(latestState)
        } else {
            renderEmptyState()
        }
        resetAutoHideTimer()
        startPollTimer()
        startSettingsKeyMonitor()
        if config.multiMonitorHUDMode == .unified,
           config.unifiedHUDVisibility == .active,
           case .custom = config.hudPosition {
            startPanelDragMonitor()
        }
        
        // Fetch data in background, update UI when ready
        fetchStateAndRender()
    }

    /// Query once at launch so the first HUD invocation can render complete
    /// content too, rather than showing an empty frame while yabai is queried.
    func prewarmState() {
        let cfg = config
        YabaiClient.runOnYabaiQueue { [weak self] in
            let state = YabaiClient.buildGridState(config: cfg)
            DispatchQueue.main.async {
                guard let self else { return }
                self.latestState = state
                self.preloadIcons(for: state)
                self.refreshAllThumbnails(state: state, force: true)
                if self.isVisible, self.currentState == nil {
                    self.displayCachedState(state)
                }
            }
        }
    }
    
    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.isVisible, !self.isPollingFocusedSpace else { return }
            self.isPollingFocusedSpace = true
            // Do not enqueue another poll while one is waiting behind a refresh.
            // Otherwise polls can delay interactive focus commands indefinitely.
            YabaiClient.runOnYabaiQueue { [weak self] in
                let focused = YabaiClient.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isPollingFocusedSpace = false
                    guard self.isVisible else { return }
                    self.handlePolledFocus(focused)
                }
            }
        }
    }
    
    private func fetchStateAndRender() {
        // Cancel any pending work and mark as fetching so refreshState can't race
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        isFetching = true
        let cfg = config
        var workCancelled = false
        let work: DispatchWorkItem = DispatchWorkItem { [weak self] in
            let state = YabaiClient.buildGridState(config: cfg)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Guard against stale completions
                guard !workCancelled, self.isFetching else {
                    NSLog("spacemap/HUD: fetchStateAndRender cancelled (stale)")
                    self.isFetching = false
                    return
                }
                self.isFetching = false
                guard self.isVisible else { return }
                self.latestState = state
                self.currentState = state
                self.dragHandler.cachedWindows = state.windows
                self.preloadIcons(for: state)
                self.refreshAllThumbnails(state: state, force: true)
                self.renderState(state)
                self.updateCellFrames(state: state)
                self.lastFocusedSpaceIndex = state.focusedIndex
                self.dragHandler.start()
                self.refreshFocusedWindowID()
                NSLog("spacemap/HUD: fetchStateAndRender complete, focused=\(state.focusedIndex ?? -1), spaces=\(state.spaces.count), windows=\(state.windows.count)")
            }
        }
        work.notify(queue: .main) { [weak work] in
            if work?.isCancelled == true { workCancelled = true }
        }
        refreshWorkItem = work
        YabaiClient.runOnYabaiQueue(work)
    }

    private func renderEmptyState() {
        guard config.multiMonitorHUDMode == .unified else { return }
        let emptyState = GridState(
            config: config,
            spaces: [],
            windows: [],
            displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil
        )
        renderState(emptyState)
    }

    private func displayCachedState(_ cachedState: GridState) {
        let state = GridState(
            config: config,
            spaces: cachedState.spaces,
            windows: cachedState.windows,
            displayBounds: cachedState.displayBounds,
            focusedIndex: cachedState.focusedIndex,
            displays: cachedState.displays
        )
        currentState = state
        dragHandler.cachedWindows = state.windows
        preloadIcons(for: state)
        renderState(state)
        updateCellFrames(state: state)
        lastFocusedSpaceIndex = state.focusedIndex
        dragHandler.start()
    }

    private func state(_ state: GridState, withFocusedIndex focusedIndex: Int?) -> GridState {
        GridState(
            config: state.config,
            spaces: state.spaces,
            windows: state.windows,
            displayBounds: state.displayBounds,
            focusedIndex: focusedIndex,
            displays: state.displays
        )
    }

    private func refreshFocusedWindowID() {
        YabaiClient.runOnYabaiQueue { [weak self] in
            let focusedWindowID = try? YabaiClient.queryFocusedWindow()
            DispatchQueue.main.async {
                guard let self, self.isVisible, let focusedWindowID else { return }
                self.dragHandler.focusedWindowIDAtOpen = focusedWindowID
            }
        }
    }

    private func preloadIcons(for state: GridState) {
        guard config.cellStyle == .icons || config.cellStyle == .hybrid || config.showIconStrip else { return }
        let visibleWindows = state.windows.filter {
            $0.shouldDisplay(
                showExtraWindows: config.showExtraWindows,
                ownerIsRegularApplication: IconCache.shared.isRegularApplication(
                    processIdentifier: $0.pid
                )
            )
        }
        IconCache.shared.preload(appNames: visibleWindows.map(\.app))
    }
    
    func hide() {
        guard isVisible else { 
            // Already hidden; do nothing
            return
        }
        NSLog("spacemap/HUD: hide() called")
        isPinned = false
        dragHandler.stop()
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        
        tearDownPanels()
        
        isVisible = false
        hoveredCell = nil
        currentState = nil
        isPollingFocusedSpace = false
        pendingFocusedSpaceIndex = nil
        pendingFocusDeadline = nil
        dragHandler.cellFrames = []
        dragHandler.cachedWindows = []
        dragHandler.focusedWindowIDAtOpen = nil
        stopSettingsKeyMonitor()
        stopPanelDragMonitor()
    }
    
    // Called by SocketListener — also handles full content refresh (windows moved etc.)
    func refresh() {
        guard isVisible else {
            refreshCachedFocus()
            return
        }
        resetAutoHideTimer()
        refreshState()
    }

    /// Keep the highlighted space current while the HUD is hidden without
    /// paying for a complete windows/displays refresh on every space signal.
    private func refreshCachedFocus() {
        guard let latestState else {
            prewarmState()
            return
        }
        YabaiClient.runOnYabaiQueue { [weak self] in
            let focusedIndex = YabaiClient.queryFocusedSpaceIndex()
            DispatchQueue.main.async {
                guard let self, !self.isVisible, let focusedIndex else { return }
                self.latestState = self.state(latestState, withFocusedIndex: focusedIndex)
            }
        }
    }
    
    private func refreshState() {
        guard isVisible else { return }
        // Debounce: cancel any in-flight work
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        isFetching = false  // allow fetchStateAndRender to re-fetch

        var workCancelled = false
        let work: DispatchWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let cfg = self.config
            let state = YabaiClient.buildGridState(config: cfg)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !workCancelled, self.isVisible else {
                    NSLog("spacemap/HUD: refreshState cancelled (stale)")
                    return
                }
                let displayedState = self.statePreservingPendingFocus(state)
                self.latestState = displayedState
                self.currentState = displayedState
                self.dragHandler.cachedWindows = displayedState.windows
                self.preloadIcons(for: displayedState)
                self.refreshAllThumbnails(state: displayedState)
                self.renderState(displayedState)
                self.updateCellFrames(state: displayedState)
                self.lastFocusedSpaceIndex = displayedState.focusedIndex
                NSLog("spacemap/HUD: refreshState complete, focused=\(displayedState.focusedIndex ?? -1)")
            }
        }
        work.notify(queue: .main) { [weak work] in
            if work?.isCancelled == true { workCancelled = true }
        }
        refreshWorkItem = work
        YabaiClient.runOnYabaiQueue(work)
    }
    
    private func renderState(_ state: GridState) {
        switch config.multiMonitorHUDMode {
        case .unified:
            renderUnifiedState(state)
        case .separate:
            renderSeparateStates(state)
        }
    }

    private func renderUnifiedState(_ state: GridState) {
        let gridView = makeGridView(state: state, hoveredCell: hoveredCell)
        let size = gridView.idealSize

        if config.unifiedHUDVisibility == .all {
            if let panel {
                panel.orderOut(nil)
                panel.close()
                self.panel = nil
                hostingView = nil
            }

            let displayIndices = state.populatedDisplayIndices
            let staleIndices = Set(displayPanels.keys).subtracting(displayIndices)
            for index in staleIndices {
                displayPanels[index]?.orderOut(nil)
                displayPanels[index]?.close()
                displayPanels[index] = nil
                displayHostingViews[index] = nil
            }

            for displayIndex in displayIndices {
                guard let screen = screen(forDisplay: displayIndex, in: state) else { continue }
                let panel: NSPanel
                if let existing = displayPanels[displayIndex] {
                    panel = existing
                } else {
                    panel = makePanel()
                    displayPanels[displayIndex] = panel
                }

                let hostingView = NSHostingView(rootView: AnyView(gridView))
                hostingView.frame = NSRect(origin: .zero, size: size)
                panel.contentView = hostingView
                displayHostingViews[displayIndex] = hostingView
                panel.setContentSize(size)
                panel.setFrameOrigin(config.hudPosition.point(for: size, screen: screen.frame))
                panel.orderFrontRegardless()
            }
            return
        }

        closeDisplayPanels()
        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        let hostingView = NSHostingView(rootView: AnyView(gridView))
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        self.hostingView = hostingView

        panel.setContentSize(size)
        let focusedScreen = state.focusedIndex
            .flatMap { state.displayIndex(forSpace: $0) }
            .flatMap { screen(forDisplay: $0, in: state) }
        if let screen = focusedScreen ?? NSScreen.main {
            panel.setFrameOrigin(config.hudPosition.point(for: size, screen: screen.frame))
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

        let displayIndices: [Int]
        if config.separateHUDVisibility == .active,
           let focusedIndex = state.focusedIndex,
           let focusedDisplayIndex = state.displayIndex(forSpace: focusedIndex) {
            displayIndices = [focusedDisplayIndex]
        } else {
            displayIndices = state.populatedDisplayIndices
        }
        let staleIndices = Set(displayPanels.keys).subtracting(displayIndices)
        for index in staleIndices {
            displayPanels[index]?.orderOut(nil)
            displayPanels[index]?.close()
            displayPanels[index] = nil
            displayHostingViews[index] = nil
        }

        for displayIndex in displayIndices {
            let spaces = state.spaces(forDisplay: displayIndex).map(\.index)
            guard !spaces.isEmpty else { continue }
            guard let screen = screen(forDisplay: displayIndex, in: state) else { continue }

            let panel: NSPanel
            if let existing = displayPanels[displayIndex] {
                panel = existing
            } else {
                panel = makePanel()
                displayPanels[displayIndex] = panel
            }

            let gridView = makeGridView(state: state, hoveredCell: hoveredCell, spaceIndices: spaces)
            let size = gridView.idealSize
            let hostingView = NSHostingView(rootView: AnyView(gridView))
            hostingView.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hostingView
            displayHostingViews[displayIndex] = hostingView
            panel.setContentSize(size)
            panel.setFrameOrigin(config.hudPosition.point(for: size, screen: screen.frame))
            panel.orderFrontRegardless()
        }
    }

    private func makeGridView(
        state: GridState,
        hoveredCell: Int?,
        spaceIndices: [Int]? = nil
    ) -> GridView {
        GridView(state: state, hoveredCell: hoveredCell, onSelect: { [weak self] index in
            YabaiClient.focusSpaceAsync(index)
            self?.hide()
        }, uiScale: config.uiScale, theme: config.theme, spaceIndices: spaceIndices)
    }

    private func updateCellFrames(state: GridState) {
        var frames: [(spaceIndex: Int, frame: CGRect)] = []
        switch config.multiMonitorHUDMode {
        case .unified:
            let cells = GridView.computeVisibleSpaceIndices(
                maxSpaces: config.maxSpaces,
                showMode: config.showMode,
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
        dragHandler.cellFrames = frames
    }

    private func cellFrames(for cells: [Int], in panel: NSPanel) -> [(spaceIndex: Int, frame: CGRect)] {
        guard !cells.isEmpty else { return [] }
        let scale = GridView.effectiveScale(for: config.uiScale)
        let cellWidth: CGFloat = 80 * scale
        let cellHeight: CGFloat = 50 * scale
        let gap: CGFloat = 6 * scale
        let padding: CGFloat = 12 * scale
        let slotWidth = cellWidth + gap
        let slotHeight = cellHeight + gap
        let cols = max(1, min(config.cols, cells.count))
        let rowCount = (cells.count + cols - 1) / cols
        let totalHeight = CGFloat(rowCount) * (cellHeight + gap) - gap + padding * 2
        let origin = panel.frame.origin

        return cells.enumerated().map { offset, spaceIndex in
            let row = offset / cols
            let col = offset % cols
            let x = origin.x + padding + CGFloat(col) * (cellWidth + gap) - gap / 2
            let appKitSlotTop = origin.y + totalHeight - padding - CGFloat(row) * (cellHeight + gap) - gap / 2
            let quartzY = quartzMainScreenFrame.maxY - appKitSlotTop
            return (spaceIndex, CGRect(x: x, y: quartzY, width: slotWidth, height: slotHeight))
        }
    }

    private func screen(forDisplay displayIndex: Int, in state: GridState) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        guard let yabaiDisplay = state.displays.first(where: { $0.index == displayIndex }) else {
            return screens.indices.contains(displayIndex - 1) ? screens[displayIndex - 1] : NSScreen.main
        }

        let yabaiFrame = yabaiDisplay.frame.cgFrame
        let appKitFrame = CGRect(
            x: yabaiFrame.minX,
            y: quartzMainScreenFrame.maxY - yabaiFrame.maxY,
            width: yabaiFrame.width,
            height: yabaiFrame.height
        )
        return screens.min { first, second in
            screenMatchScore(first.frame, targetFrame: appKitFrame) <
                screenMatchScore(second.frame, targetFrame: appKitFrame)
        }
    }

    private func screenMatchScore(_ screenFrame: CGRect, targetFrame: CGRect) -> CGFloat {
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

    private func tearDownPanels() {
        if let panel {
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
        hostingView = nil
        closeDisplayPanels()
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
        p.hasShadow = true
        return p
    }
    
    private func resetAutoHideTimer() {
        if isPanelDragging { return }
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard !isPinned else { return }
        if config.autoHideTimeout > 0 {
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.autoHideTimeout), repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }
    
    func reloadConfig() {
        _config = nil
    }

    private func refreshAllThumbnails(state: GridState, force: Bool = false) {
        guard #available(macOS 14.0, *) else { return }
        guard config.cellStyle == .thumbnails else { return }

        let visibleSpaceIndices: Set<Int>
        switch config.multiMonitorHUDMode {
        case .unified:
            visibleSpaceIndices = Set(GridView.computeVisibleSpaceIndices(
                maxSpaces: config.maxSpaces,
                showMode: config.showMode,
                activeIndices: Set(state.spaces.map(\.index))
            ))
        case .separate:
            visibleSpaceIndices = Set(state.spaces.map(\.index))
        }

        let cellScale = GridView.effectiveScale(for: config.uiScale)
        let backingScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let thumbnailPixelSize = CGSize(
            width: 80 * cellScale * backingScale,
            height: 50 * cellScale * backingScale
        )
        let requests = ThumbnailCache.captureRequests(
            for: state,
            spaceIndices: visibleSpaceIndices,
            thumbnailPixelSize: thumbnailPixelSize
        )

        ThumbnailCache.shared.refreshSpaces(requests, force: force)
    }

    private func startPanelDragMonitor() {
        guard panelDragMonitor == nil else { return }
        panelDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let panel = self.panel, self.isVisible else { return event }
            guard let window = panel.contentView?.window else { return event }
            let loc = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            guard panel.contentView?.bounds.contains(loc) == true else { return event }

            switch event.type {
            case .leftMouseDown:
                self.panelDragStart = NSEvent.mouseLocation
                self.panelDragOrigin = panel.frame.origin
                self.panelDragDidMove = false
                self.isPanelDragging = true
                // Cancel any timer already ticking — resetAutoHideTimer() only
                // prevents *new* timers from being scheduled while dragging;
                // it doesn't touch one already in flight from before the drag
                // started, which is what let the HUD hide itself mid-drag.
                self.autoHideTimer?.invalidate()
                self.autoHideTimer = nil
            case .leftMouseDragged:
                guard let start = self.panelDragStart,
                      let origin = self.panelDragOrigin else { break }
                let current = NSEvent.mouseLocation
                let dx = current.x - start.x
                let dy = current.y - start.y
                // Check if over a cell — if so, don't move panel
                let cgPoint = self.quartzPoint(fromAppKit: current)
                let overCell = self.dragHandler.cellFrames.contains { $0.frame.contains(cgPoint) }
                if !overCell {
                    var newOrigin = origin
                    newOrigin.x += dx
                    newOrigin.y += dy
                    panel.setFrameOrigin(newOrigin)
                    self.panelDragDidMove = true
                }
            case .leftMouseUp:
                if self.panelDragDidMove {
                    self.savePanelPosition()
                }
                self.panelDragStart = nil
                self.panelDragOrigin = nil
                self.panelDragDidMove = false
                // Drag has ended — allow the auto-hide timer to run again and
                // start it fresh now, rather than leaving it suppressed for
                // the rest of the HUD session.
                self.isPanelDragging = false
                self.resetAutoHideTimer()
            default: break
            }
            return event
        }
    }

    private func stopPanelDragMonitor() {
        if let monitor = panelDragMonitor {
            NSEvent.removeMonitor(monitor)
            panelDragMonitor = nil
        }
        panelDragStart = nil
        panelDragOrigin = nil
        panelDragDidMove = false
        isPanelDragging = false
    }

    private func savePanelPosition() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let panelFrame = panel.frame
        let x = Double((panelFrame.midX - screenFrame.minX) / screenFrame.width)
        let y = Double((panelFrame.midY - screenFrame.minY) / screenFrame.height)
        var config = ConfigReader.load()
        config.hudPosition = .custom(x: x, y: y)
        config.customHUDX = x
        config.customHUDY = y
        ConfigReader.saveConfig(config)
        NSLog("spacemap/HUD: saved custom position x=%.2f y=%.2f", x, y)
        NotificationCenter.default.post(name: Notification.Name("settingsChanged"), object: nil)
    }

    private func startSettingsKeyMonitor() {
        guard keyboardEventTap == nil else { return }
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HUDWindowController>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = controller.keyboardEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard controller.isVisible else { return Unmanaged.passUnretained(event) }
                if type == .keyDown {
                    controller.handleHUDKeyDown(event)
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("spacemap/HUD: keyboard capture event tap creation failed")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        keyboardEventTap = tap
        keyboardRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopSettingsKeyMonitor() {
        if let source = keyboardRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = keyboardEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        keyboardRunLoopSource = nil
        keyboardEventTap = nil
    }

    private func handleHUDKeyDown(_ event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if Self.isSettingsShortcut(keyCode: keyCode, flags: flags) {
            DispatchQueue.main.async { [weak self] in
                self?.hide()
                self?.onShowSettings?()
            }
            return
        }
        if let direction = Self.navigationDirection(
            keyCode: keyCode,
            flags: flags,
            useArrowKeys: config.useArrowKeys,
            useVimKeys: config.useVimKeys
        ) {
            DispatchQueue.main.async { [weak self] in
                self?.navigateSpace(direction)
            }
        }
    }

    static func isSettingsShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        keyCode == 43 && flags.contains(.maskCommand)
    }

    static func navigationDirection(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        useArrowKeys: Bool,
        useVimKeys: Bool
    ) -> SpaceNavigationDirection? {
        guard !flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate) else { return nil }
        if useArrowKeys {
            switch keyCode {
            case 123: return .left
            case 124: return .right
            case 125: return .down
            case 126: return .up
            default: break
            }
        }
        if useVimKeys {
            switch keyCode {
            case 38: return .down
            case 40: return .up
            case 37: return .right
            case 4: return .left
            default: break
            }
        }
        return nil
    }

    private func navigateSpace(_ direction: SpaceNavigationDirection) {
        guard let currentIdx = lastFocusedSpaceIndex, let state = currentState else { return }
        let target: Int?
        switch config.displayNavigationWrap {
        case .within:
            let sourceSpaces: [YabaiSpace]
            if let displayIndex = state.displayIndex(forSpace: currentIdx) {
                sourceSpaces = state.spaces(forDisplay: displayIndex)
            } else {
                sourceSpaces = state.spaces
            }
            let cells = SpaceNavigator.navigableSpaceIndices(
                activeSpaceIndices: sourceSpaces.map(\.index),
                maxSpaces: config.maxSpaces
            )
            target = SpaceNavigator.destination(
                from: currentIdx,
                visibleSpaceIndices: cells,
                columns: config.cols,
                direction: direction
            )
        case .between:
            target = SpaceNavigator.destinationAcrossDisplays(
                from: currentIdx,
                displaySpaceIndices: state.populatedDisplayIndices.map {
                    state.spaces(forDisplay: $0).map(\.index)
                },
                maxSpaces: config.maxSpaces,
                columns: config.cols,
                direction: direction
            )
        }
        guard let target else { return }

        NSLog("spacemap/HUD: navigate \(direction) from yabai=\(currentIdx) → target yabai=\(target)")
        pendingFocusedSpaceIndex = target
        pendingFocusDeadline = Date().addingTimeInterval(1)
        YabaiClient.focusSpaceAsync(target)
        lastFocusedSpaceIndex = target
        renderPendingFocus(target, in: state)
        resetAutoHideTimer()
    }

    private func handlePolledFocus(_ focusedIndex: Int?) {
        if let pending = pendingFocusedSpaceIndex {
            if focusedIndex == pending {
                pendingFocusedSpaceIndex = nil
                pendingFocusDeadline = nil
                refreshState()
                return
            }
            if pendingFocusDeadline.map({ Date() < $0 }) ?? false {
                // The focus command is still in flight. Ignore the stale result
                // so it cannot overwrite the optimistic selection.
                return
            }
            pendingFocusedSpaceIndex = nil
            pendingFocusDeadline = nil
        }

        if focusedIndex != lastFocusedSpaceIndex {
            NSLog("spacemap/HUD: poll detected change last=\(lastFocusedSpaceIndex ?? -1) current=\(focusedIndex ?? -1)")
            refreshState()
            resetAutoHideTimer()
        }
    }

    private func renderPendingFocus(_ focusedIndex: Int, in state: GridState) {
        let pendingState = GridState(
            config: state.config,
            spaces: state.spaces,
            windows: state.windows,
            displayBounds: state.displayBounds,
            focusedIndex: focusedIndex,
            displays: state.displays
        )
        currentState = pendingState
        switch config.multiMonitorHUDMode {
        case .unified:
            if let hostingView {
                hostingView.rootView = AnyView(makeGridView(state: pendingState, hoveredCell: hoveredCell))
            } else if !displayHostingViews.isEmpty {
                for hostingView in displayHostingViews.values {
                    hostingView.rootView = AnyView(makeGridView(state: pendingState, hoveredCell: hoveredCell))
                }
            } else {
                renderState(pendingState)
            }
        case .separate:
            guard !displayHostingViews.isEmpty else {
                renderState(pendingState)
                return
            }
            for (displayIndex, hostingView) in displayHostingViews {
                let spaces = pendingState.spaces(forDisplay: displayIndex).map(\.index)
                hostingView.rootView = AnyView(makeGridView(
                    state: pendingState,
                    hoveredCell: hoveredCell,
                    spaceIndices: spaces
                ))
            }
        }
    }

    private func statePreservingPendingFocus(_ state: GridState) -> GridState {
        guard let pending = pendingFocusedSpaceIndex else { return state }
        if state.focusedIndex == pending || !(pendingFocusDeadline.map { Date() < $0 } ?? false) {
            pendingFocusedSpaceIndex = nil
            pendingFocusDeadline = nil
            return state
        }
        return GridState(
            config: state.config,
            spaces: state.spaces,
            windows: state.windows,
            displayBounds: state.displayBounds,
            focusedIndex: pending,
            displays: state.displays
        )
    }
    
    /// AppKit uses a bottom-left origin; Quartz (and yabai's frames) use the
    /// top-left corner of the primary display as their global origin.
    private var quartzMainScreenFrame: CGRect {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainDisplayID
        }?.frame ?? NSScreen.screens.first?.frame ?? .zero
    }

    private func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: quartzMainScreenFrame.maxY - point.y)
    }
}
