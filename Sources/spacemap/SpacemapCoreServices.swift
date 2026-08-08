import AppKit
import Foundation
import ServiceManagement
import Sparkle

/// Core dependencies shared across application modules.
final class SpacemapCoreServices {

    // MARK: - Fundamental services

    let yabaiService: YabaiService
    let appConfig: AppConfig
    let themeService: ThemeService
    let iconCache: IconCacheService
    let thumbnailCache: Any
    let sparkleController: SPUStandardUpdaterController
    let fileManager: FileManagerProtocol
    let process: ProcessProtocol
    let workspace: WorkspaceProtocol

    // MARK: - Factories (stateless)

    let socketListenerFactory: SocketListenerFactory
    let hotkeyMonitorFactory: HotkeyMonitorFactory
    let alertsService: AlertsService

    // MARK: - Initialization

    init(
        yabaiService: YabaiService? = nil,
        appConfig: AppConfig? = nil,
        themeService: ThemeService? = nil,
        iconCache: IconCacheService? = nil,
        thumbnailCache: Any? = nil,
        sparkleController: SPUStandardUpdaterController? = nil,
        fileManager: FileManagerProtocol? = nil,
        process: ProcessProtocol? = nil,
        workspace: WorkspaceProtocol? = nil,
        socketListenerFactory: SocketListenerFactory? = nil,
        hotkeyMonitorFactory: HotkeyMonitorFactory? = nil,
        alertsService: AlertsService? = nil
    ) {
        // STEP 1: Initialize all `let` properties that do NOT depend on `self`
        self.yabaiService = yabaiService ?? YabaiClientImpl()
        self.appConfig = appConfig ?? AppConfig()
        self.themeService = themeService ?? ThemeService()
        self.iconCache = iconCache ?? IconCacheService()
        if #available(macOS 14.0, *) {
            self.thumbnailCache = thumbnailCache ?? ThumbnailCacheService()
        } else {
            self.thumbnailCache = thumbnailCache ?? NSNull()
        }
        self.sparkleController = sparkleController ?? SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.fileManager = fileManager ?? FileManager.default
        self.process = process ?? Process()
        self.workspace = workspace ?? (NSWorkspace.shared as WorkspaceProtocol)
        self.socketListenerFactory = socketListenerFactory ?? SocketListenerFactory()
        self.hotkeyMonitorFactory = hotkeyMonitorFactory ?? HotkeyMonitorFactory()
        self.alertsService = alertsService ?? AlertsServiceImpl()
    }

    // MARK: - Convenience

    /// The shared `GridConfig` loaded from disk.
    var currentConfig: GridConfig {
        get { appConfig.load() }
        set { appConfig.save(newValue) }
    }

    /// The path to the config file on disk.
    var configPath: String {
        appConfig.configPath
    }
}
