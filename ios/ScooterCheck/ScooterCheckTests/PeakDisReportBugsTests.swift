import XCTest
@testable import ScooterCheck

/// Peak-/DIS-Decode und Analysebericht-Report-Bugs.
final class PeakDisReportBugsTests: XCTestCase {

    // MARK: - Peak / DIS decode

    func testTripPeakClassicTenths() throws {
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(250)), 25.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(450)), 45.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(327)), 32.7, accuracy: 0.01)
    }

    func testTripPeakG3PackedHighByte() throws {
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(0x2D00)), 45.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(0x1616)), 22.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(0x140F)), 20.0, accuracy: 0.01)
    }

    func testTripPeakWholeKmhNotMisreadAsTenths() throws {
        // Rohwert 25/45 = ganze km/h — nicht 2.5 / 4.5.
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(25)), 25.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(45)), 45.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RegisterScale.tripPeakKmh(20)), 20.0, accuracy: 0.01)
    }

    func testDisLimitDoesNotFillPeak() {
        var reading = IntegrityReading()
        let limit = DiagnosticMap.Spec(
            id: "dis_limit",
            board: .dis,
            register: Nb.Register.speedLimit,
            readLen: 2,
            category: .limit
        )
        // 25 km/h whole
        DiagnosticMap.apply(spec: limit, data: Data([25, 0]), into: &reading)
        XCTAssertEqual(reading.speedLimitKmh ?? -1, 25, accuracy: 0.01)
        XCTAssertNil(reading.peakSpeedKmh)
    }

    func testDisTripMaxFillsPeak() {
        var reading = IntegrityReading()
        let trip = DiagnosticMap.Spec(
            id: "dis_trip_max",
            board: .dis,
            register: Nb.Register.tripMaxSpeed,
            readLen: 2,
            category: .history
        )
        // 32.7 km/h as ×0.1
        DiagnosticMap.apply(spec: trip, data: Data([0x47, 0x01]), into: &reading) // 327 LE
        XCTAssertEqual(reading.peakSpeedKmh ?? -1, 32.7, accuracy: 0.01)
    }

    func testVcuG3Register24IsNotTripPeak() {
        // F3-Pro-Bericht SC-20261021-2C3CA01C: VCU 0x24 = 3543 → fälschlich 67 km/h.
        // Auf der G3-Karte gibt es kein VCU-rSigMaxSpeed — Peak darf daraus nicht entstehen.
        XCTAssertFalse(DiagnosticMap.fields(for: .maxG3D).map(\.id).contains("vcu_g3_trip_max"))
        XCTAssertFalse(DiagnosticMap.fields(for: .ninebotF3D).map(\.id).contains("vcu_g3_trip_max"))

        var reading = IntegrityReading()
        let bogus = DiagnosticMap.Spec(
            id: "vcu_g3_trip_max",
            board: .vcuG3,
            register: Nb.Register.tripMaxSpeed,
            readLen: 2,
            category: .history
        )
        DiagnosticMap.apply(spec: bogus, data: Data([0x35, 0x43]), into: &reading)
        XCTAssertNil(reading.peakSpeedKmh)
    }

    func testLiveSpeedDoesNotCreateInsanePeak() {
        // Roh ×0.1 ohne Cap: 14130 → 1413 km/h — darf Peak nicht setzen.
        var reading = IntegrityReading()
        let speed = DiagnosticMap.Spec(
            id: "vcu_g3_speed",
            board: .vcuG3,
            register: Nb.G3Register.currentSpeed,
            readLen: 2,
            category: .limit
        )
        DiagnosticMap.apply(spec: speed, data: Data([0x32, 0x37]), into: &reading) // 14130 LE
        XCTAssertNil(reading.peakSpeedKmh)
        XCTAssertNil(reading.speedCurrentKmh)
    }

    func testLiveSpeedTenthsStillUpdatesPeak() {
        var reading = IntegrityReading()
        let speed = DiagnosticMap.Spec(
            id: "dis_speed",
            board: .dis,
            register: Nb.Register.currentSpeed,
            readLen: 2,
            category: .history
        )
        DiagnosticMap.apply(spec: speed, data: Data([0xC8, 0x00]), into: &reading) // 200 → 20.0
        XCTAssertEqual(reading.speedCurrentKmh ?? -1, 20.0, accuracy: 0.01)
        XCTAssertEqual(reading.peakSpeedKmh ?? -1, 20.0, accuracy: 0.01)
    }

    func testLiveSpeedKmhHelperRejectsInsaneTenths() {
        XCTAssertNil(RegisterScale.liveSpeedKmh(14130))
        XCTAssertEqual(RegisterScale.liveSpeedKmh(200) ?? -1, 20.0, accuracy: 0.01)
        XCTAssertEqual(RegisterScale.liveSpeedKmh(0x2D00) ?? -1, 45.0, accuracy: 0.01)
    }

    func testLiveSpeedRejectsAsciiLikePackedGarbage() {
        // SC-20261116-8A81191E: dis_speed Hex 3237 → LE 0x3732; High-Byte 55 ohne Padding.
        XCTAssertNil(RegisterScale.liveSpeedKmh(0x3732))
        var reading = IntegrityReading()
        let speed = DiagnosticMap.Spec(
            id: "dis_speed",
            board: .dis,
            register: Nb.Register.currentSpeed,
            readLen: 2,
            category: .history
        )
        DiagnosticMap.apply(spec: speed, data: Data([0x32, 0x37]), into: &reading)
        XCTAssertNil(reading.speedCurrentKmh)
        XCTAssertNil(reading.peakSpeedKmh)
    }

    func testRatedDoesNotSoftUnlockFromTenthsGarbage() {
        var reading = IntegrityReading()
        let rated = DiagnosticMap.Spec(
            id: "dis_rated",
            board: .dis,
            register: Nb.Register.ratedSpeed,
            readLen: 2,
            category: .limit
        )
        // Hex 1414 → LE 0x1414; g3Stored → 20 km/h (High-Byte), nicht 514.
        DiagnosticMap.apply(spec: rated, data: Data([0x14, 0x14]), into: &reading)
        XCTAssertEqual(reading.speedRatedKmh ?? -1, 20.0, accuracy: 0.01)
        XCTAssertNotEqual(reading.hiddenTuningDetected, true)
    }

    func testZT3ProUsesG3RegisterMap() {
        XCTAssertTrue(ScooterProfile.zt3ProD.usesG3RegisterMap)
        XCTAssertTrue(DiagnosticMap.fields(for: .zt3ProD).map(\.id).contains("vcu_g3_speed"))
        XCTAssertTrue(DiagnosticMap.fields(for: .zt3ProD).map(\.id).contains("dis_trip_max"))
    }

    // MARK: - Soft-Unlock report wording

    func testSoftUnlockFactShowsPeakWhenOnlyPeakCrossesThreshold() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 35,
            fwMcu: "1.0.0",
            hiddenTuningDetected: true
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        let soft = result.facts.first { $0.id == "flag.hidden" }
        XCTAssertNotNil(soft)
        XCTAssertTrue(
            soft?.auslesewert.contains("Trip-Peak") == true,
            "Expected Trip-Peak in auslesewert, got: \(soft?.auslesewert ?? "nil")"
        )
        XCTAssertFalse(
            soft?.auslesewert.hasPrefix("Limit 20") == true,
            "Stock limit must not mask Peak unlock evidence: \(soft?.auslesewert ?? "nil")"
        )
    }

    func testSoftUnlockFactShowsLimitWhenLimitCrossesThreshold() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 32,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0",
            hiddenTuningDetected: true
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        let soft = result.facts.first { $0.id == "flag.hidden" }
        XCTAssertTrue(soft?.auslesewert.contains("Limit") == true, soft?.auslesewert ?? "nil")
    }

    // MARK: - Positive findings / Analysebericht facts

    func testMissingLimitDoesNotInventStockLimitPositive() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            peakSpeedKmh: 18,
            fwMcu: "1.0.0"
        )
        let positives = EvidenceExplanationEngine.positiveFindings(
            reading: reading,
            profile: .maxG3D,
            results: [],
            powerCycle: nil
        )
        XCTAssertFalse(positives.contains { $0.id == "positive.limit.stock" })
        XCTAssertTrue(positives.contains { $0.id == "positive.peak.stock" })
    }

    func testStockPeakAndLimitPositivesWhenBothRead() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0"
        )
        let positives = EvidenceExplanationEngine.positiveFindings(
            reading: reading,
            profile: .maxG3D,
            results: [],
            powerCycle: nil
        )
        XCTAssertTrue(positives.contains { $0.id == "positive.limit.stock" })
        XCTAssertTrue(positives.contains { $0.id == "positive.peak.stock" })
        let peak = positives.first { $0.id == "positive.peak.stock" }
        XCTAssertTrue(peak?.auslesewert.contains("18") == true)
    }
}
