import Foundation
import CryptoKit

// MARK: - Catalog version (reproduzierbare historische Bewertungen)

enum EvidenceCatalog {
    /// Bei Regel-/Marker-Änderungen hochzählen — landet in PDF/JSON.
    static let version = 12
}

// MARK: - Taxonomy

enum PersistenceClass: String, Codable, CaseIterable, Sendable {
    case fleeting = "flüchtig"
    case semiPersistent = "semi-persistent"
    case persistent = "persistent"

    var label: String { rawValue }

    var resetsOnPowerOffHint: String {
        switch self {
        case .fleeting: return "meist weg nach Ausschalten"
        case .semiPersistent: return "oft weg nach Trip-Reset/Panic"
        case .persistent: return "typisch power-cycle-resistent (Katalog)"
        }
    }
}

typealias MarkerVolatility = PersistenceClass

/// Woher die Belastbarkeit des Markers stammt.
enum KnowledgeSource: String, Codable, CaseIterable, Sendable {
    case manufacturer
    case referenceVehicle
    case verifiedModSample
    case heuristic
    case unknown

    var label: String {
        switch self {
        case .manufacturer: return "Hersteller/Doku"
        case .referenceVehicle: return "Referenzfahrzeug"
        case .verifiedModSample: return "verifizierte Mod-Probe"
        case .heuristic: return "Heuristik"
        case .unknown: return "unbekannt"
        }
    }
}

enum EvidenceClass: String, Codable, CaseIterable, Sendable {
    case info = "Info"
    case abweichung = "Abweichung"
    case indiz = "Manipulationsindiz"
    case starkerHinweis = "starker Manipulationshinweis"

    var label: String { rawValue }

    var rank: Int {
        switch self {
        case .info: return 0
        case .abweichung: return 1
        case .indiz: return 2
        case .starkerHinweis: return 3
        }
    }

    /// Beitrag zur Score-Verdichtung (nicht urteilsbildend).
    var scorePoints: Int {
        switch self {
        case .info: return 0
        case .abweichung: return 8
        case .indiz: return 18
        case .starkerHinweis: return 32
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "Info", "info", "unbekannt / Rohwert", "unknown": self = .info
        case "Abweichung", "abweichung", "bloße Abweichung": self = .abweichung
        case "Manipulationsindiz", "indiz": self = .indiz
        case "starker Manipulationshinweis", "starker_hinweis", "Manipulationsnachweis", "nachweis":
            self = .starkerHinweis
        default: self = EvidenceClass(rawValue: raw) ?? .info
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Fact → Result → Assessment

/// Rohfakt für die Engine — keine Bewertung.
struct EvidenceFact: Identifiable, Codable, Hashable, Sendable {
    var id: String { markerID }
    let markerID: String
    let title: String
    let source: String
    let register: String?
    let rawValue: String
    let interpretedValue: String?
    let expectedValue: String?
    let persistence: PersistenceClass
    let resetResistant: Bool?
    let confidence: Double
    let knowledgeSource: KnowledgeSource
    /// z. B. "mod.fw.customMarked", "region.us.1CGC"
    let knownModMatchId: String?
    let knownStockMatch: Bool?
}

/// Explizite Neutralisierung — im PDF nachvollziehbar.
struct NeutralizationRecord: Codable, Hashable, Sendable {
    let ruleId: String
    let reason: String
    let classBefore: EvidenceClass
    let classAfter: EvidenceClass
}

/// Bewertete Evidenz zu einem Fakt.
struct EvidenceResult: Identifiable, Codable, Hashable, Sendable {
    var id: String { fact.markerID }
    let fact: EvidenceFact
    /// Finale Klasse nach Neutralisierung.
    let classification: EvidenceClass
    let classBeforeNeutralization: EvidenceClass
    let weight: Int
    let correlations: [String]
    let neutralizations: [NeutralizationRecord]
    let explanation: String

    var isNeutralized: Bool { !neutralizations.isEmpty }

    var contributesToVerdict: Bool {
        !isNeutralized && classification.rank >= EvidenceClass.abweichung.rank
    }

    var chainCitation: String {
        var parts = [
            "Quelle: \(fact.source)" + (fact.register.map { " / \($0)" } ?? ""),
            "Rohwert: \(fact.rawValue)",
            "Interpretation: \(fact.interpretedValue ?? "—")",
            "Soll: \(fact.expectedValue ?? "—")",
            "Persistenz: \(fact.persistence.label)",
            "Erkenntnis: \(fact.knowledgeSource.label)",
            "Initiale Klasse: \(classBeforeNeutralization.label)",
            "Finale Klasse: \(classification.label)"
        ]
        if let mod = fact.knownModMatchId { parts.append("Mod-Match: \(mod)") }
        for n in neutralizations {
            parts.append("Neutralisierung \(n.ruleId): \(n.reason)")
        }
        parts.append(contributesToVerdict ? "Beitrag Urteil: ja (Gewicht \(weight))" : "Beitrag Urteil: keiner")
        return parts.joined(separator: " · ")
    }
}

struct TemporalDelta: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let previous: String
    let current: String
    let priorProtocol: String
}

struct CrossBoardIssue: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let boards: [String]
}

struct BaselineFingerprint: Codable, Hashable, Sendable {
    let profileId: String
    let digestSHA256: String
    let fields: [String: String]
}

struct PowerCycleDiffRow: Identifiable, Codable, Hashable, Sendable {
    var id: String { markerID }
    let markerID: String
    let title: String
    let scanA: String
    let scanB: String
    /// Am konkreten Fahrzeug beobachtet.
    let observedPersistence: PersistenceClass
    let catalogPersistence: PersistenceClass?
    let note: String
}

struct PowerCycleReport: Codable, Hashable, Sendable {
    let rows: [PowerCycleDiffRow]
    let summary: String
}

/// Ausgabe der Engine — UI/PDF/JSON dürfen Bewertung nicht nachbauen.
struct EvidenceAssessment: Codable, Hashable, Sendable {
    let catalogVersion: Int
    let results: [EvidenceResult]
    let verdict: VerdictLevel
    /// Verdichtung 0…100 (höher = unauffälliger). Niemals allein urteilsbildend.
    let score: Int
    let decisiveEvidence: [String]
    let warnings: [String]
    let shortVerdictText: String
    let correlations: [String]
    let temporalDeltas: [TemporalDelta]
    let crossBoardIssues: [CrossBoardIssue]
    let fingerprint: BaselineFingerprint
    let unknownRegisters: [RawRegister]
    let powerCycle: PowerCycleReport?

