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
        XCTAssertEqual(r.shortTitle, "Ländereinstellung weicht ab")
        XCTAssertTrue(r.humanReadableExplanation.contains("Ländereinstellung")
            || r.humanReadableExplanation.contains("Region"))
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
        XCTAssertTrue(r.shortTitle.lowercased().contains("erklärbar")
            || r.shortTitle.lowercased().contains("zählt nicht"))
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
        XCTAssertTrue(r.plainLanguage.title.lowercased().contains("software")
            || r.plainLanguage.title.lowercased().contains("firmware"))
        XCTAssertTrue(r.relevanceExplanation?.lowercased().contains("firmware") == true
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
        XCTAssertFalse(text.lowercased().contains("beweist nicht"))
        XCTAssertTrue(text.lowercased().contains("zeigt nicht") || text.lowercased().contains("heuristisch"))
    }

    func testEindeutigVerdictPlainLanguage() {
        let text = VerdictLevel.eindeutig.laymanText
        XCTAssertTrue(text.lowercased().contains("klar") || text.contains("Serienzustand"))
        XCTAssertFalse(text.lowercased().contains("illegal"))
        XCTAssertFalse(text.lowercased().contains("straftat"))
        XCTAssertFalse(text.lowercased().contains("behörde"))
    }

    func testGearMaxLaymanBulletExplainsUnlockNotEcoSport() {
        let r = result(
            fact(id: "gear.max", title: "Gang", interpreted: "max. Stufe 3", expected: "1", modMatch: "gear.max.unlocked"),
            class: .indiz
        )
        XCTAssertTrue(r.plainLanguage.title.lowercased().contains("leistungsstufen")
            || r.plainLanguage.title.lowercased().contains("freigeschaltet"))
        XCTAssertTrue(r.humanReadableExplanation.lowercased().contains("eco")
            || r.humanReadableExplanation.lowercased().contains("fahrmodi"))
        let bullet = EvidenceExplanationEngine.problemBullet(for: r)
        XCTAssertTrue(bullet.lowercased().contains("leistungsstufen")
            || bullet.lowercased().contains("freigeschaltet"))
    }

    func testProblemOverviewStock() {
        let text = EvidenceExplanationEngine.problemOverview(verdict: .stock, results: [])
        XCTAssertTrue(text.lowercased().contains("nichts") || text.lowercased().contains("kein"))
        XCTAssertTrue(EvidenceExplanationEngine.problemBullets(from: []).isEmpty)
    }

    func testProblemOverviewListsBullets() {
        let limit = result(
            fact(id: "speed.limit", interpreted: "32 km/h", expected: "≤ 20 km/h"),
            class: .indiz
        )
        let gear = result(
            fact(id: "gear.max", interpreted: "max. Stufe 3", expected: "1"),
            class: .abweichung
        )
        let text = EvidenceExplanationEngine.problemOverview(verdict: .hinweise, results: [limit, gear])
        XCTAssertTrue(text.contains("•"))
        XCTAssertTrue(text.lowercased().contains("tempolimit")
            || text.lowercased().contains("geschwindigkeitslimit")
            || text.lowercased().contains("leistungsstufen"))
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

    func testPositiveFindingsForStockReading() {
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
        XCTAssertTrue(positives.contains { $0.id == "positive.region.stock" })
        XCTAssertTrue(positives.contains { $0.id == "positive.fw.stock" })
        XCTAssertTrue(positives.contains { $0.id == "positive.boards.consistent" })
    }

    func testPositiveLimitSkippedWhenUnread() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            fwMcu: "1.0.0"
        )
        let positives = EvidenceExplanationEngine.positiveFindings(
            reading: reading,
            profile: .maxG3D,
            results: [],
            powerCycle: nil
        )
        XCTAssertFalse(positives.contains { $0.id == "positive.limit.stock" })
        XCTAssertFalse(positives.contains { $0.id == "positive.peak.stock" })
    }

    func testGlossaryCoversCoreTerms() {
        for term in TechnicalTerm.allCases {
            let text = TechnicalGlossary.explanation(for: term)
            XCTAssertFalse(text.isEmpty, "Missing glossary for \(term)")
        }
    }
}
