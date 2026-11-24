import XCTest
@testable import spacemap

class ConfigSchemaTestCase: XCTestCase {
    func decoded(_ toml: String) throws -> (config: SpacemapConfig, needsRepair: Bool) {
        try TOMLParser.parse(toml)
    }

    func written(_ config: SpacemapConfig) -> String {
        ConfigLoader.tomlConfigString(from: config, includeHeaderComments: false)
    }

}
