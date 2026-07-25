import AppKit
import SwiftUI

class HUDWindowController {
    private var panel: NSPanel?
    private var isVisible = false
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
    private var autoHideTimer: Timer?
    private var pollTimer: Timer?
    private let dragHandler = WindowDragHandler()
    private var lastFocusedSpaceIndex: Int? = nil
    private var isToggling = false   // prevents re-entry during toggle animations
    private var hostingView: NSHostingView<GridView>?
    var onShowSettings: (() -> Void)?
    private var settingsKeyMonitor: Any?
    // Panel drag state for custom position mode
    private var panelDragMonitor: Any?
    private var panelDragStart: CGPoint?   // initial mouse location on drag start
    private var panelDragDidMove = false
    private var panelDragOffset: CGPoint?  // not used maybe
    private var panelDragOrigin: CGPoint?  // initial panel origin on drag start
    private var isPanelDragging = false
    private var refreshWorkItem: DispatchWorkItem?
    private var isFetching = false  // prevents concurrent fetches
    
    init() {
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, isVisible, let state = currentState else { return }
            hoveredCell = cell
            if let p = panel { renderState(state, panel: p) }
            self.resetAutoHideTimer()
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex in
            guard let self else { return }
            YabaiClient.moveWindow(windowID, toSpace: spaceIndex)
            hoveredCell = nil
            refreshState()
            resetAutoHideTimer()
        }
    }
    
    func toggle() {
        guard !isToggling else { 
            NSLog("spacemap/HUD: toggle ignored, isToggling=\(isToggling)")
            return 
        }
        NSLog("spacemap/HUD: toggle called, isVisible=\(isVisible)")
        isToggling = true
        if isVisible { hide() } else { show() }
        // Reset isToggling after a short delay to allow for animation settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggling = false
        }
    }
    
    func show() {
        guard !isVisible else { return }
        // Tear down any orphaned panel before creating new one
        if let existing = panel {
            existing.orderOut(nil)
            existing.close()
            panel = nil
            hostingView = nil
        }
        NSLog("spacemap/HUD: show() called")
        reloadConfig()
        
        panel = makePanel()
        guard let panel else { return }
        
        // Show panel immediately with empty state — don't block main
        isVisible = true
        renderEmptyState(panel: panel)
        resetAutoHideTimer()
        startPollTimer()
        startSettingsKeyMonitor()
        if case .custom = config.hudPosition { startPanelDragMonitor() }
        
        // Fetch data in background, update UI when ready
        fetchStateAndRender(panel: panel)
    }
    
    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            // Dispatch query off main — pgrep can block briefly
            YabaiClient.runOnYabaiQueue {
                let focused = YabaiClient.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isVisible else { return }
                    if focused != self.lastFocusedSpaceIndex {
                        NSLog("spacemap/HUD: poll detected change last=\(self.lastFocusedSpaceIndex ?? -1) current=\(focused ?? -1)")
                        self.refreshState()
                        self.resetAutoHideTimer()
                    }
                }
            }
        }
    }
    
    private func fetchStateAndRender(panel: NSPanel) {
        // Cancel any pending work and mark as fetching so refreshState can't race
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        isFetching = true
        let cfg = config
        var workCancelled = false
        let work: DispatchWorkItem = DispatchWorkItem { [weak self] in
            let state = YabaiClient.buildGridState(config: cfg)
            let focusedWindowID = try? YabaiClient.queryFocusedWindow()
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
                self.currentState = state
                self.dragHandler.cachedWindows = state.windows
                if let fid = focusedWindowID {
                    self.dragHandler.focusedWindowIDAtOpen = fid
                }
                self.refreshThumbnailCache(state: state)
                self.renderState(state, panel: panel)
                self.updateCellFrames(state: state, panel: panel)
                self.lastFocusedSpaceIndex = state.focusedIndex
                self.dragHandler.start()
                NSLog("spacemap/HUD: fetchStateAndRender complete, focused=\(state.focusedIndex ?? -1), spaces=\(state.spaces.count), windows=\(state.windows.count)")
            }
        }
        work.notify(queue: .main) { [weak work] in
            if work?.isCancelled == true { workCancelled = true }
        }
        refreshWorkItem = work
        YabaiClient.runOnYabaiQueue(work)
    }

    private func renderEmptyState(panel: NSPanel) {
        let emptyState = GridState(
            config: config,
            spaces: [],
            windows: [],
            displayBounds: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440),
            focusedIndex: nil
        )
        renderState(emptyState, panel: panel)
    }
    
    func hide() {
        guard isVisible else { 
            // Already hidden; do nothing
            return
        }
        NSLog("spacemap/HUD: hide() called")
        dragHandler.stop()
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        
        if let p = panel {
            p.orderOut(nil)
            p.close()
        }
        panel = nil
        hostingView = nil
        
        isVisible = false
        hoveredCell = nil
        currentState = nil
        dragHandler.cellFrames = []
        dragHandler.cachedWindows = []
        dragHandler.focusedWindowIDAtOpen = nil
        stopSettingsKeyMonitor()
        stopPanelDragMonitor()
    }
    
    // Called by SocketListener — also handles full content refresh (windows moved etc.)
    func refresh() {
        guard isVisible, panel != nil else { return }
        resetAutoHideTimer()
        refreshState()
    }
    
    private func refreshState() {
        guard isVisible, let panel else { return }
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
                self.currentState = state
                self.dragHandler.cachedWindows = state.windows
                self.refreshThumbnailCache(state: state)
                self.renderState(state, panel: panel)
                self.updateCellFrames(state: state, panel: panel)
                self.lastFocusedSpaceIndex = state.focusedIndex
                NSLog("spacemap/HUD: refreshState complete, focused=\(state.focusedIndex ?? -1)")
            }
        }
        work.notify(queue: .main) { [weak work] in
            if work?.isCancelled == true { workCancelled = true }
        }
        refreshWorkItem = work
        YabaiClient.runOnYabaiQueue(work)
    }
    
    private func renderState(_ state: GridState, panel: NSPanel) {
        let hovered = hoveredCell
        let gridView = GridView(state: state, hoveredCell: hovered, onSelect: { [weak self] index in
            YabaiClient.focusSpaceAsync(index)
            self?.hide()
        }, uiScale: config.uiScale, theme: config.theme)
        let size = gridView.idealSize
        
        let hv = NSHostingView(rootView: gridView)
        hv.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hv
        hostingView = hv
        
        panel.setContentSize(size)
        
        if let screen = NSScreen.main {
            let pos = config.hudPosition.point(for: size, screen: screen.frame)
            panel.setFrameOrigin(pos)
        }
        
        panel.orderFrontRegardless()
    }
    
    private func updateCellFrames(state: GridState, panel: NSPanel) {
        let scale = config.uiScale
        let cellWidth: CGFloat = 80 * scale * 3
        let cellHeight: CGFloat = 50 * scale * 3
        let gap: CGFloat = 6 * scale * 3
        let padding: CGFloat = 12 * scale * 3
        let slotWidth = cellWidth + gap
        let slotHeight = cellHeight + gap
        
        // Compute visible cells same as GridView
        let maxN = min(config.maxSpaces, 16)
        let all = (1...maxN).map { $0 }
        let cells: [Int]
        if config.showMode == .active {
            let activeSet = Set(state.spaces.map { $0.index })
            cells = all.filter { activeSet.contains($0) }
        } else {
            cells = all
        }
        
        let cols = min(config.cols, cells.count)
        let rowCount = (cells.count + cols - 1) / cols
        
        var frames: [(spaceIndex: Int, frame: CGRect)] = []
        let origin = panel.frame.origin
        let totalHeight = CGFloat(rowCount) * (cellHeight + gap) - gap + padding * 2
        
        for (i, spaceIndex) in cells.enumerated() {
            let row = i / cols
            let col = i % cols
            let x = origin.x + padding + CGFloat(col) * (cellWidth + gap) - gap / 2
            let appKitSlotTop = origin.y + totalHeight - padding - CGFloat(row) * (cellHeight + gap) - gap / 2
            let cgY = screenHeight - appKitSlotTop
            frames.append((spaceIndex: spaceIndex, frame: CGRect(x: x, y: cgY, width: slotWidth, height: slotHeight)))
        }
        
        dragHandler.cellFrames = frames
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
        if config.autoHideTimeout > 0 {
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.autoHideTimeout), repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }
    
    func reloadConfig() {
        _config = nil
    }

    private func refreshThumbnailCache(state: GridState) {
        guard #available(macOS 14.0, *) else { return }
        guard config.cellStyle == .thumbnails else { return }
        guard let focusedIndex = state.focusedIndex else { return }
        ThumbnailCache.shared.captureActiveSpace(spaceIndex: focusedIndex)
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
                let cgPoint = CGPoint(x: current.x, y: NSScreen.main!.frame.height - current.y)
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
        let configPath = NSString(string: "~/.config/spacemap/config").expandingTildeInPath
        guard var text = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }
        if let range = text.range(of: "HUD_POSITION=") {
            let lineStart = range.lowerBound
            var lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            if lineEnd < text.endIndex { lineEnd = text.index(after: lineEnd) }
            text.replaceSubrange(lineStart..<lineEnd, with: "HUD_POSITION=custom\n")
        } else {
            text += "\nHUD_POSITION=custom\n"
        }
        // Also update CUSTOM_HUD_X and CUSTOM_HUD_Y for SettingsView persistence
        let xString = String(x)
        let yString = String(y)
        if let range = text.range(of: "CUSTOM_HUD_X=") {
            let lineStart = range.lowerBound
            var lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            if lineEnd < text.endIndex { lineEnd = text.index(after: lineEnd) }
            text.replaceSubrange(lineStart..<lineEnd, with: "CUSTOM_HUD_X=\(xString)\n")
        } else {
            text += "\nCUSTOM_HUD_X=\(xString)\n"
        }
        if let range = text.range(of: "CUSTOM_HUD_Y=") {
            let lineStart = range.lowerBound
            var lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            if lineEnd < text.endIndex { lineEnd = text.index(after: lineEnd) }
            text.replaceSubrange(lineStart..<lineEnd, with: "CUSTOM_HUD_Y=\(yString)\n")
        } else {
            text += "\nCUSTOM_HUD_Y=\(yString)\n"
        }
        do {
            try text.write(toFile: configPath, atomically: true, encoding: .utf8)
            NSLog("spacemap/HUD: saved custom position x=%.2f y=%.2f", x, y)
            // Notify any observers (e.g., SettingsView) that the config has changed
            NotificationCenter.default.post(name: Notification.Name("settingsChanged"), object: nil)
        } catch {
            NSLog("spacemap/HUD: failed to write config: \(error)")
        }
    }

    private func startSettingsKeyMonitor() {
        settingsKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return }
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
                DispatchQueue.main.async {
                    self.hide()
                    self.onShowSettings?()
                }
                return
            }
            let code = UInt16(event.keyCode)
            let mods = event.modifierFlags
            let noModifiers = !mods.contains(.control) && !mods.contains(.command) && !mods.contains(.option)
            var dir: Direction? = nil
            if config.useArrowKeys && noModifiers {
                switch code {
                case 123: dir = .left
                case 124: dir = .right
                case 125: dir = .down
                case 126: dir = .up
                default: break
                }
            }
            if dir == nil && config.useVimKeys && noModifiers {
                switch code {
                case 38: dir = .down   // j
                case 40: dir = .up     // k
                case 37: dir = .right  // l
                case 4:  dir = .left   // h
                default: break
                }
            }
            if let d = dir {
                self.navigateSpace(d)
            }
        }
    }

    private func stopSettingsKeyMonitor() {
        if let monitor = settingsKeyMonitor {
            NSEvent.removeMonitor(monitor)
            settingsKeyMonitor = nil
        }
    }

    private enum Direction { case left, right, up, down }

    private func navigateSpace(_ direction: Direction) {
        guard let currentIdx = lastFocusedSpaceIndex else { return }
        let cols = config.cols
        let maxN = min(config.maxSpaces, 16)
        
        // Build visible cell array (same logic as GridView)
        let all = (1...maxN).map { $0 }
        let cells: [Int]
        if config.showMode == .active {
            let activeSet = Set(currentState?.spaces.map { $0.index } ?? [])
            cells = all.filter { activeSet.contains($0) }
        } else {
            cells = all
        }
        guard !cells.isEmpty else { return }
        
        guard let pos = cells.firstIndex(of: currentIdx) else {
            // Current not in visible list — navigate from first
            let target = cells[0]
            YabaiClient.focusSpaceAsync(target)
            lastFocusedSpaceIndex = target
            resetAutoHideTimer()
            return
        }
        
        let rowCount = (cells.count + cols - 1) / cols
        let col = pos % cols
        let row = pos / cols
        var targetIdx: Int? = nil
        
        switch direction {
        case .left:
            if col > 0 {
                targetIdx = cells[pos - 1]
            } else {
                // Wrap to end of same row, or previous row end
                targetIdx = cells[pos + min(cols - 1, cells.count - 1 - row * cols)]
            }
        case .right:
            let rowEnd = min((row + 1) * cols - 1, cells.count - 1)
            if col < cols - 1 && pos < rowEnd {
                targetIdx = cells[pos + 1]
            } else {
                // Wrap to start of same row
                targetIdx = cells[row * cols]
            }
        case .up:
            var newRow = row - 1
            let newCol = col
            if newRow < 0 { newRow = rowCount - 1 }
            let newPos = newRow * cols + newCol
            if newPos < cells.count {
                targetIdx = cells[newPos]
            }
        case .down:
            var newRow = row + 1
            let newCol = col
            if newRow >= rowCount { newRow = 0 }
            let newPos = newRow * cols + newCol
            if newPos < cells.count {
                targetIdx = cells[newPos]
            } else {
                targetIdx = cells[newRow * cols]
            }
        }
        
        guard let t = targetIdx else { return }
        YabaiClient.focusSpaceAsync(t)
        lastFocusedSpaceIndex = t
        resetAutoHideTimer()
    }
    
    private var screenHeight: CGFloat {
        NSScreen.main?.frame.height ?? 0
    }
}
