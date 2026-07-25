import Foundation
import AppKit

enum YabaiClient {
    private static let yabaiPath: String = {
        let arm = "/opt/homebrew/bin/yabai"
        let intel = "/usr/local/bin/yabai"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        if FileManager.default.isExecutableFile(atPath: intel) { return intel }
        return arm
    }()

    private static var _yabaiRunningCache: (result: Bool, checkedAt: TimeInterval)?
    private static let yabaiCacheTTL: TimeInterval = 5.0

    static func isYabaiRunning() -> Bool {
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
    
    static func queryWindows() throws -> [YabaiWindow] {
        guard isYabaiRunning() else { return [] }
        return try queryWindowsRaw()
    }

    private static func querySpacesRaw() throws -> [YabaiSpace] {
        let output = try shell(yabaiPath, "-m", "query", "--spaces")
        return try JSONDecoder().decode([YabaiSpace].self, from: Data(output.utf8))
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
    
    static func moveWindow(_ windowID: Int, toSpace spaceIndex: Int) {
        _ = try? shell(yabaiPath, "-m", "window", "\(windowID)", "--space", "\(spaceIndex)")
    }
    
    static func buildGridState(config: GridConfig, focusedIndex: Int? = nil) -> GridState {
        guard isYabaiRunning() else {
            let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
            return GridState(config: config, spaces: [], windows: [], displayBounds: displayBounds, focusedIndex: nil)
        }
        var spaces: [YabaiSpace] = []
        var windows: [YabaiWindow] = []
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            spaces = (try? querySpacesRaw()) ?? []
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
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: resolvedFocus)
    }

    private static func shell(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}