import Foundation

enum CLICommand: Equatable {
    case version
    case help
    case config
    case trigger
    case focusSpace(SpaceFocusTarget)
}

enum CLIParseResult: Equatable {
    case command(CLICommand)
    case error(String)
    case none
}

enum CLI {
    static let help = """
    Usage: spacemap [OPTIONS]

    Options:
      --version          Print the version and exit
      --trigger          Toggle the running HUD and exit
      --space SELECTOR   Focus a yabai space and show the HUD
                         SELECTOR: 1-16, prev, next, first, last,
                                   recent, mouse, or a space label
      --show-menu        Show the menu bar dropdown (app continues running)
      --settings         Open the settings window directly (app continues running)
      --config           Open the config file in the default editor and exit
      --help             Print this help and exit

    Without any options, Spacemap launches and waits for its configured hotkey.
    """

    static func parse(arguments: [String]) -> CLIParseResult {
        if arguments.contains("--version") { return .command(.version) }
        if arguments.contains("--help") { return .command(.help) }
        if arguments.contains("--config") { return .command(.config) }
        if let optionIndex = arguments.firstIndex(of: "--space") {
            let selectorIndex = arguments.index(after: optionIndex)
            guard selectorIndex < arguments.endIndex,
                  let target = SpaceFocusTarget(argument: arguments[selectorIndex]) else {
                return .error("--space requires next, prev, first, last, recent, mouse, a label, or an index from 1 to 16")
            }
            return .command(.focusSpace(target))
        }
        if arguments.contains("--trigger") { return .command(.trigger) }
        return .none
    }

    static func runIfRequested(arguments: [String]) -> Int32? {
        switch parse(arguments: arguments) {
        case .none:
            return nil
        case .error(let message):
            fputs("spacemap: \(message)\n", stderr)
            return 2
        case .command(.version):
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            print("Spacemap \(version)")
            return 0
        case .command(.help):
            print(help)
            return 0
        case .command(.config):
            _ = ConfigReader.load()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [ConfigReader.configPath]
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            } catch {
                fputs("spacemap: failed to open config: \(error.localizedDescription)\n", stderr)
                return 1
            }
        case .command(.trigger):
            SocketListener.sendCommand(to: socketPath, command: 4)
            return 0
        case .command(.focusSpace(let target)):
            guard YabaiClient.focusSpace(target) else { return 1 }
            SocketListener.sendCommand(to: socketPath, command: 2)
            return 0
        }
    }

    private static var socketPath: String {
        "/tmp/spacemap_\(NSUserName()).socket"
    }
}
