import XCTest
@testable import ScooterCheck

final class BleModelHintTests: XCTestCase {

    func testMaxG3From1CGB() {
        let hint = BleModelHint.recognize(bleName: "1CGBF2531C0230")
        XCTAssertEqual(hint?.profile, .maxG3D)
        XCTAssertEqual(hint?.shortBadge, "Max G3")
    }

    func testMaxG3USFrom1CGC() throws {
        let hint = BleModelHint.recognize(bleName: "1CGCF2551C3388")
        XCTAssertEqual(hint?.profile, .maxG3US)
        XCTAssertEqual(hint?.shortBadge, "Max G3 US")
        XCTAssertEqual(hint?.profile.market, .us37)
        XCTAssertEqual(try XCTUnwrap(hint?.profile.ratedMaxKmh), 37, accuracy: 0.1)
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
        XCTAssertEqual(hint?.profile, .ninebotF3D)
        XCTAssertEqual(hint?.shortBadge, "F3 Pro")
    }

    func testF3ProFrom1EFHSerial() {
        let hint = BleModelHint.recognize(bleName: nil, serial: "1EFHE2515C0440")
        XCTAssertEqual(hint?.profile, .ninebotF3D)
        XCTAssertEqual(hint?.shortBadge, "F3 Pro")
        XCTAssertTrue(hint?.profile.usesG3RegisterMap == true)
    }

    func testF3ProFrom1EFCVcuSerial() {
        let hint = BleModelHint.recognize(bleName: "1EFCE2515C0440")
        XCTAssertEqual(hint?.profile.family, .ninebotF3)
        XCTAssertEqual(hint?.profile, .ninebotF3D)
    }

