import AppKit
import CoreGraphics

extension HUDInput {
    func startPollTimer() {
        pollTimer?.invalidate()
        pollTicks = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            // Reconcile Accessibility roughly every 3s. Revocation and
            // re-grant must recover while the HUD stays visible, and the
            // per-keystroke callback only reads the cached value.
            self.pollTicks += 1
            if self.pollTicks >= 6 {
                self.pollTicks = 0
                self.reconcileAccessibilityFromPoll()
            }
            guard !self.isPollingFocusedSpace else { return }
            self.isPollingFocusedSpace = true
            self.yabaiService?.runOnYabaiQueue { [weak self] in
                let focused = self?.yabaiService?.queryFocusedSpaceIndex()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isPollingFocusedSpace = false
                    guard self.isVisible else { return }
                    if focused != self.lastFocusedSpaceIndex {
                        self.onRefresh?()
                        self.onAutoHideActivity?()
                    }
                }
            }
        }
    }


    func navigate(direction: SpaceNavigationDirection) {
        guard let currentIdx = lastFocusedSpaceIndex, let state = currentState else { return }
        let target: Int?
        switch config?.displayNavigationWrap {
        case .within:
            let ss = state.displayIndex(forSpace: currentIdx).map { state.spaces(forDisplay: $0) } ?? state.spaces
            target = SpaceNavigator.destination(
                from: currentIdx,
                visibleSpaceIndices: SpaceNavigator.navigableSpaceIndices(
                    activeSpaceIndices: ss.map(\.index),
                    maxSpaces: config?.maxSpaces ?? 10
                ),
                columns: config?.cols ?? 8,
                direction: direction
            )
        case .between:
            target = SpaceNavigator.destinationAcrossDisplays(
                from: currentIdx,
                displaySpaceIndices: state.populatedDisplayIndices.map { state.spaces(forDisplay: $0).map(\.index) },
                maxSpaces: config?.maxSpaces ?? 10,
                columns: config?.cols ?? 8,
                direction: direction
            )
        case .none:
            target = nil
        }
        guard let target else { return }
        focus(space: target)
    }

    func navigateToFirst() { navigateToEdge { $0.first } }
    func navigateToLast() { navigateToEdge { $0.last } }
    func navigateToPreviousSpace() { navigateToAdjacentSpace(by: -1) }
    func navigateToNextSpace() { navigateToAdjacentSpace(by: 1) }

    /// Steps through the spaces the HUD shows, wrapping at either end so the
    /// last space leads to the first and the other way round.
    func navigateToAdjacentSpace(by offset: Int) {
        guard let visible = navigationSpaceIndices(), !visible.isEmpty,
              let current = lastFocusedSpaceIndex,
              let position = visible.firstIndex(of: current) else { return }
        let target = visible[(position + offset + visible.count) % visible.count]
        guard target != current else { return }
        focus(space: target)
    }

    func navigateToEdge(_ pick: ([Int]) -> Int?) {
        guard let visible = navigationSpaceIndices(), let target = pick(visible) else { return }
        focus(space: target)
    }

    /// Spaces in the order the HUD navigates them: the whole grid in unified
    /// mode, or the focused display's spaces in separate mode.
    func navigationSpaceIndices() -> [Int]? {
        guard let state = currentState else { return nil }
        switch state.config.multiMonitorHUDMode {
        case .unified:
            // An `.all` grid pads out to maxSpaces with cells for spaces that
            // do not exist yet; navigation must not land on one of those.
            return SpaceNavigator.navigableSpaceIndices(
                activeSpaceIndices: state.spaces.map(\.index),
                maxSpaces: state.config.maxSpaces
            )
        case .separate:
            guard let currentIdx = lastFocusedSpaceIndex,
                  let display = state.displayIndex(forSpace: currentIdx) else { return nil }
            return state.spaces(forDisplay: display).map(\.index)
        }
    }

    func focus(space index: Int) {
        yabaiService?.focusSpaceAsync(index)
        lastFocusedSpaceIndex = index
        if let optimistic = hudStateSync?.updateFocusedIndex(index) {
            currentState = optimistic
            hudDisplay?.updateState(optimistic)
        }
        onAutoHideActivity?()
        onFocusSpaceChanged?(index)
    }
}
