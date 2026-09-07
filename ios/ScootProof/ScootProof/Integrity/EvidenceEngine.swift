import Foundation
import CryptoKit

// MARK: - Persistence & evidence classes

/// Wie lange ein Marker typischerweise sichtbar bleibt.
enum MarkerVolatility: String, Codable, CaseIterable, Sendable {
    case fleeting = "flüchtig"
    case semiPersistent = "semi-persistent"
    case persistent = "persistent"

    var label: String { rawValue }

    var resetsOnPowerOffHint: String {
        switch self {
        case .fleeting: return "meist weg nach Ausschalten"
        case .semiPersistent: return "oft weg nach Trip-Reset/Panic, teils nach Ausschalten"
        case .persistent: return "bleibt nach normalem Ausschalten typischerweise sichtbar"
        }
    }
}

/// Vier Beweisstufen — Score verdichtet nur, Urteil bleibt regelbasiert.
enum EvidenceClass: String, Codable, CaseIterable, Sendable {
    case info = "Info"
    case abweichung = "Abweichung"
    case indiz = "Manipulationsindiz"
    case starkerHinweis = "starker Manipulationshinweis"

    var label: String { rawValue }

    /// Beitrag zur Score-Verdichtung (nicht allein urteilsbildend).
    var scoreDelta: Int {
        switch self {
        case .info: return 0
        case .abweichung: return 6
        case .indiz: return 14
        case .starkerHinweis: return 28
        }
    }

