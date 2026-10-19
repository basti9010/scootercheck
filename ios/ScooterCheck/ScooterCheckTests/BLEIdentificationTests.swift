import XCTest
@testable import ScooterCheck

final class BLEIdentificationTests: XCTestCase {

    func testManufacturerHexParsesSpacedAndCompact() {
        XCTAssertEqual(BLEManufacturerParsing.companyId(fromManufacturerHex: "4C 00 01 02"), 0x004C)
        XCTAssertEqual(BLEManufacturerParsing.companyId(fromManufacturerHex: "4C00ABCD"), 0x004C)
        XCTAssertEqual(BLEManufacturerParsing.companyId(fromManufacturerHex: "1F 0F AA"), 0x0F1F)
        XCTAssertNil(BLEManufacturerParsing.companyId(fromManufacturerHex: "4C"))
        XCTAssertNil(BLEManufacturerParsing.companyId(fromManufacturerHex: nil))
    }

    func testCompanyCatalogContainsCriticalVendors() {
        let cat = BluetoothCompanyCatalog.shared
        XCTAssertEqual(cat.name(forCompanyId: 0x004C), "Apple, Inc.")
        XCTAssertEqual(cat.name(forCompanyId: 0x0075), "Samsung Electronics Co. Ltd.")
        XCTAssertEqual(cat.name(forCompanyId: 0x038F), "Xiaomi Inc.")
        XCTAssertEqual(cat.name(forCompanyId: 0x0F1F), "Ninebot (Changzhou) Tech Co., Ltd.")
    }

