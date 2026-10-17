import XCTest
@testable import ScooterCheck

final class FAQCatalogTests: XCTestCase {
    func testRequiredCategoriesPresent() {
        let ids = Set(FAQCatalog.categories.map(\.id))
        for needed in [
            "verstehen", "grundlagen", "tuning", "auslesen",
            "register", "bewertungen", "grenzen", "haeufige",
        ] {
            XCTAssertTrue(ids.contains(needed), "missing category \(needed)")
        }
    }

    func testItemsHaveContent() {
        for category in FAQCatalog.categories {
            XCTAssertFalse(category.items.isEmpty, category.id)
            for item in category.items {
                XCTAssertFalse(item.question.isEmpty)
                XCTAssertFalse(item.segments.isEmpty, item.id)
            }
        }
    }

    func testSearchFindsSoftUnlock() {
        let hits = FAQCatalog.filtered(query: "Soft Unlock")
        XCTAssertFalse(hits.isEmpty)
        let questions = hits.flatMap(\.items).map(\.question)
        XCTAssertTrue(questions.contains(where: { $0.localizedCaseInsensitiveContains("Soft Unlock") }))
    }

    func testSearchEmptyReturnsAll() {
        XCTAssertEqual(
            FAQCatalog.filtered(query: "   ").count,
            FAQCatalog.categories.count
        )
    }

    func testSoftUnlockSettingsStillAvailable() {
        // Detection-/Settings-Modell bleibt; nur der Menüpunkt wurde entfernt.
        XCTAssertTrue(SoftUnlockSettings.isEnabledSnapshot())
        XCTAssertGreaterThan(SoftUnlockSettings.thresholdKmhSnapshot(), 0)
    }
}
