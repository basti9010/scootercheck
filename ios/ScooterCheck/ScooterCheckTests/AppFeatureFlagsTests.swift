import XCTest
@testable import ScooterCheck

final class AppFeatureFlagsTests: XCTestCase {
    func testPedelecAuslesenHiddenForPresentation() {
        // Präsentation: nur E-Scooter auslesen sichtbar.
        XCTAssertFalse(AppFeatureFlags.pedelecAuslesenVisible)
    }

    /// P0 recovery: auth gate must stay on. PR #114 set `authGateEnabled = false` — never ship that here.
    func testAuthGateNotDisabledViaFeatureFlag() throws {
        // Recovery branch omits the flag (AuthGateView is unconditional app root).
        // If re-introduced, it must never be false — see AuthSecurityRegressionTests.
        let flagsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ScooterCheck/AppFeatureFlags.swift")
        let src = try String(contentsOf: flagsURL, encoding: .utf8)
        XCTAssertFalse(src.contains("authGateEnabled = false"))
        XCTAssertFalse(src.contains("DemoAuthBootstrap"))
    }
}
