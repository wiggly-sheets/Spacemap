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

enum TOMLParser: TOMLParserProtocol {
    static func parse(_ data: String) throws -> ConfigValues {
        guard let object = TOMLDocumentParser.parse(data) else {
            throw TOMLParserError.parseFailure(reason: "malformed TOML")
        }
        return TOMLConfigDecoder.decode(TOMLConfigDecoder.normalize(object))
    }
}
