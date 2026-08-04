import Foundation
import CoreGraphics

enum Config {

    static var silentMode = false
    static let configPath = NSString(string: "~/.config/spacemap/config.toml").expandingTildeInPath

    public static func load() -> GridConfig {
        let (values, _) = ConfigLoader.load(from: configPath, silentMode: silentMode)
        return values.toGridConfig().config
    }

    public static func load(from path: String) -> GridConfig {
        let (values, _) = ConfigLoader.load(from: path, silentMode: silentMode)
        return values.toGridConfig().config
    }

    internal static func parseConfig(_ text: String) -> GridConfig {
        let values = TOMLParser.parse(text)
        return values.toGridConfig().config
    }

    public static func saveConfig(_ config: GridConfig) {
        saveConfig(config, to: configPath)
    }

    public static func saveConfig(_ config: GridConfig, to path: String) {
        ConfigLoader.save(config, to: path)
    }

    internal static func cellStyleName(_ style: CellStyle) -> String {
        ConfigLoader.cellStyleName(style)
    }

}
