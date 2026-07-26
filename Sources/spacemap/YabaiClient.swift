import Foundation
import AppKit

enum YabaiClient {
    private enum YabaiError: LocalizedError {
        case commandFailed(arguments: [String], status: Int32, message: String)
        case spaceCreationMadeNoProgress(target: Int)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let arguments, let status, let message):
                let detail = message.isEmpty ? "no error output" : message
                return "yabai \(arguments.joined(separator: " ")) failed with status \(status): \(detail)"
            case .spaceCreationMadeNoProgress(let target):
                return "yabai did not create the space needed for target index \(target)"
            }
        }
    }

    private static let yabaiQueue = DispatchQueue(label: "com.spacemap.yabai", qos: .userInitiated)
    // Keep interactive focus changes out of the state-query queue. A grid
    // refresh can wait for multiple yabai queries, but keyboard navigation
    // should never wait behind it.
    private static let focusQueue = DispatchQueue(label: "com.spacemap.yabai.focus", qos: .userInteractive)

    static func runOnYabaiQueue(_ block: @escaping () -> Void) {
        yabaiQueue.async(execute: block)
    }

    static func runOnYabaiQueue(_ workItem: DispatchWorkItem) {
        yabaiQueue.async(execute: workItem)
    }

    private static let yabaiPath: String = {
        let arm = "/opt/homebrew/bin/yabai"
        let intel = "/usr/local/bin/yabai"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        if FileManager.default.isExecutableFile(atPath: intel) { return intel }
        return arm
    }()

    private static var _yabaiRunningCache: (result: Bool, checkedAt: TimeInterval)?
    private static let yabaiCacheTTL: TimeInterval = 5.0
    private static let cacheLock = NSLock()

    static func isYabaiRunning() -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = _yabaiRunningCache, now - cached.checkedAt < yabaiCacheTTL {
            return cached.result
        }
        let output = (try? shell("/usr/bin/pgrep", "yabai")) ?? ""
        let result = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        _yabaiRunningCache = (result, now)
        return result
    }
    
    static func querySpaces() throws -> [YabaiSpace] {
        guard isYabaiRunning() else { return [] }
        return try querySpacesRaw()
    }

    static func queryDisplays() throws -> [YabaiDisplay] {
        guard isYabaiRunning() else { return [] }
        return try queryDisplaysRaw()
    }
    
    static func queryWindows() throws -> [YabaiWindow] {
        guard isYabaiRunning() else { return [] }
        return try queryWindowsRaw()
    }

    private static func querySpacesRaw() throws -> [YabaiSpace] {
        let output = try shell(yabaiPath, "-m", "query", "--spaces")
        return try JSONDecoder().decode([YabaiSpace].self, from: Data(output.utf8))
    }

    private static func queryDisplaysRaw() throws -> [YabaiDisplay] {
        let output = try shell(yabaiPath, "-m", "query", "--displays")
        return try JSONDecoder().decode([YabaiDisplay].self, from: Data(output.utf8))
    }

    private static func queryWindowsRaw() throws -> [YabaiWindow] {
        let output = try shell(yabaiPath, "-m", "query", "--windows")
        return try JSONDecoder().decode([YabaiWindow].self, from: Data(output.utf8))
    }
    
    static func queryFocusedWindow() throws -> Int? {
        guard isYabaiRunning() else { return nil }
        let output = try shell(yabaiPath, "-m", "query", "--windows", "--window")
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiWindow.self, from: data) else { return nil }
        return json.id
    }
    
    static func queryFocusedSpaceIndex() -> Int? {
        guard isYabaiRunning() else { return nil }
        do {
            let spaces = try querySpacesRaw()
            return spaces.first { $0.hasFocus }?.index
        } catch {
            return nil
        }
    }
    
    static func registerSignals(socketPath: String) {
        guard isYabaiRunning() else { return }
        let action = "echo 1 | nc -U \(socketPath)"
        _ = try? shell(yabaiPath, "-m", "signal", "--add",
                       "label=spacemap_space_changed",
                       "event=space_changed",
                       "action=\(action)")
    }
    
    static func removeSignals() {
        guard isYabaiRunning() else { return }
        _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_space_changed")
    }
    
    static func focusSpace(_ index: Int) {
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)")
    }

    static func focusSpaceAsync(_ index: Int) {
        focusQueue.async { _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)") }
    }
    
    static func showSpacemap() {
        let path = "/tmp/spacemap_\(NSUserName()).socket"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            path.utf8CString.withUnsafeBytes { src in
                dest.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress, count: min(src.count, dest.count)))
            }
        }
        guard connect(fd, withUnsafePointer(to: &addr, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }), socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 else { return }
        var buf: [UInt8] = [2]
        _ = write(fd, &buf, buf.count)
    }
    
    static func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        yabaiQueue.async {
            do {
                guard targetIndex > 0 else {
                    throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                }

                var spaces = try querySpacesRaw()
                while !spaces.contains(where: { $0.index == targetIndex }) {
                    let previousIndices = Set(spaces.map(\.index))
                    _ = try shell(yabaiPath, "-m", "space", "--create")
                    spaces = try querySpacesRaw()

                    guard Set(spaces.map(\.index)) != previousIndices else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                }

                _ = try shell(yabaiPath, "-m", "window", "\(windowID)", "--space", "\(targetIndex)")
                if focusDestination {
                    _ = try shell(yabaiPath, "-m", "space", "--focus", "\(targetIndex)")
                }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
    
    static func buildGridState(config: GridConfig, focusedIndex: Int? = nil) -> GridState {
        // Bypass isYabaiRunning() cache — stale cache returns empty grid silently
        // Fresh process check instead
        guard (try? shell("/usr/bin/pgrep", "yabai")).flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) ?? false else {
            let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
            return GridState(config: config, spaces: [], windows: [], displayBounds: displayBounds, focusedIndex: nil)
        }
        var spaces: [YabaiSpace] = []
        var displays: [YabaiDisplay] = []
        var windows: [YabaiWindow] = []
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            spaces = (try? querySpacesRaw()) ?? []
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            displays = (try? queryDisplaysRaw()) ?? []
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            windows = (try? queryWindowsRaw()) ?? []
            group.leave()
        }
        group.wait()
        let resolvedFocus = focusedIndex ?? spaces.first { $0.hasFocus }?.index
        let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: resolvedFocus, displays: displays)
    }

    private static func shell(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw YabaiError.commandFailed(
                arguments: Array(args.dropFirst()),
                status: process.terminationStatus,
                message: message
            )
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
