import XCTest
@testable import ScooterCheck

final class RescanDiffAndConfigTests: XCTestCase {

    func testTemporalDeltasIncludeZeroStartAndBleFw() {
        let prior = IntegrityReading(
            serialDisplay: "1EFJE2515C0001",
            speedLimitKmh: 22,
            peakSpeedKmh: 21,
            startSpeedKmh: 3,
            fwBle: "1.2.3",
            fwVcu: "1.0.0"
        )
        let current = IntegrityReading(
            serialDisplay: "1EFJE2515C0001",
            speedLimitKmh: 35,
            peakSpeedKmh: 34,
            startSpeedKmh: 0,
            fwBle: "1.2.4",
            fwVcu: "1.0.0"
        )
        let deltas = EvidenceEngine.temporalDeltas(
            current: current,
            prior: prior,
            priorProtocol: "SC-OLD"
        )
        XCTAssertTrue(deltas.contains { $0.id == "history.delta.limit" })
        XCTAssertTrue(deltas.contains { $0.id == "history.delta.peak" })
        XCTAssertTrue(deltas.contains { $0.id == "history.delta.zero.start" })
        XCTAssertTrue(deltas.contains { $0.id == "history.delta.fw.ble" })
        XCTAssertFalse(deltas.contains { $0.id == "history.delta.fw.vcu" })

        let zero = deltas.first { $0.id == "history.delta.zero.start" }
        XCTAssertEqual(zero?.previous, "3.0 km/h")
        XCTAssertEqual(zero?.current, "aktiv (0 km/h)")
    }

    func testZeroStartLabel() {
        XCTAssertEqual(EvidenceEngine.zeroStartLabel(0), "aktiv (0 km/h)")
        XCTAssertEqual(EvidenceEngine.zeroStartLabel(3), "3.0 km/h")
        XCTAssertNil(EvidenceEngine.zeroStartLabel(nil))
    }

    func testConfigFactsFromTypedFields() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBF2531C0230",
            startSpeedKmh: 0,
            gearLimitS: 3,
            gearLimitE: 2,
            gearLimitD: 1,
            configBoolHex: "0x0001",
            configFunHex: "0x00AA",
            configFun2Hex: "0x0000",
            configFun3Hex: "0x0000",
            configEncFlagHex: "0xFFFF"
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        XCTAssertTrue(result.facts.contains { $0.id == "config.zero.start" && $0.group == .config })
        XCTAssertTrue(result.facts.contains { $0.id == "config.gear.s" })
        XCTAssertTrue(result.facts.contains { $0.id == "config.fun" })
        XCTAssertEqual(result.facts.first { $0.id == "config.encflag" }?.status, .abweichend)
        XCTAssertEqual(result.facts.first { $0.id == "config.custom_key" }?.status, .nichtFeststellbar)
    }

    func testDiagnosticMapAppliesGearAndConfigFlags() {
        var reading = IntegrityReading()
        let sgear = DiagnosticMap.Spec(
            id: "vcu_g3_sgear",
            board: .vcuG3,
            register: Nb.G3Register.sGear,
            readLen: 2,
            category: .limit
        )
        DiagnosticMap.apply(spec: sgear, data: Data([0x04, 0x00]), into: &reading)
        XCTAssertEqual(reading.gearLimitS, 4)

        let enc = DiagnosticMap.Spec(
            id: "vcu_g3_encflag",
            board: .vcuG3,
            register: Nb.G3Register.encryptionFlag,
            readLen: 2,
            category: .status
        )
        DiagnosticMap.apply(spec: enc, data: Data([0xFF, 0xFF]), into: &reading)
        XCTAssertEqual(reading.configEncFlagHex, "0xFFFF")
        XCTAssertEqual(reading.fwAppCustom, true)
    }
}
