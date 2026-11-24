import Foundation
import AppKit

extension YabaiClientImpl {
    func focusSpace(_ index: Int) {
        guard yabaiIsExecutable, isYabaiRunning() else { return }
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)")
        invalidateSnapshotCaches()
    }

    @discardableResult
    func focusSpace(_ target: SpaceFocusTarget) -> Bool {
        guard yabaiIsExecutable, isYabaiRunning() else { return false }
        defer { invalidateSnapshotCaches() }
        do {
            _ = try shell(yabaiPath, "-m", "space", "--focus", target.value)
            return true
        } catch {
            fputs("spacemap: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    func focusSpaceAsync(_ index: Int) {
        focusQueue.async { [weak self] in
            guard let self = self, self.yabaiIsExecutable, self.isYabaiRunning() else { return }
            _ = try? self.shell(yabaiPath, "-m", "space", "--focus", "\(index)")
            self.invalidateSnapshotCaches()
        }
    }


    struct SpaceSwapStep: Equatable {
        let windowID: Int
        let target: Int
    }

    /// Each window moves to the opposite space. IDs are captured before any
    /// move so a window never gets moved twice.
    static func spaceSwapPlan(windows: [YabaiWindow], first: Int, second: Int) -> [SpaceSwapStep] {
        let fromFirst = windows.filter { $0.space == first }
            .map { SpaceSwapStep(windowID: $0.id, target: second) }
        let fromSecond = windows.filter { $0.space == second }
            .map { SpaceSwapStep(windowID: $0.id, target: first) }
        return fromFirst + fromSecond
    }

    func swapSpaces(_ first: Int, _ second: Int, mode: SpaceDropMode, focusMode: DragFocusMode) {
        guard first > 0, second > 0, first != second else { return }
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable, self.isYabaiRunning() else { return }
            switch mode {
            case .content: self.swapSpaceContents(first, second, focusMode: focusMode)
            case .spaces: self.moveSpaces(first, second, focusMode: focusMode)
            }
            self.invalidateSnapshotCaches()
        }
    }

    /// Swap the windows between two spaces. Mission Control order and empty
    /// spaces stay unchanged; the visible content swaps.
    func swapSpaceContents(_ first: Int, _ second: Int, focusMode: DragFocusMode) {
        guard let windows = try? queryWindowsRaw() else { return }
        let plan = Self.spaceSwapPlan(windows: windows, first: first, second: second)
        for step in plan {
            _ = try? shell(yabaiPath, "-m", "window", "\(step.windowID)", "--space", "\(step.target)")
        }
        focusAfterSpaceDrag(focusMode, source: first, destination: second)
    }

    /// Reorder the spaces themselves. Requires a yabai build with macOS 27.2
    /// space-move support. yabai can only swap the selected space, so focus
    /// the source first and restore the original focus afterwards.
    func moveSpaces(_ first: Int, _ second: Int, focusMode: DragFocusMode) {
        let originalUUID = focusedSpaceUUID()
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(first)")
        for _ in 0..<40 where focusedSpaceUUID() != spaceUUID(forIndex: first) {
            Thread.sleep(forTimeInterval: 0.025)
        }
        _ = try? shell(yabaiPath, "-m", "space", "--swap", "\(second)")
        switch focusMode {
        case .stay:
            if let originalUUID, let originalIndex = spaceIndex(forUUID: originalUUID) {
                _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(originalIndex)")
            }
        case .destination:
            _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(second)")
        case .source:
            _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(first)")
        }
    }

    func focusAfterSpaceDrag(_ mode: DragFocusMode, source: Int, destination: Int) {
        switch mode {
        case .stay: return
        case .destination: _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(destination)")
        case .source: _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(source)")
        }
    }

    func spaceUUID(forIndex index: Int) -> String? {
        guard let data = try? shell(yabaiPath, "-m", "query", "--spaces"),
              let spaces = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else { return nil }
        return spaces.first(where: { $0["index"] as? Int == index })?["uuid"] as? String
    }

    /// UUIDs are not in `YabaiSpace`, but the swap restore needs them: after a
    /// swap the original space's index changes while its content stays.
    func focusedSpaceUUID() -> String? {
        guard let data = try? shell(yabaiPath, "-m", "query", "--spaces"),
              let spaces = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else { return nil }
        return spaces.first(where: { $0["has-focus"] as? Bool == true })?["uuid"] as? String
    }

    func spaceIndex(forUUID uuid: String) -> Int? {
        guard let data = try? shell(yabaiPath, "-m", "query", "--spaces"),
              let spaces = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [[String: Any]] else { return nil }
        return spaces.first(where: { $0["uuid"] as? String == uuid })?["index"] as? Int
    }

    func createSpace() {
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--create"], "createSpace")
        }
    }

    func destroySpace(_ index: Int) {
        guard index > 0 else { return }
        focusQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--destroy", "\(index)"], "destroySpace(\(index))")
        }
    }

    func setSpaceLayout(_ layout: SpaceLayout) {
        // yabaiQueue, not focusQueue: refresh() fetches state on yabaiQueue,
        // so the layout command must be enqueued ahead of that fetch on the
        // same serial queue. On focusQueue the two orderings race and the
        // HUD re-renders the pre-layout snapshot.
        yabaiQueue.async { [weak self] in
            guard let self, self.yabaiIsExecutable else { return }
            self.runIgnoringFailure(["-m", "space", "--layout", layout.rawValue], "setSpaceLayout(\(layout.rawValue))")
        }
    }

}
