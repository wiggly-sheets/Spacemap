import Foundation
import AppKit

extension YabaiClientImpl {
    func moveFocusedWindow(toSpace index: Int) {
        moveWindows([], toSpace: index)
    }

    func moveWindows(_ windowIDs: [Int], toSpace index: Int) {
        guard index > 0 else { return }
        // An empty list means "the focused window", which is yabai's default target.
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            if windowIDs.isEmpty {
                self.runIgnoringFailure(["-m", "window", "--space", "\(index)"], "moveFocusedWindow")
                return
            }
            for windowID in windowIDs {
                self.runIgnoringFailure(
                    ["-m", "window", "\(windowID)", "--space", "\(index)"],
                    "moveWindow(\(windowID))"
                )
            }
        }
    }

    func moveWindows(_ windowIDs: [Int], toSpace index: Int, focusMode: DragFocusMode, sourceSpace: Int?) {
        guard index > 0 else { return }
        // An empty list means "the focused window", which is yabai's default target.
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            if windowIDs.isEmpty {
                self.runIgnoringFailure(["-m", "window", "--space", "\(index)"], "moveFocusedWindow")
            } else {
                for windowID in windowIDs {
                    self.runIgnoringFailure(
                        ["-m", "window", "\(windowID)", "--space", "\(index)"],
                        "moveWindow(\(windowID))"
                    )
                }
            }
            switch focusMode {
            case .destination:
                _ = try? self.shell(self.yabaiPath, "-m", "space", "--focus", "\(index)")
            case .source:
                if let sourceSpace, sourceSpace > 0 {
                    _ = try? self.shell(self.yabaiPath, "-m", "space", "--focus", "\(sourceSpace)")
                }
            case .stay:
                if let sourceSpace, sourceSpace > 0 {
                    _ = try? self.shell(self.yabaiPath, "-m", "space", "--focus", "\(sourceSpace)")
                }
            }
        }
    }

    func toggleWindowFullscreen() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "window", "--toggle", "native-fullscreen"], "toggleFullscreen")
        }
    }

    func balanceWindows() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--balance"], "balanceWindows")
        }
    }

    func toggleWindowFloat() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "window", "--toggle", "float"], "toggleFloat")
        }
    }

    func showSpacemap() {
        do { try SpacemapCommand.show.send() } catch { fputs("spacemap: \(error)\n", stderr) }
    }


    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        yabaiQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard targetIndex > 0 else {
                    throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                }

                let budget = self.spaceCreationBudget
                guard budget > 0 else {
                    throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                }
                let deadline = self.currentUptime + budget

                func remainingBudget() throws -> TimeInterval {
                    let remaining = deadline - self.currentUptime
                    guard remaining > 0 else {
                        throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                    }
                    return min(remaining, YabaiClientImpl.commandTimeout)
                }

                func querySpacesWithinBudget() throws -> [YabaiSpace] {
                    let timeout = try remainingBudget()
                    do {
                        return try self.querySpacesRaw(timeout: timeout)
                    } catch YabaiError.commandTimedOut(_, _) {
                        throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                    }
                }

                func runWithinBudget(_ arguments: [String]) throws -> String {
                    let timeout = try remainingBudget()
                    do {
                        return try self.shell([self.yabaiPath] + arguments, timeout: timeout)
                    } catch YabaiError.commandTimedOut(_, _) {
                        throw YabaiError.spaceCreationTimedOut(target: targetIndex, budget: budget)
                    }
                }

                var spaces = try querySpacesWithinBudget()
                var attempts = 0
                while !spaces.contains(where: { $0.index == targetIndex }) {
                    guard attempts < 16 else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                    attempts += 1
                    let previousIndices = Set(spaces.map(\.index))
                    guard self.yabaiIsExecutable else {
                        throw YabaiError.commandFailed(arguments: ["space", "--create"], status: -1, message: "yabai not found")
                    }
                    _ = try runWithinBudget(["-m", "space", "--create"])
                    self.invalidateSnapshotCaches()
                    spaces = try querySpacesWithinBudget()

                    guard Set(spaces.map(\.index)) != previousIndices else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                }

                guard self.yabaiIsExecutable else {
                    throw YabaiError.commandFailed(arguments: ["window", "\(windowID)", "--space", "\(targetIndex)"], status: -1, message: "yabai not found")
                }
                _ = try runWithinBudget(["-m", "window", "\(windowID)", "--space", "\(targetIndex)"])
                if focusDestination {
                    _ = try runWithinBudget(["-m", "space", "--focus", "\(targetIndex)"])
                }
                self.invalidateSnapshotCaches()
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }


}
