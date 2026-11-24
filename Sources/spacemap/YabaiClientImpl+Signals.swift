import Foundation
import AppKit

extension YabaiClientImpl {
    /// Delays before each registration retry. A daemon that just started
    /// accepts `--add` before it can hold a signal, so the first attempts fail.
    /// Six attempts total: the immediate one, then one per delay (31s bound).
    static let signalRegistrationRetryDelays: [TimeInterval] = [1, 2, 4, 8, 16]

    func registerSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool = false,
        refreshWorkspacePreviews: Bool = false,
        refreshWindowGeometry: Bool = true
    ) {
        // A new trigger supersedes a retry chain that is still pending.
        signalRegistrationLock.lock()
        signalRegistrationToken += 1
        let token = signalRegistrationToken
        signalRegistrationLock.unlock()
        attemptSignalRegistration(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            refreshWorkspacePreviews: refreshWorkspacePreviews,
            refreshWindowGeometry: refreshWindowGeometry,
            attempt: 0,
            token: token
        )
    }

    func isCurrentSignalRegistration(_ token: Int) -> Bool {
        signalRegistrationLock.lock()
        defer { signalRegistrationLock.unlock() }
        return token == signalRegistrationToken
    }

    func attemptSignalRegistration(
        socketPath: String,
        showHUDOnSpaceChange: Bool,
        refreshWorkspacePreviews: Bool,
        refreshWindowGeometry: Bool,
        attempt: Int,
        token: Int
    ) {
        guard isCurrentSignalRegistration(token) else { return }
        guard isYabaiRunning(forceRefresh: true) else { return }
        // A nonce-less action is always dropped by the listener. Leave any
        // existing working signals alone instead of replacing them with no-ops.
        guard SpacemapCommand.currentNonceHex(for: socketPath) != nil else {
            NSLog("spacemap/yabai: skipping signal registration — nonce missing")
            return
        }
        guard yabaiIsExecutable else { return }
        if installSignals(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange,
            refreshWorkspacePreviews: refreshWorkspacePreviews,
            refreshWindowGeometry: refreshWindowGeometry
        ) {
            NSLog("spacemap/yabai: yabai signals registered on attempt %d", attempt + 1)
            return
        }
        let delays = Self.signalRegistrationRetryDelays
        let next = attempt + 1
        // `attempt` indexes the delay for the retry it is about to schedule, so
        // the last attempt (one past the array) gives up instead of retrying.
        guard attempt < delays.count else {
            NSLog("spacemap/yabai: yabai signal registration failed after %d attempts — signals stay unregistered until the next yabai restart", attempt + 1)
            return
        }
        signalRetryScheduler(delays[attempt]) { [weak self] in
            guard let self, self.isCurrentSignalRegistration(token) else { return }
            self.attemptSignalRegistration(
                socketPath: socketPath,
                showHUDOnSpaceChange: showHUDOnSpaceChange,
                refreshWorkspacePreviews: refreshWorkspacePreviews,
                refreshWindowGeometry: refreshWindowGeometry,
                attempt: next,
                token: token
            )
        }
    }

    /// One remove-all-then-add pass, then read the signal table back: a daemon
    /// that is still starting accepts an add and silently keeps no signal.
    func installSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool,
        refreshWorkspacePreviews: Bool,
        refreshWindowGeometry: Bool
    ) -> Bool {
        removeSignals()
        let action = spaceChangedSignalAction(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange
        )
        _ = try? shell(yabaiPath, "-m", "signal", "--add",
                       "label=spacemap_space_changed",
                       "event=space_changed",
                       "action=\(action)")
        if refreshWorkspacePreviews {
            for event in previewRefreshEvents(refreshWindowGeometry: refreshWindowGeometry) {
                _ = try? shell(yabaiPath, "-m", "signal", "--add",
                               "label=spacemap_\(event)",
                               "event=\(event)",
                               "action=\(refreshSignalAction(socketPath: socketPath))")
            }
        }
        guard let listing = try? shell(yabaiPath, "-m", "signal", "--list"),
              let nonce = SpacemapCommand.currentNonceHex(for: socketPath)
        else { return false }
        return listingShowsLiveSpaceChangedSignal(listing, nonce: nonce)
    }

    /// `--list` prints one JSON-like object per signal, with `label` before
    /// `action`. A label alone is not enough: a stale signal left behind by a
    /// failed remove still carries the old nonce, whose actions never reach
    /// this process. Require the current nonce inside this label's own object.
    func listingShowsLiveSpaceChangedSignal(_ listing: String, nonce: String) -> Bool {
        guard let label = listing.range(of: "spacemap_space_changed") else { return false }
        let remainder = listing[label.upperBound...]
        let entry = remainder.range(of: "\"label\"").map { remainder[..<$0.lowerBound] } ?? remainder
        return entry.contains(":\(nonce)")
    }

    func previewRefreshEvents(refreshWindowGeometry: Bool) -> [String] {
        refreshWindowGeometry ? workspacePreviewRefreshEvents : workspaceTopologyRefreshEvents
    }

    func spaceChangedSignalAction(socketPath: String, showHUDOnSpaceChange: Bool) -> String {
        guard let quoted = SpacemapCommand.shellQuoted(socketPath) else {
            NSLog("spacemap/yabai: refusing signal with untrusted socket path")
            return "/usr/bin/false"
        }
        guard let nonce = SpacemapCommand.currentNonceHex(for: socketPath) else {
            NSLog("spacemap/yabai: refusing signal without a nonce")
            return "/usr/bin/false"
        }
        guard let command = (showHUDOnSpaceChange ? SpacemapCommand.show : .refresh).socketByte else {
            return "/usr/bin/false"
        }
        return "printf '\(command):\(nonce)' | /usr/bin/nc -U \(quoted)"
    }

    func refreshSignalAction(socketPath: String) -> String {
        guard let quoted = SpacemapCommand.shellQuoted(socketPath) else {
            NSLog("spacemap/yabai: refusing signal with untrusted socket path")
            return "/usr/bin/false"
        }
        guard let nonce = SpacemapCommand.currentNonceHex(for: socketPath) else {
            NSLog("spacemap/yabai: refusing signal without a nonce")
            return "/usr/bin/false"
        }
        guard let command = SpacemapCommand.refresh.socketByte else { return "/usr/bin/false" }
        return "printf '\(command):\(nonce)' | /usr/bin/nc -U \(quoted)"
    }

    func removeSignals() {
        guard isYabaiRunning(), yabaiIsExecutable else { return }
        _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_space_changed")
        for event in workspacePreviewRefreshEvents {
            _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_\(event)")
        }
    }


}
