import XCTest
@testable import ScooterCheck

final class FAQCatalogTests: XCTestCase {
    func testRequiredCategoriesPresent() {
        let ids = Set(FAQCatalog.categories.map(\.id))
        for needed in [
            "verstehen", "grundlagen", "finden", "pedelec", "tuning", "auslesen",
            "register", "bewertungen", "grenzen", "haeufige",
        ] {
            XCTAssertTrue(ids.contains(needed), "missing category \(needed)")
        }
        let order = FAQCatalog.categories.map(\.id)
        guard let grundlagen = order.firstIndex(of: "grundlagen"),
              let finden = order.firstIndex(of: "finden"),
              let pedelec = order.firstIndex(of: "pedelec") else {
            return XCTFail("grundlagen/finden/pedelec missing")
        }
        XCTAssertEqual(finden, grundlagen + 1)
        XCTAssertEqual(pedelec, finden + 1)
    }

    func testPedelecSearchHits() {
        for query in ["Pedelec", "Pedelec auslesen", "eBike", "Bosch", "Ghost", "RIOT", "Kiox", "Performance Line CX", "GATT"] {
            let hits = FAQCatalog.filtered(query: query)
            XCTAssertFalse(hits.isEmpty, "no hits for \(query)")
            XCTAssertTrue(
                hits.contains(where: { $0.id == "pedelec" }),
                "pedelec category missing for \(query)"
            )
        }
        let pedelec = FAQCatalog.categories.first { $0.id == "pedelec" }
        XCTAssertEqual(pedelec?.title, "Pedelec auslesen")
        XCTAssertEqual(pedelec?.symbolName, "bicycle")
        let ids = Set(pedelec?.items.map(\.id) ?? [])
        for needed in ["pedelec-was", "pedelec-tuning", "pedelec-ghost"] {
            XCTAssertTrue(ids.contains(needed), "missing \(needed)")
        }
    }

    func testScooterFindenSearchHits() {
        for query in [
            "E-Scooter finden", "Scooter finden", "finden", "Suche", "Ortung", "Standort", "Entfernung",
            "Signal", "RSSI", "Radar", "Signal-Finder", "Geräte-Wächter", "Wächter",
            "Gerät aufspüren", "Heatmap", "Live", "Shelly", "auslesen", "E-Scooter auslesen",
            "Scooter suchen", "Alle BLE", "nicht gefunden",
        ] {
            let hits = FAQCatalog.filtered(query: query)
            XCTAssertFalse(hits.isEmpty, "no hits for \(query)")
            XCTAssertTrue(
                hits.contains(where: { $0.id == "finden" }),
                "finden category missing for \(query)"
            )
        }
        let finden = FAQCatalog.categories.first { $0.id == "finden" }
        XCTAssertGreaterThanOrEqual(finden?.items.count ?? 0, 9)
        XCTAssertEqual(finden?.symbolName, "magnifyingglass")
        let ids = Set(finden?.items.map(\.id) ?? [])
        for needed in [
            "finden-was", "finden-radar",
            "finden-waechter", "finden-signal-finder",
            "finden-geraeteaktionen",
        ] {
            XCTAssertTrue(ids.contains(needed), "missing \(needed)")
        }
        XCTAssertFalse(ids.contains("finden-geraetesuche"))
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

    func testSearchFindsEinstellungenAndSchriftgroesse() {
        for query in ["Einstellungen", "Schriftgröße", "Schriftgroesse", "Menü"] {
            let hits = FAQCatalog.filtered(query: query)
            XCTAssertFalse(hits.isEmpty, "no hits for \(query)")
        }
        let ids = Set(FAQCatalog.categories.flatMap(\.items).map(\.id))
        XCTAssertTrue(ids.contains("menue"))
        XCTAssertTrue(ids.contains("einstellungen-schrift"))
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