    func testF3ProNotConfusedWithMaxG3_1C() {
        let g3 = BleModelHint.recognize(bleName: "1CGBF2531C0230")
        XCTAssertEqual(g3?.profile.family, .maxG3)
        let f3 = BleModelHint.recognize(bleName: "1EFHE2515C0440")
        XCTAssertEqual(f3?.profile.family, .ninebotF3)
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

    func testXiaomiElectricScooter6FromMiHomeId() {
        let hint = BleModelHint.recognize(bleName: "xiaomi.scooter.6")
        XCTAssertEqual(hint?.profile.family, .xiaomiRecent)
        XCTAssertEqual(hint?.profile, .xiaomiRecentD)
        XCTAssertEqual(hint?.shortBadge, "Xiaomi 6")
        XCTAssertEqual(hint?.title, "Xiaomi Electric Scooter 6")
        XCTAssertTrue(BleClient.isLikelyScooterName("xiaomi.scooter.6"))
    }

    func testZT3NotConfusedWithESeries() {
        let hint = BleModelHint.recognize(bleName: "N2ET123456")
        XCTAssertEqual(hint?.profile.family, .zt3Pro)
    }

    func testZT3ProSerial1K1DNotMaxG3() {
        // Bericht SC-20261116-2AE360E1: SN 1K1DA2616P1917 wurde als Max G3 gelesen.
        let hint = BleModelHint.recognize(bleName: nil, serial: "1K1DA2616P1917")
        XCTAssertEqual(hint?.profile, .zt3ProD)
        XCTAssertEqual(hint?.shortBadge, "ZT3 Pro")
        // ZT3 Pro nutzt x3-VCU-Karte (Z07-MCU / VCU 0x16), nicht G30-Legacy.
        XCTAssertTrue(hint!.profile.usesG3RegisterMap)
        XCTAssertEqual(
            ScooterProfile.suggested(fromBluetoothName: nil, serial: "1K1DA2616P1917"),
            .zt3ProD
        )
        XCTAssertTrue(BleClient.isLikelyScooterName("1K1DA2616P1917"))
    }

    func testZT3ProSerial1K1EIsEuMarket() {
        let hint = BleModelHint.recognize(bleName: "1K1EA2616P1917")
        XCTAssertEqual(hint?.profile, .zt3ProE)
        XCTAssertTrue(hint!.profile.usesG3RegisterMap)
    }

    func testAllFamiliesHaveSupportNotes() {
        for family in ScooterFamily.allCases {
            XCTAssertFalse(family.supportNote.isEmpty)
        }
    }

    func testEnc2FamiliesUseLegacyOrG3Map() {
        XCTAssertTrue(ScooterProfile.maxG3D.usesG3RegisterMap)
        XCTAssertFalse(ScooterProfile.maxG2D.usesG3RegisterMap)
        XCTAssertTrue(ScooterProfile.ninebotF3D.usesG3RegisterMap)
        XCTAssertTrue(ScooterProfile.ninebotF3E.usesG3RegisterMap)
        XCTAssertTrue(ScooterProfile.gt3D.usesG3RegisterMap)
        XCTAssertTrue(ScooterProfile.zt3ProD.usesG3RegisterMap)
        XCTAssertTrue(ScooterProfile.gt3E.usesNinebotEnc2)
        XCTAssertTrue(ScooterProfile.maxG2D.usesNinebotEnc2)
        XCTAssertFalse(ScooterProfile.xiaomiClassicD.usesNinebotEnc2)
    }

    func testGT3RecognitionBeforeGenericG3() {
        let hint = BleModelHint.recognize(bleName: "Segway GT3 Pro")
        XCTAssertEqual(hint?.profile.family, .gt3)
        XCTAssertEqual(hint?.shortBadge, "GT3")
        XCTAssertEqual(hint?.profile, .gt3D)
        XCTAssertTrue(hint?.profile.usesG3RegisterMap == true)
        XCTAssertEqual(hint?.profile.stockMaxGear, 3)
    }

    func testGT3SuperScooterAndPartNumber() {
        XCTAssertEqual(BleModelHint.recognize(bleName: "SuperScooter GT3")?.profile, .gt3D)
        XCTAssertEqual(BleModelHint.recognize(bleName: "NBW84D004D0D")?.profile.family, .gt3)
        let eu = BleModelHint.recognize(bleName: "Segway GT3 25km")
        XCTAssertEqual(eu?.profile, .gt3E)
    }

    func testGT3NotConfusedWithMaxG3() {
        let g3 = BleModelHint.recognize(bleName: "1CGBF2531C0230")
        XCTAssertEqual(g3?.profile.family, .maxG3)
        let gt3 = BleModelHint.recognize(bleName: "GT3")
        XCTAssertEqual(gt3?.profile.family, .gt3)
    }

    func testLikelyScooterNameIncludesGT3NaveeSoFlow() {
        XCTAssertTrue(BleClient.isLikelyScooterName("Segway GT3 Pro"))
        XCTAssertTrue(BleClient.isLikelyScooterName("Navee XT5"))
        XCTAssertTrue(BleClient.isLikelyScooterName("SoFlow SO4 Pro"))
    }

    func testStockCatalogCoverage() {
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG3D))
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG30D))
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .maxG2D))
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .zt3ProD))
        XCTAssertNotNil(StockFirmwareCatalog.entry(for: .ninebotF3D))
        XCTAssertNil(StockFirmwareCatalog.entry(for: .ninebotED))
        XCTAssertNil(StockFirmwareCatalog.entry(for: .gt3D))
    }

    func testZT3ProStockGearAndCatalog() throws {
        XCTAssertEqual(ScooterProfile.zt3ProD.stockMaxGear, 3)
        XCTAssertEqual(ScooterProfile.zt3ProE.stockMaxGear, 3)
        let entry = try XCTUnwrap(StockFirmwareCatalog.entry(for: .zt3ProD))
        // Beobachtete DE-Serienauslese (1K1D…): MCU 1.5.2 / VCU 1.5.5 / BLE 2.1.13 / BMS 4.1.6.8
        XCTAssertTrue(entry.mcu.contains("1.5.2"))
        XCTAssertTrue(entry.vcu.contains("1.5.5"))
        XCTAssertTrue(entry.ble.contains("2.1.13"))
        XCTAssertTrue(entry.bms.contains("4.1.6.8"))
        XCTAssertEqual(StockFirmwareCatalog.classify("1.5.5", in: entry.vcu), .listedStock)
        XCTAssertEqual(StockFirmwareCatalog.classify("2.1.13", in: entry.ble), .listedStock)
    }

    func testF3ProStockGearAndCatalog() throws {
        XCTAssertEqual(ScooterProfile.ninebotF3D.stockMaxGear, 3)
        XCTAssertEqual(ScooterProfile.maxG3D.stockMaxGear, 1)
        let entry = try XCTUnwrap(StockFirmwareCatalog.entry(for: .ninebotF3D))
        XCTAssertTrue(entry.ble.contains("0.4.5"))
        XCTAssertTrue(entry.mcu.contains("2.4.0"))
        XCTAssertTrue(entry.vcu.contains("1.6.1"))
        XCTAssertFalse(entry.vcu.contains("97.1.87.1"))
    }

    func testF3ProDisplayAndVcuSerialsMatch() {
        XCTAssertFalse(TrackClassifier.serialsMismatch("1EFHE2515C0440", "1EFCE2515C0440"))
        XCTAssertTrue(TrackClassifier.sameEnc2VehicleBody("1EFHE2515C0440", "1EFCE2515C0440"))
        // 1EFH / 1EFC = Global 35 (nicht DE — DE wäre 1EFJ / 1EFD)
        XCTAssertEqual(TrackClassifier.serialRegion(for: "1EFHE2515C0440"), .us)
        XCTAssertEqual(TrackClassifier.serialRegion(for: "1EFCE2515C0440"), .us)
    }

    func testZT3ProSerialRegion1K1() {
        XCTAssertEqual(TrackClassifier.serialRegion(for: "1K1DA2616P1917"), .de)
        XCTAssertEqual(TrackClassifier.serialRegion(for: "1K1EA2616P1917"), .eu)
    }

    func testF3RegionPrefixesMatchSHU() {
        let global = TrackClassifier.resolveRegionProfile(for: "1EFHE2515C0440")
        XCTAssertEqual(global?.region, .us)
        XCTAssertEqual(global?.marketName, "Global")
        XCTAssertEqual(global?.ratedLimitKmh, 35)
        XCTAssertEqual(global?.shuStyleLabel, "F3 Pro Global (35 km/h)")

        let vcuGlobal = TrackClassifier.resolveRegionProfile(for: "1EFCE2515C0440")
        XCTAssertEqual(vcuGlobal?.shuStyleLabel, "F3 Global (35 km/h)")

        let de = TrackClassifier.resolveRegionProfile(for: "1EFJE2515C0440")
        XCTAssertEqual(de?.region, .de)
        XCTAssertEqual(de?.shuStyleLabel, "F3 Pro DE (22 km/h)")

        let eu = TrackClassifier.resolveRegionProfile(for: "1EFKE2515C0440")
        XCTAssertEqual(eu?.region, .eu)
        XCTAssertEqual(eu?.shuStyleLabel, "F3 Pro EU (25 km/h)")

        let reading = IntegrityReading(
            serialDisplay: "1EFHE2515C0440",
            serialVcu: "1EFCE2515C0440"
        )
        // Fahrzeug-/DIS-SN hat Vorrang vor VCU-Board-SN
        XCTAssertEqual(
            TrackClassifier.resolveRegionProfile(for: reading)?.shuStyleLabel,
            "F3 Pro Global (35 km/h)"
        )
    }

    func testF3GlobalOnDEProfileFlaggedAsRegionUnlock() {
        let reading = IntegrityReading(
            serialDisplay: "1EFHE2515C0440",
            serialVcu: "1EFCE2515C0440",
            speedMaxKmh: 22,
            speedLimitKmh: 22,
            fwMcu: "1.5.7",
            fwBle: "0.4.5",
            fwVcu: "1.6.1"
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .ninebotF3D)
        let region = result.facts.first { $0.id == "serial.region" }
        XCTAssertEqual(region?.status, .erheblichAbweichend, region?.bewertung ?? "")
        XCTAssertTrue((region?.auslesewert ?? "").contains("Global"))
        XCTAssertTrue((region?.auslesewert ?? "").contains("35"))

        let evidence = EvidenceEngine.evaluate(reading: reading, profile: .ninebotF3D)
        XCTAssertTrue(evidence.results.contains { $0.fact.markerID == "region.sn" })
    }

    func testF3DEStockRegionNotFlagged() {
        let reading = IntegrityReading(
            serialDisplay: "1EFJE2515C0440",
            serialVcu: "1EFDE2515C0440",
            speedMaxKmh: 22,
            speedLimitKmh: 22
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .ninebotF3D)
        let region = result.facts.first { $0.id == "serial.region" }
        XCTAssertEqual(region?.status, .regelkonform, region?.bewertung ?? "")
        XCTAssertTrue((region?.auslesewert ?? "").contains("DE"))
        let evidence = EvidenceEngine.evaluate(reading: reading, profile: .ninebotF3D)
        XCTAssertFalse(evidence.results.contains { $0.fact.markerID == "region.sn" })
    }

    func testF3ProGear3NotFlaggedAsUnlock() {
        let reading = IntegrityReading(
            serialDisplay: "1EFHE2515C0440",
            serialVcu: "1EFCE2515C0440",
            speedMaxKmh: 20,
            speedLimitKmh: 20,
            peakSpeedKmh: 19,
            fwMcu: "2.4.0",
            fwBle: "0.4.5",
            fwBms: "4.1.6.8",
            fwVcu: "1.6.1",
            gearMax: 3
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .ninebotF3D)
        let gear = result.facts.first { $0.id == "gear.max" }
        XCTAssertEqual(gear?.status, .regelkonform, gear?.bewertung ?? "")
        let evidence = EvidenceEngine.evaluate(reading: reading, profile: .ninebotF3D)
        XCTAssertFalse(evidence.results.contains { $0.fact.markerID == "gear.max" })
        XCTAssertFalse(evidence.results.contains { $0.fact.markerID == "fw.unknown" })
        XCTAssertTrue(evidence.crossBoardIssues.isEmpty, "\(evidence.crossBoardIssues)")
    }

    func testF3ProElevatedLimitStillAuffaellig() {
        let reading = IntegrityReading(
            serialDisplay: "1EFHE2515C0440",
            speedLimitKmh: 35,
            peakSpeedKmh: 45,
            fwMcu: "2.4.0",
            fwBle: "0.4.5",
            fwVcu: "1.6.1",
            gearMax: 3
        )
        let evidence = EvidenceEngine.evaluate(reading: reading, profile: .ninebotF3D)
        XCTAssertTrue(evidence.results.contains { $0.fact.markerID == "speed.limit" })
        XCTAssertFalse(evidence.results.contains { $0.fact.markerID == "gear.max" })
    }

    func testLikelyScooterNames() {
        XCTAssertTrue(BleClient.isLikelyScooterName("Max G2"))
        XCTAssertTrue(BleClient.isLikelyScooterName("Ninebot E45"))
        XCTAssertTrue(BleClient.isLikelyScooterName("F3 Pro"))
        XCTAssertTrue(BleClient.isLikelyScooterName("1EFHE2515C0440"))
        XCTAssertFalse(BleClient.isLikelyScooterName("Nuki Smart Lock"))
        XCTAssertFalse(BleClient.isLikelyScooterName("Shelly2PMG3-28372F3CFA5C"))
    }

    func testShellyHexF3IsNotNinebotF3() {
        let hint = BleModelHint.recognize(bleName: "Shelly2PMG3-28372F3CFA5C")
        XCTAssertNil(hint)
        XCTAssertEqual(BleModelHint.recognize(bleName: "Ninebot F3")?.profile.family, .ninebotF3)
        XCTAssertEqual(BleModelHint.recognize(bleName: "F3 Pro")?.profile.family, .ninebotF3)
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

    func testG3DiagnosticFieldsPreferBleBeforeVcu() throws {
        let fields = DiagnosticMap.fields(for: .maxG3US)
        let ids = fields.map(\.id)
        let bleSN = try XCTUnwrap(ids.firstIndex(of: "ble_sn"))
        let vcuSN = try XCTUnwrap(ids.firstIndex(of: "vcu_g3_sn"))
        XCTAssertLessThan(bleSN, vcuSN)
        let bleFW = try XCTUnwrap(ids.firstIndex(of: "g3_ble_fw"))
        let speed = try XCTUnwrap(ids.firstIndex(of: "vcu_g3_speed"))
        XCTAssertLessThan(bleFW, speed)
    }

    func testF3ProUsesSameG3DiagnosticMap() {
        let f3 = DiagnosticMap.fields(for: .ninebotF3D).map(\.id)
        let g3 = DiagnosticMap.fields(for: .maxG3D).map(\.id)
        XCTAssertEqual(f3, g3)
        XCTAssertTrue(f3.contains("vcu_g3_maxspd"))
        // Trip-Peak nur DIS rSigMaxSpeed — nicht VCU 0x24 (kein rSigMaxSpeed auf x3-VCU).
        XCTAssertTrue(f3.contains("dis_trip_max"))
        XCTAssertFalse(f3.contains("vcu_g3_trip_max"))
    }

}
