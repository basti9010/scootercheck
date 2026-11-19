import XCTest
@testable import ScooterCheck

final class ElevatedLimitVerdictTests: XCTestCase {

    func testStoredLimitOverSuspectIsEindeutigAndLowScore() {
        // DE: Serienlimit 22, Verdacht >25 — 26 ist eindeutig.
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 26,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertEqual(assessment.verdict, .eindeutig)
        XCTAssertLessThanOrEqual(assessment.score, 35)
        XCTAssertFalse(assessment.score >= 82)
        let limit = assessment.results.first { $0.fact.markerID == "speed.limit" }
        XCTAssertEqual(limit?.classification, .starkerHinweis)
        XCTAssertTrue(limit?.contributesToVerdict == true)
    }

    func testStoredLimitJustOverRatedButNotOverSuspectStaysCautious() {
        // DE: rated 22 → fact ab >23; 23.5 ≤ suspect 25 → nicht eindeutig allein
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 23.5,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertNotEqual(assessment.verdict, .eindeutig)
        let limit = assessment.results.first { $0.fact.markerID == "speed.limit" }
        XCTAssertNotNil(limit)
        XCTAssertNotEqual(limit?.classification, .starkerHinweis)
    }

    func testLimit26IsEindeutig() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 26,
            fwMcu: "1.0.0"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertEqual(assessment.verdict, .eindeutig)
        XCTAssertLessThanOrEqual(assessment.score, 35)
    }

    func testStockLimit22IsNotManipulation() {
        let reading = IntegrityReading(
            serialDisplay: "1K1DA2616P1917",
            speedMaxKmh: 22,
            speedLimitKmh: 22,
            peakSpeedKmh: 18,
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwBms: "4.1.6.8",
            fwVcu: "1.5.5"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .zt3ProD)
        XCTAssertNil(assessment.results.first { $0.fact.markerID == "speed.limit" })
        XCTAssertNil(assessment.results.first { $0.fact.markerID == "fw.unknown" })
        XCTAssertNotEqual(assessment.verdict, .eindeutig)
        XCTAssertEqual(ScooterProfile.zt3ProD.ratedMaxKmh, 22, accuracy: 0.01)
    }

    /// gear.max = 3 ist Serie (Eco/Drive/Sport); 4 bleibt Auffälligkeit.
    func testZT3StockGear3NotFlaggedBut4Is() {
        let stock = IntegrityReading(
            serialDisplay: "1K1DA2616P1917",
            speedLimitKmh: 22,
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwBms: "4.1.6.8",
            fwVcu: "1.5.5",
            gearMode: 3,
            gearMax: 3
        )
        let stockAssessment = EvidenceEngine.evaluate(reading: stock, profile: .zt3ProD)
        XCTAssertNil(stockAssessment.results.first { $0.fact.markerID == "gear.max" })

        let unlocked = IntegrityReading(
            serialDisplay: "1K1DA2616P1917",
            speedLimitKmh: 22,
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwBms: "4.1.6.8",
            fwVcu: "1.5.5",
            gearMode: 4,
            gearMax: 4
        )
        let unlockedAssessment = EvidenceEngine.evaluate(reading: unlocked, profile: .zt3ProD)
        XCTAssertNotNil(unlockedAssessment.results.first { $0.fact.markerID == "gear.max" })
    }

    func testStockLimitRemainsStock() {
        // Use catalogued Max G3 MCU/BLE/VCU so fw.unknown does not flip verdict.
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 22,
            peakSpeedKmh: 18,
            fwMcu: "1.4.9",
            fwBle: "0.4.0",
            fwVcu: "1.5.8"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertNil(assessment.results.first { $0.fact.markerID == "speed.limit" })
        XCTAssertNil(assessment.results.first { $0.fact.markerID == "fw.unknown" })
        XCTAssertEqual(assessment.verdict, .stock)
        XCTAssertGreaterThanOrEqual(assessment.score, 90)
    }
}
