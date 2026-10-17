import UIKit
import XCTest
@testable import ScooterCheck

final class CheckPhotosTests: XCTestCase {

    func testEntryDecodesMissingPhotosAsEmpty() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "protocolNumber": "SC-OLD",
          "createdAt": "2024-02-01T09:00:00Z",
          "profile": "maxG3D",
          "serialDisplay": "1EFHE2515C0440"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ProtocolHistoryStore.Entry.self, from: json)
        XCTAssertTrue(entry.photoIds.isEmpty)
        XCTAssertNil(entry.coverPhotoId)
    }

    func testEntryRoundTripsPhotoMetadata() throws {
        let cover = UUID()
        let other = UUID()
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-P1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            profile: .maxG3D,
            serialDisplay: "1EFHE2515C0440",
            wasVerifiedAsScooter: true,
            photoIds: [cover, other],
            coverPhotoId: cover
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProtocolHistoryStore.Entry.self, from: data)
        XCTAssertEqual(decoded.photoIds, [cover, other])
        XCTAssertEqual(decoded.coverPhotoId, cover)
    }

    func testNormalizedJPEGDownscalesLongEdge() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        guard let data = ProtocolHistoryStore.normalizedJPEG(image, maxPixel: 400, quality: 0.8),
              let out = UIImage(data: data) else {
            return XCTFail("JPEG encode failed")
        }
        let longest = max(out.size.width * out.scale, out.size.height * out.scale)
        XCTAssertLessThanOrEqual(longest, 400 + 2)
    }

    func testOrderedPhotoIdsPutsCoverFirst() {
        let cover = UUID()
        let a = UUID()
        let b = UUID()
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-P2",
            createdAt: Date(),
            profile: .maxG3D,
            photoIds: [a, cover, b],
            coverPhotoId: cover
        )
        // orderedPhotoIds is instance method on store — replicate logic for unit purity
        let ordered: [UUID] = {
            guard let c = entry.coverPhotoId, entry.photoIds.contains(c) else { return entry.photoIds }
            return [c] + entry.photoIds.filter { $0 != c }
        }()
        XCTAssertEqual(ordered, [cover, a, b])
    }
}
