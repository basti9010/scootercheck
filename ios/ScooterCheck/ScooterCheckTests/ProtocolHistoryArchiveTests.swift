import XCTest
@testable import ScooterCheck

final class ProtocolHistoryArchiveTests: XCTestCase {

    func testEntryDefaultsNotArchived() {
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-A1",
            createdAt: Date(),
            profile: .maxG3D,
            serialDisplay: "1EFHE2515C0440",
            wasVerifiedAsScooter: true
        )
        XCTAssertFalse(entry.isArchived)
    }

    func testEntryDecodesMissingArchivedAsFalse() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "protocolNumber": "SC-OLD",
          "createdAt": "2024-01-10T10:00:00Z",
          "profile": "maxG3D",
          "serialDisplay": "1CGBF2531C0230"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ProtocolHistoryStore.Entry.self, from: json)
        XCTAssertFalse(entry.isArchived)
    }

    func testEntryRoundTripsArchivedFlag() throws {
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-ARC",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            profile: .maxG3D,
            serialDisplay: "1EFHE2515C0440",
            wasVerifiedAsScooter: true,
            isArchived: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProtocolHistoryStore.Entry.self, from: data)
        XCTAssertTrue(decoded.isArchived)
        XCTAssertEqual(decoded.protocolNumber, "SC-ARC")
        XCTAssertEqual(decoded.serialDisplay, "1EFHE2515C0440")
    }
}
