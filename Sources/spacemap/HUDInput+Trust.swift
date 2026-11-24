import AppKit
import CoreGraphics

extension HUDInput {
    /// Polls trust independently of HUD visibility. The event tap outlives a
    /// hidden HUD, and the visibility-gated poll cannot notice a revocation
    /// while it is hidden, so the tap would keep its cached permission until
    /// the next presentation. Runs on the main run loop at one second.
    func startTrustWatchdog() {
        eventTapHost.startHealthTimer { [weak self] in
            self?.probeTrustWhileHidden()
        }
    }

    func probeTrustWhileHidden() {
        let provider = accessibilityTrustProvider
        PermissionProbe.shared.check(provider: provider) { [weak self] trusted in
            guard let self else { return }
            guard trusted != self.cachedAccessibilityTrusted else {
                // Untrusted but still cached true? The tap must go regardless.
                if !trusted, self.eventTapHost.isEventTapInstalled {
                    self.handleAccessibilityState(isTrusted: false)
                }
                return
            }
            self.handleAccessibilityState(isTrusted: trusted)
        }
    }

    func stopTrustWatchdog() {
        eventTapHost.stopHealthTimer()
    }

    /// Poll-driven reconciliation. Skip the never-trusted startup state so a
    /// user who has not granted Accessibility is not told capture was revoked
    /// (which would hide a mouse-usable HUD). Once trusted, any transition in
    /// either direction is applied.
    func reconcileAccessibilityFromPoll() {
        guard cachedAccessibilityTrusted || eventTapHost.isEventTapInstalled else { return }
        PermissionProbe.shared.check(provider: accessibilityTrustProvider) { [weak self] trustedNow in
            guard let self,
                  trustedNow || self.cachedAccessibilityTrusted || self.eventTapHost.isEventTapInstalled else {
                return
            }
            self.handleAccessibilityState(isTrusted: trustedNow)
        }
    }

    /// Rare path: the system disabled the tap (timeout/user input). Re-check
    /// trust instead of blindly re-enabling, so a revocation disables capture
    /// and notifies the owner; a re-grant re-installs via reconciliation.
    func handleDisabledKeyboardTap(reason: CGEventType = .tapDisabledByTimeout) {
        // A tap the system disabled on behalf of the user is suspect. Drop it
        // and build a fresh one only when trust still reads true; a revoked
        // permission makes that creation fail and leaves the keyboard free.
        if reason == .tapDisabledByUserInput {
            stopSettingsKeyMonitor()
            PermissionProbe.shared.check(provider: accessibilityTrustProvider) { [weak self] trusted in
                guard let self else { return }
                if trusted {
                    self.startSettingsKeyMonitor()
                } else {
                    self.handleAccessibilityState(isTrusted: false)
                }
            }
            return
        }
        PermissionProbe.shared.check(provider: accessibilityTrustProvider) { [weak self] trusted in
            guard let self else { return }
            guard trusted else {
                self.handleAccessibilityState(isTrusted: false)
                return
            }
            self.eventTapHost.enableTap()
        }
    }

    func handleAccessibilityState(isTrusted: Bool) {
        cachedAccessibilityTrusted = isTrusted
        guard isTrusted else {
            let hadTap = eventTapHost.isEventTapInstalled
            // A stalled probe reports false so capture can be released; that is
            // not proof of revocation, so it must not replace the process.
            let revoked = !PermissionProbe.shared.isStalled
            if hadTap {
                NSLog("spacemap/HUDInput: Accessibility revoked; releasing keyboard capture")
                stopSettingsKeyMonitor()
                // A revoked TCC entry can leave the WindowServer-side tap
                // registered even after invalidation. Replacing the process is
                // the only reliable release, and it is what a manual restart
                // does today.
                if revoked {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [relaunch] in
                        relaunch()
                    }
                }
            }
            if isVisible, revoked, !didNotifyAccessibilityRevocation {
                didNotifyAccessibilityRevocation = true
                onAccessibilityRevoked?()
            }
            return
        }

        didNotifyAccessibilityRevocation = false
        eventTapHost.reconcile(consumer: self)
    }
}
