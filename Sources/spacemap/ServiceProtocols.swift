import AppKit
import Foundation

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

extension Process: ProcessProtocol { }

/// Protocol for `NSWorkspace` to enable mocking in tests.
protocol WorkspaceProtocol {
    var frontmostApplication: NSRunningApplication? { get }
    var runningApplications: [NSRunningApplication] { get }
    func open(_ url: URL) -> Bool
    func icon(forFile path: String) -> NSImage
    var notificationCenter: NotificationCenter { get }
}

extension NSWorkspace: WorkspaceProtocol { }

/// Protocol for Menubar handling to enable mocking in tests.
protocol MenubarHandling {
    func setupMenubar()
    func showMenubarMenu()
    func applyMenubarVisibility(config: GridConfig)
    func refreshMenubarPreview(config: GridConfig?)
    func applyMenubarIcon(to item: NSStatusItem)
    func hotkeyMenuString(_ hotkey: HotkeyConfig) -> String
}

/// Protocol for Settings handling to enable mocking in tests.
protocol SettingsHandling {
    func showSettingsWindow()
    func showAboutWindow()
}

/// Protocol for CLI Tools handling to enable mocking in tests.
protocol CLIToolsHandling {
    func checkApplicationLocation()
    func showMoveToApplicationsDialog()
    func moveToApplications()
    func showFirstLaunchLaunchAtLoginPrompt()
    func showFirstLaunchUpdatePreferencePrompt()
    func setLoginAtLogin(enabled: Bool)
    func ensureCommandLineTools(allowAuthorizationPrompt: Bool, showSuccessAlert: Bool, forceAuthorizationPrompt: Bool)
    func promptForCLIInstallAuthorization()
    func installCLISymlinkWithAuthorization()
    func showCLIInstallAlert(style: NSAlert.Style, message: String, information: String)
}

/// Protocol for Deep Link handling to enable mocking in tests.
protocol DeepLinkHandling {
    func handleDeepLink(_ action: DeepLinkAction)
    func handlePendingDeepLinks()
}

/// Protocol for Hotkey handling to enable mocking in tests.
protocol HotkeyHandling {
    func startHotkey(config: GridConfig)
    func startPinnedHotkey(config: GridConfig)
    func restartHotkey(config: GridConfig)
}