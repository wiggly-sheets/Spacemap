import XCTest
import Foundation
@testable import spacemap

private final class SocketReadSource {
    private let source: DispatchSourceRead
    private let closeDescriptor: (Int32) -> Void

    init(fileDescriptor: Int32, queue: DispatchQueue, eventHandler: @escaping () -> Void, closeDescriptor: @escaping (Int32) -> Void) {
        self.closeDescriptor = closeDescriptor
        source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler(handler: eventHandler)
        source.setCancelHandler {
            closeDescriptor(fileDescriptor)
        }
    }

    func activate() {
        source.resume()
    }

    func cancel() {
        source.cancel()
    }
}

final class SocketListenerTests: XCTestCase {
    private final class CloseRecorder {
        private let lock = NSLock()
        private(set) var count = 0

        func record() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        func recordedCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    func testShowCommandFromYabaiSignal() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.show.rawValue), .show)
    }

    func testASCIIShowCommandFromYabaiSignal() {
        XCTAssertEqual(SocketListener.command(for: Character("2").asciiValue!), .show)
    }

    func testBinaryShowCommandFromCLI() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.show.rawValue), .show)
    }

    func testUnknownCommandRefreshes() {
        XCTAssertEqual(SocketListener.command(for: Character("1").asciiValue!), .refresh)
    }

    func testBinaryToggleCommandFromCLI() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.toggle.rawValue), .toggle)
    }

    func testHealthProbeDoesNotTriggerRefresh() {
        XCTAssertEqual(SocketListener.command(for: SpacemapCommand.health.rawValue), .health)
        XCTAssertEqual(SocketListener.command(for: Character("5").asciiValue!), .health)
    }

    func testStalledClientDoesNotBlockCommandsOrShutdown() throws {
        let socketPath = temporarySocketPath()
        let refreshed = expectation(description: "second client command is handled")
        let listener = SocketListener(
            socketPath: socketPath,
            healthInterval: 60,
            onRefresh: { refreshed.fulfill() },
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer {
            listener.stop()
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        XCTAssertTrue(waitForSocket(at: socketPath))

        let stalledClientSocket = try connectClient(to: socketPath)
        defer { close(stalledClientSocket) }
        XCTAssertTrue(SocketListener.sendCommand(to: socketPath, command: SpacemapCommand.refresh.rawValue))

        wait(for: [refreshed], timeout: 1)
        let started = Date()
        listener.stop()
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    func testSocketIsOwnerOnly() throws {
        let socketPath = temporarySocketPath()
        let listener = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer {
            listener.stop()
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        XCTAssertTrue(waitForSocket(at: socketPath))

        let attributes = try FileManager.default.attributesOfItem(atPath: socketPath)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testNonceSurvivesStopAndListenerRestart() throws {
        let socketPath = temporarySocketPath()
        let noncePath = socketPath + ".nonce"
        let nonceURL = URL(fileURLWithPath: noncePath)
        defer {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(atPath: noncePath)
        }

        let first = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer { first.stop() }
        XCTAssertTrue(waitForSocket(at: socketPath))

        let nonce = try Data(contentsOf: nonceURL)
        XCTAssertEqual(nonce.count, 32)
        XCTAssertTrue(SocketListener.isSocketLive(path: socketPath))

        // A runtime listener rebuild calls stop(); the nonce must remain so
        // yabai signal actions that embedded it keep working.
        first.stop()
        XCTAssertFalse(SocketListener.isSocketLive(path: socketPath))
        XCTAssertEqual(try Data(contentsOf: nonceURL), nonce)

        let restarted = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer { restarted.stop() }
        XCTAssertTrue(waitForSocket(at: socketPath))
        XCTAssertEqual(try Data(contentsOf: nonceURL), nonce)
    }

    func testSecondListenerRefusesToStealLiveSocket() throws {
        let socketPath = temporarySocketPath()
        defer {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(atPath: socketPath + ".nonce")
        }

        let first = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer { first.stop() }
        XCTAssertTrue(waitForSocket(at: socketPath))

        let second = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer { second.stop() }

        let deadline = Date().addingTimeInterval(1)
        while !second.hasFailed && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(second.hasFailed)
        XCTAssertTrue(SocketListener.isSocketLive(path: socketPath))

        // Stopping the refused listener must not unlink the live socket.
        second.stop()
        XCTAssertTrue(SocketListener.isSocketLive(path: socketPath))
    }

    func testParseFrameRejectsBareFrameWhenNonceExpected() {
        let nonce = String(repeating: "a", count: 64)
        XCTAssertNil(SocketListener.parseFrame(
            Data([SpacemapCommand.show.rawValue]),
            nonce: nonce
        ))
        XCTAssertEqual(
            SocketListener.parseFrame(
                Data([SpacemapCommand.show.rawValue]) + Data((":" + nonce).utf8),
                nonce: nonce
            ),
            .show
        )
    }

    func testStaleSocketIsReplaced() throws {
        let socketPath = temporarySocketPath()
        defer {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(atPath: socketPath + ".nonce")
        }

        try createStaleSocket(at: socketPath)
        XCTAssertFalse(SocketListener.isSocketLive(path: socketPath))

        let listener = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer { listener.stop() }
        // The stale file already exists, so wait for the new listener to bind
        // before probing liveness.
        XCTAssertTrue(waitForSocketLive(at: socketPath))
    }

    func testBindRetryExhaustionExposesFailure() throws {
        let blocker = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sp-block-\(UUID().uuidString.prefix(8))")
        try "not a directory".write(toFile: blocker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: blocker) }

        let listener = SocketListener(
            socketPath: blocker + "/spacemap.socket",
            bindRetryDelays: [0.01, 0.01],
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer { listener.stop() }

        let deadline = Date().addingTimeInterval(2)
        while !listener.hasFailed && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(listener.hasFailed)
        XCTAssertNotNil(listener.failureDescription)
    }

    func testOverflowClientsAreQueuedAndStillServeCommands() throws {
        let socketPath = temporarySocketPath()
        let refreshed = expectation(description: "command served after client overflow")
        let listener = SocketListener(
            socketPath: socketPath,
            onRefresh: { refreshed.fulfill() },
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer {
            listener.stop()
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(atPath: socketPath + ".nonce")
        }
        XCTAssertTrue(waitForSocket(at: socketPath))

        var clients: [Int32] = []
        for _ in 0..<10 {
            clients.append(try connectClient(to: socketPath))
        }
        defer { clients.forEach { close($0) } }

        // Let the listener accept the burst into slots/pending before the
        // command connects, so the kernel backlog itself is not the thing
        // under test.
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(SocketListener.sendCommand(to: socketPath, command: SpacemapCommand.refresh.rawValue))
        wait(for: [refreshed], timeout: 2)
    }

    func testNonceFileIsRechmoddedWhenReused() throws {
        let socketPath = temporarySocketPath()
        let noncePath = socketPath + ".nonce"
        let nonceURL = URL(fileURLWithPath: noncePath)
        defer { try? FileManager.default.removeItem(atPath: noncePath) }

        let bytes = Data(repeating: 0x5A, count: 32)
        try bytes.write(to: nonceURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: noncePath)

        let hex = try XCTUnwrap(SocketListener.ensureNonceFile(for: socketPath))
        XCTAssertEqual(hex, String(repeating: "5a", count: 32))

        let attributes = try FileManager.default.attributesOfItem(atPath: noncePath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testNonceSymlinkIsReplacedWithoutFollowingIt() throws {
        let socketPath = temporarySocketPath()
        let noncePath = socketPath + ".nonce"
        let targetPath = socketPath + ".target"
        defer {
            try? FileManager.default.removeItem(atPath: noncePath)
            try? FileManager.default.removeItem(atPath: targetPath)
        }

        let targetBytes = Data(repeating: 0x11, count: 32)
        try targetBytes.write(to: URL(fileURLWithPath: targetPath))
        try FileManager.default.createSymbolicLink(atPath: noncePath, withDestinationPath: targetPath)

        let hex = try XCTUnwrap(SocketListener.ensureNonceFile(for: socketPath))
        XCTAssertNotEqual(hex, String(repeating: "11", count: 32))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: targetPath)), targetBytes)

        var st = stat()
        XCTAssertEqual(lstat(noncePath, &st), 0)
        XCTAssertEqual(st.st_mode & S_IFMT, S_IFREG)
    }

    func testPrepareNonceDoesNotRotateWhileAnotherInstanceIsLive() throws {
        let socketPath = temporarySocketPath()
        let noncePath = socketPath + ".nonce"
        let nonceURL = URL(fileURLWithPath: noncePath)
        defer {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(atPath: noncePath)
        }

        let listener = SocketListener(
            socketPath: socketPath,
            onRefresh: {},
            onShow: {},
            onToggle: {},
            onSettings: {}
        )
        defer { listener.stop() }
        XCTAssertTrue(waitForSocket(at: socketPath))

        let original = try Data(contentsOf: nonceURL)
        XCTAssertEqual(original.count, 32)
        SocketListener.resetNonceRotationForTesting()

        let prepared = try XCTUnwrap(SocketListener.prepareNonceForProcess(for: socketPath))
        XCTAssertEqual(prepared, original.map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try Data(contentsOf: nonceURL), original)
    }

    func testReadSourceClosesDescriptorOnceFromCancellationHandler() {
        var descriptors: [Int32] = [-1, -1]
        XCTAssertEqual(pipe(&descriptors), 0)
        guard descriptors.allSatisfy({ $0 >= 0 }) else { return }
        defer {
            close(descriptors[0])
            close(descriptors[1])
        }

        let queue = DispatchQueue(label: "com.spacemap.tests.socket-cancellation")
        queue.suspend()
        let recorder = CloseRecorder()
        let closed = expectation(description: "descriptor closes in cancellation handler")
        closed.assertForOverFulfill = true
        let source = SocketReadSource(
            fileDescriptor: descriptors[0],
            queue: queue,
            eventHandler: {},
            closeDescriptor: { _ in
                recorder.record()
                closed.fulfill()
            }
        )
        source.activate()

        source.cancel()
        source.cancel()

        XCTAssertEqual(recorder.recordedCount(), 0)
        queue.resume()
        wait(for: [closed], timeout: 1)
        XCTAssertEqual(recorder.recordedCount(), 1)
    }

    private func temporarySocketPath() -> String {
        // Short name: the full path must stay within sun_path (103 bytes).
        (NSTemporaryDirectory() as NSString).appendingPathComponent("sp-t-\(UUID().uuidString.prefix(8)).socket")
    }

    private func waitForSocket(at path: String, timeout: TimeInterval = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    private func waitForSocketLive(at path: String, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if SocketListener.isSocketLive(path: path) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    private func connectClient(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENFILE) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyMemory(from: UnsafeRawBufferPointer(
                    start: source.baseAddress,
                    count: min(source.count, destination.count - 1)
                ))
            }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED
            close(fd)
            throw POSIXError(error)
        }
        return fd
    }

    /// Create a bound-but-closed UNIX socket, the crash-leftover shape the
    /// listener must prove stale before unlinking.
    private func createStaleSocket(at path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENFILE) }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyMemory(from: UnsafeRawBufferPointer(
                    start: source.baseAddress,
                    count: min(source.count, destination.count - 1)
                ))
            }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }
    }
}
