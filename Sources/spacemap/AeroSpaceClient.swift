import AppKit
import Foundation

/// AeroSpace adapter for the app's existing workspace-service seam.
/// It deliberately produces Yabai model values so all HUD, menu, input, and
/// drag code use one pipeline regardless of selected window manager.
final class AeroSpaceClient: YabaiService {
    private let queue = DispatchQueue(label: "com.spacemap.aerospace", qos: .userInitiated)
    private let focusQueue = DispatchQueue(label: "com.spacemap.aerospace.focus", qos: .userInteractive)
    private let aerospacePath: String = {
        let arm = "/opt/homebrew/bin/aerospace"
        let intel = "/usr/local/bin/aerospace"
        return FileManager.default.isExecutableFile(atPath: arm) ? arm : intel
    }()
    private var eventListener: Process?
    private var runningCache: (value: Bool, checked: TimeInterval)?
    private let cacheLock = NSLock()

    var yabaiProcessCheck: () -> Bool = { false }
    let windowGeometryRefreshEvents: [String] = []
    let workspaceTopologyRefreshEvents: [String] = []
    let workspacePreviewRefreshEvents: [String] = []

    init() {
        yabaiProcessCheck = { [unowned self] in self.defaultProcessCheck() }
    }

    func runOnYabaiQueue(_ block: @escaping () -> Void) { queue.async(execute: block) }
    func runOnYabaiQueue(_ workItem: DispatchWorkItem) { queue.async(execute: workItem) }

