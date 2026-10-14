import AppKit
import Foundation
import ServiceManagement
import Sparkle

final class SpacemapServices {
    let yabaiService: YabaiService
    let appConfig: AppConfig
    let themeService: ThemeManager
    let sparkleController: SPUStandardUpdaterController
    let fileManager: FileManagerProtocol
    let process: ProcessProtocol
    let workspace: WorkspaceProtocol
    let alertsService: AlertsService
    lazy var menubarService: MenubarHandler = MenubarHandler(
        yabaiService: yabaiService,
        onToggleHUD: { [weak self] in self?.hud.toggle() },
        onShowAbout: { [weak self] in self?.showAboutWindow() },
        onShowSettings: { [weak self] in self?.showSettingsWindow() },
        onInstallCLI: { [weak self] in self?.installCommandLineTools() },
        onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
        onRestartApp: { [weak self] in self?.restartApp() },
        onGetConfig: { [weak self] in self?.currentConfig ?? GridConfig.default },
        onSetLoginAtLogin: { [weak self] in self?.setLoginAtLogin(enabled: $0) },
        onChangeSpaceNameProfile: { [weak self] index in self?.changeSpaceNameProfile(index: index) }
    )
    lazy var settingsService: SettingsService = SettingsService(yabaiService: yabaiService, checkForUpdates: { [weak self] in self?.checkForUpdates() })
    private(set) lazy var glyphStrip = GlyphStripPanelController(yabaiService: yabaiService)
    lazy var cliToolsService = CLIToolsService(
        onUpdateSparkleConfig: { [weak self] updateMode in self?.updateSparkleConfig(updateMode: updateMode) },
        sparkleController: sparkleController
    )
    lazy var deepLinkService: DeepLinkService = {
        DeepLinkService(
            hud: hud,
            themeService: themeService,
            showSettings: { [weak self] in self?.showSettingsWindow() },
            showMenu: { [weak self] in self?.showMenubarMenu() }
        )
    }()
    lazy var hotkeyService: HotkeyService = HotkeyService(
        hud: hud,
        glyphStrip: glyphStrip
    )
    private(set) lazy var hud: HUDWindowController = HUDWindowController(services: self)
    init(
        yabaiService: YabaiService? = nil,
        appConfig: AppConfig? = nil,
        themeService: ThemeManager? = nil,
        sparkleController: SPUStandardUpdaterController? = nil,
        fileManager: FileManagerProtocol? = nil,
        process: ProcessProtocol? = nil,
        workspace: WorkspaceProtocol? = nil,
        alertsService: AlertsService? = nil
    ) {
        self.yabaiService = yabaiService ?? YabaiClientImpl()
        self.appConfig = appConfig ?? AppConfig()
        self.themeService = themeService ?? ThemeManager.shared
        self.sparkleController = sparkleController ?? SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.fileManager = fileManager ?? FileManager.default
        self.process = process ?? Process()
        self.workspace = workspace ?? (NSWorkspace.shared as WorkspaceProtocol)
        self.alertsService = alertsService ?? AlertsServiceImpl()
    }
    var currentConfig: GridConfig {
        get { appConfig.load() }
        set { appConfig.save(newValue) }
    }
    var configPath: String { appConfig.configPath }
    func setupMenubar() { menubarService.setupMenubar() }
    func showMenubarMenu() { menubarService.showMenubarMenu() }
    func applyMenubarVisibility(config: GridConfig) { menubarService.applyMenubarVisibility(config: config) }
    func refreshMenubarPreview(config: GridConfig? = nil) { menubarService.refreshMenubarPreview(config: config) }
    func applyGlyphStrip(config: GridConfig) { glyphStrip.update(config: config) }
    func refreshGlyphStrip() { glyphStrip.refresh() }
    func applyMenubarIcon(to item: NSStatusItem) { menubarService.applyMenubarIcon(to: item) }
    func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String { menubarService.hotkeyMenuString(hotkey) }
    func restartHotkeys(config: GridConfig) { hotkeyService.restartHotkeys(config: config) }
    func stopHotkeys() { hotkeyService.stopHotkeys() }
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
        SparkleConfig.configureSparkleUpdater(controller: sparkleController, updateMode: updateMode)
    }
    func updateSparkleConfig(updateMode: UpdateMode) { configureSparkleUpdater(updateMode: updateMode) }
    func showYabaiAlert() { alertsService.showYabaiAlert() }
    func showYabaiUntrustedAlert(detail: String, refusing: Bool) { alertsService.showYabaiUntrustedAlert(detail: detail, refusing: refusing) }
    func isMRUSpacesEnabled() -> Bool { alertsService.isMRUSpacesEnabled() }
    func showMRUAlert() { alertsService.showMRUAlert() }
    func showSeparateSpacesAlert() { alertsService.showSeparateSpacesAlert() }
    func changeSpaceNameProfile(index: Int) {
        var config = currentConfig
        guard (0..<config.spaceNameProfiles.count).contains(index) else { return }
        config.activeSpaceNameProfileIndex = index
        let profile = config.spaceNameProfiles[index]
        config.spaceNames = profile.spaceNames
        currentConfig = config
        refreshMenubarPreview(config: config)
        hud.reloadConfig()
    }
    func makeSocketListener(
        socketPath: String,
        healthInterval: Int,
        onRefresh: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> SocketListener {
        SocketListener(
            socketPath: socketPath,
            healthInterval: healthInterval,
            onRefresh: onRefresh,
            onShow: onShow,
            onToggle: onToggle,
            onSettings: onSettings
        )
    }
}
