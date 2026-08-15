import Foundation

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
