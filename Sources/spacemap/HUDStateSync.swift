import Foundation

/// Clean interface wrapping GridStateCoordinator, hiding internal phase/generation/pendingFocus details.
protocol HUDStateSync {
    var currentState: GridState? { get }
    var focusedIndex: Int? { get }
    func updateFocusedIndex(_ index: Int) -> GridState?
    func fetch(completion: @escaping () -> Void)
    func refresh(completion: @escaping () -> Void)
    func clearPendingFocus()
    func cancelPendingFetch()
    func reloadConfig()
}

final class DefaultHUDStateSync: HUDStateSync {
    let coordinator: GridStateCoordinator

    init(coordinator: GridStateCoordinator) {
        self.coordinator = coordinator
    }

    var currentState: GridState? {
        coordinator.state
    }

    var focusedIndex: Int? {
        coordinator.state?.focusedIndex
    }

    func updateFocusedIndex(_ index: Int) -> GridState? {
        coordinator.updateFocusedIndex(index)
    }

    func fetch(completion: @escaping () -> Void) {
        coordinator.fetch(completion: completion)
    }

    func refresh(completion: @escaping () -> Void) {
        coordinator.refresh(completion: completion)
    }

    func clearPendingFocus() {
        coordinator.clearPendingFocus()
    }

    func cancelPendingFetch() {
        coordinator.cancelPendingFetch()
    }

    func reloadConfig() {
        coordinator.reloadConfig()
    }
}
