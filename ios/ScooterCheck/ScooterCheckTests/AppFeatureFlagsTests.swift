import XCTest
@testable import ScooterCheck

final class AppFeatureFlagsTests: XCTestCase {
    func testPedelecAuslesenHiddenForPresentation() {
        // Präsentation: nur E-Scooter auslesen sichtbar.
        XCTAssertFalse(AppFeatureFlags.pedelecAuslesenVisible)
    }
}
