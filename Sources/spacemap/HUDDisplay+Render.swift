import AppKit
import SwiftUI

extension HUDDisplay {
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
    func clearThumbnailsIfNeeded() {
        guard showingThumbnails else { return }
        showingThumbnails = false
        guard #available(macOS 14.0, *) else { return }
        // Both sides are main in the HUD path; clear synchronously so a new
        // refresh queued in the same turn cannot be cancelled by a late task.
        ThumbnailCache.shared.clear()
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


    func renderUnifiedState(_ state: GridState) {
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

    func renderSeparateStates(_ state: GridState) {
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
}