    func isYabaiRunning(forceRefresh: Bool = false) -> Bool {
        cacheLock.lock(); defer { cacheLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        if !forceRefresh, let cache = runningCache, now - cache.checked < 5 { return cache.value }
        let value = yabaiProcessCheck()
        runningCache = (value, now)
        return value
    }

    func resetYabaiRunningCache() { cacheLock.lock(); runningCache = nil; cacheLock.unlock() }
    func resetYabaiProcessCheck() { yabaiProcessCheck = { [unowned self] in self.defaultProcessCheck() }; resetYabaiRunningCache() }

    func querySpaces() throws -> [YabaiSpace] {
        let workspaces = try fetchWorkspaces()
        let focused = try focusedWorkspace()
        return workspaces.enumerated().map { offset, workspace in
            YabaiSpace(id: offset + 1, index: offset + 1, display: workspace.monitor, hasFocus: workspace.name == focused, isVisible: true, label: workspace.name)
        }
    }

    func queryDisplays() throws -> [YabaiDisplay] {
        NSScreen.screens.enumerated().map { offset, screen in
            YabaiDisplay(index: offset + 1, frame: .init(x: screen.frame.minX, y: screen.frame.minY, w: screen.frame.width, h: screen.frame.height), hasFocus: screen == NSScreen.main)
        }
    }

    func queryWindows() throws -> [YabaiWindow] {
        let workspaces = try fetchWorkspaces()
        let output = try shell(aerospacePath, "list-windows", "--all", "--json", "--format", "%{window-id}%{app-name}%{workspace}%{window-title}%{window-is-fullscreen}%{window-layout}")
        let windows = try JSONDecoder().decode([AeroSpaceWindow].self, from: Data(output.utf8))
        return windows.compactMap { window in
            guard let space = workspaces.firstIndex(where: { $0.name == window.workspace }).map({ $0 + 1 }) else { return nil }
            let frame = frame(for: window.appName, title: window.windowTitle) ?? .init(x: 0, y: 0, w: 100, h: 100)
            return YabaiWindow(id: window.windowId, app: window.appName, space: space, frame: frame, isHidden: window.isHidden, isMinimized: false, subLayer: window.sublayer ?? "below", pid: nil, role: "AXWindow", subrole: "AXStandardWindow", isRootWindow: true, hasAXReference: true, isVisible: true, isFloating: nil)
        }
    }

    func queryFocusedWindow() throws -> Int? {
        let output = try shell(aerospacePath, "list-windows", "--focused", "--json", "--format", "%{window-id}%{app-name}%{workspace}%{window-title}%{window-is-fullscreen}%{window-layout}")
        return try JSONDecoder().decode([AeroSpaceWindow].self, from: Data(output.utf8)).first?.windowId
    }
    func queryFocusedSpaceIndex() -> Int? { guard let focused = try? focusedWorkspace(), let spaces = try? fetchWorkspaces() else { return nil }; return spaces.firstIndex { $0.name == focused }.map { $0 + 1 } }

    func registerSignals(socketPath: String, showHUDOnSpaceChange: Bool, refreshWorkspacePreviews: Bool, refreshWindowGeometry: Bool) {
        removeSignals()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aerospacePath)
        process.arguments = ["subscribe", "--no-send-initial", "focus-changed", "focused-monitor-changed", "focused-workspace-changed", "window-detected", "window-moved", "window-destroyed"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { _ in
            let command = showHUDOnSpaceChange ? SpacemapCommand.show.rawValue : SpacemapCommand.refresh.rawValue
            SocketListener.sendCommand(to: socketPath, command: command)
        }
        do { try process.run(); eventListener = process } catch { NSLog("spacemap/AeroSpace: event subscription failed: \(error.localizedDescription)") }
    }
    func removeSignals() { eventListener?.standardOutput = nil; eventListener?.terminate(); eventListener = nil }

    func focusSpace(_ index: Int) { focusSpaceAsync(index) }
    func focusSpace(_ target: SpaceFocusTarget) -> Bool { guard let index = Int(target.value) else { return false }; focusSpaceAsync(index); return true }
    func focusSpaceAsync(_ index: Int) { focusQueue.async { [weak self] in guard let self, let workspaces = try? self.fetchWorkspaces(), workspaces.indices.contains(index - 1) else { return }; _ = try? self.shell(self.aerospacePath, "workspace", workspaces[index - 1].name) } }
    func showSpacemap() { try? SpacemapCommand.show.send() }

    func moveWindowCreatingSpacesIfNeeded(_ windowID: Int, toSpace targetIndex: Int, focusDestination: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let workspaces = try self.fetchWorkspaces()
                guard workspaces.indices.contains(targetIndex - 1) else { throw AeroSpaceError.workspaceDoesNotExist(targetIndex) }
                let name = workspaces[targetIndex - 1].name
                _ = try self.shell(self.aerospacePath, "move-node-to-workspace", name, "--window-id", "\(windowID)")
                if focusDestination { _ = try? self.shell(self.aerospacePath, "workspace", name) }
                DispatchQueue.main.async { completion(.success(())) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState {
        guard isYabaiRunning(forceRefresh: true) else { return GridState(config: config, spaces: [], windows: [], displayBounds: NSScreen.main?.frame ?? .zero, focusedIndex: nil) }
        let spaces = (try? querySpaces()) ?? []
        return GridState(config: config, spaces: spaces, windows: (try? queryWindows()) ?? [], displayBounds: NSScreen.main?.frame ?? .zero, focusedIndex: focusedIndex ?? spaces.first(where: \.hasFocus)?.index, displays: (try? queryDisplays()) ?? [])
    }

    private func fetchWorkspaces() throws -> [AeroSpaceWorkspace] { try decode("list-workspaces", "--all", "--json", "--format", "%{workspace}%{monitor-id}") }
    private func focusedWorkspace() throws -> String { guard let name = try decode("list-workspaces", "--focused", "--json", "--format", "%{workspace}%{monitor-id}").first?.name else { throw AeroSpaceError.noFocusedWorkspace }; return name }
    private func decode(_ args: String...) throws -> [AeroSpaceWorkspace] { try JSONDecoder().decode([AeroSpaceWorkspace].self, from: Data(shell(aerospacePath, args).utf8)) }
    private func shell(_ executable: String, _ arguments: String...) throws -> String { try shell(executable, arguments) }
    private func shell(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(); let error = Pipe(); process.standardOutput = output; process.standardError = error
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AeroSpaceError.commandFailed(String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "") }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    private func frame(for appName: String, title: String?) -> YabaiWindow.WindowFrame? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier); var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return nil }
        let window = windows.first { window in var result: CFTypeRef?; return AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &result) == .success && result as? String == title } ?? windows.first
        guard let window else { return nil }; var position: CFTypeRef?; var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success, AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success, let position, let size else { return nil }
        let positionValue = position as! AXValue
        let sizeValue = size as! AXValue
        var point = CGPoint.zero; var dimensions = CGSize.zero; guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions) else { return nil }
        return .init(x: point.x, y: point.y, w: dimensions.width, h: dimensions.height)
    }

    private func defaultProcessCheck() -> Bool {
        guard let output = try? shell("/usr/bin/pgrep", "aerospace") else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum AeroSpaceError: LocalizedError { case workspaceDoesNotExist(Int), noFocusedWorkspace, commandFailed(String); var errorDescription: String? { switch self { case .workspaceDoesNotExist(let index): return "AeroSpace workspace \(index) does not exist"; case .noFocusedWorkspace: return "AeroSpace did not report a focused workspace"; case .commandFailed(let message): return message } } }

struct AeroSpaceWorkspace: Decodable { let name: String; let monitor: Int; enum CodingKeys: String, CodingKey { case name = "workspace"; case monitor = "monitor-id" } }
struct AeroSpaceWindow: Decodable {
    let windowId: Int; let appName: String; let workspace: String; let windowTitle: String?; let isHidden: Bool; let sublayer: String?
    enum CodingKeys: String, CodingKey { case windowId = "window-id"; case appName = "app-name"; case workspace; case windowTitle = "window-title"; case isHidden = "is-hidden"; case sublayer }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        windowId = try values.decode(Int.self, forKey: .windowId)
        appName = try values.decode(String.self, forKey: .appName)
        workspace = try values.decode(String.self, forKey: .workspace)
        windowTitle = try values.decodeIfPresent(String.self, forKey: .windowTitle)
        isHidden = try values.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        sublayer = try values.decodeIfPresent(String.self, forKey: .sublayer)
    }
}
