import Sparkle

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

        switch updateMode {
        case .auto:
            updater.automaticallyDownloadsUpdates = true
            updater.automaticallyChecksForUpdates = true
        case .notify:
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = true
        case .off:
            updater.automaticallyChecksForUpdates = false
        }

        NSLog("spacemap/Sparkle: configured updater mode \(updateMode)")

        if updateMode != .off {
            controller.startUpdater()
        }
    }
}
