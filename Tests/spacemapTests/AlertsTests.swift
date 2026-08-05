import XCTest
@testable import spacemap

final class AlertsTests: XCTestCase {

    // MARK: - isMRUSpacesEnabled

    func testIsMRUSpacesEnabledReturnsBool() {
        // Just verify it returns a Bool without crashing
        // The actual value depends on system defaults
        let _ = Alerts().isMRUSpacesEnabled()
    }

    // MARK: - showYabaiAlert

    func testShowYabaiAlertDoesNotCrash() {
        // NSAlert.runModal() and NSApp.terminate() are not testable in unit tests
        // Just verify the method exists and can be called without crashing
        Alerts().showYabaiAlert()
    }

    // MARK: - showMRUAlert

    func testShowMRUAlertDoesNotCrash() {
        // NSAlert.runModal() and NSApp.terminate() are not testable in unit tests
        Alerts().showMRUAlert()
    }

    // MARK: - showSeparateSpacesAlert

    func testShowSeparateSpacesAlertDoesNotCrash() {
        // NSAlert.runModal() is not testable in unit tests
        Alerts().showSeparateSpacesAlert()
    }
}