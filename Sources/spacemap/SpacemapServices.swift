import AppKit
import Foundation
import ServiceManagement
import Sparkle

/// Central dependency injection container for the Spacemap application.
///
/// All shared services are created once and injected through this
/// container, replacing the previous pattern of static singletons,
/// force-unwrapped optionals, and direct `YabaiClientImpl()` calls
/// scattered across the codebase.
///
/// Usage:
/// ```swift
/// let services = SpacemapServices()
/// let hud = HUDWindowController(services: services)
/// ```
final class SpacemapServices {

    // MARK: - Public services

    let yabaiService: YabaiService
    let appConfig: AppConfig
    let themeService: ThemeService
    let iconCache: IconCacheService
    let thumbnailCache: Any
    let sparkleController: SPUStandardUpdaterController
    let fileManager: FileManagerProtocol
    let process: ProcessProtocol
    let workspace: WorkspaceProtocol

    // MARK: - Services that are lazily initialized to break circular dependencies

    lazy var menubarHandler: MenubarHandler = {
        MenubarHandler(
            yabaiService: self.yabaiService,
            onToggleHUD: { [weak self] in self?.hud?.toggle() },
            onShowAbout: { [weak self] in self?.showAboutWindow() },
            onShowSettings: { [weak self] in self?.showSettingsWindow() },
            onInstallCLI: { [weak self] in self?.installCommandLineTools() },
            onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
            onRestartApp: { [weak self] in self?.restartApp() },
            onGetConfig: { [weak self] in self?.currentConfig ?? GridConfig.default },
            onSetLoginAtLogin: { [weak self] _ in self?.toggleLoginAtLogin() }
        )
    }()

    lazy var settingsHandler: SettingsHandler = {
        SettingsHandler(yabaiService: self.yabaiService, checkForUpdates: { [weak self] in self?.checkForUpdates() })
    }()

    lazy var cliToolsHandler: CLIToolsHandler = {
        CLIToolsHandler(onUpdateSparkleConfig: { [weak self] updateMode in self?.updateSparkleConfig(updateMode: updateMode) })
    }()

    lazy var deepLinkHandler: DeepLinkHandler = {
        DeepLinkHandler(
            hud: self.hud!,
            themeService: self.themeService,
            showSettings: { [weak self] in self?.showSettingsWindow() },
            showMenu: { [weak self] in self?.showMenubarMenu() }
        )
    }()

    lazy var hotkeyHandler: HotkeyHandler = {
        HotkeyHandler(hud: self.hud!, hotkeyMonitorFactory: self.hotkeyMonitorFactory)
    }()

    // MARK: - Private services

    let socketListenerFactory: SocketListenerFactory
    let hotkeyMonitorFactory: HotkeyMonitorFactory
    let alertsService: AlertsService

    // MARK: - HUD (set during initialization)

    var hud: HUDWindowController!

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
        // STEP 1: Initialize ALL let properties that DO NOT depend on self
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
        self.workspace = workspace ?? NSWorkspace.shared
        self.socketListenerFactory = socketListenerFactory ?? SocketListenerFactory()
        self.hotkeyMonitorFactory = hotkeyMonitorFactory ?? HotkeyMonitorFactory()
        self.alertsService = alertsService ?? AlertsServiceImpl()

        // STEP 2: Now we can use 'self' to initialize the HUD (it's an implicitly unwrapped optional)
        self.hud = HUDWindowController(services: self)
        // Note: The lazy vars above will be initialized on first access, after init is complete
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

    // MARK: - Menu Bar Handlers (delegated to MenubarHandler)

    func setupMenubar() {
        menubarHandler.setupMenubar()
    }

    func showMenubarMenu() {
        menubarHandler.showMenubarMenu()
    }

    func applyMenubarVisibility(config: GridConfig) {
        menubarHandler.applyMenubarVisibility(config: config)
    }

    func refreshMenubarPreview(config: GridConfig? = nil) {
        menubarHandler.refreshMenubarPreview(config: config)
    }

    func applyMenubarIcon(to item: NSStatusItem) {
        menubarHandler.applyMenubarIcon(to: item)
    }

    func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String {
        menubarHandler.hotkeyMenuString(hotkey)
    }

    func startHotkey(config: GridConfig) {
        hotkeyHandler.startHotkey(config: config)
    }

    func startPinnedHotkey(config: GridConfig) {
        hotkeyHandler.startPinnedHotkey(config: config)
    }

    // MARK: - Hotkey Handlers (delegated to HotkeyHandler)

    func restartHotkey(config: GridConfig) {
        hotkeyHandler.restartHotkey(config: config)
    }

    // MARK: - CLI Tools Handlers (delegated to CLIToolsHandler)

