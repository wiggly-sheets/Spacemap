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

    private func querySpaces() -> [Space] {
        guard isAerospaceRunning() else { return [] }
        do {
            let workspaces = try fetchWorkspaces()
            let focusedName = (try? fetchFocusedWorkspaceName()) ?? workspaces.first?.name

            return workspaces.enumerated().map { offset, ws in
                Space(
                    id: offset + 1,
                    index: offset + 1,
                    display: ws.monitor,
                    hasFocus: ws.name == focusedName,
                    label: ws.name
                )
            }
        } catch {
            return []
        }
    }

    func queryWindows() throws -> [Window] {
        guard isAerospaceRunning() else { return [] }
        let output = try shell(aerospacePath, "list-windows", "--all", "--json")
        let aerospaceWindows = try JSONDecoder().decode([AeroSpaceWindow].self, from: Data(output.utf8))

        let workspaces = try fetchWorkspaces()

        return aerospaceWindows.compactMap { aw -> Window? in
            let spaceIndex = (workspaces.firstIndex { $0.name == aw.workspace } ?? 0) + 1
            let frame = getWindowFrame(forApp: aw.appName, windowTitle: aw.windowTitle)
                ?? Window.WindowFrame(x: 0, y: 0, w: 100, h: 100)

            return Window(
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

    private func getWindowFrame(forApp appName: String, windowTitle: String?) -> Window.WindowFrame? {
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

    private func getWindowFrameFromAX(_ axWindow: AXUIElement) -> Window.WindowFrame? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return Window.WindowFrame(x: position.x, y: position.y, w: size.width, h: size.height)
    }

    func queryFocusedWindow() throws -> Int? {
        guard isAerospaceRunning() else { return nil }
        let output = try shell(aerospacePath, "list-windows", "--focused", "--json")
        let windows = try JSONDecoder().decode([AeroSpaceWindow].self, from: Data(output.utf8))
        return windows.first?.windowId
    }

    func queryFocusedSpaceIndex() -> Int? {
        guard isAerospaceRunning() else { return nil }
        do {
            let workspaces = try fetchWorkspaces()
            let focusedName = try fetchFocusedWorkspaceName()
            return workspaces.firstIndex { $0.name == focusedName }.map { $0 + 1 }
        } catch {
            return nil
        }
    }

    func buildGridState(config: GridConfig) -> GridState {
        guard isAerospaceRunning() else {
            let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
            return GridState(config: config, spaces: [], windows: [], displayBounds: displayBounds, focusedIndex: nil)
        }

        let spaces = querySpaces()
        let windows = (try? queryWindows()) ?? []
        let resolvedFocus = spaces.first { $0.hasFocus }?.index
        let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let displays = NSScreen.screens.enumerated().map { offset, screen in
            YabaiDisplay(
                index: offset + 1,
                frame: YabaiDisplay.Frame(
                    x: screen.frame.minX,
                    y: screen.frame.minY,
                    w: screen.frame.width,
                    h: screen.frame.height
                ),
                hasFocus: screen == NSScreen.main
            )
        }
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: resolvedFocus, displays: displays)
    }

    func focusSpaceAsync(_ index: Int) {
        guard isAerospaceRunning() else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            do {
                let workspaces = try fetchWorkspaces()
                if index > 0 && index <= workspaces.count {
                    let workspaceName = workspaces[index - 1].name
                    _ = try? shell(aerospacePath, "workspace", workspaceName)
                }
            } catch {}
        }
    }

    func moveWindowCreatingSpacesIfNeeded(
        _ windowID: Int,
        toSpace spaceIndex: Int,
        focusDestination: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let workspaces = try fetchWorkspaces()
                guard spaceIndex > 0, spaceIndex <= workspaces.count else {
                    throw AeroSpaceError.workspaceDoesNotExist(index: spaceIndex)
                }
                let workspaceName = workspaces[spaceIndex - 1].name
                _ = try shell(aerospacePath, "move-node-to-workspace", workspaceName, "--window-id", "\(windowID)")
                if focusDestination {
                    _ = try? shell(aerospacePath, "workspace", workspaceName)
                }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func runOnQueue(_ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: block)
    }

    func runOnQueue(_ workItem: DispatchWorkItem) {
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    func registerRefreshSignals(socketPath: String) {}
    func removeRefreshSignals() {}

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
        let workspaces = try JSONDecoder().decode([AeroSpaceWorkspace].self, from: Data(output.utf8))
        guard let workspace = workspaces.first else {
            throw AeroSpaceError.noFocusedWorkspace
        }
        return workspace.name
    }

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
            throw AeroSpaceError.commandFailed(
                arguments: Array(args.dropFirst()),
                status: process.terminationStatus,
                message: message
            )
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

private enum AeroSpaceError: LocalizedError {
    case workspaceDoesNotExist(index: Int)
    case commandFailed(arguments: [String], status: Int32, message: String)
    case noFocusedWorkspace

    var errorDescription: String? {
        switch self {
        case .workspaceDoesNotExist(let index):
            return "AeroSpace workspace \(index) does not exist"
        case .commandFailed(let arguments, let status, let message):
            let detail = message.isEmpty ? "no error output" : message
            return "aerospace \(arguments.joined(separator: " ")) failed with status \(status): \(detail)"
        case .noFocusedWorkspace:
            return "AeroSpace did not report a focused workspace"
        }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowId = try container.decode(Int.self, forKey: .windowId)
        appName = try container.decode(String.self, forKey: .appName)
        workspace = try container.decode(String.self, forKey: .workspace)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        isFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isFullscreen) ?? false
        windowLayout = try container.decodeIfPresent(String.self, forKey: .windowLayout)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        sublayer = try container.decodeIfPresent(String.self, forKey: .sublayer)
    }
}
