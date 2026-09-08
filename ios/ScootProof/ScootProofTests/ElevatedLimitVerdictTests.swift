import XCTest
@testable import ScootProof

final class ElevatedLimitVerdictTests: XCTestCase {

    func testStoredLimitOver22IsEindeutigAndLowScore() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 25,
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
        // DE: rated 20, suspect 22 → 21.5 is over rated+1 path? 21.5 > 21 → fact exists
        // 21.5 <= 22 → should NOT be eindeutig alone
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 21.5,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertNotEqual(assessment.verdict, .eindeutig)
        let limit = assessment.results.first { $0.fact.markerID == "speed.limit" }
        XCTAssertNotNil(limit)
        XCTAssertNotEqual(limit?.classification, .starkerHinweis)
    }

    func testLimit23IsEindeutig() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 23,
            fwMcu: "1.0.0"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertEqual(assessment.verdict, .eindeutig)
        XCTAssertLessThanOrEqual(assessment.score, 35)
    }

    func testStockLimitRemainsStock() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertEqual(assessment.verdict, .stock)
        XCTAssertGreaterThanOrEqual(assessment.score, 90)
    }
}
