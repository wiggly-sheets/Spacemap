import Foundation

/// The app-facing route to `config.toml`: the default path plus the
/// process-wide silent flag. Decode, repair, and encode live in
/// `ConfigSchema`/`TOMLConfigCodec`; the disk layer beneath is `ConfigLoader`.
final class ConfigStore {
    static let shared = ConfigStore()

    private let silentModeLock = NSLock()
    private var _silentMode = false

    static var silentMode: Bool {
        get { shared.silentMode }
        set { shared.silentMode = newValue }
    }

    static var configPath: String { shared.configPath }

    let configPath: String

    init(configPath: String = NSString(string: "~/.config/spacemap/config.toml").expandingTildeInPath) {
        self.configPath = configPath
    }

    var silentMode: Bool {
        get { silentModeLock.lock(); defer { silentModeLock.unlock() }; return _silentMode }
        set { silentModeLock.lock(); defer { silentModeLock.unlock() }; _silentMode = newValue }
    }

    static func load() -> SpacemapConfig { shared.load() }

    static func load(from path: String) -> SpacemapConfig { shared.load(from: path) }

    static func saveConfig(_ config: SpacemapConfig) { shared.save(config) }

    static func saveConfig(_ config: SpacemapConfig, to path: String) { shared.save(config, to: path) }

    @discardableResult
    static func saveConfigReportingResult(_ config: SpacemapConfig) -> Bool {
        ConfigLoader.saveReportingResult(config, to: shared.configPath)
    }

    /// Atomic read-modify-write. Use this instead of a separate `load()` +
    /// `saveConfig()` pair when two tasks may update different fields.
    @discardableResult
    static func updateConfig(_ mutate: (inout SpacemapConfig) -> Void) -> Bool {
        ConfigLoader.update(at: shared.configPath, silentMode: shared.silentMode, mutate)
    }

    static func loadReportingResult() -> (config: SpacemapConfig, needsRepair: Bool, status: ConfigLoadStatus) {
        shared.loadReportingResult()
    }

    /// Parsed config with the defaults standing in for unreadable text.
    static func parseConfig(_ text: String) -> SpacemapConfig {
        shared.parseConfig(text)
    }

    func load() -> SpacemapConfig {
        ConfigLoader.load(from: configPath, silentMode: silentMode).config
    }

    func loadReportingResult() -> (config: SpacemapConfig, needsRepair: Bool, status: ConfigLoadStatus) {
        ConfigLoader.loadReportingResult(from: configPath, silentMode: silentMode)
    }

    func load(from path: String) -> SpacemapConfig {
        ConfigLoader.load(from: path, silentMode: silentMode).config
    }

    func save(_ config: SpacemapConfig) {
        ConfigLoader.save(config, to: configPath)
    }

    func save(_ config: SpacemapConfig, to path: String) {
        ConfigLoader.save(config, to: path)
    }

    func parseConfig(_ text: String) -> SpacemapConfig {
        do {
            return try TOMLParser.parse(text).config
        } catch {
            if !silentMode { NSLog("spacemap/ConfigStore: parse failed (\(error.localizedDescription)) — using defaults") }
            return .default
        }
    }
}
