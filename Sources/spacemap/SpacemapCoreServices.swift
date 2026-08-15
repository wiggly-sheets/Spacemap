import AppKit
import Foundation
import ServiceManagement
import Sparkle

final class SpacemapCoreServices {


    let yabaiService: YabaiService
    let appConfig: AppConfig
    let themeService: ThemeService
    let iconCache: IconCacheService
    let thumbnailCache: Any
    let sparkleController: SPUStandardUpdaterController
    let fileManager: FileManagerProtocol
    let process: ProcessProtocol
    let workspace: WorkspaceProtocol


    let socketListenerFactory: SocketListenerFactory
    let hotkeyMonitorFactory: HotkeyMonitorFactory
    let alertsService: AlertsService


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


    var currentConfig: GridConfig {
        get { appConfig.load() }
        set { appConfig.save(newValue) }
    }

    var configPath: String {
        appConfig.configPath
    }
}