    // Kompatibilität / Anzeigehelfer
    var integrityScore: Int { score }
    var justifyingMarkers: [EvidenceResult] {
        results.filter(\.contributesToVerdict)
            .sorted { $0.classification.rank > $1.classification.rank }
    }
    var markers: [EvidenceResult] { results }
    var hits: [EvidenceResult] { results }
    var suggestedVerdict: VerdictLevel { verdict }
    var summary: String {
        let n = results.filter(\.isNeutralized).count
        let s = results.filter { $0.classification == .starkerHinweis && !$0.isNeutralized }.count
        let i = results.filter { $0.classification == .indiz && !$0.isNeutralized }.count
        let a = results.filter { $0.classification == .abweichung && !$0.isNeutralized }.count
        return "Katalog v\(catalogVersion) · \(s)× stark · \(i)× Indiz · \(a)× Abweichung · \(n)× neutralisiert → \(verdict.label)"
    }
    var starkerHinweisCount: Int {
        results.filter { !$0.isNeutralized && $0.classification == .starkerHinweis }.count
    }
    var indizCount: Int {
        results.filter { !$0.isNeutralized && $0.classification == .indiz }.count
    }
    var abweichungCount: Int {
        results.filter { !$0.isNeutralized && $0.classification == .abweichung }.count
    }
    var nachweisCount: Int { starkerHinweisCount }
    var neutralizationNotes: [String] {
        results.flatMap { $0.neutralizations.map { "\($0.ruleId): \($0.reason)" } }
    }

    static let empty = EvidenceAssessment(
        catalogVersion: EvidenceCatalog.version,
        results: [],
        verdict: .stock,
        score: 100,
        decisiveEvidence: [],
        warnings: [],
        shortVerdictText: VerdictLevel.stock.laymanText,
        correlations: [],
        temporalDeltas: [],
        crossBoardIssues: [],
        fingerprint: BaselineFingerprint(profileId: "", digestSHA256: "", fields: [:]),
        unknownRegisters: [],
        powerCycle: nil
    )
}

// Compatibility aliases used by older UI paths
extension EvidenceResult {
    var markerId: String { fact.markerID }
    var title: String { fact.title }
    var persistenceClass: PersistenceClass { fact.persistence }
    var evidenceClass: EvidenceClass { classification }
    var interpretedValue: String { fact.interpretedValue ?? "—" }
    var expectedValue: String { fact.expectedValue ?? "—" }
    var boardSource: String { fact.source }
    var registerOrField: String { fact.register ?? "—" }
    var rawValue: String { fact.rawValue }
    var rawCitation: String { chainCitation }
    var neutralized: Bool { isNeutralized }
    var neutralizationReason: String? { neutralizations.first?.reason }
    var resetsOnPowerOff: Bool { fact.resetResistant == false || fact.persistence != .persistent }
    var contributionLabel: String {
        isNeutralized
            ? "neutralisiert (\(neutralizations.first?.ruleId ?? "—"))"
            : "\(classification.label) · Gewicht \(weight)"
    }
}

// MARK: - Engine

enum EvidenceEngine {