    func checkApplicationLocation() {
        cliToolsHandler.checkApplicationLocation()
    }

    func showMoveToApplicationsDialog() {
        cliToolsHandler.showMoveToApplicationsDialog()
    }

    func moveToApplications() {
        cliToolsHandler.moveToApplications()
    }

    func showFirstLaunchLaunchAtLoginPrompt() {
        cliToolsHandler.showFirstLaunchLaunchAtLoginPrompt()
    }

    func showFirstLaunchUpdatePreferencePrompt() {
        cliToolsHandler.showFirstLaunchUpdatePreferencePrompt()
    }

    func setLoginAtLogin(enabled: Bool) {
        cliToolsHandler.setLoginAtLogin(enabled: enabled)
    }

    func ensureCommandLineTools(
        allowAuthorizationPrompt: Bool,
        showSuccessAlert: Bool = false,
        forceAuthorizationPrompt: Bool = false
    ) {
        cliToolsHandler.ensureCommandLineTools(
            allowAuthorizationPrompt: allowAuthorizationPrompt,
            showSuccessAlert: showSuccessAlert,
            forceAuthorizationPrompt: forceAuthorizationPrompt
        )
    }

    func promptForCLIInstallAuthorization() {
        cliToolsHandler.promptForCLIInstallAuthorization()
    }

    func installCLISymlinkWithAuthorization() {
        cliToolsHandler.installCLISymlinkWithAuthorization()
    }

    func showCLIInstallAlert(style: NSAlert.Style, message: String, information: String) {
        cliToolsHandler.showCLIInstallAlert(style: style, message: message, information: information)
    }

    // MARK: - Settings Handlers (delegated to SettingsHandler)

    func showSettingsWindow() {
        settingsHandler.showSettingsWindow()
    }

    func showAboutWindow() {
        settingsHandler.showAboutWindow()
    }

    private func installCommandLineTools() {
        cliToolsHandler.ensureCommandLineTools(
            allowAuthorizationPrompt: true,
            showSuccessAlert: true,
            forceAuthorizationPrompt: true
        )
    }

    private func checkForUpdates() {
        sparkleController.checkForUpdates(nil)
    }

    private func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(bundlePath)\" --args --restarting"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }

    private func toggleLoginAtLogin() {
        let service = SMAppService.mainApp
        let newEnabled = service.status != .enabled
        setLoginAtLogin(enabled: newEnabled)
    }

    // MARK: - Deep Link Handlers (delegated to DeepLinkHandler)

    func handleDeepLink(_ action: DeepLinkAction) {
        deepLinkHandler.handle(action)
    }

    func handlePendingDeepLinks() {
        deepLinkHandler.handlePending()
    }

    // MARK: - Sparkle Handlers (delegated to SparkleConfig)

    func configureSparkleUpdater(updateMode: UpdateMode) {
        SparkleConfig.configureSparkleUpdater(controller: sparkleController, updateMode: updateMode)
    }

    func updateSparkleConfig(updateMode: UpdateMode) {
        configureSparkleUpdater(updateMode: updateMode)
    }

    // MARK: - Alert Handlers (delegated to AlertsService)

    func showYabaiAlert() {
        alertsService.showYabaiAlert()
    }

    func isMRUSpacesEnabled() -> Bool {
        alertsService.isMRUSpacesEnabled()
    }

    func showMRUAlert() {
        alertsService.showMRUAlert()
    }

    func showSeparateSpacesAlert() {
        alertsService.showSeparateSpacesAlert()
    }

    // MARK: - Socket Listener Factory

    func makeSocketListener(
        socketPath: String,
        healthInterval: Int,
        onRefresh: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> SocketListener {
        socketListenerFactory.makeSocketListener(
            socketPath: socketPath,
            healthInterval: healthInterval,
            onRefresh: onRefresh,
            onShow: onShow,
            onToggle: onToggle,
            onSettings: onSettings
        )
    }

    // MARK: - Hotkey Monitor Factory

    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitor {
        hotkeyMonitorFactory.makeHotkeyMonitor(config: config, onTrigger: onTrigger)
    }
}

// MARK: - AppConfig

/// Manages loading, saving, and the silent-mode flag for the
/// Spacemap configuration. Replaces the `Config` enum static
/// globals with an injectable, testable service.
final class AppConfig {

    var silentMode: Bool = false
    let configPath: String = NSString(
        string: "~/.config/spacemap/config.toml"
    ).expandingTildeInPath

    func load() -> GridConfig {
        let (values, _) = ConfigLoader.load(
            from: configPath,
            silentMode: silentMode
        )
        return values.gridConfig
    }

