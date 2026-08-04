import Foundation
import AppKit

class YabaiClientImpl: YabaiService {
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

    private let yabaiQueue = DispatchQueue(label: "com.spacemap.yabai", qos: .userInitiated)
    // Keep interactive focus changes out of the state-query queue. A grid
    // refresh can wait for multiple yabai queries, but keyboard navigation
    // should never wait behind it.
    private let focusQueue = DispatchQueue(label: "com.spacemap.yabai.focus", qos: .userInteractive)

    private let yabaiPath: String? = {
        let arm = "/opt/homebrew/bin/yabai"
        let intel = "/usr/local/bin/yabai"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        if FileManager.default.isExecutableFile(atPath: intel) { return intel }
        return nil
    }()

    private var _yabaiRunningCache: (result: Bool, checkedAt: TimeInterval)?
    private let yabaiCacheTTL: TimeInterval = 5.0
    private let cacheLock = NSLock()

    var yabaiProcessCheck: () -> Bool = { false }

    init() {
        yabaiProcessCheck = { [unowned self] in self.defaultYabaiProcessCheck() }
    }

    // MARK: - Queue dispatch

    func runOnYabaiQueue(_ block: @escaping () -> Void) {
        yabaiQueue.async(execute: block)
    }

    func runOnYabaiQueue(_ workItem: DispatchWorkItem) {
        yabaiQueue.async(execute: workItem)
    }

    // MARK: - Yabai running check

    private func defaultYabaiProcessCheck() -> Bool {
        let output = (try? shell("/usr/bin/pgrep", "yabai")) ?? ""
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isYabaiRunning(forceRefresh: Bool = false) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        if !forceRefresh,
           let cached = _yabaiRunningCache,
           now - cached.checkedAt < yabaiCacheTTL {
            return cached.result
        }
        let result = yabaiProcessCheck()
        _yabaiRunningCache = (result, now)
        return result
    }

    func resetYabaiRunningCache() {
        cacheLock.lock()
        _yabaiRunningCache = nil
        cacheLock.unlock()
    }

    func resetYabaiProcessCheck() {
        yabaiProcessCheck = { [unowned self] in self.defaultYabaiProcessCheck() }
        resetYabaiRunningCache()
    }

    // MARK: - Queries

    func querySpaces() throws -> [YabaiSpace] {
        guard isYabaiRunning() else { return [] }
        return try querySpacesRaw()
    }

    func queryDisplays() throws -> [YabaiDisplay] {
        guard isYabaiRunning() else { return [] }
        return try queryDisplaysRaw()
    }

    func queryWindows() throws -> [YabaiWindow] {
        guard isYabaiRunning() else { return [] }
        return try queryWindowsRaw()
    }

    private func querySpacesRaw() throws -> [YabaiSpace] {
        guard let yabaiPath = yabaiPath else { return [] }
        let output = try shell(yabaiPath, "-m", "query", "--spaces")
        return try JSONDecoder().decode([YabaiSpace].self, from: Data(output.utf8))
    }

    private func queryDisplaysRaw() throws -> [YabaiDisplay] {
        guard let yabaiPath = yabaiPath else { return [] }
        let output = try shell(yabaiPath, "-m", "query", "--displays")
        return try JSONDecoder().decode([YabaiDisplay].self, from: Data(output.utf8))
    }

    private func queryWindowsRaw() throws -> [YabaiWindow] {
        guard let yabaiPath = yabaiPath else { return [] }
        let output = try shell(yabaiPath, "-m", "query", "--windows")
        return try JSONDecoder().decode([YabaiWindow].self, from: Data(output.utf8))
    }