    static func evaluate(
        reading: IntegrityReading,
        profile: ScooterProfile,
        priorUnlock: PriorUnlockEvidence? = nil,
        priorReading: IntegrityReading? = nil,
        priorProtocolNumber: String? = nil,
        powerCycle: PowerCycleReport? = nil
    ) -> EvidenceAssessment {
        var facts = collectFacts(
            reading: reading,
            profile: profile,
            priorUnlock: priorUnlock
        )
        let cross = crossBoardIssues(reading: reading, profile: profile)
        for issue in cross where issue.id.hasPrefix("cross.serial") {
            facts.append(EvidenceFact(
                markerID: "serial.cross.\(issue.id)",
                title: "Cross-Board-SN",
                source: issue.boards.joined(separator: "/"),
                register: "SN 0x10",
                rawValue: issue.detail,
                interpretedValue: issue.detail,
                expectedValue: "konsistente Fahrzeug-SN",
                persistence: .persistent,
                resetResistant: true,
                confidence: 0.85,
                knowledgeSource: .heuristic,
                knownModMatchId: "cross.serial.mismatch",
                knownStockMatch: false
            ))
        }

        var correlations: [String] = []
        var results = facts.map { classify($0, profile: profile) }

        // Korrelationen + Gewichtsanhebung
        results = applyCorrelations(results, correlations: &correlations)

        // Neutralisierungen (explizit pro Result)
        results = applyNeutralizations(results, reading: reading, profile: profile)

        let temporal = temporalDeltas(current: reading, prior: priorReading, priorProtocol: priorProtocolNumber)
        let fingerprint = baselineFingerprint(reading: reading, profile: profile)
        let unknown = unknownRegisters(in: reading)

        let verdict = ruleBasedVerdict(results: results, correlations: correlations, powerCycle: powerCycle)
        let score = densifyScore(results)
        let decisive = decisiveEvidence(from: results, verdict: verdict, correlations: correlations)
        var warnings: [String] = []
        if results.contains(where: { $0.fact.knowledgeSource == .heuristic && $0.classification.rank >= 2 }) {
            warnings.append("Mindestens ein Indiz beruht auf Heuristik — Belastbarkeit prüfen.")
        }
        if let pc = powerCycle, pc.rows.contains(where: { $0.observedPersistence != $0.catalogPersistence && $0.catalogPersistence != nil }) {
            warnings.append("Beobachtete Persistenz weicht vom Katalog ab — siehe Power-Cycle-Diff.")
        }

        return EvidenceAssessment(
            catalogVersion: EvidenceCatalog.version,
            results: results,
            verdict: verdict,
            score: score,
            decisiveEvidence: decisive,
            warnings: warnings,
            shortVerdictText: verdict.laymanText,
            correlations: correlations,
            temporalDeltas: temporal,
            crossBoardIssues: cross,
            fingerprint: fingerprint,
            unknownRegisters: unknown,
            powerCycle: powerCycle
        )
    }

    // MARK: Collect facts (no scoring)

    private static func collectFacts(
        reading: IntegrityReading,
        profile: ScooterProfile,
        priorUnlock: PriorUnlockEvidence?
    ) -> [EvidenceFact] {
        var facts: [EvidenceFact] = []
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let rated = profile.ratedMaxKmh
        let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
        let custom = CustomFirmwareDiff.analyze(reading: reading, profile: profile)
        let limit = reading.speedLimitKmh ?? reading.speedMaxKmh
        let peak = reading.peakSpeedKmh
        let sessionUnlock = reading.hiddenTuningDetected == true
            || (limit ?? 0) >= threshold
            || (peak ?? 0) >= threshold

        if region == .us {
            let sn = reading.serialDisplay ?? reading.serialVcu ?? "—"
            facts.append(EvidenceFact(
                markerID: "region.sn",
                title: "SN-Region",
                source: "VCU/DIS",
                register: "SN 0x10",
                rawValue: rawHex(forNames: ["vcu_g3_sn", "dis_sn", "vcu_sn"], in: reading) ?? sn,
                interpretedValue: "US-Region (\(sn))",
                expectedValue: profile.market == .de20 ? "DE (1CGB…)" : "EU / marktüblich",
                persistence: .persistent,
                resetResistant: true,
                confidence: 0.92,
                knowledgeSource: .referenceVehicle,
                knownModMatchId: profile.market == .de20 ? "region.us.1CGC.on_de_profile" : nil,
                knownStockMatch: profile.market != .de20
            ))
        }

        if let limit, limit > rated + 1 {
            facts.append(EvidenceFact(
                markerID: "speed.limit",
                title: "Gespeichertes Limit",
                source: "VCU",
                register: "maxSpeed 0x46",
                rawValue: rawHex(forNames: ["vcu_g3_maxspd", "dis_limit", "vcu_g3_edmax"], in: reading)
                    ?? Format.kmh.format(Optional(limit)),
                interpretedValue: Format.kmh.format(Optional(limit)),
                expectedValue: "≤ \(Format.kmh.format(Optional(rated)))",
                persistence: .persistent,
                resetResistant: true,
                confidence: 0.88,
                knowledgeSource: .referenceVehicle,
                knownModMatchId: limit >= profile.tuningClearKmh ? "speed.limit.over_clear" : "speed.limit.over_rated",
                knownStockMatch: false
            ))
        }

        if let peak, peak > rated + 1 {
            facts.append(EvidenceFact(
                markerID: "speed.peak",
                title: "Trip-Spitze",
                source: "DIS/VCU",
                register: "rSigMaxSpeed 0x24",
                rawValue: rawHex(forNames: ["dis_trip_max", "vcu_g3_trip_max", "tft_trip_max"], in: reading)
                    ?? Format.kmh.format(Optional(peak)),
                interpretedValue: Format.kmh.format(Optional(peak)),
                expectedValue: "≤ \(Format.kmh.format(Optional(rated)))",
                persistence: .semiPersistent,
                resetResistant: false,
                confidence: 0.8,
                knowledgeSource: .heuristic,
                knownModMatchId: peak >= profile.tuningClearKmh ? "speed.peak.over_clear" : "speed.peak.over_rated",
                knownStockMatch: false
            ))
        }

        if sessionUnlock {
            facts.append(EvidenceFact(
                markerID: "speed.session",
                title: "Session-Unlock",
                source: "VCU",
                register: "Limit/Peak Session",
                rawValue: rawHex(forNames: ["vcu_g3_maxspd", "dis_trip_max"], in: reading) ?? "session",
                interpretedValue: "Session-Tempo ≥ \(Int(threshold)) km/h",
                expectedValue: "inaktiv nach Ausschalten",
                persistence: .fleeting,
                resetResistant: false,
                confidence: 0.75,
                knowledgeSource: .heuristic,
                knownModMatchId: "speed.session.unlock",
                knownStockMatch: nil
            ))
        }

        switch custom.level {
        case .confirmed:
            facts.append(EvidenceFact(
                markerID: "fw.custom",
                title: "Custom-/Mod-Firmware",
                source: "MCU/BLE/BMS/VCU",
                register: "Versionsregister",
                rawValue: fwRawCitation(reading),
                interpretedValue: custom.summaryLine,
                expectedValue: "Serienkatalog \(profile.shortLabel)",
                persistence: .persistent,
                resetResistant: true,
                confidence: 0.93,
                knowledgeSource: .verifiedModSample,
                knownModMatchId: "fw.custom.confirmed",
                knownStockMatch: false
            ))
        case .suspected:
            facts.append(EvidenceFact(
                markerID: "fw.unknown",
                title: "Unbekannter Firmwarestand",
                source: "MCU/VCU",
                register: "Versionsregister",
                rawValue: fwRawCitation(reading),
                interpretedValue: custom.summaryLine,
                expectedValue: "Serienkatalog \(profile.shortLabel)",
                persistence: .persistent,
                resetResistant: true,
                confidence: 0.65,
                knowledgeSource: .heuristic,
                knownModMatchId: nil,
                knownStockMatch: false
            ))
        case .none:
            break
        }

        if let gear = reading.gearMax, gear > 1 {
            facts.append(EvidenceFact(
                markerID: "gear.max",
                title: "Gangfreigabe",
                source: "VCU",
                register: "gearMode",
                rawValue: rawHex(forNames: ["vcu_g3_gear", "vcu_g3_sgear"], in: reading) ?? "\(gear)",
                interpretedValue: "max. Gang \(gear)",
                expectedValue: "1",
                persistence: .persistent,
                resetResistant: true,
                confidence: 0.8,
                knowledgeSource: .referenceVehicle,
                knownModMatchId: "gear.max.unlocked",
                knownStockMatch: false
            ))
        }

        if reading.safeLockActive == false {
            facts.append(EvidenceFact(
                markerID: "safelock",
                title: "SafeLock",
                source: "MCU/VCU",
                register: "speedSafeLock",
                rawValue: rawHex(forNames: ["mcu_safe", "vcu_g3_safe"], in: reading) ?? "0",
                interpretedValue: "inaktiv",
                expectedValue: "aktiv",
                persistence: .persistent,
                resetResistant: true,
                confidence: 0.7,
                knowledgeSource: .heuristic,
                knownModMatchId: nil,
                knownStockMatch: false
            ))
        }

        if let prior = priorUnlock, prior.showsUnlock(threshold: threshold), !sessionUnlock {
            facts.append(EvidenceFact(
                markerID: "session.reset",
                title: "Session nach Ausschalten",
                source: "Verlauf",
                register: "Protokollvergleich",
                rawValue: prior.protocolNumber,
                interpretedValue: "früher \(Format.kmh.format(Optional(prior.observedTempoKmh))), jetzt Session weg",
                expectedValue: "kein Vorher-Unlock nötig",
                persistence: .fleeting,
                resetResistant: false,
                confidence: 0.82,
                knowledgeSource: .referenceVehicle,
                knownModMatchId: "session.reset.after_poweroff",
                knownStockMatch: nil
            ))
        }

        return facts
    }

