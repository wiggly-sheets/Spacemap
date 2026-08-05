import AppKit
import SwiftUI

/// Delegate for HUDDisplay to report visual state changes.
protocol HUDDisplayDelegate: AnyObject {
    func render(state: GridState)
    func updateCellFrames(state: GridState)
    func show()
    func hide()
}

/// Owns NSPanel lifecycle, unified vs separate display modes, cell frame computation, thumbnail preloading.
final class HUDDisplay {
    weak var delegate: HUDDisplayDelegate?

    private var panel: NSPanel?
    private var displayPanels: [Int: NSPanel] = [:]
    private var hostingView: NSHostingView<AnyView>?
    private var displayHostingViews: [Int: NSHostingView<AnyView>] = [:]
    private var currentConfig: GridConfig = .default
    private var hoveredCell: Int? = nil
    private var yabaiService: YabaiService

    var unifiedPanel: NSPanel? { panel }

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService
    }

    func updateConfig(_ config: GridConfig) {
        currentConfig = config
    }

    func updateHoveredCell(_ cell: Int?) {
        hoveredCell = cell
    }

    func show() {
        delegate?.show()
    }

    func hide() {
        tearDownPanels()
        delegate?.hide()
    }

    func updateState(_ state: GridState) {
        currentConfig = state.config
        let gridView = makeGridView(state: state, hoveredCell: hoveredCell)
        if let hostingView {
            hostingView.rootView = AnyView(gridView)
        } else if !displayHostingViews.isEmpty {
            for (displayIndex, hostingView) in displayHostingViews {
                let mode = currentConfig.multiMonitorHUDMode.hudMode(for: displayIndex, in: state)
                if mode == .unified {
                    hostingView.rootView = AnyView(makeGridView(state: state, hoveredCell: hoveredCell))
                } else {
                    let spaces = state.spaces(forDisplay: displayIndex).map(\.index)
                    hostingView.rootView = AnyView(makeGridView(state: state, hoveredCell: hoveredCell, spaceIndices: spaces))
                }
            }
        } else {
            render(state: state)
        }
    }

    func render(state: GridState) {
        currentConfig = state.config
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
        delegate?.updateCellFrames(state: state)
    }

    func preloadIcons(for state: GridState) {
        guard currentConfig.cellStyle == .icons || currentConfig.cellStyle == .hybrid || currentConfig.showIconStrip else { return }
        let visibleWindows = state.windows.filter {
            $0.shouldDisplay(showExtraWindows: currentConfig.showExtraWindows)
        }
        IconCache.shared.preload(appNames: visibleWindows.map(\.app))
    }

    func refreshThumbnails(state: GridState, force: Bool = false) {
        guard #available(macOS 14.0, *) else { return }
        guard currentConfig.cellStyle == .thumbnails else { return }

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
        let requests = ThumbnailCache.captureRequests(
            for: state,
            spaceIndices: visibleSpaceIndices,
            thumbnailPixelSize: thumbnailPixelSize
        )

        ThumbnailCache.shared.refreshSpaces(requests, force: force)
    }

    func savePanelPosition() {
        guard let panel = unifiedPanel ?? displayPanels.first?.value, let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let panelFrame = panel.frame
        let x = Double((panelFrame.midX - screenFrame.minX) / screenFrame.width)
        let y = Double((panelFrame.midY - screenFrame.minY) / screenFrame.height)
        var config = Config.load()
        config.hudPosition = .custom(x: x, y: y)
        config.customHUDX = x
        config.customHUDY = y
        Config.saveConfig(config)
        NSLog("spacemap/HUDDisplay: saved custom position x=%.2f y=%.2f", x, y)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    // MARK: - Prewarm & refresh-render

    func prewarm(state: GridState) {
        preloadIcons(for: state)
        refreshThumbnails(state: state, force: true)
    }

    func refreshAndRender(state: GridState, force: Bool) {
        preloadIcons(for: state)
        refreshThumbnails(state: state, force: force)
        render(state: state)
        updateCellFrames(state: state)
    }

    // MARK: - Private rendering

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
                panel.setFrameOrigin(currentConfig.hudPosition.point(for: size, screen: screen.frame))
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
            panel.setFrameOrigin(currentConfig.hudPosition.point(for: size, screen: screen.frame))
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
        if currentConfig.separateHUDVisibility == .active,
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
            panel.setFrameOrigin(currentConfig.hudPosition.point(for: size, screen: screen.frame))
            panel.orderFrontRegardless()
        }
    }

    private func makeGridView(
        state: GridState,
        hoveredCell: Int?,
        spaceIndices: [Int]? = nil
    ) -> GridView {
        GridView(state: state, hoveredCell: hoveredCell, onSelect: { [weak self] index in
            self?.yabaiService.focusSpaceAsync(index)
            self?.delegate?.hide()
        }, uiScale: currentConfig.uiScale, theme: currentConfig.theme, spaceIndices: spaceIndices)
    }

    private func cellFrames(for cells: [Int], in panel: NSPanel) -> [(spaceIndex: Int, frame: CGRect)] {
        guard !cells.isEmpty else { return [] }
        let cols = max(1, min(currentConfig.cols, cells.count))
        let gridLocalFrames = GridLayout.cellFrames(count: cells.count, cols: cols, uiScale: currentConfig.uiScale)
        let origin = panel.frame.origin
        let quartzMaxY = quartzMainScreenFrame.maxY
        let panelMaxY = origin.y + panel.frame.height

        return cells.enumerated().map { offset, spaceIndex in
            var gridLocal = gridLocalFrames[offset]
            gridLocal.origin.x += origin.x
            gridLocal.origin.y = quartzMaxY - panelMaxY + gridLocal.origin.y + gridLocal.height
            return (spaceIndex, gridLocal)
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

    private var quartzMainScreenFrame: CGRect {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainDisplayID
        }?.frame ?? NSScreen.screens.first?.frame ?? .zero
    }

    func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: quartzMainScreenFrame.maxY - point.y)
    }
}
