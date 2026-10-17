import XCTest
@testable import ScooterCheck

final class ScooterThumbnailAssetTests: XCTestCase {
    func testFamilyMapping() {
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .zt3Pro), "scooter_zt3pro")
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .maxG3), "scooter_max_g3")
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .maxG2), "scooter_max_g2")
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .ninebotF), ScooterThumbnailAsset.generic)
        XCTAssertEqual(ScooterThumbnailAsset.name(for: nil as ScooterFamily?), ScooterThumbnailAsset.generic)
    }

    func testProfileMapping() {
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .maxG3D), "scooter_max_g3")
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .zt3ProE), "scooter_zt3pro")
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .maxG2D), "scooter_max_g2")
        XCTAssertEqual(ScooterThumbnailAsset.name(for: .xiaomiClassicD), ScooterThumbnailAsset.generic)
    }

    func testLabelMapping() {
        XCTAssertEqual(
            ScooterThumbnailAsset.name(fromModelText: "Ninebot ZT3 Pro"),
            "scooter_zt3pro"
        )
        XCTAssertEqual(
            ScooterThumbnailAsset.name(fromModelText: "Ninebot Max G3 / MAX3"),
            "scooter_max_g3"
        )
        XCTAssertEqual(
            ScooterThumbnailAsset.name(fromModelText: "Ninebot Max G2"),
            "scooter_max_g2"
        )
        XCTAssertEqual(
            ScooterThumbnailAsset.name(fromModelText: "Unknown Scooter"),
            ScooterThumbnailAsset.generic
        )
    }

    func testCombinedResolverPrefersProfile() {
        XCTAssertEqual(
            ScooterThumbnailAsset.name(
                profile: .maxG3D,
                modelLabel: "Ninebot ZT3 Pro"
            ),
            "scooter_max_g3"
        )
    }
}
