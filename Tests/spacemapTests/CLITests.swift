import XCTest
import Foundation
@testable import spacemap

final class CLITests: XCTestCase {
    func testParsesEverySupportedSpaceIndex() {
        for index in 1...16 {
            XCTAssertEqual(
                CLI.parse(arguments: ["spacemap", "--space", "\(index)"]),
                .focusSpace(SpaceFocusTarget(argument: "\(index)")!)
            )
        }
    }

    func testParsesNamedAndLabelSpaceSelectors() {
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--space", "recent"]),
            .focusSpace(SpaceFocusTarget(argument: "recent")!)
        )
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--space", "web"]),
            .focusSpace(SpaceFocusTarget(argument: "web")!)
        )
    }

    func testRejectsMissingAndOutOfRangeSpaceSelectors() {
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--space"]),
            .error("--space requires next, prev, first, last, recent, mouse, a label, or an index from 1 to 16")
        )
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--space", "17"]),
            .error("--space requires next, prev, first, last, recent, mouse, a label, or an index from 1 to 16")
        )
        // A following flag is not a selector.
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--space", "--version"]),
            .error("--space requires next, prev, first, last, recent, mouse, a label, or an index from 1 to 16")
        )
    }

    func testParsesOtherExitOnlyCommands() {
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--help"]), .command(.help))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--version"]), .command(.version))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--config"]), .command(.config))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--print-config"]), .command(.printConfig))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--status"]), .command(.status))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--trigger"]), .command(.toggle))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--update"]), .command(.update))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--update-font"]), .command(.updateFont))
        XCTAssertEqual(CLI.parse(arguments: ["spacemap"]), .none)
    }

    func testUnknownFlagsAreRejectedInsteadOfLaunchingASecondInstance() {
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--settigns"]),
            .error("unknown option: --settigns")
        )
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "-x"]),
            .error("unknown option: -x")
        )
        // Positional arguments are harmless (the executable path itself is one).
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "extra"]), .none)
        // Internal launch markers must still reach the app, not exit as errors.
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--settings"]), .none)
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--show-menu"]), .none)
        XCTAssertEqual(CLI.parse(arguments: ["spacemap", "--restarting"]), .none)
    }

    func testParsesConfigPresetAndRejectsMissingOrUnsafeNames() {
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--config-preset", "My Work"]),
            .configPreset("My Work")
        )
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--config-preset"]),
            .error("--config-preset requires a preset name (letters, digits, spaces, - or _)")
        )
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--config-preset", "../escape"]),
            .error("--config-preset requires a preset name (letters, digits, spaces, - or _)")
        )
        XCTAssertEqual(
            CLI.parse(arguments: ["spacemap", "--config-preset", "--version"]),
            .error("--config-preset requires a preset name (letters, digits, spaces, - or _)")
        )
    }

    func testEveryTableFlagIsRecognised() {
        for row in CLIFlagTable.rows {
            let arguments: [String]
            switch row.target {
            case .focusSpace:
                arguments = ["spacemap", row.flag, "1"]
            case .configPreset:
                arguments = ["spacemap", row.flag, "Work"]
            case .exit, .deliver, .marker:
                arguments = ["spacemap", row.flag]
            }
            XCTAssertNotEqual(
                CLI.parse(arguments: arguments),
                .error("unknown option: \(row.flag)"),
                "\(row.flag) must be in the flag table"
            )
        }
    }

    func testFlagTableHasUniqueFlags() {
        let flags = CLIFlagTable.rows.map(\.flag)
        XCTAssertEqual(Set(flags).count, flags.count)
        XCTAssertTrue(flags.allSatisfy { $0.hasPrefix("--") })
    }

    func testDeliverAndMarkerFlagsFallThroughToLaunch() {
        for row in CLIFlagTable.rows {
            switch row.target {
            case .deliver, .marker:
                XCTAssertEqual(CLI.parse(arguments: ["spacemap", row.flag]), .none)
            case .exit, .focusSpace, .configPreset:
                continue
            }
        }
    }

    func testVersionLineUsesTheSharedVersionSource() {
        XCTAssertEqual(CLI.versionLine(shortVersion: "1.2.3"), "Spacemap 1.2.3")
        XCTAssertEqual(CLI.versionLine(shortVersion: nil), "Spacemap Unknown")
    }

    func testStatusLinesReportEveryField() {
        XCTAssertEqual(
            CLI.statusLines(
                version: "1.2.3",
                appPath: "/Applications/Spacemap.app",
                configPath: "/Users/me/.config/spacemap/config.toml",
                running: true,
                yabaiAvailable: false
            ),
            [
                "Spacemap 1.2.3",
                "App: /Applications/Spacemap.app",
                "Config: /Users/me/.config/spacemap/config.toml",
                "Running: yes",
                "yabai: unavailable",
            ]
        )
    }

    func testUnknownOptionExitsWithUsageCode() {
        let cli = CLI(yabaiService: MockYabaiService())
        XCTAssertEqual(cli.runIfRequested(arguments: ["spacemap", "--bogus"]) ?? -1, 2)
        XCTAssertNil(cli.runIfRequested(arguments: ["spacemap"]))
    }

    func testMoveToApplicationsUsesPathComponents() {
        let applicationsPaths = ["/Applications"]
        XCTAssertTrue(CLIToolsService.isInApplications(
            appPath: "/Applications/Spacemap.app",
            applicationsPaths: applicationsPaths
        ))
        XCTAssertTrue(CLIToolsService.isInApplications(
            appPath: "/Applications/Spacemap.app/",
            applicationsPaths: applicationsPaths
        ))
        XCTAssertFalse(CLIToolsService.isInApplications(
            appPath: "/Applications-old/Spacemap.app",
            applicationsPaths: applicationsPaths
        ))
        XCTAssertFalse(CLIToolsService.isInApplications(
            appPath: "/Applications",
            applicationsPaths: applicationsPaths
        ))
    }

    func testDefaultApplicationsPathIsSystemApplications() {
        XCTAssertEqual(CLIToolsService.applicationsPaths, ["/Applications"])
    }

    func testMovePromptRespectsDeclinedFlag() {
        let applicationsPaths = ["/Applications"]
        XCTAssertTrue(CLIToolsService.shouldPromptToMove(
            appPath: "/Users/me/Downloads/Spacemap.app",
            hasDeclined: false,
            applicationsPaths: applicationsPaths
        ))
        XCTAssertFalse(CLIToolsService.shouldPromptToMove(
            appPath: "/Users/me/Downloads/Spacemap.app",
            hasDeclined: true,
            applicationsPaths: applicationsPaths
        ))
        XCTAssertFalse(CLIToolsService.shouldPromptToMove(
            appPath: "/Applications/Spacemap.app",
            hasDeclined: false,
            applicationsPaths: applicationsPaths
        ))
        XCTAssertTrue(CLIToolsService.shouldPromptToMove(
            appPath: "/Users/me/Applications/Spacemap.app",
            hasDeclined: false,
            applicationsPaths: applicationsPaths
        ))
    }

    func testSymlinkTargetsDeriveFromTheRunningBundle() {
        let bundle = URL(fileURLWithPath: "/tmp/Spacemap.app")
        let executable = URL(fileURLWithPath: "/tmp/Spacemap.app/Contents/MacOS/Spacemap")
        let manPage = URL(fileURLWithPath: "/tmp/Spacemap.app/Contents/Resources/spacemap.1")

        XCTAssertEqual(
            CLIToolsService.cliTargetPath(bundleURL: bundle, executableURL: executable),
            executable.path
        )
        XCTAssertEqual(
            CLIToolsService.cliTargetPath(bundleURL: bundle, executableURL: nil),
            "/tmp/Spacemap.app/Contents/MacOS/Spacemap"
        )
        XCTAssertEqual(
            CLIToolsService.manPageTargetPath(bundleURL: bundle, resourceURL: manPage),
            manPage.path
        )
        XCTAssertEqual(
            CLIToolsService.manPageTargetPath(bundleURL: bundle, resourceURL: nil),
            "/tmp/Spacemap.app/Contents/Resources/spacemap.1"
        )
    }

    func testAuthorizationScriptQuotesDerivedPaths() throws {
        let cliPath = "/Applications/My App.app/Contents/MacOS/Spacemap"
        let manPagePath = "/Applications/My App.app/Contents/Resources/spacemap.1"
        let script = try XCTUnwrap(CLIToolsService.authorizationScript(
            cliPath: cliPath,
            manPagePath: manPagePath
        ))

        XCTAssertTrue(script.contains("'\(cliPath)'"))
        XCTAssertTrue(script.contains("'\(manPagePath)'"))
        XCTAssertFalse(script.contains("/Applications/Spacemap.app"))
        XCTAssertNil(CLIToolsService.authorizationScript(cliPath: "relative/path", manPagePath: manPagePath))
        XCTAssertNil(CLIToolsService.authorizationScript(
            cliPath: "/bad\"path",
            manPagePath: manPagePath
        ))
    }

    func testAppleScriptEscapesShellCommand() {
        let source = CLIToolsService.appleScriptSource(forShellCommand: "echo \"hi\"")
        XCTAssertTrue(source.hasPrefix("do shell script \""))
        XCTAssertTrue(source.contains("\\\"hi\\\""))
        XCTAssertTrue(source.hasSuffix("\" with administrator privileges"))
    }

    func testRestartPlanWaitsForParentThenOpensBundle() {
        let plan = AppRestartPlan.make(bundlePath: "/Applications/My App.app", parentPID: 1234)

        XCTAssertEqual(plan.executablePath, "/bin/sh")
        XCTAssertEqual(plan.arguments.first, "-c")
        XCTAssertTrue(plan.arguments[1].contains("kill -0"))
        XCTAssertTrue(plan.arguments[1].contains("/usr/bin/open"))
        XCTAssertTrue(plan.arguments[1].contains("[ \"$i\" -lt 50 ]"))
        XCTAssertEqual(plan.arguments[3], "1234")
        XCTAssertEqual(plan.arguments[4], "/Applications/My App.app")
        XCTAssertTrue(plan.arguments[1].contains("--restarting"))
    }

    func testLaunchAtLoginStatusIsVerified() {
        XCTAssertTrue(CLIToolsService.launchAtLoginSucceeded(enabled: true, status: .enabled))
        XCTAssertTrue(CLIToolsService.launchAtLoginSucceeded(enabled: true, status: .requiresApproval))
        XCTAssertFalse(CLIToolsService.launchAtLoginSucceeded(enabled: true, status: .notRegistered))
        XCTAssertTrue(CLIToolsService.launchAtLoginSucceeded(enabled: false, status: .notRegistered))
        XCTAssertFalse(CLIToolsService.launchAtLoginSucceeded(enabled: false, status: .enabled))

        XCTAssertTrue(CLIToolsService.launchAtLoginNeedsApproval(enabled: true, status: .requiresApproval))
        XCTAssertFalse(CLIToolsService.launchAtLoginNeedsApproval(enabled: true, status: .enabled))
        XCTAssertFalse(CLIToolsService.launchAtLoginNeedsApproval(enabled: false, status: .requiresApproval))

        // Toggle direction: pending approval counts as on, so toggling disables.
        XCTAssertTrue(CLIToolsService.launchAtLoginIsEnabled(status: .enabled))
        XCTAssertTrue(CLIToolsService.launchAtLoginIsEnabled(status: .requiresApproval))
        XCTAssertFalse(CLIToolsService.launchAtLoginIsEnabled(status: .notRegistered))
    }

    func testSingleInstanceForwardingArguments() {
        XCTAssertEqual(
            SingleInstanceGuard.forwardingURL(for: "--settings")?.absoluteString,
            "spacemap://settings"
        )
        XCTAssertEqual(
            SingleInstanceGuard.forwardingURL(for: "--show-menu")?.absoluteString,
            "spacemap://menu"
        )
        XCTAssertNil(SingleInstanceGuard.forwardingURL(for: "--version"))
        XCTAssertEqual(SingleInstanceGuard.socketCommand(for: "--settings"), .settings)
        XCTAssertNil(SingleInstanceGuard.socketCommand(for: "--show-menu"))
    }

    func testEveryDeliveredFlagForwardsAccordingToTheTable() {
        for row in CLIFlagTable.rows {
            guard case .deliver(let command, let deepLink) = row.target else { continue }
            XCTAssertEqual(
                SingleInstanceGuard.socketCommand(for: row.flag),
                command.socketByte == nil ? nil : command
            )
            XCTAssertEqual(
                SingleInstanceGuard.forwardingURL(for: row.flag)?.absoluteString,
                deepLink
            )
        }
        XCTAssertEqual(
            CLIFlagTable.deliveredCommands(in: ["spacemap", "--show-menu", "--settings"]),
            [.showMenu, .settings]
        )
        XCTAssertEqual(CLIFlagTable.deliveredCommands(in: ["spacemap", "--trigger"]), [])
    }

    func testSettingsForwardUsesLiveSocketFirst() {
        let socketPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sp-fwd-\(UUID().uuidString.prefix(8)).socket")
        let delivered = expectation(description: "settings forwarded over socket")
        let listener = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: { delivered.fulfill() }
        )
        defer {
            listener.stop()
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(atPath: socketPath + ".nonce")
        }
        XCTAssertTrue(waitForSocket(at: socketPath))

        SingleInstanceGuard.forward(arguments: ["--settings"], socketPath: socketPath)
        wait(for: [delivered], timeout: 1)
    }

    func testAtomicBundleCopyReplacesExistingDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacemap-move-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "one".write(to: source, atomically: true, encoding: .utf8)
        try CLIToolsService.copyBundleAtomically(source: source, destination: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "one")

        try "two".write(to: source, atomically: true, encoding: .utf8)
        try CLIToolsService.copyBundleAtomically(source: source, destination: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "two")
    }

    private func waitForSocket(at path: String, timeout: TimeInterval = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }
}
