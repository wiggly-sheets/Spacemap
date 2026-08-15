import AppKit
import Foundation
import ServiceManagement
import Sparkle

final class SpacemapServices {
    private let core: SpacemapCoreServices
    var yabaiService: YabaiService { core.yabaiService }
    var appConfig: AppConfig { core.appConfig }
    var themeService: ThemeService { core.themeService }
    var iconCache: IconCacheService { core.iconCache }
    var thumbnailCache: Any { core.thumbnailCache }
    var sparkleController: SPUStandardUpdaterController { core.sparkleController }
    var fileManager: FileManagerProtocol { core.fileManager }
    var process: ProcessProtocol { core.process }
    var workspace: WorkspaceProtocol { core.workspace }
    var alertsService: AlertsService { core.alertsService }
    lazy var menubarService: MenubarHandler = MenubarHandler(
        yabaiService: yabaiService,
        onToggleHUD: { [weak self] in self?.hud?.toggle() },
        onShowAbout: { [weak self] in self?.showAboutWindow() },
        onShowSettings: { [weak self] in self?.showSettingsWindow() },
        onInstallCLI: { [weak self] in self?.installCommandLineTools() },
        onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
        onRestartApp: { [weak self] in self?.restartApp() },
        onGetConfig: { [weak self] in self?.currentConfig ?? GridConfig.default },
        onSetLoginAtLogin: { [weak self] in self?.setLoginAtLogin(enabled: $0) }
    )
    lazy var settingsService: SettingsService = SettingsService(yabaiService: yabaiService, checkForUpdates: { [weak self] in self?.checkForUpdates() })
    lazy var cliToolsService = CLIToolsService(
        onUpdateSparkleConfig: { [weak self] updateMode in self?.updateSparkleConfig(updateMode: updateMode) },
        sparkleController: core.sparkleController
    )
    lazy var deepLinkService: DeepLinkService = {
        DeepLinkService(
            hud: hud!,
            themeService: themeService,
            showSettings: { [weak self] in self?.showSettingsWindow() },
            showMenu: { [weak self] in self?.showMenubarMenu() }
        )
    }()
    lazy var hotkeyService: HotkeyService = HotkeyService(hud: hud!, hotkeyMonitorFactory: core.hotkeyMonitorFactory)
    var hud: HUDWindowController!
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
        self.core = SpacemapCoreServices(
            yabaiService: yabaiService,
            appConfig: appConfig,
            themeService: themeService,
            iconCache: iconCache,
            thumbnailCache: thumbnailCache,
            sparkleController: sparkleController,
            fileManager: fileManager,
            process: process,
            workspace: workspace,
            socketListenerFactory: socketListenerFactory,
            hotkeyMonitorFactory: hotkeyMonitorFactory,
            alertsService: alertsService
        )
        self.hud = HUDWindowController(services: self)
    }
    var currentConfig: GridConfig {
        get { core.appConfig.load() }
        set { core.appConfig.save(newValue) }
    }
    var configPath: String { core.appConfig.configPath }
    func setupMenubar() { menubarService.setupMenubar() }
    func showMenubarMenu() { menubarService.showMenubarMenu() }
    func applyMenubarVisibility(config: GridConfig) { menubarService.applyMenubarVisibility(config: config) }
    func refreshMenubarPreview(config: GridConfig? = nil) { menubarService.refreshMenubarPreview(config: config) }
    func applyMenubarIcon(to item: NSStatusItem) { menubarService.applyMenubarIcon(to: item) }
    func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String { menubarService.hotkeyMenuString(hotkey) }
    func startHotkey(config: GridConfig) { hotkeyService.startHotkey(config: config) }
    func startPinnedHotkey(config: GridConfig) { hotkeyService.startPinnedHotkey(config: config) }
    func restartHotkey(config: GridConfig) { hotkeyService.restartHotkey(config: config) }
    func checkApplicationLocation() { cliToolsService.checkApplicationLocation() }
    func showMoveToApplicationsDialog() { cliToolsService.showMoveToApplicationsDialog() }
    func moveToApplications() { cliToolsService.moveToApplications() }
    func showFirstLaunchLaunchAtLoginPrompt() { cliToolsService.showFirstLaunchLaunchAtLoginPrompt() }
    func showFirstLaunchUpdatePreferencePrompt() { cliToolsService.showFirstLaunchUpdatePreferencePrompt() }
    func setLoginAtLogin(enabled: Bool) { cliToolsService.setLoginAtLogin(enabled: enabled) }
    func ensureCommandLineTools(
        allowAuthorizationPrompt: Bool,
        showSuccessAlert: Bool = false,
        forceAuthorizationPrompt: Bool = false
    ) {
        cliToolsService.ensureCommandLineTools(
            allowAuthorizationPrompt: allowAuthorizationPrompt,
            showSuccessAlert: showSuccessAlert,
            forceAuthorizationPrompt: forceAuthorizationPrompt
        )
    }
    func promptForCLIInstallAuthorization() { cliToolsService.promptForCLIInstallAuthorization() }
    func installCLISymlinkWithAuthorization() { cliToolsService.installCLISymlinkWithAuthorization() }
    func showCLIInstallAlert(style: NSAlert.Style, message: String, information: String) {
        cliToolsService.showCLIInstallAlert(style: style, message: message, information: information)
    }
    func showSettingsWindow() { settingsService.showSettingsWindow() }
    func showAboutWindow() { settingsService.showAboutWindow() }
    func installCommandLineTools() { cliToolsService.installCommandLineTools() }
    func checkForUpdates() { cliToolsService.checkForUpdates() }
    func restartApp() { cliToolsService.restartApp() }
    func toggleLoginAtLogin() { cliToolsService.toggleLoginAtLogin() }
    func handleDeepLink(_ action: DeepLinkAction) { deepLinkService.handleDeepLink(action) }
    func openDeepLinks(_ urls: [URL]) { deepLinkService.open(urls: urls) }
    func setDeepLinksReady() { deepLinkService.setReady(true) }
    func handlePendingDeepLinks() { deepLinkService.handlePendingDeepLinks() }
    func configureSparkleUpdater(updateMode: UpdateMode) {
        SparkleConfig.configureSparkleUpdater(controller: core.sparkleController, updateMode: updateMode)
    }
    func updateSparkleConfig(updateMode: UpdateMode) { configureSparkleUpdater(updateMode: updateMode) }
    func showYabaiAlert() { core.alertsService.showYabaiAlert() }
    func isMRUSpacesEnabled() -> Bool { core.alertsService.isMRUSpacesEnabled() }
    func showMRUAlert() { core.alertsService.showMRUAlert() }
    func showSeparateSpacesAlert() { core.alertsService.showSeparateSpacesAlert() }
    func makeSocketListener(
        socketPath: String,
        healthInterval: Int,
        onRefresh: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> SocketListener {
        core.socketListenerFactory.makeSocketListener(
            socketPath: socketPath,
            healthInterval: healthInterval,
            onRefresh: onRefresh,
            onShow: onShow,
            onToggle: onToggle,
            onSettings: onSettings
        )
    }
    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitor {
        core.hotkeyMonitorFactory.makeHotkeyMonitor(config: config, onTrigger: onTrigger)
    }
}