    var rank: Int {
        switch self {
        case .info: return 0
        case .abweichung: return 1
        case .indiz: return 2
        case .starkerHinweis: return 3
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
        default:
            self = EvidenceClass(rawValue: raw) ?? .info
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Canonical marker object

/// Interne Feststellung: Quelle → Rohwert → Interpretation → Persistenz → Gewicht → Urteilbeitrag.
struct EvidenceMarker: Identifiable, Codable, Hashable, Sendable {
    var id: String { markerId }

    let markerId: String
    let title: String
    let boardSource: String
    let registerOrField: String
    let rawValue: String
    let interpretedValue: String
    let expectedValue: String
    let persistenceClass: MarkerVolatility
    /// 0…1 — Lesesicherheit / Deutungssicherheit.
    let confidence: Double
    let evidenceClass: EvidenceClass
    /// Relatives Gewicht innerhalb der Klasse (0…1), vor Neutralisierung.
    let weight: Double
    let knownStockMatch: Bool?
    let knownModMatch: Bool?
    let notes: String
    /// True wenn durch Gegenbelege neutralisiert (z. B. plausible US-Serie).
    let neutralized: Bool
    let neutralizationReason: String?

    /// Wirksames Gewicht nach Neutralisierung.
    var effectiveWeight: Double { neutralized ? 0 : weight }

    var contributionLabel: String {
        if neutralized {
            return "neutralisiert (\(neutralizationReason ?? "Gegenbeleg"))"
        }
        return "\(evidenceClass.label) · Gewicht \(String(format: "%.2f", effectiveWeight))"
    }

    /// Kette Quelle → Rohwert → Interpretation → Persistenz → Beweisgewicht.
    var chainCitation: String {
        [
            "Quelle: \(boardSource) / \(registerOrField)",
            "Rohwert: \(rawValue.isEmpty ? "—" : rawValue)",
            "Interpretation: \(interpretedValue)",
            "Persistenz: \(persistenceClass.label)",
            "Beweis: \(contributionLabel)",
            "Soll: \(expectedValue)"
        ].joined(separator: " · ")
    }

    /// Alias für ältere PDF-/UI-Pfade.
    var rawCitation: String { chainCitation }

    var resetsOnPowerOff: Bool { persistenceClass != .persistent }
}

// MARK: - Engine result (UI-entkoppelt)

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

/// Verdichtung für Score — erzeugt allein kein Urteil.
struct EvidenceScoreBreakdown: Codable, Hashable, Sendable {
    let rawScore: Int
    /// 0 = keine Auffälligkeit, 100 = maximale Verdichtung.
    let suspicionIndex: Int
    let activeMarkerCount: Int
    let neutralizedCount: Int
}

struct EvidenceEngineResult: Codable, Hashable, Sendable {
    /// Ebene 1 — Kurzurteil (regelbasiert).
    let verdict: VerdictLevel
    let shortVerdictText: String
    /// Ebene 2 — begründende Marker (nicht neutralisiert, rank ≥ Abweichung).
    let justifyingMarkers: [EvidenceMarker]
    /// Alle Marker inkl. Info / neutralisiert.
    let markers: [EvidenceMarker]
    let correlations: [String]
    let neutralizationNotes: [String]
    let temporalDeltas: [TemporalDelta]
    let crossBoardIssues: [CrossBoardIssue]
    let fingerprint: BaselineFingerprint
    let unknownRegisters: [RawRegister]
    let score: EvidenceScoreBreakdown
    /// Kompatibilität: Verdachtsscore 0…100 (höher = unauffälliger, wie bisher).
    var integrityScore: Int { score.rawScore }

    var infoCount: Int { markers.filter { $0.evidenceClass == .info }.count }
    var abweichungCount: Int { markers.filter { !$0.neutralized && $0.evidenceClass == .abweichung }.count }
    var indizCount: Int { markers.filter { !$0.neutralized && $0.evidenceClass == .indiz }.count }
    var starkerHinweisCount: Int { markers.filter { !$0.neutralized && $0.evidenceClass == .starkerHinweis }.count }
    var persistentHitCount: Int {
        markers.filter { !$0.neutralized && $0.persistenceClass == .persistent && $0.evidenceClass.rank >= EvidenceClass.abweichung.rank }.count
    }

    var summary: String {
        "\(starkerHinweisCount)× starker Hinweis · \(indizCount)× Indiz · \(abweichungCount)× Abweichung · \(score.neutralizedCount)× neutralisiert → \(verdict.label)"
    }

    static let empty = EvidenceEngineResult(
        verdict: .stock,
        shortVerdictText: VerdictLevel.stock.laymanText,
        justifyingMarkers: [],
        markers: [],
        correlations: [],
        neutralizationNotes: [],
        temporalDeltas: [],
        crossBoardIssues: [],
        fingerprint: BaselineFingerprint(profileId: "", digestSHA256: "", fields: [:]),
        unknownRegisters: [],
        score: EvidenceScoreBreakdown(rawScore: 100, suspicionIndex: 0, activeMarkerCount: 0, neutralizedCount: 0)
    )
}

/// Rückwärtskompatibles Alias für IntegrityResult.evidence.
typealias EvidenceAssessment = EvidenceEngineResult

extension EvidenceEngineResult {
    var hits: [EvidenceMarker] { markers }
    var suggestedVerdict: VerdictLevel { verdict }
    var nachweisCount: Int { starkerHinweisCount }
}

// MARK: - Catalog entry

struct MarkerCatalogEntry: Sendable, Hashable {
    let markerId: String
    let title: String
    let boardSource: String
    let registerOrField: String
    let persistence: MarkerVolatility
    let defaultClass: EvidenceClass
    let stockHint: String
    let modHint: String?
}

// MARK: - EvidenceEngine

/// Eigenes Modul: Score verdichtet, Urteil regelbasiert — UI nur Anzeige.
enum EvidenceEngine {

    static let catalog: [MarkerCatalogEntry] = [
        .init(markerId: "region.sn", title: "SN-Region", boardSource: "VCU/DIS", registerOrField: "SN 0x10",
              persistence: .persistent, defaultClass: .indiz, stockHint: "DE 1CGB… / EU", modHint: "US 1CGC bei DE-Soll"),
        .init(markerId: "speed.limit", title: "Gespeichertes Limit", boardSource: "VCU", registerOrField: "maxSpeed 0x46",
              persistence: .persistent, defaultClass: .indiz, stockHint: "≤ Typgenehmigung", modHint: "> Typ dauerhaft"),
        .init(markerId: "speed.peak", title: "Trip-Spitze", boardSource: "DIS/VCU", registerOrField: "rSigMaxSpeed 0x24",
              persistence: .semiPersistent, defaultClass: .indiz, stockHint: "≤ Typ + Toleranz", modHint: "Peak ≫ Typ"),
        .init(markerId: "speed.session", title: "Session-Unlock", boardSource: "VCU", registerOrField: "Limit/Peak Session",
              persistence: .fleeting, defaultClass: .abweichung, stockHint: "inaktiv nach Ausschalten", modHint: nil),
        .init(markerId: "fw.custom", title: "Custom-/Mod-Firmware", boardSource: "MCU/BLE/BMS/VCU", registerOrField: "Versionsregister",
              persistence: .persistent, defaultClass: .starkerHinweis, stockHint: "Serienkatalog", modHint: "bekannte Mod-Version"),
        .init(markerId: "fw.unknown", title: "Unbekannter Firmwarestand", boardSource: "MCU/VCU", registerOrField: "Versionsregister",
              persistence: .persistent, defaultClass: .abweichung, stockHint: "bekannter Serienstand", modHint: nil),
        .init(markerId: "gear.max", title: "Gangfreigabe", boardSource: "VCU", registerOrField: "gearMode / s|e|dGear",
              persistence: .persistent, defaultClass: .abweichung, stockHint: "1", modHint: "> 1"),
        .init(markerId: "serial.cross", title: "Cross-Board-SN", boardSource: "VCU/MCU/BLE/BMS", registerOrField: "SN 0x10",
              persistence: .persistent, defaultClass: .indiz, stockHint: "konsistent", modHint: "Mismatch"),
        .init(markerId: "safelock", title: "SafeLock", boardSource: "MCU/VCU", registerOrField: "speedSafeLock",
              persistence: .persistent, defaultClass: .abweichung, stockHint: "aktiv", modHint: "inaktiv"),
        .init(markerId: "session.reset", title: "Session nach Ausschalten", boardSource: "Verlauf", registerOrField: "Protokollvergleich",
              persistence: .fleeting, defaultClass: .indiz, stockHint: "kein Vorher-Unlock", modHint: "früher Tempo, jetzt weg")
    ]

    static func evaluate(
        reading: IntegrityReading,
        profile: ScooterProfile,
        priorUnlock: PriorUnlockEvidence?,
        priorReading: IntegrityReading?,
        priorProtocolNumber: String?
    ) -> EvidenceEngineResult {
        var markers: [EvidenceMarker] = []
        var correlations: [String] = []
        var neutralizationNotes: [String] = []

        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let rated = profile.ratedMaxKmh
        let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
        let custom = CustomFirmwareDiff.analyze(reading: reading, profile: profile)
        let limit = reading.speedLimitKmh ?? reading.speedMaxKmh
        let peak = reading.peakSpeedKmh
        let sessionUnlock = reading.hiddenTuningDetected == true
            || (limit ?? 0) >= threshold
            || (peak ?? 0) >= threshold

        // --- Collect markers ---
        if region == .us {
            let sn = reading.serialDisplay ?? reading.serialVcu ?? "—"
            let raw = rawHex(forNames: ["vcu_g3_sn", "dis_sn", "vcu_sn"], in: reading) ?? sn
            let expected = profile.market == .de20 ? "DE (1CGB…)" : "EU / marktüblich"
            let stockPlausibleUS = profile.market != .de20
            markers.append(make(
                id: "region.sn",
                raw: raw,
                interpreted: "US-Region (\(sn))",
                expected: expected,
                cls: profile.market == .de20 ? .indiz : .info,
                weight: profile.market == .de20 ? 0.7 : 0.2,
                confidence: 0.9,
                stockMatch: stockPlausibleUS,
                modMatch: profile.market == .de20 ? true : nil,
                notes: "Region aus SN-Präfix"
            ))
        }

        if let limit, limit > rated + 1 {
            let cls: EvidenceClass = limit >= profile.tuningClearKmh ? .indiz : .abweichung
            markers.append(make(
                id: "speed.limit",
                raw: rawHex(forNames: ["vcu_g3_maxspd", "dis_limit", "vcu_g3_edmax"], in: reading) ?? Format.kmh.format(Optional(limit)),
                interpreted: "\(Format.kmh.format(Optional(limit))) gespeichertes Limit",
                expected: "≤ \(Format.kmh.format(Optional(rated)))",
                cls: cls,
                weight: limit >= profile.tuningClearKmh ? 0.75 : 0.45,
                confidence: 0.85,
                stockMatch: false,
                modMatch: true,
                notes: "Persistentes Limit-Register"
            ))
        }

        if let peak, peak > rated + 1 {
            let cls: EvidenceClass = peak >= profile.tuningClearKmh ? .indiz : .abweichung
            markers.append(make(
                id: "speed.peak",
                raw: rawHex(forNames: ["dis_trip_max", "vcu_g3_trip_max", "tft_trip_max"], in: reading) ?? Format.kmh.format(Optional(peak)),
                interpreted: "\(Format.kmh.format(Optional(peak))) Trip-Spitze",
                expected: "≤ \(Format.kmh.format(Optional(rated)))",
                cls: cls,
                weight: peak >= profile.tuningClearKmh ? 0.7 : 0.4,
                confidence: 0.8,
                stockMatch: false,
                modMatch: true,
                notes: "Semi-persistent bis Trip-Reset"
            ))
        }

        if sessionUnlock {
            markers.append(make(
                id: "speed.session",
                raw: rawHex(forNames: ["vcu_g3_maxspd", "dis_trip_max"], in: reading) ?? "session",
                interpreted: "Session-Tempo ≥ \(Int(threshold)) km/h",
                expected: "inaktiv nach Ausschalten",
                cls: .abweichung,
                weight: 0.35,
                confidence: 0.75,
                stockMatch: nil,
                modMatch: nil,
                notes: "Flüchtiger Session-Zustand"
            ))
        }

        switch custom.level {
        case .confirmed:
            markers.append(make(
                id: "fw.custom",
                raw: fwRawCitation(reading),
                interpreted: custom.summaryLine,
                expected: "Serienkatalog \(profile.shortLabel)",
                cls: .starkerHinweis,
                weight: 0.95,
                confidence: 0.9,
                stockMatch: false,
                modMatch: true,
                notes: "Bestätigte Custom-/Mod-Kennung"
            ))
        case .suspected:
            markers.append(make(
                id: "fw.unknown",
                raw: fwRawCitation(reading),
                interpreted: custom.summaryLine,
                expected: "Serienkatalog \(profile.shortLabel)",
                cls: .abweichung,
                weight: 0.5,
                confidence: 0.65,
                stockMatch: false,
                modMatch: nil,
                notes: "Unbekannter Stand — Abweichung, kein Automatik-Nachweis"
            ))
        case .none:
            break
        }

        if let gear = reading.gearMax, gear > 1 {
            markers.append(make(
                id: "gear.max",
                raw: rawHex(forNames: ["vcu_g3_gear", "vcu_g3_sgear", "vcu_g3_egear", "vcu_g3_dgear"], in: reading) ?? "\(gear)",
                interpreted: "max. Gang \(gear)",
                expected: "1",
                cls: .abweichung,
                weight: 0.4,
                confidence: 0.8,
                stockMatch: false,
                modMatch: true,
                notes: "Allein kein Tuning-Nachweis"
            ))
        }

        if reading.safeLockActive == false {
            markers.append(make(
                id: "safelock",
                raw: rawHex(forNames: ["mcu_safe", "vcu_g3_safe", "mcu_g3_safe"], in: reading) ?? "0",
                interpreted: "SafeLock inaktiv",
                expected: "aktiv",
                cls: .abweichung,
                weight: 0.35,
                confidence: 0.7,
                stockMatch: false,
                modMatch: nil,
                notes: ""
            ))
        }

        if let prior = priorUnlock, prior.showsUnlock(threshold: threshold), !sessionUnlock {
            markers.append(make(
                id: "session.reset",
                raw: prior.protocolNumber,
                interpreted: "zurückgesetzt · früher \(Format.kmh.format(Optional(prior.observedTempoKmh)))",
                expected: "kein Vorher-Unlock nötig",
                cls: prior.observedTempoKmh >= profile.tuningClearKmh ? .indiz : .abweichung,
                weight: 0.55,
                confidence: 0.8,
                stockMatch: nil,
                modMatch: true,
                notes: "Vergleich mit Protokoll \(prior.protocolNumber)"
            ))
        }

        let cross = crossBoardIssues(reading: reading, profile: profile)
        for issue in cross where issue.id.hasPrefix("cross.serial") {
            markers.append(make(
                id: "serial.cross",
                raw: issue.detail,
                interpreted: issue.detail,
                expected: "konsistente Fahrzeug-SN",
                cls: .indiz,
                weight: 0.6,
                confidence: 0.85,
                stockMatch: false,
                modMatch: true,
                notes: issue.boards.joined(separator: "/")
            ))
        }

        // --- Neutralization (negative evidence) ---
        markers = applyNeutralization(
            markers,
            reading: reading,
            profile: profile,
            region: region,
            notes: &neutralizationNotes
        )

        // --- Correlations (on non-neutralized) ---
        let activeIds = Set(markers.filter { !$0.neutralized }.map(\.markerId))
        if activeIds.contains("region.sn"),
           activeIds.contains("speed.limit") || activeIds.contains("speed.peak") {
            correlations.append("US-Region + erhöhtes Tempo → starker Manipulationshinweis (Korrelation)")
            markers = elevate(markers, id: "region.sn", to: .starkerHinweis)
            markers = elevate(markers, id: "speed.limit", to: .starkerHinweis)
        }
        if activeIds.contains("fw.custom"),
           activeIds.contains("speed.limit") || activeIds.contains("speed.peak") {
            correlations.append("Custom-FW + Tempo-Marker → starker Manipulationshinweis")
            markers = elevate(markers, id: "speed.limit", to: .starkerHinweis)
            markers = elevate(markers, id: "speed.peak", to: .starkerHinweis)
        }
        if activeIds.contains("speed.limit"),
           !activeIds.contains("region.sn"),
           !activeIds.contains("fw.custom"),
           !activeIds.contains("speed.peak") {
            correlations.append("Isoliertes Limit: nur Abweichung/Indiz — kein Automatik-Urteil „eindeutig“")
            markers = demote(markers, id: "speed.limit", to: .abweichung)
        }
        if activeIds.contains("gear.max"), markers.filter({ !$0.neutralized }).count == 1 {
            correlations.append("Nur Gangfreigabe: Abweichung, kein alleiniger Manipulationshinweis")
        }

        let temporal = temporalDeltas(current: reading, prior: priorReading, priorProtocol: priorProtocolNumber)
        let fingerprint = baselineFingerprint(reading: reading, profile: profile)
        let unknown = unknownRegisters(in: reading)

        let score = densifyScore(markers: markers)
        let verdict = ruleBasedVerdict(markers: markers, correlations: correlations)
        let justifying = markers.filter {
            !$0.neutralized && $0.evidenceClass.rank >= EvidenceClass.abweichung.rank
        }.sorted { $0.evidenceClass.rank > $1.evidenceClass.rank }

        return EvidenceEngineResult(
            verdict: verdict,
            shortVerdictText: verdict.laymanText,
            justifyingMarkers: justifying,
            markers: markers,
            correlations: correlations,
            neutralizationNotes: neutralizationNotes,
            temporalDeltas: temporal,
            crossBoardIssues: cross,
            fingerprint: fingerprint,
            unknownRegisters: unknown,
            score: score
        )
    }

    // MARK: - Facts for UI (Anzeige only)

    static func buildFacts(_ result: EvidenceEngineResult) -> [MeasuredFact] {
        var facts: [MeasuredFact] = []

        facts.append(MeasuredFact(
            id: "evidence.summary",
            group: .evidence,
            title: "Kurzurteil (EvidenceEngine)",
            auslesewert: result.verdict.label,
            sollwert: VerdictLevel.stock.label,
            status: factStatus(for: result.verdict),
            bewertung: result.summary,
            erlaeuterung: """
            Urteil regelbasiert aus Marker-Ketten (Quelle→Rohwert→Interpretation→Persistenz→Gewicht). \
            Der Score (\(result.integrityScore)) verdichtet nur; er erzeugt das Urteil nicht allein.
            """,
            raw: result.fingerprint.digestSHA256,
            volatility: .persistent,
            evidenceClass: result.starkerHinweisCount > 0 ? .starkerHinweis : (result.indizCount > 0 ? .indiz : .abweichung),
            sourceBoard: "EvidenceEngine",
            sourceRegister: "verdict",
            rawHex: nil,
            resetsOnPowerOff: false
        ))

        for (idx, note) in result.neutralizationNotes.enumerated() {
            facts.append(MeasuredFact(
                id: "evidence.neutral.\(idx)",
                group: .evidence,
                title: "Neutralisierung",
                auslesewert: note,
                sollwert: "Gegenbeleg geprüft",
                status: .regelkonform,
                bewertung: "False-Positive-Schutz",
                erlaeuterung: note,
                raw: note,
                volatility: .persistent,
                evidenceClass: .info,
                sourceBoard: "EvidenceEngine",
                sourceRegister: "neutralization",
                rawHex: nil,
                resetsOnPowerOff: false
            ))
        }

        for marker in result.markers {
            facts.append(MeasuredFact(
                id: "evidence.\(marker.markerId)\(marker.neutralized ? ".neutral" : "")",
                group: .evidence,
                title: "\(marker.title) [\(marker.persistenceClass.label)]",
                auslesewert: marker.interpretedValue,
                sollwert: marker.expectedValue,
                status: marker.neutralized ? .regelkonform : status(for: marker.evidenceClass),
                bewertung: marker.contributionLabel,
                erlaeuterung: marker.chainCitation + (marker.notes.isEmpty ? "" : " — \(marker.notes)"),
                raw: marker.chainCitation,
                volatility: marker.persistenceClass,
                evidenceClass: marker.evidenceClass,
                sourceBoard: marker.boardSource,
                sourceRegister: marker.registerOrField,
                rawHex: marker.rawValue,
                resetsOnPowerOff: marker.resetsOnPowerOff
            ))
        }

        for issue in result.crossBoardIssues {
            facts.append(MeasuredFact(
                id: issue.id,
                group: .evidence,
                title: "Cross-Board: \(issue.title)",
                auslesewert: issue.detail,
                sollwert: "konsistent",
                status: .abweichend,
                bewertung: issue.boards.joined(separator: ", "),
                erlaeuterung: issue.detail,
                raw: issue.detail,
                volatility: .persistent,
                evidenceClass: .indiz,
                sourceBoard: issue.boards.joined(separator: "/"),
                sourceRegister: "SN/FW",
                rawHex: nil,
                resetsOnPowerOff: false
            ))
        }

        for delta in result.temporalDeltas {
            facts.append(MeasuredFact(
                id: delta.id,
                group: .evidence,
                title: "Historie: \(delta.title)",
                auslesewert: "\(delta.previous) → \(delta.current)",
                sollwert: "unverändert",
                status: .abweichend,
                bewertung: "seit \(delta.priorProtocol)",
                erlaeuterung: "Zeitlicher Vergleich derselben SN.",
                raw: delta.priorProtocol,
                volatility: .persistent,
                evidenceClass: .indiz,
                sourceBoard: "Verlauf",
                sourceRegister: delta.title,
                rawHex: nil,
                resetsOnPowerOff: false
            ))
        }

        if !result.unknownRegisters.isEmpty {
            let sample = result.unknownRegisters.prefix(8).map {
                "\($0.name) \($0.address)=\($0.valueHex)"
            }.joined(separator: "; ")
            facts.append(MeasuredFact(
                id: "evidence.unknown.registers",
                group: .evidence,
                title: "Unknown-State Register",
                auslesewert: "\(result.unknownRegisters.count) ohne sichere Deutung",
                sollwert: "dokumentiert, nicht überinterpretiert",
                status: .nichtFeststellbar,
                bewertung: "Info — Rohwert + FW-Kontext",
                erlaeuterung: sample,
                raw: sample,
                volatility: .persistent,
                evidenceClass: .info,
                sourceBoard: "div.",
                sourceRegister: "—",
                rawHex: nil,
                resetsOnPowerOff: false
            ))
        }

        facts.append(MeasuredFact(
            id: "evidence.fingerprint",
            group: .evidence,
            title: "Baseline-Fingerprint",
            auslesewert: String(result.fingerprint.digestSHA256.prefix(16)) + "…",
            sollwert: result.fingerprint.profileId,
            status: .regelkonform,
            bewertung: "\(result.fingerprint.fields.count) Felder",
            erlaeuterung: "SHA-256 über Region/SN-Präfix, FW, Limit, Gänge.",
            raw: result.fingerprint.digestSHA256,
            volatility: .persistent,
            evidenceClass: .info,
            sourceBoard: "Fingerprint",
            sourceRegister: "composite",
            rawHex: result.fingerprint.digestSHA256,
            resetsOnPowerOff: false
        ))

        return facts
    }

    // MARK: - Rule-based verdict (Score spielt keine Rolle)

    private static func ruleBasedVerdict(markers: [EvidenceMarker], correlations: [String]) -> VerdictLevel {
        let active = markers.filter { !$0.neutralized }
        let stark = active.filter { $0.evidenceClass == .starkerHinweis }
        let indiz = active.filter { $0.evidenceClass == .indiz }
        let abweichung = active.filter { $0.evidenceClass == .abweichung }
        let persistentStarkOrIndiz = active.filter {
            $0.persistenceClass == .persistent
                && ($0.evidenceClass == .starkerHinweis || $0.evidenceClass == .indiz)
        }

        // Technisch eindeutig: bestätigter starker Hinweis (z. B. Custom-FW) oder Korrelation Region+Tempo / FW+Tempo.
        if stark.contains(where: { $0.markerId == "fw.custom" }) { return .eindeutig }
        if correlations.contains(where: { $0.contains("starker Manipulationshinweis") }),
           stark.count >= 1 {
            return .eindeutig
        }
        if persistentStarkOrIndiz.count >= 3, stark.count + indiz.count >= 3 {
            return .eindeutig
        }

        // Manipulationshinweise: ≥1 starker Hinweis oder ≥2 persistente Indizien.
        if !stark.isEmpty { return .hinweise }
        if indiz.filter({ $0.persistenceClass == .persistent }).count >= 2 { return .hinweise }
        if indiz.count >= 2, persistentStarkOrIndiz.count >= 1 { return .hinweise }

        // Auffällig: Abweichungen oder einzelnes Indiz / nur flüchtige Marker.
        if !indiz.isEmpty || !abweichung.isEmpty { return .auffaellig }

        return .stock
    }

    /// Score nur Verdichtung — nie allein urteilsbildend.
    private static func densifyScore(markers: [EvidenceMarker]) -> EvidenceScoreBreakdown {
        var suspicion = 0.0
        var active = 0
        var neutralized = 0
        for m in markers {
            if m.neutralized {
                neutralized += 1
                continue
            }
            guard m.evidenceClass != .info else { continue }
            active += 1
            suspicion += Double(m.evidenceClass.scoreDelta) * m.effectiveWeight * m.confidence
        }
        let index = min(100, Int(suspicion.rounded()))
        let raw = min(100, max(0, 100 - index))
        return EvidenceScoreBreakdown(
            rawScore: raw,
            suspicionIndex: index,
            activeMarkerCount: active,
            neutralizedCount: neutralized
        )
    }

    // MARK: - Neutralization

    private static func applyNeutralization(
        _ markers: [EvidenceMarker],
        reading: IntegrityReading,
        profile: ScooterProfile,
        region: SerialRegion,
        notes: inout [String]
    ) -> [EvidenceMarker] {
        markers.map { marker in
            // US-Region + DE-Soll: neutralisieren wenn alles zu einer US-Serie passt
            // (Profil wäre eigentlich US/EU, oder SN/FW konsistent US ohne Tempo-Tuning).
            if marker.markerId == "region.sn", region == .us {
                let limit = reading.speedLimitKmh ?? reading.speedMaxKmh ?? 0
                let peak = reading.peakSpeedKmh ?? 0
                let tempoOk = limit <= profile.ratedMaxKmh + 1 && peak <= profile.ratedMaxKmh + 1
                let fw = StockFirmwareCatalog.analyze(reading: reading, profile: profile)
                let fwPlausible = fw.notInCatalogCount == 0 && fw.customCount == 0
                let sn = reading.serialDisplay ?? reading.serialVcu ?? ""
                let usSerialShape = sn.uppercased().hasPrefix("1CGC")
                // Wenn DE-Sollprofil aber Fahrzeug klar US-Serie ohne Tempo-Auffälligkeit und FW im Katalog:
                // Marker auf Info/neutral — False Positive vermeiden.
                if profile.market == .de20, usSerialShape, tempoOk, fwPlausible {
                    let reason = "US-SN + Serien-FW + Limit/Peak ≤ Typ — Region allein kein Manipulationsindiz (mögliche US-Ausführung / falsches Sollprofil)"
                    notes.append(reason)
                    return neutralized(marker, reason: reason, asInfo: true)
                }
                if profile.market != .de20, usSerialShape, tempoOk {
                    let reason = "Marktprofil nicht DE — US-Region zum Profil passend"
                    notes.append(reason)
                    return neutralized(marker, reason: reason, asInfo: true)
                }
            }
            return marker
        }
    }

    private static func neutralized(_ m: EvidenceMarker, reason: String, asInfo: Bool) -> EvidenceMarker {
        EvidenceMarker(
            markerId: m.markerId,
            title: m.title,
            boardSource: m.boardSource,
            registerOrField: m.registerOrField,
            rawValue: m.rawValue,
            interpretedValue: m.interpretedValue,
            expectedValue: m.expectedValue,
            persistenceClass: m.persistenceClass,
            confidence: m.confidence,
            evidenceClass: asInfo ? .info : m.evidenceClass,
            weight: m.weight,
            knownStockMatch: true,
            knownModMatch: false,
            notes: m.notes,
            neutralized: true,
            neutralizationReason: reason
        )
    }

    // MARK: - Helpers

    private static func catalog(_ id: String) -> MarkerCatalogEntry? {
        catalog.first { $0.markerId == id }
    }

    private static func make(
        id: String,
        raw: String,
        interpreted: String,
        expected: String,
        cls: EvidenceClass,
        weight: Double,
        confidence: Double,
        stockMatch: Bool?,
        modMatch: Bool?,
        notes: String
    ) -> EvidenceMarker {
        let entry = catalog(id)
        return EvidenceMarker(
            markerId: id,
            title: entry?.title ?? id,
            boardSource: entry?.boardSource ?? "—",
            registerOrField: entry?.registerOrField ?? "—",
            rawValue: raw,
            interpretedValue: interpreted,
            expectedValue: expected,
            persistenceClass: entry?.persistence ?? .semiPersistent,
            confidence: confidence,
            evidenceClass: cls,
            weight: weight,
            knownStockMatch: stockMatch,
            knownModMatch: modMatch,
            notes: notes,
            neutralized: false,
            neutralizationReason: nil
        )
    }

    private static func elevate(_ markers: [EvidenceMarker], id: String, to cls: EvidenceClass) -> [EvidenceMarker] {
        markers.map { m in
            guard m.markerId == id, !m.neutralized, cls.rank > m.evidenceClass.rank else { return m }
            return EvidenceMarker(
                markerId: m.markerId, title: m.title, boardSource: m.boardSource,
                registerOrField: m.registerOrField, rawValue: m.rawValue,
                interpretedValue: m.interpretedValue, expectedValue: m.expectedValue,
                persistenceClass: m.persistenceClass, confidence: m.confidence,
                evidenceClass: cls, weight: min(1, m.weight + 0.15),
                knownStockMatch: m.knownStockMatch, knownModMatch: m.knownModMatch,
                notes: m.notes, neutralized: false, neutralizationReason: nil
            )
        }
    }

    private static func demote(_ markers: [EvidenceMarker], id: String, to cls: EvidenceClass) -> [EvidenceMarker] {
        markers.map { m in
            guard m.markerId == id, !m.neutralized else { return m }
            return EvidenceMarker(
                markerId: m.markerId, title: m.title, boardSource: m.boardSource,
                registerOrField: m.registerOrField, rawValue: m.rawValue,
                interpretedValue: m.interpretedValue + " (isoliert)",
                expectedValue: m.expectedValue,
                persistenceClass: m.persistenceClass, confidence: m.confidence,
                evidenceClass: cls, weight: min(m.weight, 0.45),
                knownStockMatch: m.knownStockMatch, knownModMatch: m.knownModMatch,
                notes: m.notes, neutralized: false, neutralizationReason: nil
            )
        }
    }

    private static func status(for cls: EvidenceClass) -> FactStatus {
        switch cls {
        case .info: return .nichtFeststellbar
        case .abweichung: return .abweichend
        case .indiz: return .abweichend
        case .starkerHinweis: return .erheblichAbweichend
        }
    }

    private static func factStatus(for verdict: VerdictLevel) -> FactStatus {
        switch verdict {
        case .stock: return .regelkonform
        case .auffaellig: return .abweichend
        case .hinweise, .eindeutig: return .erheblichAbweichend
        }
    }

    static func crossBoardIssues(reading: IntegrityReading, profile: ScooterProfile) -> [CrossBoardIssue] {
        var issues: [CrossBoardIssue] = []
        let vehicle = reading.serialDisplay ?? reading.serialVcu
        let pairs: [(String, String?)] = [
            ("VCU", reading.serialVcu), ("MCU", reading.serialMcu),
            ("BLE", reading.serialBle), ("BMS", reading.serialBms), ("DIS", reading.serialDisplay)
        ]
        if let vehicle {
            for (board, sn) in pairs {
                guard let sn, !sn.isEmpty else { continue }
                if TrackClassifier.looksLikeModuleSerial(sn) { continue }
                if TrackClassifier.serialsMismatch(sn, vehicle) {
                    issues.append(CrossBoardIssue(
                        id: "cross.serial.\(board.lowercased())",
                        title: "SN \(board) ≠ Fahrzeug",
                        detail: "\(board)-SN \(sn) weicht von \(vehicle) ab",
                        boards: [board, "Fahrzeug"]
                    ))
                }
            }
        }
        let regions = [
            ("DIS/VCU", TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)),
            ("MCU", TrackClassifier.serialRegion(for: reading.serialMcu)),
            ("BLE", TrackClassifier.serialRegion(for: reading.serialBle))
        ].filter { $0.1 != .unknown }
        if let first = regions.first {
            for other in regions.dropFirst() where other.1 != first.1 {
                issues.append(CrossBoardIssue(
                    id: "cross.region.\(other.0)",
                    title: "Region inkonsistent",
                    detail: "\(first.0)=\(first.1.label), \(other.0)=\(other.1.label)",
                    boards: [first.0, other.0]
                ))
            }
        }
        if profile.family == .maxG3 {
            let catalog = StockFirmwareCatalog.analyze(reading: reading, profile: profile)
            let mismatches = catalog.components.filter { $0.match == .notInCatalog || $0.match == .customMarked }
            if mismatches.count >= 2 {
                issues.append(CrossBoardIssue(
                    id: "cross.fw.catalog",
                    title: "Mehrere FW-Module nicht Serie",
                    detail: mismatches.map { "\($0.title):\($0.version ?? "—")" }.joined(separator: ", "),
                    boards: mismatches.map(\.title)
                ))
            }
        }
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
            let left = a ?? "—"; let right = b ?? "—"
            guard left != right else { return }
            deltas.append(TemporalDelta(id: "history.delta.\(id)", title: title, previous: left, current: right, priorProtocol: proto))
        }
        add("region", "Region",
            TrackClassifier.serialRegion(for: prior.serialDisplay ?? prior.serialVcu).label,
            TrackClassifier.serialRegion(for: current.serialDisplay ?? current.serialVcu).label)
        add("fw.mcu", "MCU-FW", prior.fwMcu, current.fwMcu)
        add("fw.vcu", "VCU-FW", prior.fwVcu, current.fwVcu)
        add("fw.ble", "BLE-FW", prior.fwBle, current.fwBle)
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
            "profile": profile.id,
            "region": region.rawValue,
            "snPrefix": String((reading.serialDisplay ?? reading.serialVcu ?? "").prefix(4)),
            "fwMcu": reading.fwMcu ?? "",
            "fwBle": reading.fwBle ?? "",
            "fwBms": reading.fwBms ?? "",
            "fwVcu": reading.fwVcu ?? "",
            "limit": reading.speedLimitKmh.map { String(format: "%.1f", $0) } ?? "",
            "max": reading.speedMaxKmh.map { String(format: "%.1f", $0) } ?? "",
            "gearMax": reading.gearMax.map(String.init) ?? "",
            "safeLock": reading.safeLockActive.map { $0 ? "1" : "0" } ?? ""
        ]
        let canonical = fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return BaselineFingerprint(profileId: profile.id, digestSHA256: digest, fields: fields)
    }

