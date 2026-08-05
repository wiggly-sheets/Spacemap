import AppKit
import Foundation
import ServiceManagement

/// System‑level services that interact with the OS, filesystem, alerts, and CLI tools.
final class SpacemapSystemServices {
    let alertsService: AlertsService
    let cliToolsHandler: CLIToolsHandler

    init(
        core: SpacemapCoreServices
    ) {
        self.alertsService = AlertsServiceImpl()
        self.cliToolsHandler = CLIToolsHandler(onUpdateSparkleConfig: { _ in })
    }
}