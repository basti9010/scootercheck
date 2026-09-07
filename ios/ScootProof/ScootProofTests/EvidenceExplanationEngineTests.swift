import XCTest
@testable import ScootProof

final class EvidenceExplanationEngineTests: XCTestCase {

    private func fact(
        id: String,
        title: String = "Marker",
        interpreted: String = "x",
        expected: String? = "Soll",
        persistence: PersistenceClass = .persistent,
        modMatch: String? = nil
    ) -> EvidenceFact {
        EvidenceFact(
            markerID: id,
            title: title,
            source: "VCU",
            register: id,
            rawValue: interpreted,
            interpretedValue: interpreted,
            expectedValue: expected,
            persistence: persistence,
            resetResistant: persistence == .persistent,
            confidence: 0.8,
            knowledgeSource: .heuristic,
            knownModMatchId: modMatch,
            knownStockMatch: nil
        )
    }

    private func result(
        _ fact: EvidenceFact,
        class cls: EvidenceClass,
        neutralized: NeutralizationRecord? = nil
    ) -> EvidenceResult {
        let r = EvidenceResult(
            fact: fact,
            classification: neutralized?.classAfter ?? cls,
            classBeforeNeutralization: cls,
            weight: neutralized == nil ? cls.scorePoints : 0,
            correlations: [],
            neutralizations: neutralized.map { [$0] } ?? [],
            explanation: fact.title
        )
        return EvidenceExplanationEngine.enrich([r])[0]
    }

    func testStockLimitExplanation() {
        let r = result(
            fact(id: "speed.limit", title: "Limit", interpreted: "20 km/h", expected: "≤ 20 km/h"),
            class: .info
        )
        XCTAssertTrue(r.humanReadableExplanation.lowercased().contains("entspricht")
            || r.plainLanguage.title.lowercased().contains("soll"))
        XCTAssertEqual(r.verdictContributionExplanation, "Kein Beitrag zum Gesamturteil.")
    }

    func testElevatedLimitExplanation() {
        let r = result(
            fact(id: "speed.limit", interpreted: "32 km/h", expected: "≤ 20 km/h", modMatch: "speed.limit.over_clear"),
            class: .indiz
        )
        XCTAssertTrue(r.plainLanguage.title.lowercased().contains("weicht")
            || r.humanReadableExplanation.lowercased().contains("über"))
        XCTAssertNotNil(r.relevanceExplanation)
    }

    func testRegionDeviationExplanation() {
        let r = result(
            fact(id: "region.sn", interpreted: "US-Region", expected: "DE"),
            class: .indiz
        )
        XCTAssertEqual(r.shortTitle, "Auffällige Regionseinstellung")
        XCTAssertTrue(r.humanReadableExplanation.contains("Region"))
    }

    func testRegionNeutralizedExplanation() {
        let n = NeutralizationRecord(
            ruleId: "REGION_US_STOCK_PROFILE",
            reason: "US-Stock plausibel",
            classBefore: .indiz,
            classAfter: .abweichung
        )
        let r = result(
            fact(id: "region.sn", interpreted: "US 1CGC"),
            class: .indiz,
            neutralized: n
        )
        XCTAssertEqual(r.shortTitle, "Abweichung technisch erklärbar")
        XCTAssertTrue(r.verdictContributionExplanation?.contains("Kein Beitrag") == true)
        XCTAssertFalse(r.contributesToVerdict)
    }

    func testUnknownFirmwareNoOverclaim() {
        let r = result(
            fact(id: "fw.unknown", interpreted: "unbekannter Stand"),
            class: .abweichung
        )
        XCTAssertFalse(r.humanReadableExplanation.lowercased().contains("ist manipuliert"))
        XCTAssertTrue(r.humanReadableExplanation.lowercased().contains("bekannten serienstand")
            || r.humanReadableExplanation.lowercased().contains("serienstand"))
    }

    func testCustomFirmwareStrongExplanation() {
        let r = result(
            fact(id: "fw.custom", interpreted: "mod fingerprint", modMatch: "fw.custom.confirmed"),
            class: .starkerHinweis
        )
        XCTAssertTrue(r.plainLanguage.title.lowercased().contains("firmware"))
        XCTAssertTrue(r.relevanceExplanation?.lowercased().contains("werkzeug") == true
            || r.humanReadableExplanation.lowercased().contains("nicht serien"))
    }

    func testSerialMismatchSuggestsPossibleSwap() {
        let r = result(
            fact(id: "serial.cross.mcu", interpreted: "MCU ≠ Fahrzeug"),
            class: .indiz
        )
        XCTAssertTrue(r.humanReadableExplanation.lowercased().contains("kennung"))
        XCTAssertTrue(r.relevanceExplanation?.lowercased().contains("modultausch") == true)
        XCTAssertTrue(r.relevanceExplanation?.contains("nicht automatisch") == true)
    }

