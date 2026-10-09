import Foundation

enum ConfigLoader: ConfigLoaderProtocol {

    static let configPath = NSString(string: "~/.config/spacemap/config.toml").expandingTildeInPath

    /// Fail-closed ceilings. Decode logic below is untouched; oversized input
    /// never reaches it.
    static let maxConfigBytes = 256 * 1024
    static let maxLineBytes = 16 * 1024

    static func isSymlink(at path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    static func load(from path: String, silentMode: Bool) -> (values: ConfigValues, needsRepair: Bool) {
        // O_NOFOLLOW equivalent: never read through a link someone else owns.
        guard !isSymlink(at: path) else {
            NSLog("spacemap/ConfigLoader: refusing to read symlinked config at \(path)")
            return (ConfigValues(), true)
        }
        let contents: String
        do {
            var raw = try String(contentsOfFile: path, encoding: .utf8)
            if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
            contents = raw
            if !silentMode { NSLog("spacemap/ConfigLoader: successfully read config from \(path)") }
        } catch {
            if !silentMode { NSLog("spacemap/ConfigLoader: failed to read config at \(path) — error: \(error)") }
            createDefaultConfigFile(at: path)
            return (ConfigValues(), true)
        }

        // Fail closed on bombs: oversized file or absurd single line.
        guard contents.utf8.count <= maxConfigBytes,
              contents.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy({ $0.utf8.count <= maxLineBytes }) else {
            NSLog("spacemap/ConfigLoader: config at \(path) exceeds size ceilings — using defaults")
            return (ConfigValues(), true)
        }

        let parsed: ConfigValues
        do {
            parsed = try TOMLParser.parse(contents)
        } catch {
            if !silentMode { NSLog("spacemap/ConfigLoader: parse failed (\(error.localizedDescription)) — using defaults") }
            parsed = ConfigValues()
        }
        let values = sanitizeLabels(parsed)
        let (_, needsRepair) = values.toGridConfig()
        if needsRepair {
            save(values, to: path)
        }
        return (values, needsRepair)
    }

    static func save(_ values: ConfigValues, to path: String) {
        // EEXIST + O_NOFOLLOW: never write through a planted link or dir.
        guard !isSymlink(at: path) else {
            NSLog("spacemap/ConfigLoader: refusing to write through symlink at \(path)")
            return
        }
        let dir = (path as NSString).deletingLastPathComponent
        secureDirectory(at: dir)
        backupConfig(at: path)
        let content = tomlConfigString(from: values, includeHeaderComments: true)
        secureWrite(content, to: path)
    }

    static func save(_ config: GridConfig, to path: String) {
        let values = ConfigValues(from: config)
        save(values, to: path)
    }

    static func createDefaultConfigFile(at path: String) {
        guard !isSymlink(at: path) else {
            NSLog("spacemap/ConfigLoader: refusing to write through symlink at \(path)")
            return
        }
        secureDirectory(at: (path as NSString).deletingLastPathComponent)
        backupConfig(at: path)
        let content = tomlConfigString(from: ConfigValues(), includeHeaderComments: true)
        if secureWrite(content, to: path) {
            NSLog("spacemap: default config created at \(path)")
        }
    }

    /// Config dir 0700, files 0600. XDG config holds hotkeys/behavior — no
    /// reason group/other ever reads it.
    @discardableResult
    static func secureWrite(_ content: String, to path: String) -> Bool {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch {
            NSLog("spacemap: failed to save config to \(path): \(error)")
            return false
        }
    }

    static func secureDirectory(at path: String) {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        } catch {
            NSLog("spacemap: failed to secure config dir at \(path): \(error)")
        }
    }

