import Sparkle

/// Sparkle flags for each user-visible update mode. Kept separate from the
/// controller so the transitions are unit-testable.
struct SparkleUpdatePolicy: Equatable {
    let automaticallyChecksForUpdates: Bool
    let automaticallyDownloadsUpdates: Bool

    init(updateMode: UpdateMode) {
        switch updateMode {
        case .auto:
            automaticallyChecksForUpdates = true
            automaticallyDownloadsUpdates = true
        case .notify:
            automaticallyChecksForUpdates = true
            automaticallyDownloadsUpdates = false
        case .off:
            automaticallyChecksForUpdates = false
            automaticallyDownloadsUpdates = false
        }
    }
}

/// Signing key hygiene: sparklesigner.pem must live at 0600 and never enter
/// git. Long term it belongs in the Keychain (EdDSA private key), with only
/// the public key in the repo/CI. See validate-sparkle-keys.sh.
enum SparkleConfig {
    static func configureSparkleUpdater(controller: SPUStandardUpdaterController, updateMode: UpdateMode) {
        if let feed = controller.updater.feedURL, feed.scheme?.lowercased() != "https" {
            NSLog("spacemap/Sparkle: refusing non-https feed URL: \(feed)")
            return
        }
        let updater = controller.updater
        let policy = SparkleUpdatePolicy(updateMode: updateMode)
        updater.automaticallyChecksForUpdates = policy.automaticallyChecksForUpdates
        updater.automaticallyDownloadsUpdates = policy.automaticallyDownloadsUpdates

        NSLog("spacemap/Sparkle: configured updater mode \(updateMode)")

        // Always start: `.off` disables automatic checks but manual
        // "Check for Updates" must still work.
        controller.startUpdater()
    }
}
