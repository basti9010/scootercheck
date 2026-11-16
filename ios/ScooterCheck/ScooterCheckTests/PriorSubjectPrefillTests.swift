import XCTest
@testable import ScooterCheck

final class PriorSubjectPrefillTests: XCTestCase {

    func testPrefersCurrentNonEmptySubject() {
        let current = ProtocolSubject(lastName: "Aktuell", licensePlate: "B-NEU 1").sanitized()
        let prior = ProtocolSubject(lastName: "Alt", licensePlate: "B-ALT 1").sanitized()
        let resolved = SubjectPrefill.resolve(preserving: current, prior: prior)
        XCTAssertEqual(resolved.subject.lastName, "Aktuell")
        XCTAssertFalse(resolved.prefilled)
    }

    func testUsesPriorWhenCurrentEmpty() {
        let prior = ProtocolSubject(
            lastName: "Neukirch",
            firstName: nil,
            birthDate: nil,
            licensePlate: "905YFI"
        ).sanitized()
        let resolved = SubjectPrefill.resolve(preserving: .empty, prior: prior)
        XCTAssertTrue(resolved.prefilled)
        XCTAssertEqual(resolved.subject.lastName, "Neukirch")
        XCTAssertEqual(resolved.subject.licensePlate, "905YFI")
    }

    func testEmptyWhenNoPrior() {
        let resolved = SubjectPrefill.resolve(preserving: nil, prior: nil)
        XCTAssertTrue(resolved.subject.isEmpty)
        XCTAssertFalse(resolved.prefilled)
    }

    func testIgnoresWhitespaceOnlyPrior() {
        let prior = ProtocolSubject(lastName: "   ", licensePlate: "\n")
        let resolved = SubjectPrefill.resolve(preserving: nil, prior: prior)
        XCTAssertTrue(resolved.subject.isEmpty)
        XCTAssertFalse(resolved.prefilled)
    }
}
