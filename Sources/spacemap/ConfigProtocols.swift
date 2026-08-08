import Foundation
import CoreGraphics

protocol ConfigValuesProtocol {
    var cols: Int? { get set }
    var rows: Int? { get set }
    var cellStyle: CellStyle? { get set }
    var hotkey: HotkeyConfig? { get set }
    var pinnedHotkey: HotkeyConfig? { get set }
    var socketHealthInterval: Int? { get set }
    var uiScale: Double? { get set }
    var autoHideTimeout: Int? { get set }
    var theme: String? { get set }
    var showMode: ShowMode? { get set }
    var multiMonitorHUDMode: MultiMonitorHUDMode? { get set }
    var unifiedHUDVisibility: SeparateHUDVisibility? { get set }
    var separateHUDVisibility: SeparateHUDVisibility? { get set }
    var displayNavigationWrap: DisplayNavigationWrap? { get set }
    var maxSpaces: Int? { get set }
    var backgroundAlpha: Double? { get set }
    var hudShadow: Bool? { get set }
    var mode: ThemeMode? { get set }
    var iconScale: Double? { get set }
    var showSpaceNumbers: Bool? { get set }
    var showSpaceNames: Bool? { get set }
    var showIconStrip: Bool? { get set }
    var showMultiAppIcons: Bool? { get set }
    var hideMenuBarIcon: Bool? { get set }
    var menuBarDisplayMode: MenuBarDisplayMode? { get set }
    var menuBarNearbyCount: Int? { get set }
    var spaceNames: [Int: String]? { get set }
    var useVimKeys: Bool? { get set }
    var useArrowKeys: Bool? { get set }
    var jumpToSpaceEnabled: Bool? { get set }
    var hudPosition: HUDPosition? { get set }
    var customHUDX: Double? { get set }
    var customHUDY: Double? { get set }
    var showExtraWindows: Bool? { get set }
    var focusSpaceOnWindowDrop: WindowDropFocusMode? { get set }
    var focusSpaceOnWindowDropModifier: WindowDropFocusModifier? { get set }
    var showHUDOnSpaceChange: Bool? { get set }
    var updateMode: UpdateMode? { get set }

    func toGridConfig() -> (config: GridConfig, needsRepair: Bool)

    var gridConfig: GridConfig { get }
}

protocol TOMLParserProtocol {
    static func parse(_ data: String) throws -> ConfigValues
}

protocol ConfigLoaderProtocol {
    static func load(from path: String, silentMode: Bool) -> (values: ConfigValues, needsRepair: Bool)
    static func save(_ values: ConfigValues, to path: String)
    static func save(_ config: GridConfig, to path: String)
    static func createDefaultConfigFile(at path: String)
}
