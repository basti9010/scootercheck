import XCTest
@testable import ScooterCheck

final class StockFirmwareCatalogRemoteTests: XCTestCase {

    override func tearDown() {
        StockFirmwareCatalogRemote.installForTesting(nil)
        super.tearDown()
    }

    func testMergeRemoteExtendsBundled() {
        let bundled = StockFirmwareCatalog.maxG3
        let remote = StockFirmwareCatalog.Entry(
            mcu: ["9.9.9"],
            vcu: [],
            ble: [],
            bms: []
        )
        let merged = StockFirmwareCatalog.merge(bundled: bundled, remote: remote)
        XCTAssertNotNil(merged)
        XCTAssertTrue(merged!.mcu.contains("1.4.12"))
        XCTAssertTrue(merged!.mcu.contains("9.9.9"))
    }

    func testRemoteOnlyFamilyCreatesCatalog() {
        let remote = StockFirmwareCatalogRemote.Payload(
            schemaVersion: 1,
            updatedAt: "2026-10-16",
            sourceNote: "test",
            families: [
                "ninebotF3": .init(
                    mcu: ["2.0.0"],
                    vcu: ["2.1.0"],
                    ble: ["1.0.0"],
                    bms: ["1.0.0"]
                )
            ]
        )
        StockFirmwareCatalogRemote.installForTesting(
            .init(payload: remote, fetchedAt: Date(), sourceURL: "test://local")
        )
        let entry = StockFirmwareCatalog.entry(for: .ninebotF3D)
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.mcu.contains("2.0.0"))
        XCTAssertTrue(StockFirmwareCatalog.provenanceLabel.contains("Online"))
    }

    func testBundledWithoutRemoteStaysBundledLabel() {
        StockFirmwareCatalogRemote.installForTesting(nil)
        XCTAssertEqual(StockFirmwareCatalog.provenanceLabel, "Bundled")
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG3D))
    }
}
