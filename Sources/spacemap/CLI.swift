import Foundation

/// One table for every flag argv can carry. Parse, the post-launch actions,
/// and single-instance forwarding all read it, so a new flag lands in every
/// call site at once.
enum CLIFlagTable {
    struct Row: Equatable {
        let flag: String
        let target: Target
    }

    enum Target: Equatable {
        /// Perform this command in this process, then exit.
        case exit(SpacemapCommand)
        /// Validate the next argument as a space selector, then exit.
        case focusSpace
        /// Validate the next argument as a preset name, then exit.
        case configPreset
        /// The instance that keeps running handles it: a socket command when
        /// one is live, a deep link as fallback, and a post-AppKit action on a
        /// fresh launch.
        case deliver(SpacemapCommand, deepLink: String?)
        /// Recognised so it never errors; the running app reads it from argv.
        case marker(SpacemapCommand)
    }

    static let rows: [Row] = [
        Row(flag: "--version", target: .exit(.version)),
        Row(flag: "--help", target: .exit(.help)),
        Row(flag: "--config", target: .exit(.config)),
        Row(flag: "--print-config", target: .exit(.printConfig)),
        Row(flag: "--status", target: .exit(.status)),
        Row(flag: "--update", target: .exit(.update)),
        Row(flag: "--update-font", target: .exit(.updateFont)),
        Row(flag: "--trigger", target: .exit(.toggle)),
        Row(flag: "--space", target: .focusSpace),
        Row(flag: "--config-preset", target: .configPreset),
        Row(flag: "--settings", target: .deliver(.settings, deepLink: "spacemap://settings")),
        Row(flag: "--show-menu", target: .deliver(.showMenu, deepLink: "spacemap://menu")),
        Row(flag: "--restarting", target: .marker(.restarting)),
    ]

    static func row(for flag: String) -> Row? {
        rows.first { $0.flag == flag }
    }

    /// Commands a running instance must handle for these arguments, in argv
    /// order.
    static func deliveredCommands(in arguments: [String]) -> [SpacemapCommand] {
        arguments.compactMap { argument in
            guard let target = row(for: argument)?.target,
                  case .deliver(let command, _) = target else { return nil }
            return command
        }
    }

    static func contains(_ command: SpacemapCommand, in arguments: [String]) -> Bool {
        arguments.contains { argument in
            guard let target = row(for: argument)?.target else { return false }
            switch target {
            case .exit(let found), .deliver(let found, _), .marker(let found):
                return found == command
            case .focusSpace, .configPreset:
                return false
            }
        }
    }
}

/// What this process should do with its arguments. Parse produces it with no
/// side effects; the executor performs it.
enum CLIInvocation: Equatable {
    /// Perform here, then exit.
    case command(SpacemapCommand)
    case focusSpace(SpaceFocusTarget)
    case configPreset(String)
    /// Not a CLI request: continue the normal launch.
    case none
    case error(String)
}

final class CLI {
    private let yabaiService: YabaiService
    private let configStore: ConfigStore
    private let presetStore: ConfigPresetStore

    init(
        yabaiService: YabaiService,
        configStore: ConfigStore = .shared,
        presetStore: ConfigPresetStore? = nil
    ) {
        self.yabaiService = yabaiService
        self.configStore = configStore
        self.presetStore = presetStore ?? ConfigPresetStore(
            directory: ConfigPresetStore.defaultDirectory,
            configPath: configStore.configPath
        )
    }

    /// Hand-kept: update these lines when CLIFlagTable gains or drops a flag.
    static let help = """
    Usage: spacemap [OPTIONS]

    Options:
      --version          Print the version and exit
      --trigger          Toggle the running HUD and exit
      --space SELECTOR   Focus a yabai space and show the HUD
                         SELECTOR: 1-16, prev, next, first, last,
                                   recent, mouse, or a space label
      --config           Open the config file in the default editor and exit
      --print-config     Print the resolved config as TOML and exit
      --status           Print app, config, running, and yabai status
      --update           Check for app updates in the running app and exit
      --update-font      Check for app font updates in the running app and exit
      --config-preset NAME
                         Apply a config preset from ~/.config/spacemap/presets
                         and exit (the running app reloads immediately)
      --help             Print this help and exit

    Without any options, Spacemap launches and waits for its configured hotkey.
    """

