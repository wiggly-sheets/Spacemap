import AppKit
import ServiceManagement
import Sparkle

extension CLIToolsService {
    func checkApplicationLocation() {
        let appPath = Bundle.main.bundleURL.path
        let defaults = UserDefaults.standard

        if Self.shouldPromptToMove(
            appPath: appPath,
            hasDeclined: defaults.bool(forKey: Self.declinedMoveToApplicationsKey),
            applicationsPaths: Self.applicationsPaths
        ) {
            showMoveToApplicationsDialog()
        }

        if !defaults.bool(forKey: Self.askedLaunchAtLoginKey) {
            // Persist "asked" only when the user actually answered and the
            // system accepted the choice; a failed SMAppService call should be
            // retried on the next launch.
            if showFirstLaunchLaunchAtLoginPrompt() {
                defaults.set(true, forKey: Self.askedLaunchAtLoginKey)
            }
        }

        if !defaults.bool(forKey: Self.askedUpdatePreferenceKey) {
            showFirstLaunchUpdatePreferencePrompt()
            defaults.set(true, forKey: Self.askedUpdatePreferenceKey)
        }
    }

    /// Component-wise check: `/Applications-old/Spacemap.app` is not inside
    /// `/Applications`, while nested builds under it are.
    static func isInApplications(appPath: String) -> Bool {
        isInApplications(appPath: appPath, applicationsPaths: applicationsPaths)
    }

    static func isInApplications(appPath: String, applicationsPaths: [String]) -> Bool {
        let appComponents = URL(fileURLWithPath: appPath).standardizedFileURL.pathComponents
        return applicationsPaths.contains { applicationsPath in
            let applicationsComponents = URL(fileURLWithPath: applicationsPath).standardizedFileURL.pathComponents
            guard appComponents.count > applicationsComponents.count else { return false }
            return Array(appComponents.prefix(applicationsComponents.count)) == applicationsComponents
        }
    }

    static func shouldPromptToMove(appPath: String, hasDeclined: Bool) -> Bool {
        shouldPromptToMove(
            appPath: appPath,
            hasDeclined: hasDeclined,
            applicationsPaths: applicationsPaths
        )
    }

    static func shouldPromptToMove(
        appPath: String,
        hasDeclined: Bool,
        applicationsPaths: [String]
    ) -> Bool {
        !hasDeclined && !isInApplications(appPath: appPath, applicationsPaths: applicationsPaths)
    }

    func showMoveToApplicationsDialog() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Move Spacemap to Applications?", comment: "")
        alert.informativeText = NSLocalizedString("Spacemap should be run from the Applications folder for best performance. Would you like to move it there now?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Move to Applications", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let response = presentAlert(alert)
        if response == .alertFirstButtonReturn {
            moveToApplications()
        } else {
            // Remember a decline so an app deliberately run from Downloads
            // does not prompt on every launch.
            UserDefaults.standard.set(true, forKey: Self.declinedMoveToApplicationsKey)
        }
    }

    enum MoveToApplicationsResult {
        case moved
        case alreadyUpToDate
        case signatureFailed
        case failed(Error)
    }

    func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: applicationsPath).appendingPathComponent(source.lastPathComponent)

        // codesign and the bundle copy both block; keep them off the main
        // thread and only present the outcome on the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.performMoveToApplications(source: source, destination: destination)
            DispatchQueue.main.async {
                self.presentMoveToApplicationsResult(result)
            }
        }
    }

    func performMoveToApplications(source: URL, destination: URL) -> MoveToApplicationsResult {
        guard verifyBundleSignature(at: source) else {
            return .signatureFailed
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            // Never clobber a newer install (downgrade = attacker rollback).
            if Self.compareVersions(installedVersion(at: destination), bundleVersion(at: source)) != .orderedAscending {
                return .alreadyUpToDate
            }
        }

        do {
            try Self.copyBundleAtomically(source: source, destination: destination)
            return .moved
        } catch {
            return .failed(error)
        }
    }

    /// Stage beside the destination, then rename/replace so the destination is
    /// never absent while a copy is in progress.
    static func copyBundleAtomically(
        source: URL,
        destination: URL,
        fileManager: FileManager = .default
    ) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.copyItem(at: source, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    func presentMoveToApplicationsResult(_ result: MoveToApplicationsResult) {
        switch result {
        case .moved:
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("Moved to Applications", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap has been copied to the Applications folder. Please quit and relaunch from there.", comment: "")
            presentAlert(alert)
        case .alreadyUpToDate:
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = NSLocalizedString("Already up to date", comment: "")
            alert.informativeText = NSLocalizedString("The Applications copy is the same version or newer. Nothing was overwritten.", comment: "")
            presentAlert(alert)
        case .signatureFailed:
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = NSLocalizedString("Spacemap could not verify its own code signature. The install was refused.", comment: "")
            presentAlert(alert)
        case .failed(let error):
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to move", comment: "")
            alert.informativeText = String(format: NSLocalizedString("Could not move Spacemap to Applications: %@", comment: ""), error.localizedDescription)
            presentAlert(alert)
        }
    }
}
