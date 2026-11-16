import XCTest
@testable import ScooterCheck

final class ZeroStartDetectionTests: XCTestCase {
    func testStartSpeedZeroDecodedAsZeroStart() {
        var reading = IntegrityReading()
        let data = Data([0x00, 0x00])
        DiagnosticMap.apply("vcu_g3_startspd", data: data, into: &reading)
        XCTAssertEqual(reading.startSpeedKmh, 0, accuracy: 0.01)
    }

    func testKickStartThresholdDecoded() {
        var reading = IntegrityReading()
        let data = Data([0x05, 0x00]) // LE 5
        DiagnosticMap.apply("vcu_g3_startspd", data: data, into: &reading)
        XCTAssertEqual(reading.startSpeedKmh, 5, accuracy: 0.01)
    }

    func testZeroStartEvidenceForDE() {
        let reading = IntegrityReading(
            serialDisplay: "1K1DA2616P1917",
            speedLimitKmh: 22,
            startSpeedKmh: 0,
            gearMax: 3,
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwBms: "4.1.6.8",
            fwVcu: "1.5.5"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .zt3ProD)
        XCTAssertNotNil(assessment.results.first { $0.fact.markerID == "zero.start" })
        XCTAssertEqual(
            assessment.results.first { $0.fact.markerID == "zero.start" }?.classification,
            .abweichung
        )
    }

    func testKickStartNotFlagged() {
        let reading = IntegrityReading(
            serialDisplay: "1K1DA2616P1917",
            speedLimitKmh: 22,
            startSpeedKmh: 5,
            gearMax: 3,
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwBms: "4.1.6.8",
            fwVcu: "1.5.5"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .zt3ProD)
        XCTAssertNil(assessment.results.first { $0.fact.markerID == "zero.start" })
    }

    func testAnalyzerFactShowsZeroStart() {
        let reading = IntegrityReading(startSpeedKmh: 0)
        let facts = IntegrityAnalyzer.analyze(
            reading: reading,
            profile: .zt3ProD
        ).facts
        let zero = facts.first { $0.id == "zero.start" }
        XCTAssertEqual(zero?.status, .abweichend)
        XCTAssertTrue(zero?.auslesewert.contains("aktiv") == true)
    }
}