    func queryFocusedWindow() throws -> Int? {
        guard isYabaiRunning(), let yabaiPath = yabaiPath else { return nil }
        let output = try shell(yabaiPath, "-m", "query", "--windows", "--window")
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiWindow.self, from: data) else { return nil }
        return json.id
    }

    func queryFocusedSpaceIndex() -> Int? {
        guard isYabaiRunning() else { return nil }
        do {
            let spaces = try querySpacesRaw()
            return spaces.first { $0.hasFocus }?.index
        } catch {
            return nil
        }
    }

    // MARK: - Signals

    func registerSignals(
        socketPath: String,
        showHUDOnSpaceChange: Bool = false,
        refreshWorkspacePreviews: Bool = false,
        refreshWindowGeometry: Bool = true
    ) {
        guard isYabaiRunning(forceRefresh: true) else { return }
        removeSignals()
        let action = spaceChangedSignalAction(
            socketPath: socketPath,
            showHUDOnSpaceChange: showHUDOnSpaceChange
        )
        guard let yabaiPath = yabaiPath else { return }
        _ = try? shell(yabaiPath, "-m", "signal", "--add",
                       "label=spacemap_space_changed",
                       "event=space_changed",
                       "action=\(action)")
        guard refreshWorkspacePreviews else { return }
        let events = refreshWindowGeometry
            ? windowGeometryRefreshEvents
            : workspaceTopologyRefreshEvents
        for event in events {
            _ = try? shell(yabaiPath, "-m", "signal", "--add",
                           "label=spacemap_\(event)",
                           "event=\(event)",
                           "action=\(refreshSignalAction(socketPath: socketPath))")
        }
    }

    let windowGeometryRefreshEvents: [String] = [
        "window_created",
        "window_destroyed",
        "window_moved",
        "window_resized",
        "window_minimized",
        "window_deminimized"
    ]

    let workspaceTopologyRefreshEvents: [String] = [
        "space_created",
        "space_destroyed",
        "display_added",
        "display_removed",
        "display_moved",
        "display_resized"
    ]

    var workspacePreviewRefreshEvents: [String] {
        windowGeometryRefreshEvents + workspaceTopologyRefreshEvents
    }

    func spaceChangedSignalAction(socketPath: String, showHUDOnSpaceChange: Bool) -> String {
        let command = showHUDOnSpaceChange ? SpacemapCommand.show.rawValue : SpacemapCommand.refresh.rawValue
        return "echo \(command) | /usr/bin/nc -U \(socketPath)"
    }

    func refreshSignalAction(socketPath: String) -> String {
        "echo \(SpacemapCommand.refresh.rawValue) | /usr/bin/nc -U \(socketPath)"
    }

    func removeSignals() {
        guard isYabaiRunning(), let yabaiPath = yabaiPath else { return }
        _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_space_changed")
        for event in workspacePreviewRefreshEvents {
            _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_\(event)")
        }
    }

    // MARK: - Focus

    func focusSpace(_ index: Int) {
        guard let yabaiPath = yabaiPath, isYabaiRunning() else { return }
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)")
    }

    @discardableResult
    func focusSpace(_ target: SpaceFocusTarget) -> Bool {
        guard let yabaiPath = yabaiPath, isYabaiRunning() else { return false }
        do {
            _ = try shell(yabaiPath, "-m", "space", "--focus", target.value)
            return true
        } catch {
            fputs("spacemap: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    func focusSpaceAsync(_ index: Int) {
        focusQueue.async { [weak self] in
            guard let self = self, let yabaiPath = self.yabaiPath, self.isYabaiRunning() else { return }
            _ = try? self.shell(yabaiPath, "-m", "space", "--focus", "\(index)")
        }
    }

    // MARK: - Spacemap

    func showSpacemap() {
        do { try SpacemapCommand.show.send() } catch { fputs("spacemap: \(error)\n", stderr) }
    }

    // MARK: - Window movement

    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace targetIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        yabaiQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard targetIndex > 0 else {
                    throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                }

                var spaces = try self.querySpacesRaw()
                while !spaces.contains(where: { $0.index == targetIndex }) {
                    let previousIndices = Set(spaces.map(\.index))
                    guard let yabaiPath = self.yabaiPath else {
                        throw YabaiError.commandFailed(arguments: ["space", "--create"], status: -1, message: "yabai not found")
                    }
                    _ = try self.shell(yabaiPath, "-m", "space", "--create")
                    spaces = try self.querySpacesRaw()

                    guard Set(spaces.map(\.index)) != previousIndices else {
                        throw YabaiError.spaceCreationMadeNoProgress(target: targetIndex)
                    }
                }

                guard let yabaiPath = self.yabaiPath else {
                    throw YabaiError.commandFailed(arguments: ["window", "\(windowID)", "--space", "\(targetIndex)"], status: -1, message: "yabai not found")
                }
                _ = try self.shell(yabaiPath, "-m", "window", "\(windowID)", "--space", "\(targetIndex)")
                if focusDestination {
                    _ = try self.shell(yabaiPath, "-m", "space", "--focus", "\(targetIndex)")
                }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Grid state

    func buildGridState(config: GridConfig, focusedIndex: Int? = nil) -> GridState {
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { group.leave(); return }
            spaces = (try? self.querySpacesRaw()) ?? []
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { group.leave(); return }
            displays = (try? self.queryDisplaysRaw()) ?? []
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { group.leave(); return }
            windows = (try? self.queryWindowsRaw()) ?? []
            group.leave()
        }
        group.wait()
        let resolvedFocus = focusedIndex ?? spaces.first { $0.hasFocus }?.index
        let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: resolvedFocus, displays: displays)
    }

    // MARK: - Shell

    private func shell(_ args: String...) throws -> String {
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