    func load(from path: String) -> GridConfig {
        let (values, _) = ConfigLoader.load(from: path, silentMode: silentMode)
        return values.gridConfig
    }

    func save(_ config: GridConfig) {
        ConfigLoader.save(config, to: configPath)
    }

    func save(_ config: GridConfig, to path: String) {
        ConfigLoader.save(config, to: path)
    }

    func parseConfig(_ text: String) -> GridConfig {
        let values = (try? TOMLParser.parse(text)) ?? ConfigValues()
        return values.gridConfig
    }

    func parseHotkey(_ value: String) -> HotkeyConfig? {
        Hotkey.parseHotkey(value)
    }
}

// MARK: - ThemeService

/// Wraps `ThemeManager` to remove the static shared singleton.
/// All theme loading and application goes through this service.
final class ThemeService {

    private let themeManager: ThemeManager

    init(themeManager: ThemeManager = ThemeManager()) {
        self.themeManager = themeManager
    }

    func reload() {
        themeManager.reload()
    }

    func named(_ name: String) -> AppTheme {
        themeManager.named(name)
    }

    func allNames() -> [String] {
        themeManager.allNames()
    }

    static func themesDir() -> URL {
        ThemeManager.themesDir()
    }
}

// MARK: - IconCacheService

/// Wraps `IconCache` to remove the static shared singleton.
/// All app-icon caching goes through this service.
final class IconCacheService {

    private let iconCache: IconCache

    init(iconCache: IconCache = IconCache()) {
        self.iconCache = iconCache
    }

    func icon(for appName: String) -> NSImage? {
        iconCache.icon(for: appName)
    }

    func preload(appNames: some Sequence<String>) {
        iconCache.preload(appNames: appNames)
    }

    func clear() {
        iconCache.clear()
    }
}

// MARK: - ThumbnailCacheService

/// Wraps `ThumbnailCache` to remove the static shared singleton.
/// All window thumbnail capture goes through this service.
@available(macOS 14.0, *)
final class ThumbnailCacheService {

    private let thumbnailCache = ThumbnailCache()

    func captureRequests(
        for state: GridState,
        spaceIndices: Set<Int>,
        thumbnailPixelSize: CGSize
    ) -> [ThumbnailCache.CaptureRequest] {
        ThumbnailCache.captureRequests(
            for: state,
            spaceIndices: spaceIndices,
            thumbnailPixelSize: thumbnailPixelSize
        )
    }

    func refreshSpaces(_ requests: [ThumbnailCache.CaptureRequest], force: Bool = false) {
        thumbnailCache.refreshSpaces(requests, force: force)
    }

    static let maxConcurrentCaptures = ThumbnailCache.maxConcurrentCaptures
    static let defaultThumbnailPixelSize = ThumbnailCache.defaultThumbnailPixelSize
}

// MARK: - SocketListenerFactory

/// Factory for creating `SocketListener` instances.
/// Abstracts the socket listener creation so it can be mocked in tests.
final class SocketListenerFactory {
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

// MARK: - HotkeyMonitorFactory

/// Factory for creating `HotkeyMonitor` instances.
/// Abstracts the hotkey monitor creation so it can be mocked in tests.
final class HotkeyMonitorFactory {
    func makeHotkeyMonitor(config: HotkeyConfig, onTrigger: @escaping () -> Void) -> HotkeyMonitor {
        HotkeyMonitor(config: config, onTrigger: onTrigger)
    }
}

// MARK: - System Service Protocols

/// Protocol for `FileManager` to enable mocking in tests.
protocol FileManagerProtocol {
    func fileExists(atPath path: String) -> Bool
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func isExecutableFile(atPath path: String) -> Bool
    func isWritableFile(atPath path: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws
    func createSymbolicLink(atPath path: String, withDestinationPath destPath: String) throws
    func removeItem(atPath path: String) throws
    func copyItem(atPath srcPath: String, toPath dstPath: String) throws
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func destinationOfSymbolicLink(atPath path: String) throws -> String
}

extension FileManager: FileManagerProtocol { }

/// Protocol for `Process` to enable mocking in tests.
protocol ProcessProtocol {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    var standardOutput: Any? { get set }
    var standardError: Any? { get set }
    func run() throws
    func waitUntilExit()
    var terminationStatus: Int32 { get }
}

extension Process: ProcessProtocol {}

/// Protocol for `NSWorkspace` to enable mocking in tests.
protocol WorkspaceProtocol {
    var frontmostApplication: NSRunningApplication? { get }
    var runningApplications: [NSRunningApplication] { get }
    func open(_ url: URL) -> Bool
    func icon(forFile path: String) -> NSImage
    var notificationCenter: NotificationCenter { get }
}

extension NSWorkspace: WorkspaceProtocol {}