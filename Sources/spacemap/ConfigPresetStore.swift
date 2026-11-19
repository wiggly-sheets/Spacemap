import Foundation

extension Notification.Name {
    /// config.toml was replaced from outside Settings (preset apply or import).
    /// An open Settings window must rebuild: its controls still hold the old
    /// values, and the next control change would save them back over the new
    /// file.
    static let configReplacedExternally = Notification.Name("configReplacedExternally")
}

/// Named config packages. A preset is one complete config.toml under
/// `~/.config/spacemap/presets/`; the active name lives beside them in
/// `.active`. Switching flushes config.toml back into the outgoing preset
/// first, so edits made while a preset is active survive the next switch.
struct ConfigPresetStore {
    /// Where a new preset starts from.
    enum Source: Hashable {
        case defaults
        case current
        case preset(String)
    }

    static let defaultDirectory = NSString(
        string: "~/.config/spacemap/presets"
    ).expandingTildeInPath

    static let shared = ConfigPresetStore(
        directory: defaultDirectory,
        configPath: ConfigStore.configPath
    )

    let directory: String
    let configPath: String

    private var activePath: String {
        URL(fileURLWithPath: directory).appendingPathComponent(".active").path
    }

    private static let maxNameLength = 40
    private static let nameCharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-"
    )

    /// One safe path component. Rejects separators, dotfiles, and traversal.
    static func sanitizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxNameLength,
              !trimmed.hasPrefix("."),
              trimmed.unicodeScalars.allSatisfy({ nameCharacterSet.contains($0) }) else { return nil }
        return trimmed
    }

    private func presetPath(_ name: String) -> String {
        URL(fileURLWithPath: directory).appendingPathComponent(name + ".toml").path
    }

    func names() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return entries
            .filter { $0.hasSuffix(".toml") }
            .map { String($0.dropLast(".toml".count)) }
            .filter { Self.sanitizedName($0) == $0 }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Active preset, or nil when config.toml is the only config (the default).
    var activeName: String? {
        guard let text = ConfigLoader.readText(at: activePath) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.sanitizedName(name) == name, names().contains(name) else { return nil }
        return name
    }

    /// Switch presets: save config.toml into the outgoing preset, then load the
    /// target. Returns false when the target is missing or unparsable, leaving
    /// the current config in place.
    @discardableResult
    func apply(_ rawName: String) -> Bool {
        guard let name = Self.sanitizedName(rawName) else { return false }
        flushActive()
        guard let text = ConfigLoader.readText(at: presetPath(name)),
              let parsed = try? TOMLParser.parse(text) else { return false }
        // Preset text may be partial or hand-edited: save the resolved config,
        // never the raw text, so repairs apply before it reaches config.toml.
        guard ConfigLoader.saveReportingResult(Self.exportable(parsed.config), to: configPath) else { return false }
        setActive(name)
        return true
    }

    /// Write config.toml into the active preset. Called before a switch, so the
    /// active preset file is allowed to lag behind current edits until then.
    func flushActive() {
        guard let active = activeName else { return }
        let config = ConfigLoader.loadReportingResult(from: configPath, silentMode: true).config
        _ = ConfigLoader.saveReportingResult(Self.exportable(config), to: presetPath(active))
    }

    @discardableResult
    func create(_ rawName: String, from source: Source) -> Bool {
        guard let name = Self.sanitizedName(rawName) else { return false }
        let path = presetPath(name)
        guard !FileManager.default.fileExists(atPath: path) else { return false }

        let config: SpacemapConfig
        switch source {
        case .defaults:
            config = .default
        case .current:
            config = ConfigLoader.loadReportingResult(from: configPath, silentMode: true).config
        case .preset(let rawSource):
            guard let sourceName = Self.sanitizedName(rawSource),
                  let text = ConfigLoader.readText(at: presetPath(sourceName)),
                  let parsed = try? TOMLParser.parse(text) else { return false }
            config = parsed.config
        }
        return ConfigLoader.saveReportingResult(Self.exportable(config), to: path)
    }

    /// Remove a preset file. config.toml keeps whatever is loaded now.
    @discardableResult
    func delete(_ rawName: String) -> Bool {
        guard let name = Self.sanitizedName(rawName) else { return false }
        if activeName == name {
            try? FileManager.default.removeItem(atPath: activePath)
        }
        do {
            try FileManager.default.removeItem(atPath: presetPath(name))
            return true
        } catch {
            return false
        }
    }

    func exportConfig(to url: URL) -> Bool {
        let config = ConfigLoader.loadReportingResult(from: configPath, silentMode: true).config
        let text = ConfigLoader.tomlConfigString(
            from: Self.exportable(config),
            includeHeaderComments: true
        )
        return ConfigLoader.secureWrite(text, to: url.path)
    }

    /// Replace config.toml with a picked file. Rejects unparsable input rather
    /// than leaving the user with a broken config.
    @discardableResult
    func importConfig(from url: URL) -> Bool {
        guard let text = ConfigLoader.readText(at: url.path),
              let parsed = try? TOMLParser.parse(text) else { return false }
        return ConfigLoader.saveReportingResult(Self.exportable(parsed.config), to: configPath)
    }

    /// Font install state is machine state, not taste: a shared preset must not
    /// claim another machine's font version.
    static func exportable(_ config: SpacemapConfig) -> SpacemapConfig {
        var copy = config
        copy.appFont.installedVersion = ""
        copy.appFont.lastCheck = 0
        return copy
    }

    private func setActive(_ name: String) {
        ConfigLoader.secureDirectory(at: directory)
        _ = ConfigLoader.secureWrite(name + "\n", to: activePath)
    }
}
