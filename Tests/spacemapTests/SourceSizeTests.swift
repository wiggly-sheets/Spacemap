import Foundation
import XCTest

/// Keeps every Swift file small enough to read and edit safely.
///
/// Files regrow when a new feature lands in the file that already holds the
/// previous one, so a new concern belongs in a new extension file. Raise
/// `lineLimit` only with a reason in the commit message.
final class SourceSizeTests: XCTestCase {
    private static let lineLimit = 500

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testNoSwiftFileExceedsTheLineLimit() throws {
        var oversized: [String] = []

        for url in try swiftFiles(in: "Sources") + swiftFiles(in: "Tests") {
            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
            if lines > Self.lineLimit {
                let path = url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                oversized.append("\(path): \(lines) lines")
            }
        }

        XCTAssertTrue(
            oversized.isEmpty,
            "Split these into extension files (limit \(Self.lineLimit) lines):\n\(oversized.joined(separator: "\n"))"
        )
    }

    private func swiftFiles(in directory: String) throws -> [URL] {
        let root = repositoryRoot.appendingPathComponent(directory, isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