    func testPowerCycleFleeting() {
        let row = PowerCycleDiffRow(
            markerID: "speed.session",
            title: "Session",
            scanA: "1",
            scanB: "0",
            observedPersistence: .fleeting,
            catalogPersistence: .fleeting,
            changeKind: .disappeared,
            note: "test"
        )
        let exp = EvidenceExplanationEngine.explanation(forPowerCycleRow: row)
        XCTAssertTrue(exp.title.lowercased().contains("vorübergehend")
            || exp.summary.lowercased().contains("temporär")
            || exp.relevance?.lowercased().contains("temporär") == true)
    }

    func testPowerCyclePersistent() {
        let row = PowerCycleDiffRow(
            markerID: "speed.limit",
            title: "Limit",
            scanA: "32 km/h",
            scanB: "32 km/h",
            observedPersistence: .persistent,
            catalogPersistence: .persistent,
            changeKind: .unchanged,
            note: "test"
        )
        let exp = EvidenceExplanationEngine.explanation(forPowerCycleRow: row)
        XCTAssertTrue(exp.title.lowercased().contains("bestehen")
            || exp.summary.lowercased().contains("gleich"))
    }

    func testUnavailableAfterRestartNotFleetingClaim() {
        let row = PowerCycleDiffRow(
            markerID: "speed.session",
            title: "Session",
            scanA: "1",
            scanB: "—",
            observedPersistence: .semiPersistent,
            catalogPersistence: .fleeting,
            changeKind: .unavailableAfterRestart,
            note: "unavailable"
        )
        let exp = EvidenceExplanationEngine.explanation(forPowerCycleRow: row)
        XCTAssertFalse(exp.summary.lowercased().contains("vorübergehend festgestellt")
            && exp.title.lowercased().contains("vorübergehend"))
        XCTAssertTrue(exp.summary.lowercased().contains("nicht")
            || exp.relevance?.lowercased().contains("keine aussage über flüchtigkeit") == true)
    }

    func testUnknownStateNeutral() {
        let r = result(
            fact(id: "misc.unknown", title: "Unbekanntes Register", interpreted: "0xDEAD"),
            class: .abweichung
        )
        XCTAssertTrue(
            r.humanReadableExplanation.lowercased().contains("dokumentiert")
                || r.humanReadableExplanation.lowercased().contains("zuordnung")
        )
    }

    func testAttributionLowConfidenceCautious() {
        let attr = AttributionAssessment(
            suspectedMethod: .unknownSoftwareManipulation,
            confidence: 0.25,
            supportingMarkerIds: ["speed.limit"],
            contradictingMarkerIds: ["fw.unknown"],
            knownPatternId: nil,
            explanation: "unklar",
            catalogVersion: AttributionCatalog.version
        )
        let text = EvidenceExplanationEngine.attributionPlain(attr)
        XCTAssertTrue(text.contains("nicht eindeutig") || text.lowercased().contains("heuristisch"))
        XCTAssertFalse(text.lowercased().contains("definitiv"))
    }

    func testAttributionHighConfidenceNoToolClaim() {
        let attr = AttributionAssessment(
            suspectedMethod: .customFirmware,
            confidence: 0.95,
            supportingMarkerIds: ["fw.custom", "speed.limit"],
            contradictingMarkerIds: [],
            knownPatternId: "ATTR_CUSTOM_FW_GENERIC_V1",
            explanation: "strong",
            catalogVersion: AttributionCatalog.version
        )
        let text = EvidenceExplanationEngine.attributionPlain(attr)
        XCTAssertTrue(text.lowercased().contains("vereinbar") || text.lowercased().contains("heuristisch"))
        XCTAssertFalse(text.lowercased().contains("scooterhacking"))
        XCTAssertFalse(text.lowercased().contains("definitiv mit"))
    }

    func testEindeutigVerdictPlainLanguage() {
        let text = VerdictLevel.eindeutig.laymanText
        XCTAssertTrue(text.contains("technisch eindeutiges Merkmal") || text.contains("Serienzustand"))
        XCTAssertFalse(text.lowercased().contains("illegal"))
        XCTAssertFalse(text.lowercased().contains("straftat"))
        XCTAssertFalse(text.lowercased().contains("behörde"))
    }

    func testNeutralizedNoVerdictContribution() {
        let n = NeutralizationRecord(
            ruleId: "REGION_US_STOCK_PROFILE",
            reason: "plausibel",
            classBefore: .indiz,
            classAfter: .abweichung
        )
        let r = result(fact(id: "region.sn"), class: .indiz, neutralized: n)
        XCTAssertFalse(r.contributesToVerdict)
        XCTAssertTrue(r.verdictContributionExplanation?.contains("Kein Beitrag") == true)
    }

    func testGlossaryCoversCoreTerms() {
        for term in TechnicalTerm.allCases {
            let text = TechnicalGlossary.explanation(for: term)
            XCTAssertFalse(text.isEmpty, "Missing glossary for \(term)")
        }
    }
}
