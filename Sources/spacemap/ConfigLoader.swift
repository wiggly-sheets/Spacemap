import Foundation

enum ConfigLoader {

    static let configPath = NSString(string: "~/.config/spacemap/config.toml").expandingTildeInPath

    /// Fail-closed ceilings. Decode logic below is untouched; oversized input
    /// never reaches it.
    static let maxConfigBytes = 256 * 1024
    static let maxLineBytes = 16 * 1024

    static func isSymlink(at path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    static func load(from path: String, silentMode: Bool) -> (values: ConfigValues, needsRepair: Bool) {
        if isSymlink(at: path) {
            NSLog("spacemap/ConfigLoader: refusing to read symlinked config at \(path)")
            return (ConfigValues(), true)
        }
        // O_NOFOLLOW open: a link swapped in after the check above still
        // fails here instead of being followed (TOCTOU). Nil also covers
        // missing/unreadable files.
        guard let rawContents = nofollowContents(at: path) else {
            if !silentMode { NSLog("spacemap/ConfigLoader: failed to read config at \(path)") }
            createDefaultConfigFile(at: path)
            return (ConfigValues(), true)
        }
        var raw = rawContents
        if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
        let contents = raw
        if !silentMode { NSLog("spacemap/ConfigLoader: successfully read config from \(path)") }

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

    /// O_NOFOLLOW read of a regular file. Returns nil for symlinks (even
    /// ones planted after `isSymlink`), directories, and read failures.
    private static func nofollowContents(at path: String) -> String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var statBuf = stat()
        guard fstat(fd, &statBuf) == 0, (statBuf.st_mode & S_IFMT) == S_IFREG else { return nil }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
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
    /// Temp file born 0600, then renamed: no world-readable window
    /// between create and chmod. Rename over symlink replaces link itself.
    @discardableResult
    static func secureWrite(_ content: String, to path: String) -> Bool {
        guard let data = content.data(using: .utf8) else { return false }
        let dir = (path as NSString).deletingLastPathComponent
        let tmpPath = (dir as NSString).appendingPathComponent(
            ".spacemap.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp")
        let fd = open(tmpPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else {
            NSLog("spacemap: failed to save config to \(path): cannot create temp file")
            return false
        }
        defer { close(fd) }
        let bytes = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        // write() on blocking fd writes all or fails; short write = failure.
        guard bytes == data.count else {
            unlink(tmpPath)
            NSLog("spacemap: failed to save config to \(path): short write")
            return false
        }
        _ = fchmod(fd, mode_t(0o600))
        guard rename(tmpPath, path) == 0 else {
            unlink(tmpPath)
            NSLog("spacemap: failed to save config to \(path): rename failed")
            return false
        }
        return true
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
            let sanitized = Dictionary(uniqueKeysWithValues: names.map { ($0.key, sanitizeLabel($0.value)) })
            if sanitized != names { out.hasInvalidSpaceNames = true }
            out.spaceNames = sanitized
        }
        if let profiles = out.spaceNameProfiles {
            out.spaceNameProfiles = profiles.map { profile in
                var copy = profile
                let name = sanitizeLabel(profile.name)
                if name != profile.name { out.hasInvalidSpaceNames = true }
                copy.name = name
                let spaceNames = Dictionary(uniqueKeysWithValues: profile.spaceNames.map { ($0.key, sanitizeLabel($0.value)) })
                if spaceNames != profile.spaceNames { out.hasInvalidSpaceNames = true }
                copy.spaceNames = spaceNames
                return copy
            }
        }
        return out
    }

    static let maxLabelChars = 64

    static func sanitizeLabel(_ label: String) -> String {
        let filtered = String(label.unicodeScalars.filter { scalar in
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
        return String(filtered.prefix(maxLabelChars))
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
            "showSpaceLayout = \(values.showSpaceLayout ?? defaults.showSpaceLayout)",
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
            "showExtraWindows = \(values.showExtraWindows ?? defaults.showExtraWindows)",
            "refuseUntrustedYabai = \(values.refuseUntrustedYabai ?? defaults.refuseUntrustedYabai)"
        ]
        return lines.joined(separator: "\n") + "\n"
    }


    private static func backupConfig(at path: String) {
        // Pin source with O_NOFOLLOW fd: link swapped in after isSymlink
        // check fails open() instead of being followed (TOCTOU).
        guard !isSymlink(at: path) else { return }
        let srcFd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard srcFd >= 0 else { return }
        defer { close(srcFd) }
        var srcStat = stat()
        guard fstat(srcFd, &srcStat) == 0, (srcStat.st_mode & S_IFMT) == S_IFREG else { return }
        let data = FileHandle(fileDescriptor: srcFd, closeOnDealloc: false).readDataToEndOfFile()
        let backupPath = path + ".bak"
        let rotatedPath = path + ".bak.1"
        // unlink() never follows: removes planted link itself, not target.
        unlink(rotatedPath)
        var backupStat = stat()
        if lstat(backupPath, &backupStat) == 0 {
            if (backupStat.st_mode & S_IFMT) == S_IFLNK || (backupStat.st_mode & S_IFMT) != S_IFREG {
                unlink(backupPath)
            } else if rename(backupPath, rotatedPath) == 0 {
                // rename moves link itself; lstat gate stops chmod through link.
                var rotStat = stat()
                if lstat(rotatedPath, &rotStat) == 0, (rotStat.st_mode & S_IFMT) == S_IFREG {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rotatedPath)
                }
            }
        }
        // O_EXCL|O_NOFOLLOW: fail closed if link planted after rotation.
        let dstFd = open(backupPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard dstFd >= 0 else { return }
        defer { close(dstFd) }
        let written = data.withUnsafeBytes { write(dstFd, $0.baseAddress, $0.count) }
        guard written == data.count else {
            unlink(backupPath)
            return
        }
        _ = fchmod(dstFd, mode_t(0o600))
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