    private static func classify(_ fact: EvidenceFact, profile: ScooterProfile) -> EvidenceResult {
        let initial: EvidenceClass
        switch fact.markerID {
        case "fw.custom":
            initial = .starkerHinweis
        case "region.sn":
            initial = profile.market == .de20 ? .indiz : .info
        case "speed.limit", "speed.peak":
            let overClear: Bool = {
                if fact.markerID == "speed.limit",
                   let v = readingSpeed(from: fact.interpretedValue), v >= profile.tuningClearKmh { return true }
                if fact.markerID == "speed.peak",
                   let v = readingSpeed(from: fact.interpretedValue), v >= profile.tuningClearKmh { return true }
                return fact.knownModMatchId?.contains("over_clear") == true
            }()
            initial = overClear ? .indiz : .abweichung
        case "speed.session", "gear.max", "safelock", "fw.unknown", "session.reset":
            initial = fact.markerID == "session.reset" && fact.knownModMatchId != nil ? .indiz : .abweichung
        case let id where id.hasPrefix("serial.cross"):
            initial = .indiz
        default:
            initial = .info
        }

        let weight: Int
        switch initial {
        case .info: weight = 0
        case .abweichung: weight = Int(10.0 * fact.confidence)
        case .indiz: weight = Int(22.0 * fact.confidence)
        case .starkerHinweis: weight = Int(40.0 * fact.confidence)
        }

        return EvidenceResult(
            fact: fact,
            classification: initial,
            classBeforeNeutralization: initial,
            weight: weight,
            correlations: [],
            neutralizations: [],
            explanation: "\(fact.title): \(fact.interpretedValue ?? fact.rawValue) (Soll \(fact.expectedValue ?? "—"))"
        )
    }

    private static func readingSpeed(from text: String?) -> Double? {
        guard let text else { return nil }
        let num = text.replacingOccurrences(of: ",", with: ".")
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .first
        return num.flatMap { Double($0) }
    }

