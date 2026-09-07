import XCTest
@testable import ScootProof

final class AttributionEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func fact(
        id: String,
        title: String = "Marker",
        persistence: PersistenceClass = .persistent,
        knowledge: KnowledgeSource = .heuristic,
        modMatch: String? = nil,
        interpreted: String = "x"
    ) -> EvidenceFact {
        EvidenceFact(
            markerID: id,
            title: title,
            source: "TEST",
            register: id,
            rawValue: interpreted,
            interpretedValue: interpreted,
            expectedValue: "stock",
            persistence: persistence,
            resetResistant: persistence == .persistent,
            confidence: 0.85,
            knowledgeSource: knowledge,
            knownModMatchId: modMatch,
            knownStockMatch: false
        )
    }

    private func result(
        _ fact: EvidenceFact,
        class cls: EvidenceClass,
        neutralized: NeutralizationRecord? = nil
    ) -> EvidenceResult {
        EvidenceResult(
            fact: fact,
            classification: neutralized?.classAfter ?? cls,
            classBeforeNeutralization: cls,
            weight: neutralized == nil ? cls.scorePoints : 0,
            correlations: [],
            neutralizations: neutralized.map { [$0] } ?? [],
            explanation: fact.title
        )
    }

    private func powerCycle(rows: [(String, String, String, PowerCycleChangeKind)]) -> PowerCycleReport {
        let diffRows = rows.map { id, a, b, kind in
            PowerCycleDiffRow(
                markerID: id,
                title: id,
                scanA: a,
                scanB: b,
                observedPersistence: kind == .unchanged ? .persistent : .fleeting,
                catalogPersistence: .persistent,
                changeKind: kind,
                note: kind.rawValue
            )
        }
        return PowerCycleReport(rows: diffRows, summary: "test")
    }

    // MARK: - Cases

    func testStockVehicle_noAttribution() {
        let attr = AttributionEngine.assess(results: [], powerCycle: nil)
        XCTAssertNil(attr.suspectedMethod)
        XCTAssertFalse(attr.isDeterminate)
        XCTAssertLessThan(attr.confidence, 0.4)
    }

    func testSingleElevatedLimit_noSecureAttribution() {
        let r = result(
            fact(id: "speed.limit", title: "Limit", interpreted: "28 km/h", modMatch: "speed.limit.over_rated"),
            class: .abweichung
        )
        let attr = AttributionEngine.assess(results: [r], powerCycle: nil)
        XCTAssertFalse(attr.isDeterminate, "Einzelmarker darf keine sichere Attribution liefern")
        XCTAssertLessThan(attr.confidence, 0.4)
    }

    func testCustomFirmwarePlusSpeed_highConfidence() {
        let results = [
            result(
                fact(
                    id: "fw.custom",
                    title: "Custom-FW",
                    knowledge: .verifiedModSample,
                    modMatch: "fw.custom.confirmed",
                    interpreted: "mod fingerprint"
                ),
                class: .starkerHinweis
            ),
            result(
                fact(id: "speed.limit", title: "Limit", interpreted: "45 km/h", modMatch: "speed.limit.over_clear"),
                class: .starkerHinweis
            )
        ]
        let attr = AttributionEngine.assess(results: results, powerCycle: nil)
        XCTAssertEqual(attr.suspectedMethod, .customFirmware)
        XCTAssertGreaterThanOrEqual(attr.confidence, 0.9)
        XCTAssertEqual(attr.knownPatternId, "ATTR_CUSTOM_FW_GENERIC_V1")
        XCTAssertTrue(attr.supportingMarkerIds.contains("fw.custom"))
    }

    func testStockFwPersistentRegionAndLimit_configOrLicensed() {
        let results = [
            result(
                fact(id: "region.sn", title: "Region", interpreted: "US", modMatch: "region.us.1CGC.on_de_profile"),
                class: .indiz
            ),
            result(
                fact(id: "speed.limit", title: "Limit", interpreted: "32 km/h", modMatch: "speed.limit.over_clear"),
                class: .indiz
            ),
            result(
                fact(id: "gear.max", title: "Gang", interpreted: "3", modMatch: "gear.max.unlocked"),
                class: .abweichung
            )
        ]
        let attr = AttributionEngine.assess(results: results, powerCycle: nil)
        XCTAssertTrue(attr.isDeterminate)
        XCTAssertTrue(
            attr.suspectedMethod == .configurationModification
                || attr.suspectedMethod == .licensedSoftwareUnlock
        )
        XCTAssertGreaterThanOrEqual(attr.confidence, 0.4)
        XCTAssertLessThan(attr.confidence, 0.9)
        XCTAssertNotEqual(attr.suspectedMethod, .customFirmware)
    }

    func testSessionUnlockClearedByPowerCycle() {
        let results = [
            result(
                fact(
                    id: "speed.session",
                    title: "Session",
                    persistence: .fleeting,
                    modMatch: "speed.session.unlock",
                    interpreted: "≥ 30 km/h"
                ),
                class: .abweichung
            )
        ]
        let pc = powerCycle(rows: [
            ("speed.session", "1", "0", .disappeared),
            ("speed.limit", "20 km/h", "20 km/h", .unchanged),
            ("fw.mcu", "1.2.3", "1.2.3", .unchanged)
        ])
        let attr = AttributionEngine.assess(results: results, powerCycle: pc)
        XCTAssertEqual(attr.suspectedMethod, .sessionUnlock)
        XCTAssertGreaterThanOrEqual(attr.confidence, 0.5)
        XCTAssertTrue(
            attr.supportingMarkerIds.contains("speed.session")
                || attr.supportingMarkerIds.contains("powercycle.session.disappeared")
        )
    }

    func testCrossBoardSerial_hardwareSwap() {
        let r = result(
            fact(
                id: "serial.cross.mcu",
                title: "Cross-Board",
                modMatch: "cross.serial.mismatch",
                interpreted: "MCU ≠ Fahrzeug"
            ),
            class: .indiz
        )
        let attr = AttributionEngine.assess(results: [r], powerCycle: nil)
        XCTAssertEqual(attr.suspectedMethod, .hardwareOrModuleSwap)
        XCTAssertEqual(attr.knownPatternId, "ATTR_MODULE_SWAP_CROSS_BOARD_V1")
        XCTAssertGreaterThanOrEqual(attr.confidence, 0.55)
    }

    func testContradictoryMarkers_unknownOrLowConfidence() {
        let results = [
            result(
                fact(id: "fw.unknown", title: "FW unbekannt", interpreted: "hash?"),
                class: .abweichung
            ),
            result(
                fact(id: "speed.limit", title: "Limit", interpreted: "40 km/h", modMatch: "speed.limit.over_clear"),
                class: .indiz
            ),
            result(
                fact(id: "speed.session", title: "Session", persistence: .fleeting, interpreted: "session"),
                class: .abweichung
            )
        ]
        // licensed has contradicting fw.unknown → score drop; mixed signals
        let attr = AttributionEngine.assess(results: results, powerCycle: nil)
        if attr.suspectedMethod == .licensedSoftwareUnlock {
            XCTAssertLessThan(attr.confidence, 0.7)
            XCTAssertFalse(attr.contradictingMarkerIds.isEmpty)
        } else {
            XCTAssertTrue(
                attr.suspectedMethod == .unknownSoftwareManipulation
                    || attr.suspectedMethod == .sessionUnlock
                    || attr.suspectedMethod == .configurationModification
                    || !attr.isDeterminate
            )
        }
    }

    func testNeutralizedMarker_doesNotInflateAttribution() {
        let neutralized = NeutralizationRecord(
            ruleId: "REGION_US_STOCK_PROFILE",
            reason: "US stock",
            classBefore: .indiz,
            classAfter: .abweichung
        )
        let region = result(
            fact(id: "region.sn", title: "Region", interpreted: "US 1CGC"),
            class: .indiz,
            neutralized: neutralized
        )
        let attr = AttributionEngine.assess(results: [region], powerCycle: nil)
        XCTAssertNotEqual(attr.suspectedMethod, .regionChange)
        XCTAssertFalse(attr.isDeterminate)
        // Neutralized region alone must not invent a method
        XCTAssertNil(attr.suspectedMethod)
    }

    func testUnavailableAfterRestart_notCountedAsSessionUnlock() {
        let results = [
            result(
                fact(
                    id: "speed.session",
                    title: "Session",
                    persistence: .fleeting,
                    modMatch: "speed.session.unlock",
                    interpreted: "session"
                ),
                class: .abweichung
            )
        ]
        let pc = powerCycle(rows: [
            ("speed.session", "1", "—", .unavailableAfterRestart)
        ])
        let attr = AttributionEngine.assess(results: results, powerCycle: pc)
        // May still have weak session suspicion from marker, but unavailable must not boost to strong session claim
        if attr.suspectedMethod == .sessionUnlock {
            XCTAssertLessThan(attr.confidence, 0.5)
            XCTAssertTrue(attr.contradictingMarkerIds.contains("powercycle.session.unavailableAfterRestart"))
        }
        XCTAssertNotEqual(
            PowerCycleChangeClassifier.classify(scanA: "1", scanB: "—"),
            .disappeared
        )
        XCTAssertEqual(
            PowerCycleChangeClassifier.classify(scanA: "1", scanB: "—"),
            .unavailableAfterRestart
        )
    }

    func testChangeClassifier_disappearedFlag() {
        XCTAssertEqual(PowerCycleChangeClassifier.classify(scanA: "1", scanB: "0"), .disappeared)
        XCTAssertEqual(PowerCycleChangeClassifier.classify(scanA: "20 km/h", scanB: "20 km/h"), .unchanged)
    }

    func testAttributionNeverAffectsVerdictPath() {
        // Smoke: EvidenceEngine verdict stays rule-based; attribution is attached after.
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 18,
            fwMcu: "1.0.0"
        )
        let assessment = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        XCTAssertEqual(assessment.verdict, .stock)
        // Attribution optional / not determinate on stock
        XCTAssertTrue(assessment.attribution == nil || assessment.attribution?.isDeterminate == false)
    }
}
