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
        print("Spacemap: Configuring Sparkle updater with mode: \(updateMode)")
        let updater = controller.updater
        print("Spacemap: Updater feed URL: \(String(describing: updater.feedURL))")
        print("Spacemap: Current auto-check setting: \(updater.automaticallyChecksForUpdates)")
        print("Spacemap: Current auto-download setting: \(updater.automaticallyDownloadsUpdates)")

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

        print("Spacemap: After config - auto-check: \(updater.automaticallyChecksForUpdates), auto-download: \(updater.automaticallyDownloadsUpdates)")

        if updateMode != .off {
            controller.startUpdater()
        }
    }
}