    private static func applyCorrelations(
        _ results: [EvidenceResult],
        correlations: inout [String]
    ) -> [EvidenceResult] {
        let ids = Set(results.map(\.fact.markerID))
        var out = results

        func bump(_ id: String, to cls: EvidenceClass, corr: String) {
            guard let idx = out.firstIndex(where: { $0.fact.markerID == id }) else { return }
            let r = out[idx]
            guard cls.rank > r.classification.rank else { return }
            correlations.append(corr)
            out[idx] = EvidenceResult(
                fact: r.fact,
                classification: cls,
                classBeforeNeutralization: r.classBeforeNeutralization,
                weight: max(r.weight, cls.scorePoints),
                correlations: r.correlations + [corr],
                neutralizations: r.neutralizations,
                explanation: r.explanation + " · Korrelation: \(corr)"
            )
        }

        if ids.contains("region.sn"), ids.contains("speed.limit") || ids.contains("speed.peak") {
            let corr = "US-Region + erhöhtes Tempo"
            bump("region.sn", to: .starkerHinweis, corr: corr)
            bump("speed.limit", to: .starkerHinweis, corr: corr)
        }
        if ids.contains("fw.custom"), ids.contains("speed.limit") || ids.contains("speed.peak") {
            let corr = "Custom-FW + Tempo-Marker"
            bump("speed.limit", to: .starkerHinweis, corr: corr)
            bump("speed.peak", to: .starkerHinweis, corr: corr)
        }
        if ids.contains("speed.limit"),
           !ids.contains("region.sn"),
           !ids.contains("fw.custom"),
           !ids.contains("speed.peak") {
            let corr = "Isoliertes Limit — keine Automatik-Eindeutigkeit"
            correlations.append(corr)
            if let idx = out.firstIndex(where: { $0.fact.markerID == "speed.limit" }) {
                let r = out[idx]
                out[idx] = EvidenceResult(
                    fact: r.fact,
                    classification: .abweichung,
                    classBeforeNeutralization: r.classBeforeNeutralization,
                    weight: min(r.weight, 12),
                    correlations: r.correlations + [corr],
                    neutralizations: r.neutralizations,
                    explanation: r.explanation + " · \(corr)"
                )
            }
        }
        return out
    }

    private static func applyNeutralizations(
        _ results: [EvidenceResult],
        reading: IntegrityReading,
        profile: ScooterProfile
    ) -> [EvidenceResult] {
        results.map { result in
            var r = result
            if r.fact.markerID == "region.sn" {
                let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
                guard region == .us else { return r }
                let limit = reading.speedLimitKmh ?? reading.speedMaxKmh ?? 0
                let peak = reading.peakSpeedKmh ?? 0
                let tempoOk = limit <= profile.ratedMaxKmh + 1 && peak <= profile.ratedMaxKmh + 1
                let fw = StockFirmwareCatalog.analyze(reading: reading, profile: profile)
                let fwPlausible = fw.notInCatalogCount == 0 && fw.customCount == 0
                let sn = (reading.serialDisplay ?? reading.serialVcu ?? "").uppercased()
                let usShape = sn.hasPrefix("1CGC")

                if profile.market == .de20, usShape, tempoOk, fwPlausible {
                    let record = NeutralizationRecord(
                        ruleId: "REGION_US_STOCK_PROFILE",
                        reason: "Fahrzeug-/Firmwarevariante entspricht plausibler US-Konfiguration (1CGC, Serien-FW, Limit/Peak ≤ Typ). Kein Beitrag zum Manipulationsurteil.",
                        classBefore: r.classBeforeNeutralization,
                        classAfter: .abweichung
                    )
                    r = EvidenceResult(
                        fact: r.fact,
                        classification: .abweichung,
                        classBeforeNeutralization: r.classBeforeNeutralization,
                        weight: 0,
                        correlations: r.correlations,
                        neutralizations: r.neutralizations + [record],
                        explanation: """
                        Region 1CGC erkannt → zunächst \(r.classBeforeNeutralization.label). \
                        Neutralisiert (\(record.ruleId)): \(record.reason) \
                        Finale Klasse: \(record.classAfter.label). Beitrag Urteil: keiner.
                        """
                    )
                } else if profile.market != .de20, usShape, tempoOk {
                    let record = NeutralizationRecord(
                        ruleId: "REGION_US_MATCHES_MARKET",
                        reason: "Marktprofil nicht DE — US-Region zum Profil passend.",
                        classBefore: r.classBeforeNeutralization,
                        classAfter: .info
                    )
                    r = EvidenceResult(
                        fact: r.fact,
                        classification: .info,
                        classBeforeNeutralization: r.classBeforeNeutralization,
                        weight: 0,
                        correlations: r.correlations,
                        neutralizations: [record],
                        explanation: r.explanation + " · Neutralisiert: \(record.reason)"
                    )
                }
            }
            return r
        }
    }

