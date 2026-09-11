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
        "/private/tmp/spacemap-tests-\(UUID().uuidString).socket"
    }

    private func waitForSocket(at path: String, timeout: TimeInterval = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
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
}
