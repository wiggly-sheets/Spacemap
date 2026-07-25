import Foundation
import AppKit
import ApplicationServices

final class AeroSpaceClient: WindowManager {
    static let shared = AeroSpaceClient()
    
    var type: WindowManagerType { .aerospace }
    
    private let aerospacePath: String = {
        let arm = "/opt/homebrew/bin/aerospace"
        let intel = "/usr/local/bin/aerospace"
        if FileManager.default.isExecutableFile(atPath: arm) { return arm }
        if FileManager.default.isExecutableFile(atPath: intel) { return intel }
        return arm
    }()
    
    private var _aerospaceRunningCache: (result: Bool, checkedAt: TimeInterval)?
    private let aerospaceCacheTTL: TimeInterval = 5.0
    
    private var cachedWorkspaces: [AeroSpaceWorkspace] = []
    private var lastWorkspacesFetch: TimeInterval = 0
    private let workspacesCacheTTL: TimeInterval = 2.0
    
    private var eventListenerProcess: Process?
    
    private init() {}
    
    func isRunning() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = _aerospaceRunningCache, now - cached.checkedAt < aerospaceCacheTTL {
            return cached.result
        }
        let output = (try? shell("/usr/bin/pgrep", "aerospace")) ?? ""
        let result = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        _aerospaceRunningCache = (result, now)
        return result
    }
    
    private func isAerospaceRunning() -> Bool { isRunning() }
    
    func querySpaces() -> [YabaiSpace] {
        guard isAerospaceRunning() else { return [] }
        do {
            let workspaces = try fetchWorkspaces()
            let focusedName = (try? fetchFocusedWorkspaceName()) ?? workspaces.first?.name
            
            return workspaces.enumerated().map { index, ws in
                YabaiSpace(
                    id: index,
                    index: index,
                    display: ws.monitor,
                    hasFocus: ws.name == focusedName,
                    label: ws.name
                )
            }
        } catch {
            return []
        }
    }
    
    func queryWindows() throws -> [YabaiWindow] {
        guard isAerospaceRunning() else { return [] }
        let output = try shell(aerospacePath, "list-windows", "--all", "--json")
        let aerospaceWindows = try JSONDecoder().decode([AeroSpaceWindow].self, from: Data(output.utf8))
        
        let workspaces = (try? fetchWorkspaces()) ?? []
        let windowManager = AXUIElementCreateApplication(0)
        
        return aerospaceWindows.compactMap { aw -> YabaiWindow? in
            let spaceIndex = workspaces.firstIndex { $0.name == aw.workspace } ?? 0
            let frame = getWindowFrame(forApp: aw.appName, windowTitle: aw.windowTitle) ?? WindowFrame(x: 0, y: 0, width: 100, height: 100)
            
            return YabaiWindow(
                id: aw.windowId,
                app: aw.appName,
                space: spaceIndex,
                frame: frame,
                isHidden: aw.isHidden,
                isMinimized: false,
                subLayer: aw.sublayer ?? "below"
            )
        }
    }
    
    private func getWindowFrame(forApp appName: String, windowTitle: String?) -> WindowFrame? {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let app = runningApps.first(where: { $0.localizedName == appName }) else { return nil }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return nil }
        
        for window in windows {
            if let title = getWindowTitle(window), let targetTitle = windowTitle, title == targetTitle {
                return getWindowFrameFromAX(window)
            }
        }
        return windows.first.flatMap { getWindowFrameFromAX($0) }
    }
    
    private func getWindowTitle(_ axWindow: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
    }
    
    private func getWindowFrameFromAX(_ axWindow: AXUIElement) -> WindowFrame? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef else { return nil }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        
        return WindowFrame(x: position.x, y: position.y, width: size.width, height: size.height)
    }
    
    func queryFocusedWindow() -> Int? {
        guard isAerospaceRunning() else { return nil }
        let output = (try? shell(aerospacePath, "list-windows", "--focused", "--json")) ?? ""
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(AeroSpaceWindow.self, from: data) else { return nil }
        return json.windowId
    }
    
    func queryFocusedSpaceIndex() -> Int? {
        guard isAerospaceRunning() else { return nil }
        do {
            let workspaces = try fetchWorkspaces()
            let focusedName = try fetchFocusedWorkspaceName()
            return workspaces.firstIndex { $0.name == focusedName }
        } catch {
            return nil
        }
    }
    
    func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState {
        guard isAerospaceRunning() else {
            let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
            return GridState(config: config, spaces: [], windows: [], displayBounds: displayBounds, focusedIndex: nil)
        }
        
        let spaces = querySpaces()
        let windows = (try? queryWindows()) ?? []
        let resolvedFocus = focusedIndex ?? spaces.first { $0.hasFocus }?.index
        let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: resolvedFocus)
    }
    
    func focusSpace(_ index: Int) {
        guard isAerospaceRunning() else { return }
        do {
            let workspaces = try fetchWorkspaces()
            if index >= 0 && index < workspaces.count {
                let workspaceName = workspaces[index]
                _ = try? shell(aerospacePath, "workspace", workspaceName)
            }
        } catch {}
    }
    
    func moveWindow(_ windowID: Int, toSpace spaceIndex: Int) {
        guard isAerospaceRunning() else { return }
        do {
            let workspaces = try fetchWorkspaces()
            if spaceIndex >= 0 && spaceIndex < workspaces.count {
                let workspaceName = workspaces[spaceIndex]
                _ = try? shell(aerospacePath, "move-node-to-workspace", workspaceName, "--window-id", "\(windowID)")
            }
        } catch {}
    }
    
    func startListening(socketPath: String, onRefresh: @escaping () -> Void, onShow: @escaping () -> Void, onSettings: @escaping () -> Void) {
        guard isAerospaceRunning() else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.subscribeToEvents(onRefresh: onRefresh, onShow: onShow, onSettings: onSettings)
        }
    }
    
    func stopListening() {
        eventListenerProcess?.terminate()
        eventListenerProcess = nil
    }
    
    // MARK: - Private Helpers
    
    private func fetchWorkspaces() throws -> [AeroSpaceWorkspace] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastWorkspacesFetch < workspacesCacheTTL && !cachedWorkspaces.isEmpty {
            return cachedWorkspaces
        }
        let output = try shell(aerospacePath, "list-workspaces", "--all", "--json")
        cachedWorkspaces = try JSONDecoder().decode([AeroSpaceWorkspace].self, from: Data(output.utf8))
        lastWorkspacesFetch = now
        return cachedWorkspaces
    }
    
    private func fetchFocusedWorkspaceName() throws -> String {
        let output = try shell(aerospacePath, "list-workspaces", "--focused", "--json")
        let workspace = try JSONDecoder().decode(AeroSpaceWorkspace.self, from: Data(output.utf8))
        return workspace.name
    }
    
    private func subscribeToEvents(onRefresh: @escaping () -> Void, onShow: @escaping () -> Void, onSettings: @escaping () -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: aerospacePath)
        task.arguments = ["subscribe",
                         "focused-workspace-changed",
                         "workspace-created",
                         "workspace-destroyed",
                         "focus-changed"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            eventListenerProcess = task
            
            let fileHandle = pipe.fileHandleForReading
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    task.terminate()
                    return
                }
                if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    if let jsonData = line.data(using: .utf8),
                       let event = try? JSONDecoder().decode(AeroSpaceEvent.self, from: jsonData) {
                        switch event.event {
                        case "focused-workspace_changed":
                            DispatchQueue.main.async { onRefresh() }
                        case "workspace_created", "workspace_destroyed":
                            DispatchQueue.main.async { onRefresh() }
                        case "focus_changed":
                            DispatchQueue.main.async { onRefresh() }
                        default:
                            break
                        }
                    }
                }
            }
            
            task.waitUntilExit()
        } catch {
            print("Failed to start AeroSpace event listener: \(error)")
        }
    }
    
    private func shell(_ args: String...) throws -> String {
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

// MARK: - AeroSpace Data Models

struct AeroSpaceWorkspace: Decodable {
    let name: String
    let monitor: Int
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        monitor = try container.decodeIfPresent(Int.self, forKey: .monitor) ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case monitor = "monitor-id"
    }
}

struct AeroSpaceWindow: Decodable {
    let windowId: Int
    let appName: String
    let workspace: String
    let windowTitle: String?
    let isFullscreen: Bool
    let windowLayout: String?
    let isHidden: Bool
    let sublayer: String?
    
    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case appName = "app-name"
        case workspace = "workspace"
        case windowTitle = "window-title"
        case isFullscreen = "is-fullscreen"
        case windowLayout = "window-layout"
        case isHidden = "is-hidden"
        case sublayer = "sublayer"
    }
}

struct AeroSpaceEvent: Decodable {
    let event: String
    let workspace: String?
    let prevWorkspace: String?
    let windowId: Int?
    let appName: String?
    let appBundleId: String?
    
    enum CodingKeys: String, CodingKey {
        case event = "_event"
        case workspace = "workspace"
        case prevWorkspace = "prev_workspace"
        case windowId = "window_id"
        case appName = "app_name"
        case appBundleId = "app_bundle_id"
    }
}