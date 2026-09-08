import XCTest
@testable import ScootProof

final class ProtocolSubjectTests: XCTestCase {

    func testEmptyWhenAllBlank() {
        let subject = ProtocolSubject(lastName: "  ", firstName: "", birthDate: nil, licensePlate: "\n")
        XCTAssertTrue(subject.sanitized().isEmpty)
        XCTAssertNil(subject.sanitized().summaryLine)
    }

    func testSummaryIncludesNamePlateAndBirth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let birth = cal.date(from: DateComponents(year: 1990, month: 5, day: 12))!
        let subject = ProtocolSubject(
            lastName: " Mustermann ",
            firstName: "Max",
            birthDate: birth,
            licensePlate: "b-ab 1234"
        ).sanitized()
        XCTAssertEqual(subject.displayName, "Max Mustermann")
        XCTAssertEqual(subject.licensePlate, "B-AB 1234")
        XCTAssertFalse(subject.isEmpty)
        let line = try XCTUnwrap(subject.summaryLine)
        XCTAssertTrue(line.contains("Max Mustermann"))
        XCTAssertTrue(line.contains("B-AB 1234"))
    }

    func testCheckSessionDecodesWithoutSubject() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "profile": "maxG3D",
          "createdAt": "2023-11-14T22:13:20Z",
          "protocolNumber": "SC-20231114-TESTTEST"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(CheckSession.self, from: json)
        XCTAssertTrue(session.subject.isEmpty)
        XCTAssertEqual(session.protocolNumber, "SC-20231114-TESTTEST")
        XCTAssertEqual(session.id, id)
    }
}