    /// Label charset allowlist: Unicode letters/numbers/marks/punctuation/
    /// symbols/space separators (emoji survive); control/format/private-use
    /// rejected. Runs post-decode — decode logic itself is untouched.
    static func sanitizeLabels(_ values: ConfigValues) -> ConfigValues {
        var out = values
        if let names = out.spaceNames {
            out.spaceNames = Dictionary(uniqueKeysWithValues: names.map { ($0.key, sanitizeLabel($0.value)) })
        }
        if let profiles = out.spaceNameProfiles {
            out.spaceNameProfiles = profiles.map { profile in
                var copy = profile
                copy.name = sanitizeLabel(profile.name)
                copy.spaceNames = Dictionary(uniqueKeysWithValues: profile.spaceNames.map { ($0.key, sanitizeLabel($0.value)) })
                return copy
            }
        }
        return out
    }

    static func sanitizeLabel(_ label: String) -> String {
        String(label.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation,
                 .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
                 .spaceSeparator, .lineSeparator, .paragraphSeparator:
                return true
            default:
                return false
            }
        })
    }


    static func tomlConfigString(from values: ConfigValues, includeHeaderComments: Bool) -> String {
        let defaults = GridConfig.default
        var lines: [String] = []
        if includeHeaderComments {
            lines += [
                "# Spacemap config",
                ""
            ]
        }

        lines += [
            "[grid]",
            "cols = \(values.cols ?? defaults.cols)",
            "rows = \(values.rows ?? defaults.rows)",
            "cellStyle = \(tomlString(ConfigLoader.cellStyleName(values.cellStyle ?? defaults.cellStyle)))",
            "showMode = \(tomlString((values.showMode ?? defaults.showMode).rawValue))",
            "multiMonitorHUDMode = \(tomlString((values.multiMonitorHUDMode ?? defaults.multiMonitorHUDMode).rawValue))",
            "unifiedHUDVisibility = \(tomlString((values.unifiedHUDVisibility ?? defaults.unifiedHUDVisibility).rawValue))",
            "separateHUDVisibility = \(tomlString((values.separateHUDVisibility ?? defaults.separateHUDVisibility).rawValue))",
            "maxSpaces = \(values.maxSpaces ?? defaults.maxSpaces)",
            "showSpaceNumbers = \(values.showSpaceNumbers ?? defaults.showSpaceNumbers)",
            "showIconStrip = \(values.showIconStrip ?? defaults.showIconStrip)",
            "showMultiAppIcons = \(values.showMultiAppIcons ?? defaults.showMultiAppIcons)",
            "",
            "[spaceNames]",
            "showSpaceNames = \(values.showSpaceNames ?? defaults.showSpaceNames)",
            "",
            "[spaceNames.names]"
        ]
        let spaceNames = values.spaceNames ?? defaults.spaceNames
        for key in spaceNames.keys.sorted() {
            if let name = spaceNames[key] {
                lines.append("\(tomlString(String(key))) = \(tomlString(name))")
            }
        }

        lines += [
            "",
            "[appearance]",
            "theme = \(tomlString(values.theme ?? defaults.theme))",
            "mode = \(tomlString((values.mode ?? defaults.mode).rawValue))",
            "backgroundAlpha = \(values.backgroundAlpha ?? defaults.backgroundAlpha)",
            "hudShadow = \(values.hudShadow ?? defaults.hudShadow)",
            "iconScale = \(values.iconScale ?? defaults.iconScale)",
            "uiScale = \(values.uiScale ?? defaults.uiScale)",
            "",
            "[behavior]",
            "autoHideTimeout = \(values.autoHideTimeout ?? defaults.autoHideTimeout)",
            "displayNavigationWrap = \(tomlString((values.displayNavigationWrap ?? defaults.displayNavigationWrap).rawValue))",
            "useVimKeys = \(values.useVimKeys ?? defaults.useVimKeys)",
            "useArrowKeys = \(values.useArrowKeys ?? defaults.useArrowKeys)",
            "useExtendedKeys = \(values.useExtendedKeys ?? defaults.useExtendedKeys)",
            "jumpToSpaceEnabled = \(values.jumpToSpaceEnabled ?? defaults.jumpToSpaceEnabled)",
            "customHUDX = \(values.customHUDX ?? defaults.customHUDX)",
            "customHUDY = \(values.customHUDY ?? defaults.customHUDY)",
            "focusSpaceOnWindowDrop = \(tomlString((values.focusSpaceOnWindowDrop ?? defaults.focusSpaceOnWindowDrop).rawValue))",
            "focusSpaceOnWindowDropModifier = \(tomlString((values.focusSpaceOnWindowDropModifier ?? defaults.focusSpaceOnWindowDropModifier).rawValue))",
            "showHUDOnSpaceChange = \(values.showHUDOnSpaceChange ?? defaults.showHUDOnSpaceChange)",
            "hideMenuBarIcon = \(values.hideMenuBarIcon ?? defaults.hideMenuBarIcon)",
            "menuBarDisplayMode = \(tomlString((values.menuBarDisplayMode ?? defaults.menuBarDisplayMode).rawValue))",
            "menuBarNearbyCount = \(values.menuBarNearbyCount ?? defaults.menuBarNearbyCount)",
            "updateMode = \(tomlString((values.updateMode ?? defaults.updateMode).rawValue))"
        ]
        appendHotkey(values.hotkey ?? defaults.hotkey, section: "behavior.hotkey", to: &lines)
        appendHotkey(values.pinnedHotkey ?? defaults.pinnedHotkey, section: "behavior.pinnedHotkey", to: &lines)
        appendHotkey(
            values.glyphStripHotkey ?? defaults.glyphStripHotkey,
            section: "behavior.glyphStripHotkey",
            to: &lines
        )

        lines += ["", "[behavior.hudPosition]"]
        switch values.hudPosition ?? defaults.hudPosition {
        case .center: lines.append("kind = \"center\"")
        case .top: lines.append("kind = \"top\"")
        case .bottom: lines.append("kind = \"bottom\"")
        case .custom(let x, let y):
            lines += ["kind = \"custom\"", "x = \(x)", "y = \(y)"]
        }

        lines += ["", "[glyphStrip]"]
        let glyphStrip = values.glyphStrip ?? defaults.glyphStrip
        lines += [
            "enabled = \(glyphStrip.enabled)",
            "theme = \(tomlString(glyphStrip.theme))",
            "showSpaceNumbers = \(glyphStrip.showSpaceNumbers)",
            "showLayoutSuffix = \(glyphStrip.showLayoutSuffix)",
            "showAppIcons = \(glyphStrip.showAppIcons)",
            "iconSource = \(tomlString(glyphStrip.iconSource.rawValue))",
            "dedupeAppsPerSpace = \(glyphStrip.dedupeAppsPerSpace)",
            "maxIconsPerSpace = \(glyphStrip.maxIconsPerSpace)",
            "iconSize = \(glyphStrip.iconSize)",
            "indexSize = \(glyphStrip.indexSize)",
            "highlightCurrentSpace = \(glyphStrip.highlightCurrentSpace)",
            "backgroundMaterial = \(tomlString(glyphStrip.backgroundMaterial.rawValue))",
            "glassAmount = \(glyphStrip.glassAmount)",
            "useThemeTint = \(glyphStrip.useThemeTint)",
            "shape = \(tomlString(glyphStrip.shape.rawValue))",
            "backgroundOpacity = \(glyphStrip.backgroundOpacity)",
            "cornerRadius = \(glyphStrip.cornerRadius)",
            "margin = \(glyphStrip.margin)",
            "iconSpacing = \(glyphStrip.iconSpacing)",
            "indexPadding = \(glyphStrip.indexPadding)",
            "yOffset = \(glyphStrip.yOffset)",
            "hoverPadding = \(glyphStrip.hoverPadding)",
            "hoverCornerRadius = \(glyphStrip.hoverCornerRadius)",
            "showDisplaySeparators = \(glyphStrip.showDisplaySeparators)",
            "showAddSpaceButton = \(glyphStrip.showAddSpaceButton)",
            "showPlaceholders = \(glyphStrip.showPlaceholders)",
            "leftClickAction = \(tomlString(glyphStrip.leftClickAction.rawValue))",
            "rightClickAction = \(tomlString(glyphStrip.rightClickAction.rawValue))",
            "middleClickAction = \(tomlString(glyphStrip.middleClickAction.rawValue))",
            "position = \(tomlString(glyphStrip.position.rawValue))",
            "xOffset = \(glyphStrip.xOffset)",
            "borderEnabled = \(glyphStrip.borderEnabled)"
        ]

        let appFont = values.appFont ?? defaults.appFont
        lines += [
            "",
            "[appFont]",
            "updateMode = \(tomlString(appFont.updateMode.rawValue))",
            "installedVersion = \(tomlString(appFont.installedVersion))",
            "lastCheck = \(appFont.lastCheck)"
        ]

        let profiles = values.spaceNameProfiles ?? defaults.spaceNameProfiles
        let activeProfileIndex = values.activeSpaceNameProfileIndex ?? defaults.activeSpaceNameProfileIndex
        let defaultProfile = SpaceNameProfile.default
        let hasNonDefaultProfiles = profiles.count != 1 ||
            profiles.first?.name != defaultProfile.name ||
            !(profiles.first?.spaceNames.isEmpty ?? true)

        if hasNonDefaultProfiles {
            // Indexed-dotted tables only: the document parser supports flat
            // `[a.b]` tables but neither `[[array]]` nor inline `{...}` maps,
            // so profiles must be written in a form the reader parses back.
            // Reader: TOMLConfigDecoder indexed-schema block. Active profile
            // is the `activeIndex` int; out-of-range heals to 0 on load.
            lines += ["", "[spaceNameProfiles]", "activeIndex = \(activeProfileIndex)"]
            for (i, profile) in profiles.enumerated() {
                lines += ["", "[spaceNameProfiles.\(i)]", "name = \(tomlString(profile.name))"]
                if !profile.spaceNames.isEmpty {
                    lines += ["", "[spaceNameProfiles.\(i).names]"]
                    for key in profile.spaceNames.keys.sorted() {
                        if let name = profile.spaceNames[key] {
                            lines.append("\(tomlString(String(key))) = \(tomlString(name))")
                        }
                    }
                }
            }
        }

        lines += [
            "",
            "[advanced]",
            "socketHealthInterval = \(values.socketHealthInterval ?? defaults.socketHealthInterval)",
            "showExtraWindows = \(values.showExtraWindows ?? defaults.showExtraWindows)"
        ]
        return lines.joined(separator: "\n") + "\n"
    }


    private static func backupConfig(at path: String) {
        guard FileManager.default.fileExists(atPath: path), !isSymlink(at: path) else { return }
        let backupPath = path + ".bak"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupPath)
    }


    private static func appendHotkey(_ hotkey: HotkeyConfig, section: String, to lines: inout [String]) {
        lines += ["", "[\(section)]"]
        switch hotkey.key {
        case .none:
            lines.append("keyKind = \"none\"")
        case .keyCode(let keyCode):
            lines += ["keyKind = \"keyCode\"", "keyCode = \(keyCode)"]
        case .mediaKey(let mediaKey):
            lines += ["keyKind = \"mediaKey\"", "mediaKey = \(tomlString(mediaKey.rawValue))"]
        }
        lines.append("modifiers = \(tomlStringArray(Hotkey.modifierNames(for: hotkey.modifiers)))")
    }

    static func tomlString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: escaped += "\\b"
            case 0x09: escaped += "\\t"
            case 0x0A: escaped += "\\n"
            case 0x0C: escaped += "\\f"
            case 0x0D: escaped += "\\r"
            case 0x22: escaped += "\\\""
            case 0x5C: escaped += "\\\\"
            case 0x00...0x1F, 0x7F:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    private static func tomlStringArray(_ values: [String]) -> String {
        "[" + values.map(tomlString).joined(separator: ", ") + "]"
    }

    static func cellStyleName(_ style: CellStyle) -> String {
        switch style {
        case .rects: return "rects"
        case .hybrid: return "hybrid"
        case .icons: return "icons"
        case .thumbnails: return "thumbnails"
        case .simple: return "simple"
        }
    }
}
