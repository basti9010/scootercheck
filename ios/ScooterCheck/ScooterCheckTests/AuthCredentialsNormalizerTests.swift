import XCTest
@testable import ScooterCheck

final class AuthCredentialsNormalizerTests: XCTestCase {
    func testNormalizedEmailLowercasesAndTrims() {
        XCTAssertEqual(
            AuthCredentialsNormalizer.normalizedEmail("  Bastian.Test@Example.COM \n"),
            "bastian.test@example.com"
        )
    }

    func testNormalizedPasswordTrimsWhitespaceOnly() {
        XCTAssertEqual(
            AuthCredentialsNormalizer.normalizedPassword("  secretPass1  "),
            "secretPass1"
        )
    }

    func testToggledLetterCaseSwapsUpperAndLower() {
        XCTAssertEqual(
            AuthCredentialsNormalizer.toggledLetterCase("AbC-xyZ1!"),
            "aBc-XYz1!"
        )
    }

    func testToggledLetterCaseIdempotentTwice() {
        let original = "ScooterCheck!42"
        let once = AuthCredentialsNormalizer.toggledLetterCase(original)
        let twice = AuthCredentialsNormalizer.toggledLetterCase(once)
        XCTAssertEqual(twice, original)
        XCTAssertNotEqual(once, original)
    }

    func testWrongCredentialsMessageDetection() {
        XCTAssertTrue(
            AuthCredentialsNormalizer.isWrongCredentialsMessage("E-Mail oder Passwort falsch")
        )
        XCTAssertFalse(
            AuthCredentialsNormalizer.isWrongCredentialsMessage("Freischaltung ausstehend")
        )
    }
}
