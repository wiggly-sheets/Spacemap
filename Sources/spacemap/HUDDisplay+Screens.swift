import AppKit
import SwiftUI

extension HUDDisplay {
    var availableScreenFrames: [CGRect] {
        ScreenContext.availableScreenFrames(override: screenFramesOverride)
    }

    func screenFrame(forDisplay displayIndex: Int, in state: GridState) -> CGRect? {
        ScreenContext.screenFrame(
            forDisplay: displayIndex,
            in: state,
            frames: availableScreenFrames,
            quartzMaxY: quartzMainScreenFrame.maxY
        )
    }

    /// Resolve display indices to physical screen frames, dropping duplicate
    /// frames (mirrored/stale yabai topology) so two logical displays can
    /// never stack two HUD panels on one screen.
    func screenAssignments(
        for displayIndices: [Int],
        in state: GridState
    ) -> [(displayIndex: Int, frame: CGRect)] {
        ScreenContext.screenAssignments(
            for: displayIndices,
            in: state,
            frames: availableScreenFrames,
            quartzMaxY: quartzMainScreenFrame.maxY,
            mainFrame: screenFramesOverride?.first ?? NSScreen.main?.frame
        )
    }

    static func deduplicatedAssignments(
        _ assignments: [(displayIndex: Int, screenFrame: CGRect)]
    ) -> [(displayIndex: Int, screenFrame: CGRect)] {
        var seenFrames: [CGRect] = []
        return assignments.filter { assignment in
            guard !seenFrames.contains(assignment.screenFrame) else { return false }
            seenFrames.append(assignment.screenFrame)
            return true
        }
    }

    func closeDisplayPanels() {
        for panel in displayPanels.values {
            panel.orderOut(nil)
            panel.close()
        }
        displayPanels.removeAll()
        displayHostingViews.removeAll()
    }
}
