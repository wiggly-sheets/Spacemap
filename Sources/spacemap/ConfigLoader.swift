import Foundation

/// Why a load replaced or repaired the file. `load` keeps its existing tuple;
/// `loadReportingResult` exposes this for callers that can surface a message.
enum ConfigLoadStatus: Equatable {
    case loaded
    case repaired
    case createdDefault
    case unreadable
    case oversized
    case parseFailed
}
enum ConfigLoader {
    /// Fail-closed ceilings. Decode logic below is untouched; oversized input
    /// never reaches it.
    static let maxConfigBytes = 256 * 1024
    static let maxLineBytes = 16 * 1024

    /// One lock for every disk load/save. Recursive because self-heal saves
    /// while a load holds the lock, and `update` nests a load inside a save.
    static let ioLock = NSRecursiveLock()
    /// Log a parse failure once per path; cleared after a successful parse so
    /// a later relapse logs again instead of staying silent forever.
    static var loggedParseFailures: Set<String> = []

    static let maxLabelChars = 64

}
