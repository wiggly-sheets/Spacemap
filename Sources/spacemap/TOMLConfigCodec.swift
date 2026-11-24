import Foundation
import CoreGraphics

enum TOMLParserError: LocalizedError {
    case parseFailure(reason: String)

    var errorDescription: String? {
        switch self {
        case .parseFailure(let reason):
            return "TOML parse failure: \(reason)"
        }
    }
}

enum TOMLConfigCodec {
    /// Decodes and repairs in one walk: the result is a complete config seeded
    /// from the defaults, plus whether the file needs a rewritten copy.
    static func parse(_ data: String) throws -> (config: SpacemapConfig, needsRepair: Bool) {
        guard let object = TOMLDocumentParser.parse(data) else {
            throw TOMLParserError.parseFailure(reason: "malformed TOML")
        }
        return TOMLConfigDecoder.decode(TOMLConfigDecoder.normalize(object))
    }
}

typealias TOMLParser = TOMLConfigCodec
