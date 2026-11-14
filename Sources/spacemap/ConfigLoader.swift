import Foundation

/// Why a load replaced or repaired the file. `load` keeps its existing tuple;
/// `loadReportingResult` exposes this for callers that can surface a message.
enum ConfigLoadStatus: Equatable {
    case loaded
    case repaired
    case createdDefault
    case unreadable
    case oversized
    case parseFailed
}

enum ConfigLoader {

    static let configPath = NSString(string: "~/.config/spacemap/config.toml").expandingTildeInPath

    /// Fail-closed ceilings. Decode logic below is untouched; oversized input
    /// never reaches it.
    static let maxConfigBytes = 256 * 1024
    static let maxLineBytes = 16 * 1024

    /// One lock for every disk load/save. Recursive because self-heal saves
    /// while a load holds the lock, and `update` nests a load inside a save.
    private static let ioLock = NSRecursiveLock()
    /// Log a parse failure once per path; cleared after a successful parse so
    /// a later relapse logs again instead of staying silent forever.
    private static var loggedParseFailures: Set<String> = []

    static func isSymlink(at path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    static func load(from path: String, silentMode: Bool) -> (values: ConfigValues, needsRepair: Bool) {
        let result = loadReportingResult(from: path, silentMode: silentMode)
        return (result.values, result.needsRepair)
    }

    /// Additive counterpart to `load`: same behavior plus a status explaining
    /// unreadable / oversized / parse-failed files.
    static func loadReportingResult(
        from path: String,
        silentMode: Bool
    ) -> (values: ConfigValues, needsRepair: Bool, status: ConfigLoadStatus) {
        ioLock.lock()
        defer { ioLock.unlock() }
        return loadUnlocked(from: path, silentMode: silentMode)
    }

    private static func loadUnlocked(
        from path: String,
        silentMode: Bool,
        repair: Bool = true
    ) -> (values: ConfigValues, needsRepair: Bool, status: ConfigLoadStatus) {
        if isSymlink(at: path) {
            NSLog("spacemap/ConfigLoader: refusing to read symlinked config at \(path)")
            return (ConfigValues(), true, .unreadable)
        }
        // O_NOFOLLOW open: a link swapped in after the check above still
        // fails here instead of being followed (TOCTOU). Nil also covers
        // missing/unreadable files.
        guard let read = nofollowData(at: path, limit: maxConfigBytes) else {
            if !silentMode { NSLog("spacemap/ConfigLoader: failed to read config at \(path)") }
            let wroteDefault = createDefaultConfigFileUnlocked(at: path)
            return (ConfigValues(), true, wroteDefault ? .createdDefault : .unreadable)
        }
        // Stop at the ceiling instead of slurping a huge file into memory.
        guard !read.exceeded else {
            NSLog("spacemap/ConfigLoader: config at \(path) exceeds size ceilings — using defaults")
            return (ConfigValues(), true, .oversized)
        }
        guard var raw = String(data: read.data, encoding: .utf8) else {
            if !silentMode { NSLog("spacemap/ConfigLoader: config at \(path) is not UTF-8") }
            _ = createDefaultConfigFileUnlocked(at: path)
            return (ConfigValues(), true, .unreadable)
        }
        if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
        let contents = raw
        if !silentMode { NSLog("spacemap/ConfigLoader: successfully read config from \(path)") }

        // Fail closed on absurd single lines even though the byte ceiling passed.
        guard contents.split(separator: "\n", omittingEmptySubsequences: false)
            .allSatisfy({ $0.utf8.count <= maxLineBytes }) else {
            NSLog("spacemap/ConfigLoader: config at \(path) has an oversized line — using defaults")
            return (ConfigValues(), true, .oversized)
        }

        let parsed: ConfigValues
        do {
            parsed = try TOMLParser.parse(contents)
        } catch {
            // Never overwrite a file we could not understand: the user can fix
            // a broken file, but cannot recover defaults written over it. Fall
            // back for this session and leave the bytes untouched.
            logParseFailureOnce(at: path, error.localizedDescription)
            return (ConfigValues(), true, .parseFailed)
        }
        // A later relapse should log again.
        loggedParseFailures.remove(path)
        let values = sanitizeLabels(parsed)
        let (resolved, needsRepair) = values.toGridConfig()
        guard needsRepair else {
            return (values, false, .loaded)
        }
        // Persist the resolved model, not the raw values: writing raw input
        // (e.g. `cols = 9223372036854775807`) makes every load rediscover the
        // same repair and rewrite the file forever. `update` passes
        // `repair: false` so it writes once, after applying its mutation.
        if repair {
            _ = saveUnlocked(ConfigValues(from: resolved), to: path)
        }
        let resolvedValues = ConfigValues(from: resolved)
        return (resolvedValues, true, .repaired)
    }

    /// O_NOFOLLOW read of a regular file, capped at `limit + 1` bytes so the
    /// size check is decided on one extra byte rather than a full slurp.
    /// Returns nil for symlinks (even ones planted after `isSymlink`),
    /// directories, and read failures.
    private static func nofollowData(at path: String, limit: Int) -> (data: Data, exceeded: Bool)? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var statBuf = stat()
        guard fstat(fd, &statBuf) == 0, (statBuf.st_mode & S_IFMT) == S_IFREG else { return nil }
        var data = Data()
        data.reserveCapacity(min(Int(statBuf.st_size), limit + 1))
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count <= limit {
            let remaining = limit + 1 - data.count
            let chunk = min(buffer.count, max(remaining, 1))
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, chunk) }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return (data, data.count > limit)
    }

    static func save(_ values: ConfigValues, to path: String) {
        _ = saveReportingResult(values, to: path)
    }

    /// Additive counterpart to `save`: returns whether the file was written.
    @discardableResult
    static func saveReportingResult(_ values: ConfigValues, to path: String) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        return saveUnlocked(values, to: path)
    }

    private static func saveUnlocked(_ values: ConfigValues, to path: String) -> Bool {
        // EEXIST + O_NOFOLLOW: never write through a planted link or dir.
        guard !isSymlink(at: path) else {
            NSLog("spacemap/ConfigLoader: refusing to write through symlink at \(path)")
            return false
        }
        let dir = (path as NSString).deletingLastPathComponent
        secureDirectory(at: dir)
        backupConfig(at: path)
        let content = tomlConfigString(from: values, includeHeaderComments: true)
        return secureWrite(content, to: path)
    }

    static func save(_ config: GridConfig, to path: String) {
        _ = saveReportingResult(config, to: path)
    }

    /// Additive counterpart to `save(_:to:)` for GridConfig callers.
    @discardableResult
    static func saveReportingResult(_ config: GridConfig, to path: String) -> Bool {
        saveReportingResult(ConfigValues(from: config), to: path)
    }

    /// Atomic read-modify-write of the on-disk config. Prefer this over a
    /// separate `load` + `save` pair so concurrent writers cannot drop each
    /// other's changes.
    @discardableResult
    static func update(
        at path: String,
        silentMode: Bool,
        _ mutate: (inout GridConfig) -> Void
    ) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        // One write only: a repair write here would immediately be followed by
        // the post-mutation save, rotating the backup twice.
        let result = loadUnlocked(from: path, silentMode: silentMode, repair: false)
        guard result.status != .parseFailed else { return false }
        var config = result.values.gridConfig
        mutate(&config)
        return saveUnlocked(ConfigValues(from: config), to: path)
    }

    static func createDefaultConfigFile(at path: String) {
        ioLock.lock()
        defer { ioLock.unlock() }
        _ = createDefaultConfigFileUnlocked(at: path)
    }

    @discardableResult
    static func createDefaultConfigFileReportingResult(at path: String) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        return createDefaultConfigFileUnlocked(at: path)
    }

    private static func createDefaultConfigFileUnlocked(at path: String) -> Bool {
        guard !isSymlink(at: path) else {
            NSLog("spacemap/ConfigLoader: refusing to write through symlink at \(path)")
            return false
        }
        secureDirectory(at: (path as NSString).deletingLastPathComponent)
        backupConfig(at: path)
        let content = tomlConfigString(from: ConfigValues(), includeHeaderComments: true)
        let written = secureWrite(content, to: path)
        if written {
            NSLog("spacemap: default config created at \(path)")
        }
        return written
    }

    private static func logParseFailureOnce(at path: String, _ reason: String) {
        guard loggedParseFailures.insert(path).inserted else { return }
        NSLog("spacemap/ConfigLoader: parse failed at \(path) (\(reason)) — using defaults")
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
        // U+2028/U+2029 are line breaks to many consumers and cannot survive a
        // line-oriented config round-trip. Replace with a space rather than
        // letting them split the document; the writer also escapes them.
        let replaced = label
            .replacingOccurrences(of: "\u{2028}", with: " ")
            .replacingOccurrences(of: "\u{2029}", with: " ")
        let filtered = String(replaced.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation,
                 .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
                 .spaceSeparator:
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
            "backgroundStyle = \(tomlString((values.backgroundStyle ?? defaults.backgroundStyle).rawValue))",
            "glassStyle = \(tomlString((values.glassStyle ?? defaults.glassStyle).rawValue))",
            "glassClearVariant = \(values.glassClearVariant ?? defaults.glassClearVariant)",
            "glassRegularVariant = \(values.glassRegularVariant ?? defaults.glassRegularVariant)",
            "glassTintedVariant = \(values.glassTintedVariant ?? defaults.glassTintedVariant)",
            "glassTintedMaterial = \(tomlString((values.glassTintedMaterial ?? defaults.glassTintedMaterial).rawValue))",
            "glassClearOpacity = \(values.glassClearOpacity ?? defaults.glassClearOpacity)",
            "glassRegularOpacity = \(values.glassRegularOpacity ?? defaults.glassRegularOpacity)",
            "glassTintedOpacity = \(values.glassTintedOpacity ?? defaults.glassTintedOpacity)",
            "solidOpacity = \(values.solidOpacity ?? defaults.solidOpacity)",
            "matchBackgroundOpacity = \(values.matchBackgroundOpacity ?? defaults.matchBackgroundOpacity)",
            "hudShadow = \(values.hudShadow ?? defaults.hudShadow)",
            "hudCornerRadius = \(values.hudCornerRadius ?? defaults.hudCornerRadius)",
            "spacesMatchBackground = \(values.spacesMatchBackground ?? defaults.spacesMatchBackground)",
            "spacesBackgroundStyle = \(tomlString((values.spacesBackgroundStyle ?? defaults.spacesBackgroundStyle).rawValue))",
            "spacesGlassStyle = \(tomlString((values.spacesGlassStyle ?? defaults.spacesGlassStyle).rawValue))",
            "spacesGlassClearVariant = \(values.spacesGlassClearVariant ?? defaults.spacesGlassClearVariant)",
            "spacesGlassRegularVariant = \(values.spacesGlassRegularVariant ?? defaults.spacesGlassRegularVariant)",
            "spacesGlassTintedVariant = \(values.spacesGlassTintedVariant ?? defaults.spacesGlassTintedVariant)",
            "spacesGlassTintedMaterial = \(tomlString((values.spacesGlassTintedMaterial ?? defaults.spacesGlassTintedMaterial).rawValue))",
            "spacesOpacity = \(values.spacesOpacity ?? defaults.spacesOpacity)",
            "spacesCornerRadius = \(values.spacesCornerRadius ?? defaults.spacesCornerRadius)",
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
            "glassStyle = \(tomlString(glyphStrip.glassStyle.rawValue))",
            "glassClearVariant = \(glyphStrip.glassClearVariant)",
            "glassRegularVariant = \(glyphStrip.glassRegularVariant)",
            "glassTintedVariant = \(glyphStrip.glassTintedVariant)",
            "glassTintedMaterial = \(tomlString(glyphStrip.glassTintedMaterial.rawValue))",
            "matchHUDAppearance = \(glyphStrip.matchHUDAppearance)",
            "backgroundOpacity = \(glyphStrip.backgroundOpacity)",
            "matchBackgroundOpacity = \(glyphStrip.matchBackgroundOpacity)",
            "glassClearOpacity = \(glyphStrip.glassClearOpacity)",
            "glassRegularOpacity = \(glyphStrip.glassRegularOpacity)",
            "glassTintedOpacity = \(glyphStrip.glassTintedOpacity)",
            "solidOpacity = \(glyphStrip.solidOpacity)",
            "shape = \(tomlString(glyphStrip.shape.rawValue))",
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
            "orientation = \(tomlString(glyphStrip.orientation.rawValue))",
            "verticalLayout = \(tomlString(glyphStrip.verticalLayout.rawValue))",
            "lockPosition = \(glyphStrip.lockPosition)",
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
        let backupPath = path + ".bak"
        rotateBackup(at: backupPath)
        // Oversized input is not worth copying, but it must not be destroyed
        // by the write that follows: move it aside instead. Cap the read as
        // well so a lying/growing file cannot make the backup unbounded.
        if srcStat.st_size > off_t(maxConfigBytes) {
            moveAside(path: path, backupPath: backupPath, srcFd: srcFd)
            return
        }
        let data = FileHandle(fileDescriptor: srcFd, closeOnDealloc: false)
            .readData(ofLength: maxConfigBytes + 1)
        guard data.count <= maxConfigBytes else {
            moveAside(path: path, backupPath: backupPath, srcFd: srcFd)
            return
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

    /// Rotate `path.bak` to `path.bak.1`, dropping whatever was there.
    private static func rotateBackup(at backupPath: String) {
        let rotatedPath = backupPath + ".1"
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
    }

    /// Move the pinned regular file from `path` to the backup slot without
    /// reading it. `fchmod` on the still-open fd avoids a path-based chmod race.
    private static func moveAside(path: String, backupPath: String, srcFd: Int32) {
        guard rename(path, backupPath) == 0 else { return }
        _ = fchmod(srcFd, mode_t(0o600))
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
            // U+2028/U+2029 split lines for many readers; escape them so a
            // label containing one still round-trips through this parser.
            case 0x2028: escaped += "\\u2028"
            case 0x2029: escaped += "\\u2029"
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
