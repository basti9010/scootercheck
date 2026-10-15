import XCTest
@testable import ScootProof

final class KnownScooterAliasTests: XCTestCase {

    func testMakeKnownLabelPrefersNameAndPlate() {
        let subject = ProtocolSubject(
            lastName: "Neukirch",
            firstName: nil,
            birthDate: nil,
            licensePlate: "905YFI"
        ).sanitized()
        XCTAssertEqual(
            ProtocolHistoryStore.makeKnownLabel(from: subject),
            "Neukirch · 905YFI"
        )
    }

    func testMakeKnownLabelPlateOnly() {
        let subject = ProtocolSubject(licensePlate: "b-ab 123").sanitized()
        XCTAssertEqual(ProtocolHistoryStore.makeKnownLabel(from: subject), "B-AB 123")
    }

    func testScanListAliasFallsBackToBereitsGeprueft() {
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-TEST",
            createdAt: Date(),
            profile: .maxG3D,
            serialDisplay: "1EFHE2515C0440"
        )
        XCTAssertEqual(entry.scanListAlias, "bereits geprüft")
    }

    func testScanListAliasUsesKnownLabel() {
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-TEST",
            createdAt: Date(),
            profile: .maxG3D,
            serialDisplay: "1EFHE2515C0440",
            subjectSummary: "Neukirch · 905YFI",
            knownLabel: "Neukirch · 905YFI"
        )
        XCTAssertEqual(entry.scanListAlias, "Neukirch · 905YFI")
    }

    func testEntryDecodesWithoutNewAliasFields() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "protocolNumber": "SC-OLD",
          "createdAt": "2023-11-14T22:13:20Z",
          "profile": "maxG3D",
          "serialDisplay": "1CGBF2531C0230",
          "subjectSummary": "Max Mustermann · B-AB 1"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ProtocolHistoryStore.Entry.self, from: json)
        XCTAssertEqual(entry.serialDisplay, "1CGBF2531C0230")
        XCTAssertEqual(entry.scanListAlias, "Max Mustermann · B-AB 1")
        XCTAssertNil(entry.blePeripheralId)
        XCTAssertNil(entry.knownLabel)
    }
}
