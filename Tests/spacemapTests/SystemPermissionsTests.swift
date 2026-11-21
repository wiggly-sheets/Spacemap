import XCTest
import ApplicationServices
@testable import spacemap

final class SystemPermissionsTests: XCTestCase {
    func testOnlyDisabledAPIProvesAccessibilityRevoked() {
        XCTAssertTrue(SystemPermissions.accessibilityIsUsable(trusted: true, error: .success))
        XCTAssertTrue(SystemPermissions.accessibilityIsUsable(trusted: true, error: .noValue))
        // A busy or protected focused app answers cannotComplete; the
        // permission itself is still granted.
        XCTAssertTrue(SystemPermissions.accessibilityIsUsable(trusted: true, error: .cannotComplete))
        XCTAssertTrue(SystemPermissions.accessibilityIsUsable(trusted: true, error: .invalidUIElement))
        XCTAssertFalse(SystemPermissions.accessibilityIsUsable(trusted: true, error: .apiDisabled))
        XCTAssertFalse(SystemPermissions.accessibilityIsUsable(trusted: false, error: .success))
    }
}
