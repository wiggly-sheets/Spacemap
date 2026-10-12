import Foundation

final class AppConfig {
    static let shared = AppConfig()

    private let silentModeLock = NSLock()
    private var _silentMode = false

    static var silentMode: Bool {
        get { shared.silentMode }
        set { shared.silentMode = newValue }
    }

    static var configPath: String { shared.configPath }

    static func load() -> GridConfig { shared.load() }

    static func load(from path: String) -> GridConfig { shared.load(from: path) }

    static func saveConfig(_ config: GridConfig) { shared.save(config) }

    static func saveConfig(_ config: GridConfig, to path: String) { shared.save(config, to: path) }

    static func parseConfig(_ text: String) -> GridConfig { shared.parseConfig(text) }

    static func parseHotkey(_ value: String) -> HotkeyConfig? { shared.parseHotkey(value) }

    var silentMode: Bool {
        get { silentModeLock.lock(); defer { silentModeLock.unlock() }; return _silentMode }
        set { silentModeLock.lock(); defer { silentModeLock.unlock() }; _silentMode = newValue }
    }
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
        do {
            return try TOMLParser.parse(text).gridConfig
        } catch {
            if !silentMode { NSLog("spacemap/AppConfig: parse failed (\(error.localizedDescription)) — using defaults") }
            return ConfigValues().gridConfig
        }
    }

    func parseHotkey(_ value: String) -> HotkeyConfig? {
        Hotkey.parseHotkey(value)
    }
}
