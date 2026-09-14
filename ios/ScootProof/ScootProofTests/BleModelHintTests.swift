import XCTest
@testable import ScootProof

final class BleModelHintTests: XCTestCase {

    func testMaxG3From1CGB() {
        let hint = BleModelHint.recognize(bleName: "1CGBF2531C0230")
        XCTAssertEqual(hint?.profile, .maxG3D)
        XCTAssertEqual(hint?.shortBadge, "Max G3")
    }

    func testMaxG3USFrom1CGC() {
        let hint = BleModelHint.recognize(bleName: "1CGCF2551C3388")
        XCTAssertEqual(hint?.profile, .maxG3US)
        XCTAssertEqual(hint?.shortBadge, "Max G3 US")
        XCTAssertEqual(hint?.profile.market, .us37)
        XCTAssertEqual(hint?.profile.ratedMaxKmh, 37, accuracy: 0.1)
    }

    func testMaxG3From1CGE() {
        let hint = BleModelHint.recognize(bleName: "1CGEF2531C0230")
        XCTAssertEqual(hint?.profile, .maxG3E)
    }

    func testMaxG2Recognition() {
        let hint = BleModelHint.recognize(bleName: "Ninebot Max G2")
        XCTAssertEqual(hint?.profile.family, .maxG2)
    }

    func testF3BeforeGenericF() {
        let hint = BleModelHint.recognize(bleName: "Ninebot F3 Pro")
        XCTAssertEqual(hint?.profile.family, .ninebotF3)
    }

    func testF2Recognition() {
        let hint = BleModelHint.recognize(bleName: "Ninebot F2")
        XCTAssertEqual(hint?.profile.family, .ninebotF)
    }

    func testESeriesRecognition() {
        let hint = BleModelHint.recognize(bleName: "Ninebot E45")
        XCTAssertEqual(hint?.profile.family, .ninebotE)
    }

    func testDSeriesEU() {
        let hint = BleModelHint.recognize(bleName: "Ninebot D38 25km")
        XCTAssertEqual(hint?.profile, .ninebotDE)
    }

    func testXiaomiClassicEssential() {
        let hint = BleModelHint.recognize(bleName: "Mi Electric Scooter Essential")
        XCTAssertEqual(hint?.profile.family, .xiaomiClassic)
    }

    func testXiaomiRecent() {
        let hint = BleModelHint.recognize(bleName: "Xiaomi Scooter 4")
        XCTAssertEqual(hint?.profile.family, .xiaomiRecent)
    }

    func testZT3NotConfusedWithESeries() {
        let hint = BleModelHint.recognize(bleName: "N2ET123456")
        XCTAssertEqual(hint?.profile.family, .zt3Pro)
    }

    func testAllFamiliesHaveSupportNotes() {
        for family in ScooterFamily.allCases {
            XCTAssertFalse(family.supportNote.isEmpty)
        }
    }

    func testEnc2FamiliesUseLegacyOrG3Map() {
        XCTAssertTrue(ScooterProfile.maxG3D.usesG3RegisterMap)
        XCTAssertFalse(ScooterProfile.maxG2D.usesG3RegisterMap)
        XCTAssertFalse(ScooterProfile.ninebotF3D.usesG3RegisterMap)
        XCTAssertTrue(ScooterProfile.maxG2D.usesNinebotEnc2)
        XCTAssertFalse(ScooterProfile.xiaomiClassicD.usesNinebotEnc2)
    }

    func testStockCatalogCoverage() {
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG3D))
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG30D))
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG2D))
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .zt3ProD))
        XCTAssertNil(StockFirmwareCatalog.entry(for: .ninebotED))
    }

    func testLikelyScooterNames() {
        XCTAssertTrue(BleClient.isLikelyScooterName("Max G2"))
        XCTAssertTrue(BleClient.isLikelyScooterName("Ninebot E45"))
        XCTAssertTrue(BleClient.isLikelyScooterName("F3 Pro"))
        XCTAssertFalse(BleClient.isLikelyScooterName("Nuki Smart Lock"))
    }

    func testMaxG3USStockRegionNotFlaggedOnUSProfile() {
        let reading = IntegrityReading(serialDisplay: "1CGCF2551C3388")
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3US)
        let region = result.facts.first { $0.id == "serial.region" }
        XCTAssertNotNil(region)
        XCTAssertEqual(region?.status, .regelkonform, region?.bewertung ?? "")
        XCTAssertFalse((region?.bewertung ?? "").localizedCaseInsensitiveContains("unlock"))
        XCTAssertTrue((region?.bewertung ?? "").localizedCaseInsensitiveContains("passend")
            || (region?.bewertung ?? "").localizedCaseInsensitiveContains("US"))
    }

    func testMaxG3USCatalogAndG3Map() {
        XCTAssertTrue(ScooterProfile.maxG3US.usesG3RegisterMap)
        XCTAssertEqual(ScooterProfile.maxG3US.market, .us37)
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG3US))
        XCTAssertEqual(ScooterProfile.profiles(in: .maxG3).count, 3)
    }

    func testG3ReadLengthModesEncodePayloadDifferently() {
        let u8 = Nb.readRequest(
            board: .ble,
            register: Nb.G3Register.bleVersion,
            length: 2,
            mode: .u8
        )
        let u16 = Nb.readRequest(
            board: .ble,
            register: Nb.G3Register.bleVersion,
            length: 2,
            mode: .u16LE
        )
        // Frame: sync sync len src dst cmd index [payload…]
        XCTAssertEqual(u8[2], 1, "u8-Länge = 1 Payload-Byte")
        XCTAssertEqual(Array(u8.suffix(1)), [2])
        XCTAssertEqual(u16[2], 2, "u16-Länge = 2 Payload-Bytes")
        XCTAssertEqual(Array(u16.suffix(2)), [2, 0])
        XCTAssertEqual(Nb.read(board: .ble, register: 0x01, length: 2), u8)
        XCTAssertEqual(Nb.readU16Len(board: .ble, register: 0x01, length: 2), u16)
    }

    func testG3DiagnosticFieldsPreferBleBeforeVcu() {
        let fields = DiagnosticMap.fields(for: .maxG3US)
        let ids = fields.map(\.id)
        let bleSN = try XCTUnwrap(ids.firstIndex(of: "ble_sn"))
        let vcuSN = try XCTUnwrap(ids.firstIndex(of: "vcu_g3_sn"))
        XCTAssertLessThan(bleSN, vcuSN)
        let bleFW = try XCTUnwrap(ids.firstIndex(of: "g3_ble_fw"))
        let speed = try XCTUnwrap(ids.firstIndex(of: "vcu_g3_speed"))
        XCTAssertLessThan(bleFW, speed)
    }

}