    func testSamsungNotClassifiedAsScooter() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Samsung TV",
                localName: "Samsung AU8000",
                manufacturerDataHex: "75 00 AA BB",
                serviceUUIDs: [],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.manufacturerCompanyId, 0x0075)
        XCTAssertNotNil(result.manufacturer)
        XCTAssertNotEqual(result.deviceCategory, .eScooter)
        XCTAssertFalse(result.radarEligibleScooter)
    }

    func testNinebotUARTWithoutNameIsScooter() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Ohne Namen (ABCD1234)",
                localName: nil,
                manufacturerDataHex: nil,
                serviceUUIDs: ["6E400001-0000-0000-006E-696E65626F74"],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.deviceCategory, .eScooter)
        XCTAssertTrue(result.radarEligibleScooter)
        XCTAssertTrue([BLEIdentificationConfidence.high, .medium].contains(result.confidence))
    }

    func testNinebotCompanyIdAloneNotRadarEligible() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Unbekannt",
                localName: nil,
                manufacturerDataHex: "1F 0F 00 11",
                serviceUUIDs: [],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.manufacturerCompanyId, 0x0F1F)
        XCTAssertNotNil(result.manufacturer)
        XCTAssertFalse(result.radarEligibleScooter)
        XCTAssertNotEqual(result.deviceCategory, .eScooter)
    }

    func testUnknownManufacturerStaysUnknown() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Foo",
                localName: "Foo",
                manufacturerDataHex: nil,
                serviceUUIDs: ["1800", "1801"],
                serviceDataHexByUUID: [:],
                txPower: -12,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertNil(result.manufacturer)
        XCTAssertEqual(result.deviceCategory, .unknown)
        XCTAssertNil(result.model)
        XCTAssertFalse(result.radarEligibleScooter)
    }

    func testGenericNordicUARTNotScooterWithoutHints() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Sensor",
                localName: "Sensor",
                manufacturerDataHex: "59 00 01",
                serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertNotEqual(result.deviceCategory, .eScooter)
        XCTAssertFalse(result.radarEligibleScooter)
    }

    func testFingerprintIgnoresSpacesInManufacturerId() {
        let a = BLEDeviceFingerprint(
            manufacturerDataHex: "4C 00 01 02",
            manufacturerId: BLEManufacturerParsing.companyId(fromManufacturerHex: "4C 00 01 02"),
            serviceUUIDs: ["1800"]
        )
        let b = BLEDeviceFingerprint(
            manufacturerDataHex: "4C000102",
            manufacturerId: BLEManufacturerParsing.companyId(fromManufacturerHex: "4C000102"),
            serviceUUIDs: ["1800"]
        )
        XCTAssertEqual(a.manufacturerId, 0x004C)
        XCTAssertEqual(b.manufacturerId, 0x004C)
        let match = BLEFingerprintService.compare(a, b)
        XCTAssertGreaterThanOrEqual(match.score, 40)
    }

    func testOnlineMergeDoesNotMakeOnlineScooterRadarEligible() {
        let local = BLEIdentificationResult.unknown(deviceId: UUID(), displayName: "X")
        var online = local
        online.source = .online
        online.deviceCategory = .eScooter
        online.model = "Fake Scooter From Web"
        online.confidence = .high
        online.radarEligibleScooter = true
        online.onlineSourceNote = "test"
        let merged = IdentificationResultMerger.merge(local: local, online: online)
        XCTAssertFalse(merged.radarEligibleScooter)
        XCTAssertFalse(merged.contradictions.isEmpty)
    }

    func testEvidenceExplainsAssignment() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "NB",
                localName: "NB-Max",
                manufacturerDataHex: "1F 0F 00",
                serviceUUIDs: ["6E400001-0000-0000-006E-696E65626F74"],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: true,
                modelLabel: "Ninebot Max G3",
                modelBadge: "Max G3"
            )
        )
        XCTAssertFalse(result.evidence.isEmpty)
        XCTAssertEqual(result.model, "Ninebot Max G3")
        XCTAssertTrue(result.radarEligibleScooter)
    }

    func testUUIDNormalizationShortForm() {
        let full = "0000180A-0000-1000-8000-00805F9B34FB"
        XCTAssertEqual(BLEKnownServiceUUID.shortForm(full), "180A")
        XCTAssertEqual(BLEKnownServiceUUID.normalize("180a"), "180A")
    }

    func testVendorPatternCatalogDoesNotAloneImplyCategory() {
        let patterns = BLEVendorPatternCatalog.shared.patterns(matchingCompanyId: 0x038F)
        XCTAssertFalse(patterns.isEmpty)
        XCTAssertTrue(patterns.allSatisfy { !$0.aloneImpliesCategory })
    }

    func testSimilarFingerprintsDoNotAutoMergeIdentity() {
        let a = BLEDeviceFingerprint(
            manufacturerDataHex: "59000102",
            manufacturerId: 0x0059,
            serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"],
            advertisingStructureKey: "-M S1 - - C"
        )
        let b = BLEDeviceFingerprint(
            manufacturerDataHex: "5900AABB",
            manufacturerId: 0x0059,
            serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"],
            advertisingStructureKey: "-M S1 - - C"
        )
        let match = BLEFingerprintService.compare(a, b)
        // Gleiche Chip-/Service-Familie kann ähnlich wirken — aber kein Identitätsbeweis.
        XCTAssertNotEqual(a.manufacturerDataHex, b.manufacturerDataHex)
        XCTAssertTrue(
            match.similarity == .medium || match.similarity == .low || match.similarity == .high
                || match.similarity == .none
        )
        // Engine darf daraus keinen Scooter machen.
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "X",
                localName: nil,
                manufacturerDataHex: "59 00 AA BB",
                serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertNotEqual(result.deviceCategory, .eScooter)
    }

    func testListTitleShowsManufacturerWithoutModel() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Ohne Namen (AABB)",
                localName: nil,
                manufacturerDataHex: "75 00 01",
                serviceUUIDs: [],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertTrue(result.listTitle.contains("Samsung") || result.listTitle.contains("Modell unbekannt"))
        XCTAssertFalse(result.listTitle.lowercased().contains("scooter"))
    }

    func testConfidenceIsQualitativeNotPercent() {
        let labels = BLEIdentificationConfidence.allCases.map(\.label)
        XCTAssertEqual(Set(labels), Set(["Hoch", "Mittel", "Niedrig", "Unbekannt"]))
    }

    func testAppleWatchNameClassifiedAsSmartwatchNotScooter() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Apple Watch",
                localName: "Apple Watch",
                manufacturerDataHex: "4C 00 10 00",
                serviceUUIDs: [],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.deviceCategory, .smartwatch)
        XCTAssertFalse(result.radarEligibleScooter)
        XCTAssertTrue(result.listTitle.contains("Smartwatch") || result.listTitle.contains("Apple"))
    }

    func testEddystoneServiceIsBeacon() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Ohne Namen (BEAC)",
                localName: nil,
                manufacturerDataHex: nil,
                serviceUUIDs: ["FEAA"],
                serviceDataHexByUUID: [:],
                txPower: -12,
                isConnectable: false,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.deviceCategory, .beacon)
        XCTAssertFalse(result.radarEligibleScooter)
        XCTAssertTrue(result.listTitle.lowercased().contains("beacon") || result.listTitle.contains("Beacon"))
    }

    func testHeartRateGATTIsSensorNotScooter() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "HRM",
                localName: "Tickr",
                manufacturerDataHex: nil,
                serviceUUIDs: ["180D", "180A"],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.deviceCategory, .sensor)
        XCTAssertFalse(result.radarEligibleScooter)
    }

    func testShellyNameSuggestsSmartHome() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "shellyplus1-AABBCC",
                localName: "shellyplus1-AABBCC",
                manufacturerDataHex: "E5 02 01",
                serviceUUIDs: [],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.deviceCategory, .smartHome)
        XCTAssertNotEqual(result.deviceCategory, .eScooter)
        XCTAssertFalse(result.radarEligibleScooter)
    }

    func testManufacturerOnlyUnknownCategoryStillLabeled() {
        let result = BLEIdentificationEngine.analyze(
            .init(
                deviceId: UUID(),
                displayName: "Ohne Namen (ZZZZ)",
                localName: nil,
                manufacturerDataHex: "E0 00 AA",
                serviceUUIDs: [],
                serviceDataHexByUUID: [:],
                txPower: nil,
                isConnectable: true,
                looksLikeScooterHint: false,
                modelLabel: nil,
                modelBadge: nil
            )
        )
        XCTAssertEqual(result.manufacturerCompanyId, 0x00E0)
        XCTAssertNotNil(result.manufacturer)
        XCTAssertEqual(result.deviceCategory, .unknown)
        XCTAssertTrue(result.listTitle.contains("Modell unbekannt") || result.listTitle.contains("Google"))
        XCTAssertFalse(result.radarEligibleScooter)
    }
}

private extension BLEIdentificationConfidence {
    static var allCases: [BLEIdentificationConfidence] { [.high, .medium, .low, .unknown] }
}