    /// Harte Regeln — Score spielt keine Rolle.
    private static func ruleBasedVerdict(
        results: [EvidenceResult],
        correlations: [String],
        powerCycle: PowerCycleReport?
    ) -> VerdictLevel {
        let contributing = results.filter(\.contributesToVerdict)
        let stark = contributing.filter { $0.classification == .starkerHinweis }
        let indiz = contributing.filter { $0.classification == .indiz }
        let abweichung = contributing.filter { $0.classification == .abweichung }
        let persistentIndiz = contributing.filter {
            $0.fact.persistence == .persistent && $0.classification.rank >= EvidenceClass.indiz.rank
        }
        _ = powerCycle

        // Technisch nachgewiesene Manipulation — niemals aus Score allein.
        if stark.contains(where: { $0.fact.markerID == "fw.custom" }) { return .eindeutig }
        if stark.count >= 1, correlations.contains(where: { $0.contains("Custom-FW") || $0.contains("US-Region +") }) {
            return .eindeutig
        }
        if persistentIndiz.count >= 3, stark.count + indiz.count >= 3 { return .eindeutig }

        // Manipulationshinweis
        if !stark.isEmpty { return .hinweise }
        if indiz.filter({ $0.fact.persistence == .persistent }).count >= 2 { return .hinweise }
        if indiz.count >= 1, abweichung.count >= 2 { return .hinweise }
        if indiz.count >= 2 { return .hinweise }

        // Auffällig
        if !abweichung.isEmpty || !indiz.isEmpty { return .auffaellig }

        return .stock
    }

    private static func densifyScore(_ results: [EvidenceResult]) -> Int {
        var suspicion = 0
        for r in results where r.contributesToVerdict {
            suspicion += Int(Double(r.classification.scorePoints) * (Double(r.weight) / 40.0).clamped(to: 0...1.5))
        }
        return min(100, max(0, 100 - min(100, suspicion)))
    }

    private static func decisiveEvidence(
        from results: [EvidenceResult],
        verdict: VerdictLevel,
        correlations: [String]
    ) -> [String] {
        var lines: [String] = []
        for r in results.filter(\.contributesToVerdict).prefix(8) {
            lines.append("\(r.fact.title): \(r.fact.interpretedValue ?? r.fact.rawValue) [\(r.classification.label)]")
        }
        for n in results.flatMap(\.neutralizations).prefix(4) {
            lines.append("Neutralisiert \(n.ruleId): \(n.classBefore.label) → \(n.classAfter.label)")
        }
        lines.append(contentsOf: correlations.prefix(3))
        if verdict == .stock { lines.insert("Keine relevanten Evidenzen", at: 0) }
        return lines
    }

    // MARK: - UI facts (Anzeige der Engine-Ausgabe, keine Neubewertung)

    static func buildFacts(_ assessment: EvidenceAssessment) -> [MeasuredFact] {
        var facts: [MeasuredFact] = []
        facts.append(MeasuredFact(
            id: "evidence.summary",
            group: .evidence,
            title: "Kurzurteil",
            auslesewert: assessment.verdict.label,
            sollwert: VerdictLevel.stock.label,
            status: {
                switch assessment.verdict {
                case .stock: return .regelkonform
                case .auffaellig: return .abweichend
                case .hinweise, .eindeutig: return .erheblichAbweichend
                }
            }(),
            bewertung: assessment.summary,
            erlaeuterung: """
            Katalog v\(assessment.catalogVersion). Urteil regelbasiert; Score \(assessment.score) nur Verdichtung. \
            \(assessment.shortVerdictText)
            """,
            raw: "catalog=\(assessment.catalogVersion);sha=\(assessment.fingerprint.digestSHA256)",
            volatility: .persistent,
            evidenceClass: assessment.starkerHinweisCount > 0 ? .starkerHinweis : (assessment.indizCount > 0 ? .indiz : .info),
            sourceBoard: "EvidenceEngine",
            sourceRegister: "verdict",
            rawHex: nil,
            resetsOnPowerOff: false
        ))

        for (idx, line) in assessment.decisiveEvidence.enumerated() {
            facts.append(MeasuredFact(
                id: "evidence.decisive.\(idx)",
                group: .evidence,
                title: "Entscheidende Evidenz",
                auslesewert: line,
                sollwert: "—",
                status: .abweichend,
                bewertung: "decisiveEvidence",
                erlaeuterung: line,
                raw: line
            ))
        }

        for r in assessment.results {
            facts.append(MeasuredFact(
                id: "evidence.\(r.fact.markerID)",
                group: .evidence,
                title: "\(r.fact.title) [\(r.fact.persistence.label)]",
                auslesewert: r.fact.interpretedValue ?? r.fact.rawValue,
                sollwert: r.fact.expectedValue ?? "—",
                status: r.isNeutralized ? .regelkonform : status(for: r.classification),
                bewertung: r.contributionLabel,
                erlaeuterung: r.chainCitation,
                raw: r.chainCitation,
                volatility: r.fact.persistence,
                evidenceClass: r.classification,
                sourceBoard: r.fact.source,
                sourceRegister: r.fact.register,
                rawHex: r.fact.rawValue,
                resetsOnPowerOff: r.fact.resetResistant == false
            ))
        }

        if let pc = assessment.powerCycle {
            facts.append(MeasuredFact(
                id: "evidence.powercycle.summary",
                group: .evidence,
                title: "Power-Cycle-Test",
                auslesewert: pc.summary,
                sollwert: "Katalog-Persistenz vs. beobachtet",
                status: .regelkonform,
                bewertung: "\(pc.rows.count) Marker verglichen",
                erlaeuterung: pc.summary,
                raw: pc.summary
            ))
            for row in pc.rows {
                facts.append(MeasuredFact(
                    id: "evidence.powercycle.\(row.markerID)",
                    group: .evidence,
                    title: "Power-Cycle: \(row.title)",
                    auslesewert: "A \(row.scanA) → B \(row.scanB)",
                    sollwert: row.catalogPersistence?.label ?? "—",
                    status: .regelkonform,
                    bewertung: "beobachtet \(row.observedPersistence.label)",
                    erlaeuterung: row.note,
                    raw: "\(row.scanA)|\(row.scanB)",
                    volatility: row.observedPersistence,
                    evidenceClass: .info,
                    sourceBoard: "PowerCycle",
                    sourceRegister: row.markerID,
                    rawHex: nil,
                    resetsOnPowerOff: row.observedPersistence == .fleeting
                ))
            }
        }

        for (idx, w) in assessment.warnings.enumerated() {
            facts.append(MeasuredFact(
                id: "evidence.warn.\(idx)",
                group: .evidence,
                title: "Hinweis",
                auslesewert: w,
                sollwert: "—",
                status: .nichtFeststellbar,
                bewertung: "warning",
                erlaeuterung: w,
                raw: w,
                evidenceClass: .info
            ))
        }

        for delta in assessment.temporalDeltas {
            facts.append(MeasuredFact(
                id: delta.id,
                group: .evidence,
                title: "Historie: \(delta.title)",
                auslesewert: "\(delta.previous) → \(delta.current)",
                sollwert: "unverändert",
                status: .abweichend,
                bewertung: delta.priorProtocol,
                erlaeuterung: "Zeitlicher Vergleich derselben SN.",
                raw: delta.priorProtocol,
                volatility: .persistent,
                evidenceClass: .indiz
            ))
        }

        facts.append(MeasuredFact(
            id: "evidence.fingerprint",
            group: .evidence,
            title: "Baseline-Fingerprint",
            auslesewert: String(assessment.fingerprint.digestSHA256.prefix(16)) + "…",
            sollwert: assessment.fingerprint.profileId,
            status: .regelkonform,
            bewertung: "Katalog v\(assessment.catalogVersion)",
            erlaeuterung: assessment.fingerprint.digestSHA256,
            raw: assessment.fingerprint.digestSHA256,
            evidenceClass: .info
        ))

        return facts
    }

