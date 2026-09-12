import XCTest
@testable import ScootProof

/// Peak-/DIS-Decode und Analysebericht-Report-Bugs.
final class PeakDisReportBugsTests: XCTestCase {

    // MARK: - Peak / DIS decode

    func testTripPeakClassicTenths() {
        XCTAssertEqual(RegisterScale.tripPeakKmh(250), 25.0, accuracy: 0.01)
        XCTAssertEqual(RegisterScale.tripPeakKmh(450), 45.0, accuracy: 0.01)
        XCTAssertEqual(RegisterScale.tripPeakKmh(327), 32.7, accuracy: 0.01)
    }

    func testTripPeakG3PackedHighByte() {
        XCTAssertEqual(RegisterScale.tripPeakKmh(0x2D00), 45.0, accuracy: 0.01)
        XCTAssertEqual(RegisterScale.tripPeakKmh(0x1616), 22.0, accuracy: 0.01)
        XCTAssertEqual(RegisterScale.tripPeakKmh(0x140F), 20.0, accuracy: 0.01)
    }

    func testTripPeakWholeKmhNotMisreadAsTenths() {
        // Rohwert 25/45 = ganze km/h — nicht 2.5 / 4.5.
        XCTAssertEqual(RegisterScale.tripPeakKmh(25), 25.0, accuracy: 0.01)
        XCTAssertEqual(RegisterScale.tripPeakKmh(45), 45.0, accuracy: 0.01)
        XCTAssertEqual(RegisterScale.tripPeakKmh(20), 20.0, accuracy: 0.01)
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
