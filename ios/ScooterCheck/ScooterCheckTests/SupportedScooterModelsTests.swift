import XCTest
@testable import ScooterCheck

final class SupportedScooterModelsTests: XCTestCase {
    func testCatalogCoversUtilityModels() throws {
        let url = URL(fileURLWithPath: "/workspace/ios/ScooterCheck/ScooterCheck/supported_scooter_models.json")
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(SupportedScooterModelsFile.self, from: data)

        let titles = Set(file.brands.flatMap(\.models).map(\.title))
        for required in [
            "Ninebot Air T15", "Ninebot D18", "Ninebot D28", "Ninebot D38",
            "Ninebot E2/E2 Plus", "Ninebot E2x/E4x", "Ninebot E3/E3 Pro", "Ninebot ESx",
            "Ninebot F-series", "Ninebot F2", "Ninebot F3", "Ninebot F40 II",
            "Ninebot GT1", "Ninebot GT2", "Ninebot GT3",
            "Ninebot Max G2", "Ninebot Max G3", "Ninebot Max G30", "Ninebot Max G65",
            "Ninebot P100", "Ninebot P65", "Ninebot ZT3",
            "Mi Electric Scooter 1S", "Mi Electric Scooter 3", "Mi Electric Scooter Lite",
            "Mi Electric Scooter Pro", "Mi Electric Scooter Pro 2", "Xiaomi M365"
        ] {
            XCTAssertTrue(titles.contains(required), "Missing \(required)")
        }

        let all = file.brands.flatMap(\.models)
        XCTAssertEqual(all.filter(\.readable).count, all.count)
    }

    func testBleHintsForNewFamilies() {
        XCTAssertEqual(BleModelHint.recognize(bleName: "Segway GT1")?.profile.family, .gt1)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Segway GT2")?.profile.family, .gt2)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Ninebot P100S")?.profile.family, .p100)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Ninebot P65")?.profile.family, .p65)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Ninebot Max G65")?.profile.family, .maxG65)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Ninebot Air T15")?.profile.family, .airT15)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Ninebot ES2")?.profile.family, .esx)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Ninebot E3 Pro")?.profile.family, .ninebotE)
        XCTAssertTrue(BleClient.isLikelyScooterName("Ninebot P100"))
        XCTAssertTrue(BleClient.isLikelyScooterName("Segway GT1"))
    }

    func testStockCatalogHasLatestG3() {
        let entry = StockFirmwareCatalog.entry(for: .maxG3D)
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry?.mcu.contains("1.5.7") == true)
        XCTAssertTrue(entry?.vcu.contains("1.6.2") == true)
        XCTAssertTrue(entry?.ble.contains("0.4.5") == true)
    }
}