    private static func status(for cls: EvidenceClass) -> FactStatus {
        switch cls {
        case .info: return .nichtFeststellbar
        case .abweichung, .indiz: return .abweichend
        case .starkerHinweis: return .erheblichAbweichend
        }
    }

    // Shared helpers (cross-board, temporal, fingerprint, unknown)
    static func crossBoardIssues(reading: IntegrityReading, profile: ScooterProfile) -> [CrossBoardIssue] {
        var issues: [CrossBoardIssue] = []
        let vehicle = reading.serialDisplay ?? reading.serialVcu
        let pairs: [(String, String?)] = [
            ("VCU", reading.serialVcu), ("MCU", reading.serialMcu),
            ("BLE", reading.serialBle), ("BMS", reading.serialBms), ("DIS", reading.serialDisplay)
        ]
        if let vehicle {
            for (board, sn) in pairs {
                guard let sn, !sn.isEmpty, !TrackClassifier.looksLikeModuleSerial(sn) else { continue }
                if TrackClassifier.serialsMismatch(sn, vehicle) {
                    issues.append(CrossBoardIssue(
                        id: "cross.serial.\(board.lowercased())",
                        title: "SN \(board) ≠ Fahrzeug",
                        detail: "\(board)-SN \(sn) ≠ \(vehicle)",
                        boards: [board, "Fahrzeug"]
                    ))
                }
            }
        }
        _ = profile
        return issues
    }

    static func temporalDeltas(
        current: IntegrityReading,
        prior: IntegrityReading?,
        priorProtocol: String?
    ) -> [TemporalDelta] {
        guard let prior, let proto = priorProtocol else { return [] }
        var deltas: [TemporalDelta] = []
        func add(_ id: String, _ title: String, _ a: String?, _ b: String?) {
            let l = a ?? "—"; let r = b ?? "—"
            guard l != r else { return }
            deltas.append(TemporalDelta(id: "history.delta.\(id)", title: title, previous: l, current: r, priorProtocol: proto))
        }
        add("region", "Region",
            TrackClassifier.serialRegion(for: prior.serialDisplay ?? prior.serialVcu).label,
            TrackClassifier.serialRegion(for: current.serialDisplay ?? current.serialVcu).label)
        add("fw.mcu", "MCU-FW", prior.fwMcu, current.fwMcu)
        add("fw.vcu", "VCU-FW", prior.fwVcu, current.fwVcu)
        add("limit", "Limit",
            prior.speedLimitKmh.map { Format.kmh.format(Optional($0)) },
            current.speedLimitKmh.map { Format.kmh.format(Optional($0)) })
        add("peak", "Trip-Peak",
            prior.peakSpeedKmh.map { Format.kmh.format(Optional($0)) },
            current.peakSpeedKmh.map { Format.kmh.format(Optional($0)) })
        add("gear", "Max-Gang", prior.gearMax.map(String.init), current.gearMax.map(String.init))
        return deltas
    }

