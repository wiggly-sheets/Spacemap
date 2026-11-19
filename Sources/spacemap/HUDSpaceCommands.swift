import Foundation

/// yabai space mutations. Each command owns its own settle polling and reports
/// a plain result on the main queue; presentation staleness is the caller's
/// concern, so nothing here knows about the HUD or its generations.
final class HUDSpaceCommands {
    private let yabaiService: YabaiService
    /// Polls stop when the presentation that started a command ends. The
    /// controller supplies the factory; commands never see a generation.
    private let makeShouldContinue: () -> (() -> Bool)
    /// yabai applies space changes asynchronously, so creation and destruction
    /// are confirmed by polling rather than trusted on return.
    private static let pollInterval: TimeInterval = 0.1
    private static let maxPollAttempts = 20

    init(
        yabaiService: YabaiService,
        makeShouldContinue: @escaping () -> (() -> Bool) = { { true } }
    ) {
        self.yabaiService = yabaiService
        self.makeShouldContinue = makeShouldContinue
    }

    // MARK: - Create

    /// Creates a space without stealing focus. Reports the new index, or nil
    /// when the space never appeared.
    func createSpace(completion: @escaping (Int?) -> Void) {
        // Plain create never steals focus — only createAndFocus does.
        // beforeMax is read on yabaiQueue before the create is enqueued:
        // createSpace() runs async on focusQueue, so the snapshot is still
        // pre-create without blocking the main thread on a yabai query.
        let shouldContinue = makeShouldContinue()
        yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            let beforeMax = (try? self.yabaiService.querySpaces())?.map(\.index).max()
            self.yabaiService.createSpace()
            self.pollForNewestSpace(
                beforeMax: beforeMax,
                attempts: 0,
                focus: false,
                shouldContinue: shouldContinue,
                completion: completion
            )
        }
    }

    /// Creates a space and focuses it once it exists.
    func createAndFocusNewestSpace(completion: @escaping (Int?) -> Void) {
        let shouldContinue = makeShouldContinue()
        yabaiService.runOnYabaiQueue { [weak self] in
            guard let self else { return }
            let beforeMax = (try? self.yabaiService.querySpaces())?.map(\.index).max()
            self.yabaiService.createSpace()
            self.pollForNewestSpace(
                beforeMax: beforeMax,
                attempts: 0,
                focus: true,
                shouldContinue: shouldContinue,
                completion: completion
            )
        }
    }

    private func pollForNewestSpace(
        beforeMax: Int?,
        attempts: Int,
        focus: Bool,
        shouldContinue: @escaping () -> Bool,
        completion: @escaping (Int?) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            guard let self, shouldContinue() else { return }
            self.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self else { return }
                if let maxNow = (try? self.yabaiService.querySpaces())?.map(\.index).max(),
                   beforeMax.map({ maxNow > $0 }) ?? true {
                    // Async: sync focus blocks yabai queue up to 10s.
                    // Same focusQueue as createSpace keeps focus ordered after create.
                    if focus { self.yabaiService.focusSpaceAsync(maxNow) }
                    DispatchQueue.main.async { completion(maxNow) }
                    return
                }
                guard attempts + 1 < Self.maxPollAttempts else {
                    NSLog("spacemap/HUD: createAndFocus timed out waiting for new space")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                self.pollForNewestSpace(
                    beforeMax: beforeMax,
                    attempts: attempts + 1,
                    focus: focus,
                    shouldContinue: shouldContinue,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Destroy

    /// Destroys a space, then waits for yabai to drop it and focuses the space
    /// before it, so the user's place survives yabai's fallback to space 1.
    func destroySpace(_ index: Int, previous: Int?, completion: @escaping () -> Void) {
        let shouldContinue = makeShouldContinue()
        yabaiService.destroySpace(index)
        waitForDestroy(index, previous: previous, attempts: 0, shouldContinue: shouldContinue, completion: completion)
    }

    private func waitForDestroy(
        _ destroyed: Int,
        previous: Int?,
        attempts: Int,
        shouldContinue: @escaping () -> Bool,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            guard let self, shouldContinue() else { return }
            self.yabaiService.runOnYabaiQueue { [weak self] in
                guard let self else { return }
                let indices = (try? self.yabaiService.querySpaces())?.map(\.index) ?? []
                if !indices.contains(destroyed) {
                    if let previous, indices.contains(previous) {
                        self.yabaiService.focusSpaceAsync(previous)
                    }
                    DispatchQueue.main.async { completion() }
                    return
                }
                guard attempts + 1 < Self.maxPollAttempts else {
                    DispatchQueue.main.async { completion() }
                    return
                }
                self.waitForDestroy(
                    destroyed,
                    previous: previous,
                    attempts: attempts + 1,
                    shouldContinue: shouldContinue,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Layout and move

    func setLayout(_ layout: SpaceLayout) {
        yabaiService.setSpaceLayout(layout)
    }

    /// Next layout in the HUD's cycle. Unknown types restart the cycle.
    func cycleLayout(from currentType: String) -> SpaceLayout {
        switch currentType {
        case "stack": return .float
        case "float": return .bsp
        default: return .stack
        }
    }

    /// Swaps the focused space with its neighbour in `direction`. Returns the
    /// moved index, or nil when the space is already at the end.
    func moveSpace(
        focusedIndex: Int?,
        indices: [Int],
        direction: SpaceNavigationDirection,
        mode: SpaceDropMode
    ) -> Int? {
        let sorted = indices.sorted()
        guard let focusedIndex, let position = sorted.firstIndex(of: focusedIndex) else { return nil }
        let offset = direction == .left ? -1 : 1
        guard sorted.indices.contains(position + offset) else { return nil }
        yabaiService.swapSpaces(focusedIndex, sorted[position + offset], mode: mode, focusMode: .stay)
        return focusedIndex
    }
}
