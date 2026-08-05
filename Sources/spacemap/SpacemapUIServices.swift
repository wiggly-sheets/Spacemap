import AppKit
import Foundation
import ServiceManagement

/// UI‑focused services that depend on the core services and the HUD.
final class SpacemapUIServices {
    let themeService: ThemeService
    let iconCache: IconCacheService
    let thumbnailCache: Any
    let menubarHandler: MenubarHandler

    init(
        core: SpacemapCoreServices,
        hud: HUDWindowController
    ) {
        self.themeService = ThemeService()
        self.iconCache = IconCacheService()
        if #available(macOS 14.0, *) {
            self.thumbnailCache = ThumbnailCacheService()
        } else {
            self.thumbnailCache = NSNull()
        }
        // The menubar handler needs callbacks that will be provided by the
        // application layer (ApplicationLifecycleService).  For now we use
        // placeholder closures that will be replaced later.
        self.menubarHandler = MenubarHandler(
            yabaiService: core.yabaiService,
            onToggleHUD: { },
            onShowAbout: { },
            onShowSettings: { },
            onInstallCLI: { },
            onCheckForUpdates: { },
            onRestartApp: { },
            onGetConfig: { core.currentConfig },
            onSetLoginAtLogin: { _ in }
        )
    }
}