    static func unknownRegisters(in reading: IntegrityReading) -> [RawRegister] {
        let knownPrefixes = ["dis_", "ble_", "vcu_", "mcu_", "bms_", "g3_", "tft_", "esc_"]
        return reading.rawRegisters.filter { reg in
            if let note = reg.note?.lowercased(), note.contains("unbekannt") || note.contains("unknown") {
                return true
            }
            let decodedEmpty = reg.valueDecoded == nil || reg.valueDecoded?.isEmpty == true
            let looksKnown = knownPrefixes.contains { reg.name.lowercased().hasPrefix($0) }
            return decodedEmpty && !looksKnown && !reg.valueHex.isEmpty
        }
    }

    private static func rawHex(forNames names: [String], in reading: IntegrityReading) -> String? {
        for name in names {
            if let reg = reading.rawRegisters.last(where: { $0.name == name || $0.name.hasSuffix(name) }) {
                return "\(reg.name) \(reg.address)=\(reg.valueHex)"
            }
        }
        return nil
    }

    private static func fwRawCitation(_ reading: IntegrityReading) -> String {
        let names = ["g3_mcu_fw", "g3_vcu_fw", "g3_ble_fw", "g3_bms_fw", "mcu_fw", "ble_fw", "vcu_fw", "bms_fw"]
        let parts = names.compactMap { name -> String? in
            guard let reg = reading.rawRegisters.last(where: { $0.name == name }) else { return nil }
            return "\(reg.name)=\(reg.valueHex)"
        }
        return parts.isEmpty ? (reading.fwMcu ?? reading.fwVcu ?? "—") : parts.joined(separator: ", ")
    }
}
