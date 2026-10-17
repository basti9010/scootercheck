import XCTest
@testable import ScooterCheck

final class CompactReportFactsTests: XCTestCase {

    func testNoSummaryOrAttributionFacts() {
        var reading = IntegrityReading()
        reading.speedLimitKmh = 35
        reading.speedMaxKmh = 35
        reading.peakSpeedKmh = 33
        reading.fwVcu = "1.5.8"
        reading.serialDisplay = "1CGBTEST000001"
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        XCTAssertFalse(result.facts.contains { $0.id == "evidence.summary" })
        XCTAssertFalse(result.facts.contains { $0.id == "evidence.attribution" })
        XCTAssertFalse(result.findings.contains { $0.id == "finding.evidence.verdict" })
        XCTAssertFalse(result.findings.contains { $0.id == "finding.evidence.attribution" })
    }

    func testSpeedDiffsNotDuplicatedAsFacts() {
        var reading = IntegrityReading()
        reading.speedLimitKmh = 40
        reading.speedMaxKmh = 40
        reading.peakSpeedKmh = 38
        reading.fwVcu = "1.5.8"
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        XCTAssertTrue(result.facts.contains { $0.id == "speed.limit" })
        XCTAssertFalse(result.facts.contains { $0.id.hasPrefix("diff.speed.") })
        XCTAssertFalse(result.facts.contains { $0.id.hasPrefix("diff.gear.") })
    }

    func testAttributionDetailOmitsHeadline() {
        let attr = AttributionAssessment(
            suspectedMethod: .customFirmware,
            confidence: 0.8,
            supportingMarkerIds: ["fw.custom"],
            contradictingMarkerIds: [],
            knownPatternId: "ATTR_CUSTOM_FW_GENERIC_V1",
            explanation: "x",
            catalogVersion: AttributionCatalog.version
        )
        let detail = EvidenceExplanationEngine.attributionDetail(attr)
        XCTAssertFalse(detail.contains(attr.headline))
        XCTAssertTrue(detail.lowercased().contains("heuristisch"))
    }
}
