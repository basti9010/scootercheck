import XCTest
@testable import ScootProof

final class ControlAssessmentTests: XCTestCase {

    func testIncompleteWithoutLimitIsNeverTypkonform() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            peakSpeedKmh: 18,
            fwMcu: "1.0.0",
            rawRegisters: [
                RawRegister(address: "4-01", index: 1, name: "g3_ble_fw", valueHex: "3E00")
            ]
        )
        let control = ControlAssessmentEngine.assess(
            reading: reading,
            profile: .maxG3D,
            technicalVerdict: .stock
        )
        XCTAssertEqual(control, .unvollstaendig)
    }

    func testEmptyRegistersIncompleteEvenWithLimitClaim() {
        // Limit gesetzt in Reading, aber keine Rohregister → unvollständig.
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 18,
            rawRegisters: []
        )
        let control = ControlAssessmentEngine.assess(
            reading: reading,
            profile: .maxG3D,
            technicalVerdict: .stock
        )
        XCTAssertEqual(control, .unvollstaendig)
    }

    func testStockLimitIsTypkonform() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0",
            rawRegisters: [
                RawRegister(address: "22-46", index: 70, name: "vcu_g3_maxspd", valueHex: "1400")
            ]
        )
        let control = ControlAssessmentEngine.assess(
            reading: reading,
            profile: .maxG3D,
            technicalVerdict: .stock
        )
        XCTAssertEqual(control, .typkonform)
    }

    func testElevatedLimitIsAuffaellig() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 45,
            peakSpeedKmh: 40,
            rawRegisters: [
                RawRegister(address: "22-46", index: 70, name: "vcu_g3_maxspd", valueHex: "2D00")
            ]
        )
        let control = ControlAssessmentEngine.assess(
            reading: reading,
            profile: .maxG3D,
            technicalVerdict: .eindeutig
        )
        XCTAssertEqual(control, .auffaellig)
    }

    func testForeignBleForcesAuffaelligEvenIfStockVerdict() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 18,
            rawRegisters: [
                RawRegister(address: "22-46", index: 70, name: "vcu_g3_maxspd", valueHex: "1400")
            ],
            foreignBleCandidates: [
                ForeignBleSighting(name: "VESC-1234", rssi: -45, reason: "test")
            ]
        )
        let control = ControlAssessmentEngine.assess(
            reading: reading,
            profile: .maxG3D,
            technicalVerdict: .stock
        )
        XCTAssertEqual(control, .auffaellig)
    }

    func testTvAndHeadphonesAreNotForeignDriveBle() {
        XCTAssertFalse(ForeignBleDetector.looksLikeForeignDriveBle(name: "LG OLED TV"))
        XCTAssertFalse(ForeignBleDetector.looksLikeForeignDriveBle(name: "AirPods Pro"))
        XCTAssertFalse(ForeignBleDetector.looksLikeForeignDriveBle(name: "Samsung TV"))
        XCTAssertFalse(ForeignBleDetector.looksLikeForeignDriveBle(name: "1CGBF2531C0230"))
        XCTAssertTrue(ForeignBleDetector.looksLikeForeignDriveBle(name: "VESC-BLE"))
        XCTAssertTrue(ForeignBleDetector.looksLikeForeignDriveBle(name: "Makerbase"))
    }

    func testWeakRssiForeignBleIgnored() {
        let sightings = ForeignBleDetector.sightings(
            from: [
                (name: "VESC-FarAway", rssi: -85, looksLikeScooter: false),
                (name: "VESC-Near", rssi: -48, looksLikeScooter: false),
                (name: "LG TV", rssi: -40, looksLikeScooter: false),
            ]
        )
        XCTAssertEqual(sightings.map(\.name), ["VESC-Near"])
    }

    func testAnalyzerExposesControlAssessment() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 17,
            fwMcu: "1.0.0",
            rawRegisters: [
                RawRegister(address: "22-46", index: 70, name: "vcu_g3_maxspd", valueHex: "1400")
            ]
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        XCTAssertEqual(result.controlAssessment, .typkonform)
        XCTAssertTrue(result.facts.contains { $0.id == "control.assessment" })
    }

    func testSparseStockReadingIsIncompleteInAnalyzer() {
        let reading = IntegrityReading(serialDisplay: "1CGCF2551C3388")
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3US)
        XCTAssertEqual(result.controlAssessment, .unvollstaendig)
        // Technisches Urteil darf stock sein — die Ampel nicht.
        XCTAssertEqual(result.verdict, .stock)
    }
}
