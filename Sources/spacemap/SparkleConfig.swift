import Sparkle

enum SparkleConfig {
    static func configureSparkleUpdater(controller: SPUStandardUpdaterController, updateMode: UpdateMode) {
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