    static func baselineFingerprint(reading: IntegrityReading, profile: ScooterProfile) -> BaselineFingerprint {
        let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
        let fields: [String: String] = [
            "profile": profile.id, "region": region.rawValue,
            "snPrefix": String((reading.serialDisplay ?? reading.serialVcu ?? "").prefix(4)),
            "fwMcu": reading.fwMcu ?? "", "fwBle": reading.fwBle ?? "",
            "fwBms": reading.fwBms ?? "", "fwVcu": reading.fwVcu ?? "",
            "limit": reading.speedLimitKmh.map { String(format: "%.1f", $0) } ?? "",
            "gearMax": reading.gearMax.map(String.init) ?? ""
        ]
        let canonical = fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return BaselineFingerprint(profileId: profile.id, digestSHA256: digest, fields: fields)
    }

    static func unknownRegisters(in reading: IntegrityReading) -> [RawRegister] {
        let known = ["dis_", "ble_", "vcu_", "mcu_", "bms_", "g3_", "tft_", "esc_"]
        return reading.rawRegisters.filter { reg in
            let empty = reg.valueDecoded == nil || reg.valueDecoded?.isEmpty == true
            let looks = known.contains { reg.name.lowercased().hasPrefix($0) }
            return empty && !looks && !reg.valueHex.isEmpty
        }
    }

    private static func rawHex(forNames names: [String], in reading: IntegrityReading) -> String? {
        for name in names {
            if let reg = reading.rawRegisters.last(where: { $0.name == name }) {
                return "\(reg.name) \(reg.address)=\(reg.valueHex)"
            }
        }
        return nil
    }

    private static func fwRawCitation(_ reading: IntegrityReading) -> String {
        let names = ["g3_mcu_fw", "g3_vcu_fw", "g3_ble_fw", "g3_bms_fw", "mcu_fw", "ble_fw", "vcu_fw"]
        let parts = names.compactMap { name -> String? in
            reading.rawRegisters.last(where: { $0.name == name }).map { "\($0.name)=\($0.valueHex)" }
        }
        return parts.isEmpty ? (reading.fwMcu ?? reading.fwVcu ?? "—") : parts.joined(separator: ", ")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Power-Cycle comparison (beobachtete Persistenz)

enum PowerCycleAnalyzer {
    static func compare(
        scanA: IntegrityReading,
        scanB: IntegrityReading,
        profile: ScooterProfile = .maxG3D
    ) -> PowerCycleReport {
        func fmt(_ v: Double?) -> String { v.map { Format.kmh.format(Optional($0)) } ?? "—" }
        func fmtI(_ v: Int?) -> String { v.map(String.init) ?? "—" }
        func fmtS(_ v: String?) -> String { (v?.isEmpty == false) ? v! : "—" }

        let pairs: [(id: String, title: String, a: String, b: String, catalog: PersistenceClass?)] = [
            ("speed.limit", "Speed Limit",
             fmt(scanA.speedLimitKmh ?? scanA.speedMaxKmh),
             fmt(scanB.speedLimitKmh ?? scanB.speedMaxKmh), .persistent),
            ("speed.peak", "Trip Peak",
             fmt(scanA.peakSpeedKmh), fmt(scanB.peakSpeedKmh), .semiPersistent),
            ("speed.session", "Session Flag",
             (scanA.hiddenTuningDetected == true) ? "1" : "0",
             (scanB.hiddenTuningDetected == true) ? "1" : "0", .fleeting),
            ("region.sn", "Region",
             TrackClassifier.serialRegion(for: scanA.serialDisplay ?? scanA.serialVcu).label,
             TrackClassifier.serialRegion(for: scanB.serialDisplay ?? scanB.serialVcu).label, .persistent),
            ("gear.mode", "Drive Mode",
             fmtI(scanA.gearMode), fmtI(scanB.gearMode), .fleeting),
            ("fw.hash", "Firmware Hash",
             String(EvidenceEngine.baselineFingerprint(reading: scanA, profile: profile).digestSHA256.prefix(12)) + "…",
             String(EvidenceEngine.baselineFingerprint(reading: scanB, profile: profile).digestSHA256.prefix(12)) + "…",
             .persistent),
            ("fw.mcu", "MCU-FW", fmtS(scanA.fwMcu), fmtS(scanB.fwMcu), .persistent),
            ("fw.vcu", "VCU-FW", fmtS(scanA.fwVcu), fmtS(scanB.fwVcu), .persistent)
        ]

        let rows: [PowerCycleDiffRow] = pairs.map { p in
            let same = p.a == p.b
            let observed: PersistenceClass = same ? .persistent : .fleeting
            let note: String
            if same {
                note = "Unverändert nach Power-Cycle → beobachtet persistent"
                    + (p.catalog.map { $0 == .persistent ? " (Katalog bestätigt)" : " (Katalog: \($0.label))" } ?? "")
            } else {
                note = "Geändert A→B → beobachtet flüchtig"
                    + (p.catalog.map { $0 == .fleeting ? " (Katalog bestätigt)" : " (Katalog erwartete \($0.label))" } ?? "")
            }
            return PowerCycleDiffRow(
                markerID: p.id,
                title: p.title,
                scanA: String(p.a),
                scanB: String(p.b),
                observedPersistence: observed,
                catalogPersistence: p.catalog,
                note: note
            )
        }

        let persistCount = rows.filter { $0.observedPersistence == .persistent }.count
        let fleetingCount = rows.filter { $0.observedPersistence == .fleeting }.count
        let summary = "Power-Cycle: \(persistCount) persistent, \(fleetingCount) flüchtig beobachtet (Katalog v\(EvidenceCatalog.version))"
        return PowerCycleReport(rows: rows, summary: summary)
    }
}