    /// Pure: no printing, no socket writes, no config reads.
    static func parse(arguments: [String]) -> CLIInvocation {
        // Positional scan: the first exit flag in argv order wins. A value
        // flag is handled inline so a missing value errors even when another
        // flag follows (SpaceFocusTarget rejects "-"-prefixed values).
        for (index, arg) in arguments.enumerated() {
            guard let row = CLIFlagTable.row(for: arg) else {
                // Never silently ignore an option: a typo such as --settigns
                // should fail instead of falling through to a second daemon.
                if arg.hasPrefix("-") {
                    return .error("unknown option: \(arg)")
                }
                continue
            }
            switch row.target {
            case .exit(let command):
                return .command(command)
            case .focusSpace:
                guard index + 1 < arguments.endIndex,
                      let target = SpaceFocusTarget(argument: arguments[index + 1]) else {
                    return .error("\(row.flag) requires next, prev, first, last, recent, mouse, a label, or an index from 1 to 16")
                }
                return .focusSpace(target)
            case .configPreset:
                guard index + 1 < arguments.endIndex,
                      !arguments[index + 1].hasPrefix("-"),
                      ConfigPresetStore.sanitizedName(arguments[index + 1]) != nil else {
                    return .error("\(row.flag) requires a preset name (letters, digits, spaces, - or _)")
                }
                return .configPreset(arguments[index + 1])
            case .deliver, .marker:
                // Handled after AppKit starts (or by the forwarding guard);
                // they must fall through to a normal app launch.
                continue
            }
        }
        return .none
    }

    /// Single version source with About (falls back to "Unknown", never a
    /// fabricated 1.0.0).
    static func versionLine(shortVersion: String? = AppVersion.short) -> String {
        "Spacemap \(shortVersion ?? AppVersion.unknown)"
    }

    static func statusLines(
        version: String,
        appPath: String,
        configPath: String,
        running: Bool,
        yabaiAvailable: Bool
    ) -> [String] {
        [
            "Spacemap \(version)",
            "App: \(appPath)",
            "Config: \(configPath)",
            "Running: \(running ? "yes" : "no")",
            "yabai: \(yabaiAvailable ? "available" : "unavailable")",
        ]
    }

    func runIfRequested(arguments: [String]) -> Int32? {
        perform(Self.parse(arguments: arguments))
    }

    /// Side effects live here so `parse` stays unit-testable.
    func perform(_ invocation: CLIInvocation) -> Int32? {
        switch invocation {
        case .none:
            return nil
        case .error(let message):
            fputs("spacemap: \(message)\n", stderr)
            return 2
        case .command(.version):
            print(Self.versionLine())
            return 0
        case .command(.help):
            print(Self.help)
            return 0
        case .command(.config):
            _ = configStore.load()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [configStore.configPath]
            do {
                try process.run()
                return 0
            } catch {
                fputs("spacemap: failed to open config: \(error.localizedDescription)\n", stderr)
                return 1
            }
        case .command(.printConfig):
            let result = configStore.loadReportingResult()
            print(ConfigLoader.tomlConfigString(from: result.config, includeHeaderComments: false))
            return 0
        case .command(.status):
            let running = (try? SpacemapCommand.health.send()) != nil
            print(Self.statusLines(
                version: AppVersion.short,
                appPath: AppVersion.bundlePath,
                configPath: configStore.configPath,
                running: running,
                yabaiAvailable: yabaiService.isYabaiRunning(forceRefresh: true)
            ).joined(separator: "\n"))
            return 0
        case .command(.update):
            return send(.update)
        case .command(.updateFont):
            return send(.updateFont)
        case .command(.toggle):
            return send(.toggle)
        case .focusSpace(let target):
            guard yabaiService.focusSpace(target) else { return 1 }
            return send(.show)
        case .configPreset(let name):
            guard presetStore.apply(name) else {
                fputs("spacemap: no preset named \"\(name)\" in \(presetStore.directory)\n", stderr)
                return 1
            }
            // No running app: the next launch reads the new config anyway.
            try? SpacemapCommand.reloadConfig.send()
            return 0
        case .command:
            // Deliver and marker flags never reach parse's exit branch.
            return nil
        }
    }

    private func send(_ command: SpacemapCommand) -> Int32 {
        do {
            try command.send()
            return 0
        } catch {
            fputs("spacemap: \(error)\n", stderr)
            return 1
        }
    }
}
