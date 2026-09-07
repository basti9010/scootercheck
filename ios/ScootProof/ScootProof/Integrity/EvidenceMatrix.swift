import Foundation
import CryptoKit

// MARK: - Marker taxonomy (Kontroll-/Gerichtstauglichkeit)

/// Wie lange ein Marker typischerweise sichtbar bleibt.
enum MarkerVolatility: String, Codable, CaseIterable, Sendable {
    /// Verschwindet bei Ausschalten / Session-Ende.
    case fleeting = "flüchtig"
    /// Oft bis Trip-Reset oder Soft-Panic, nicht dauerhaft.
    case semiPersistent = "semi-persistent"
    /// Typischerweise power-cycle-resistent.
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

/// Beweisqualität für den Score — nicht nur „abweichend“.
enum EvidenceClass: String, Codable, CaseIterable, Sendable {
    case nachweis = "Manipulationsnachweis"
    case indiz = "Manipulationsindiz"
    case abweichung = "bloße Abweichung"
    case unknown = "unbekannt / Rohwert"

    var label: String { rawValue }

    /// Score-Abzug (höher = stärkerer Nachweis).
    var scorePenalty: Int {
        switch self {
        case .nachweis: return 22
        case .indiz: return 10
        case .abweichung: return 4
        case .unknown: return 0
        }
    }
}

/// Katalog-Eintrag: Register/Quelle → Persistenz, Soll, Beweisgewicht.
struct MarkerDefinition: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let volatility: MarkerVolatility
    let baseClass: EvidenceClass
    let sourceBoard: String
    let sourceRegister: String
    let stockHint: String
    let knownModHint: String?
}

/// Einzelner bewerteter Marker mit Rohdatenbezug.
struct EvidenceHit: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let volatility: MarkerVolatility
    let evidenceClass: EvidenceClass
    let observed: String
    let stockExpected: String
    let sourceBoard: String
    let sourceRegister: String
    let rawHex: String?
    let interpretation: String
    let correlatedWith: [String]
    let resetsOnPowerOff: Bool

    var rawCitation: String {
        var parts = ["\(sourceBoard) \(sourceRegister)"]
        if let rawHex, !rawHex.isEmpty {
            parts.append("Rohwert \(rawHex)")
        }
        parts.append("interpretiert als \(interpretation)")
        parts.append("Typ-Soll: \(stockExpected)")
        return parts.joined(separator: "; ")
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

struct EvidenceAssessment: Codable, Hashable, Sendable {
    let hits: [EvidenceHit]
    let correlations: [String]
    let temporalDeltas: [TemporalDelta]
    let crossBoardIssues: [CrossBoardIssue]
    let fingerprint: BaselineFingerprint
    let unknownRegisters: [RawRegister]
    let nachweisCount: Int
    let indizCount: Int
    let abweichungCount: Int
    let persistentHitCount: Int
    let score: Int
    let suggestedVerdict: VerdictLevel
    let summary: String

    static let empty = EvidenceAssessment(
        hits: [],
        correlations: [],
        temporalDeltas: [],
        crossBoardIssues: [],
        fingerprint: BaselineFingerprint(profileId: "", digestSHA256: "", fields: [:]),
        unknownRegisters: [],
        nachweisCount: 0,
        indizCount: 0,
        abweichungCount: 0,
        persistentHitCount: 0,
        score: 100,
        suggestedVerdict: .stock,
        summary: "Keine Evidenzbewertung"
    )
}

// MARK: - Catalog + assessment

enum EvidenceMatrix {

    /// Modellübergreifende Marker-Datenbank (erweiterbar pro Firmware).
    static let catalog: [MarkerDefinition] = [
        MarkerDefinition(
            id: "region.sn",
            title: "SN-Region",
            volatility: .persistent,
            baseClass: .indiz,
            sourceBoard: "VCU/DIS",
            sourceRegister: "SN 0x10",
            stockHint: "DE 1CGB… / EU-Präfix",
            knownModHint: "US 1CGC… bei DE-Soll"
        ),
        MarkerDefinition(
            id: "speed.limit",
            title: "Gespeichertes Limit",
            volatility: .persistent,
            baseClass: .indiz,
            sourceBoard: "VCU",
            sourceRegister: "maxSpeed 0x46 / limit",
            stockHint: "≤ Typgenehmigung",
            knownModHint: "dauerhaft > Typ"
        ),
        MarkerDefinition(
            id: "speed.peak",
            title: "Trip-Spitze",
            volatility: .semiPersistent,
            baseClass: .indiz,
            sourceBoard: "DIS/VCU",
            sourceRegister: "rSigMaxSpeed 0x24",
            stockHint: "≤ Typ + Messtoleranz",
            knownModHint: "Peak deutlich über Typ"
        ),
        MarkerDefinition(
            id: "speed.session",
            title: "Session-Unlock (Tempo)",
            volatility: .fleeting,
            baseClass: .abweichung,
            sourceBoard: "VCU",
            sourceRegister: "Limit/Peak Session",
            stockHint: "inaktiv nach Ausschalten",
            knownModHint: "nur mit aktiver Session sichtbar"
        ),
        MarkerDefinition(
            id: "fw.custom",
            title: "Custom-/Mod-Firmware",
            volatility: .persistent,
            baseClass: .nachweis,
            sourceBoard: "MCU/BLE/BMS/VCU",
            sourceRegister: "Versionsregister",
            stockHint: "Katalog-Serienstände",
            knownModHint: "bekannte Mod-Version / Katalog-Miss"
        ),
        MarkerDefinition(
            id: "fw.unknown",
            title: "Unbekannter Firmwarestand",
            volatility: .persistent,
            baseClass: .abweichung,
            sourceBoard: "MCU/VCU",
            sourceRegister: "Versionsregister",
            stockHint: "bekannter Serienstand",
            knownModHint: nil
        ),
        MarkerDefinition(
            id: "gear.max",
            title: "Gangfreigabe",
            volatility: .persistent,
            baseClass: .abweichung,
            sourceBoard: "VCU",
            sourceRegister: "gearMode / s|e|dGear",
            stockHint: "1 (Serie DE)",
            knownModHint: "> 1 freigeschaltet"
        ),
        MarkerDefinition(
            id: "serial.cross",
            title: "Cross-Board-SN",
            volatility: .persistent,
            baseClass: .indiz,
            sourceBoard: "VCU/MCU/BLE/BMS",
            sourceRegister: "SN 0x10",
            stockHint: "Fahrzeug-SN konsistent",
            knownModHint: "Mismatch zwischen Boards"
        ),
        MarkerDefinition(
            id: "fw.cross",
            title: "Cross-Board-Firmware",
            volatility: .persistent,
            baseClass: .abweichung,
            sourceBoard: "MCU/BLE/BMS/VCU",
            sourceRegister: "FW-Register",
            stockHint: "stimmige Modulversionen",
            knownModHint: "inkonsistente Modulstände"
        ),
        MarkerDefinition(
            id: "safelock",
            title: "SafeLock",
            volatility: .persistent,
            baseClass: .abweichung,
            sourceBoard: "MCU/VCU",
            sourceRegister: "speedSafeLock",
            stockHint: "aktiv",
            knownModHint: "inaktiv"
        ),
        MarkerDefinition(
            id: "session.reset",
            title: "Session nach Ausschalten",
            volatility: .fleeting,
            baseClass: .indiz,
            sourceBoard: "Vergleich",
            sourceRegister: "Protokollverlauf",
            stockHint: "kein Vorher-Unlock",
            knownModHint: "früheres Tempo, jetzt zurückgesetzt"
        )
    ]

    static func definition(id: String) -> MarkerDefinition? {
        catalog.first { $0.id == id }
    }

    static func assess(
        reading: IntegrityReading,
        profile: ScooterProfile,
        priorUnlock: PriorUnlockEvidence?,
        priorReading: IntegrityReading?,
        priorProtocolNumber: String?
    ) -> EvidenceAssessment {
        var hits: [EvidenceHit] = []
        var correlations: [String] = []

        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let rated = profile.ratedMaxKmh
        let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
        let custom = CustomFirmwareDiff.analyze(reading: reading, profile: profile)
        let limit = reading.speedLimitKmh ?? reading.speedMaxKmh
        let peak = reading.peakSpeedKmh
        let sessionUnlock = reading.hiddenTuningDetected == true
            || (limit ?? 0) >= threshold
            || (peak ?? 0) >= threshold

        // --- Region ---
        if region == .us, profile.market == .de20 {
            let sn = reading.serialDisplay ?? reading.serialVcu ?? "—"
            let raw = rawHex(forNames: ["vcu_g3_sn", "dis_sn", "vcu_sn"], in: reading)
            hits.append(hit(
                id: "region.sn",
                observed: "US (\(sn))",
                stock: "DE (1CGB…)",
                rawHex: raw,
                interpretation: sn,
                evidenceClass: .indiz
            ))
        }

        // --- Gespeichertes Limit (allein nur Indiz/Abweichung, nicht automatisch Nachweis) ---
        if let limit, limit > rated + 1 {
            let cls: EvidenceClass = limit >= profile.tuningClearKmh ? .indiz : .abweichung
            hits.append(hit(
                id: "speed.limit",
                observed: Format.kmh.format(Optional(limit)),
                stock: "≤ \(Format.kmh.format(Optional(rated)))",
                rawHex: rawHex(forNames: ["vcu_g3_maxspd", "dis_limit", "vcu_g3_edmax"], in: reading),
                interpretation: "\(Format.kmh.format(Optional(limit))) gespeichertes Limit",
                evidenceClass: cls
            ))
        }

        // --- Trip-Peak ---
        if let peak, peak > rated + 1 {
            let cls: EvidenceClass = peak >= profile.tuningClearKmh ? .indiz : .abweichung
            hits.append(hit(
                id: "speed.peak",
                observed: Format.kmh.format(Optional(peak)),
                stock: "≤ \(Format.kmh.format(Optional(rated)))",
                rawHex: rawHex(forNames: ["dis_trip_max", "vcu_g3_trip_max", "tft_trip_max"], in: reading),
                interpretation: "\(Format.kmh.format(Optional(peak))) Trip-Spitze",
                evidenceClass: cls
            ))
        }

        // --- Session unlock (flüchtig) ---
        if sessionUnlock {
            hits.append(hit(
                id: "speed.session",
                observed: "aktiv (≥ \(Int(threshold)) km/h)",
                stock: "inaktiv nach Ausschalten",
                rawHex: rawHex(forNames: ["vcu_g3_maxspd", "dis_trip_max"], in: reading),
                interpretation: "Session-Tempo über Soft-Unlock-Schwelle",
                evidenceClass: .abweichung
            ))
        }

        // --- Firmware ---
        switch custom.level {
        case .confirmed:
            hits.append(hit(
                id: "fw.custom",
                observed: custom.summaryLine,
                stock: "Serienkatalog \(profile.shortLabel)",
                rawHex: fwRawCitation(reading),
                interpretation: custom.summaryLine,
                evidenceClass: .nachweis
            ))
        case .suspected:
            hits.append(hit(
                id: "fw.unknown",
                observed: custom.summaryLine,
                stock: "Serienkatalog \(profile.shortLabel)",
                rawHex: fwRawCitation(reading),
                interpretation: custom.summaryLine,
                evidenceClass: .abweichung
            ))
        case .none:
            break
        }

        // --- Gänge ---
        if let gear = reading.gearMax, gear > 1 {
            hits.append(hit(
                id: "gear.max",
                observed: "\(gear)",
                stock: "1",
                rawHex: rawHex(forNames: ["vcu_g3_gear", "vcu_g3_sgear", "vcu_g3_egear", "vcu_g3_dgear"], in: reading),
                interpretation: "max. Gang \(gear)",
                evidenceClass: .abweichung
            ))
        }

        // --- SafeLock ---
        if reading.safeLockActive == false {
            hits.append(hit(
                id: "safelock",
                observed: "inaktiv",
                stock: "aktiv",
                rawHex: rawHex(forNames: ["mcu_safe", "vcu_g3_safe", "mcu_g3_safe"], in: reading),
                interpretation: "SafeLock aus",
                evidenceClass: .abweichung
            ))
        }

        // --- Session reset vs prior unlock protocol ---
        if let prior = priorUnlock, prior.showsUnlock(threshold: threshold), !sessionUnlock {
            hits.append(hit(
                id: "session.reset",
                observed: "zurückgesetzt · früher \(Format.kmh.format(Optional(prior.observedTempoKmh)))",
                stock: "kein Vorher-Unlock nötig",
                rawHex: prior.protocolNumber,
                interpretation: "Protokoll \(prior.protocolNumber) zeigte Unlock; aktuell Session weg",
                evidenceClass: prior.observedTempoKmh >= profile.tuningClearKmh ? .indiz : .abweichung
            ))
        }

        // --- Cross-board ---
        let cross = crossBoardIssues(reading: reading, profile: profile)
        for issue in cross where issue.id.hasPrefix("cross.serial") {
            hits.append(hit(
                id: "serial.cross",
                observed: issue.detail,
                stock: "konsistente Fahrzeug-SN",
                rawHex: nil,
                interpretation: issue.detail,
                evidenceClass: .indiz
            ))
        }

        // --- Korrelationen ---
        let ids = Set(hits.map(\.id))
        if ids.contains("region.sn"), ids.contains("speed.limit") || ids.contains("speed.peak") {
            correlations.append("US-Region + erhöhtes Tempo → starke Auffälligkeit (Korrelation)")
            elevate(&hits, id: "region.sn", to: .nachweis)
            elevate(&hits, id: "speed.limit", to: .nachweis)
            elevate(&hits, id: "speed.peak", to: .indiz)
        }
        if ids.contains("fw.custom"), ids.contains("speed.limit") || ids.contains("speed.peak") {
            correlations.append("Custom-FW + Tempo-Marker → Manipulationsnachweis (Korrelation)")
            elevate(&hits, id: "speed.limit", to: .nachweis)
            elevate(&hits, id: "speed.peak", to: .nachweis)
        }
        if ids.contains("region.sn"), ids.contains("fw.custom"), ids.contains("gear.max") {
            correlations.append("Region + Custom-FW + Gangfreigabe → hohe Aussagekraft")
        }
        if ids.contains("speed.limit"), !ids.contains("region.sn"), !ids.contains("fw.custom"), !ids.contains("speed.peak") {
            correlations.append("Isoliertes Limit allein: nur geringe–mittlere Gewichtung (kein Automatik-„getunt“)")
            demoteIsolatedLimit(&hits)
        }
        if ids.contains("gear.max"), hits.count == 1 {
            correlations.append("Nur Gangfreigabe: Abweichung, kein alleiniger Tuning-Nachweis")
        }

        // Korrelationstexte an Hits anhängen
        hits = hits.map { h in
            EvidenceHit(
                id: h.id,
                title: h.title,
                volatility: h.volatility,
                evidenceClass: h.evidenceClass,
                observed: h.observed,
                stockExpected: h.stockExpected,
                sourceBoard: h.sourceBoard,
                sourceRegister: h.sourceRegister,
                rawHex: h.rawHex,
                interpretation: h.interpretation,
                correlatedWith: correlations,
                resetsOnPowerOff: h.resetsOnPowerOff
            )
        }

        let temporal = temporalDeltas(
            current: reading,
            prior: priorReading,
            priorProtocol: priorProtocolNumber
        )

        let fingerprint = baselineFingerprint(reading: reading, profile: profile)
        let unknown = unknownRegisters(in: reading)

        let nachweis = hits.filter { $0.evidenceClass == .nachweis }.count
        let indiz = hits.filter { $0.evidenceClass == .indiz }.count
        let abweichung = hits.filter { $0.evidenceClass == .abweichung }.count
        let persistentHits = hits.filter { $0.volatility == .persistent }.count

        let score = computeScore(hits: hits, trackBonus: 0)
        let verdict = suggestedVerdict(
            hits: hits,
            nachweis: nachweis,
            indiz: indiz,
            score: score,
            correlations: correlations
        )

        let summary = buildSummary(
            nachweis: nachweis,
            indiz: indiz,
            abweichung: abweichung,
            persistentHits: persistentHits,
            correlations: correlations,
            verdict: verdict
        )

        return EvidenceAssessment(
            hits: hits,
            correlations: correlations,
            temporalDeltas: temporal,
            crossBoardIssues: cross,
            fingerprint: fingerprint,
            unknownRegisters: unknown,
            nachweisCount: nachweis,
            indizCount: indiz,
            abweichungCount: abweichung,
            persistentHitCount: persistentHits,
            score: score,
            suggestedVerdict: verdict,
            summary: summary
        )
    }

    // MARK: - Fact builders for UI/PDF

    static func buildFacts(_ assessment: EvidenceAssessment) -> [MeasuredFact] {
        var facts: [MeasuredFact] = []

        facts.append(MeasuredFact(
            id: "evidence.summary",
            group: .evidence,
            title: "Evidenzmatrix (Gesamt)",
            auslesewert: "\(assessment.nachweisCount) Nachweis · \(assessment.indizCount) Indiz · \(assessment.abweichungCount) Abweichung",
            sollwert: "0 / 0 / 0",
            status: assessment.suggestedVerdict == .tuned
                ? .erheblichAbweichend
                : (assessment.suggestedVerdict == .watch ? .abweichend : .regelkonform),
            bewertung: assessment.summary,
            erlaeuterung: """
            Gewichtung nach Beweisqualität und Persistenz. Ein isoliertes Limit ist kein Automatik-„getunt“. \
            Flüchtige Marker verschwinden oft nach Ausschalten; persistente bleiben typischerweise sichtbar.
            """,
            raw: assessment.fingerprint.digestSHA256,
            volatility: .persistent,
            evidenceClass: assessment.nachweisCount > 0 ? .nachweis : (assessment.indizCount > 0 ? .indiz : .abweichung),
            sourceBoard: "Matrix",
            sourceRegister: "—",
            rawHex: assessment.fingerprint.digestSHA256,
            resetsOnPowerOff: false
        ))

        for hit in assessment.hits {
            facts.append(MeasuredFact(
                id: "evidence.\(hit.id)",
                group: .evidence,
                title: "\(hit.title) [\(hit.volatility.label)]",
                auslesewert: hit.observed,
                sollwert: hit.stockExpected,
                status: status(for: hit.evidenceClass),
                bewertung: "\(hit.evidenceClass.label) · \(hit.volatility.resetsOnPowerOffHint)",
                erlaeuterung: hit.rawCitation,
                raw: hit.rawCitation,
                volatility: hit.volatility,
                evidenceClass: hit.evidenceClass,
                sourceBoard: hit.sourceBoard,
                sourceRegister: hit.sourceRegister,
                rawHex: hit.rawHex,
                resetsOnPowerOff: hit.resetsOnPowerOff
            ))
        }

        for issue in assessment.crossBoardIssues {
            facts.append(MeasuredFact(
                id: issue.id,
                group: .evidence,
                title: "Cross-Board: \(issue.title)",
                auslesewert: issue.detail,
                sollwert: "konsistent",
                status: .abweichend,
                bewertung: "Board-Vergleich \(issue.boards.joined(separator: ", "))",
                erlaeuterung: issue.detail,
                raw: issue.boards.joined(separator: "|"),
                volatility: .persistent,
                evidenceClass: .indiz,
                sourceBoard: issue.boards.joined(separator: "/"),
                sourceRegister: "SN/FW",
                rawHex: nil,
                resetsOnPowerOff: false
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
                bewertung: "Änderung seit Protokoll \(delta.priorProtocol)",
                erlaeuterung: "Zeitlicher Vergleich derselben Seriennummer zwischen zwei Kontrollen.",
                raw: delta.priorProtocol,
                volatility: .persistent,
                evidenceClass: .indiz,
                sourceBoard: "Verlauf",
                sourceRegister: delta.title,
                rawHex: nil,
                resetsOnPowerOff: false
            ))
        }

        if !assessment.unknownRegisters.isEmpty {
            let sample = assessment.unknownRegisters.prefix(8).map {
                "\($0.name) \($0.address)=\($0.valueHex)"
            }.joined(separator: "; ")
            facts.append(MeasuredFact(
                id: "evidence.unknown.registers",
                group: .evidence,
                title: "Unknown-State Register",
                auslesewert: "\(assessment.unknownRegisters.count) ohne sichere Deutung",
                sollwert: "interpretiert oder dokumentiert",
                status: .nichtFeststellbar,
                bewertung: "Rohwert + FW-Kontext gespeichert, nicht überinterpretiert",
                erlaeuterung: sample,
                raw: sample,
                volatility: .persistent,
                evidenceClass: .unknown,
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
            auslesewert: String(assessment.fingerprint.digestSHA256.prefix(16)) + "…",
            sollwert: "Serien-Signatur \(assessment.fingerprint.profileId)",
            status: .regelkonform,
            bewertung: "\(assessment.fingerprint.fields.count) read-only Felder",
            erlaeuterung: "SHA-256 über Region/SN-Präfix, FW-Module, Limit, Gänge — Vergleichsanker für Serienzustände.",
            raw: assessment.fingerprint.digestSHA256,
            volatility: .persistent,
            evidenceClass: .abweichung,
            sourceBoard: "Fingerprint",
            sourceRegister: "composite",
            rawHex: assessment.fingerprint.digestSHA256,
            resetsOnPowerOff: false
        ))

        return facts
    }

    // MARK: - Helpers

    private static func hit(
        id: String,
        observed: String,
        stock: String,
        rawHex: String?,
        interpretation: String,
        evidenceClass: EvidenceClass
    ) -> EvidenceHit {
        let def = definition(id: id)
        let volatility = def?.volatility ?? .semiPersistent
        return EvidenceHit(
            id: id,
            title: def?.title ?? id,
            volatility: volatility,
            evidenceClass: evidenceClass,
            observed: observed,
            stockExpected: stock,
            sourceBoard: def?.sourceBoard ?? "—",
            sourceRegister: def?.sourceRegister ?? "—",
            rawHex: rawHex,
            interpretation: interpretation,
            correlatedWith: [],
            resetsOnPowerOff: volatility != .persistent
        )
    }

    private static func elevate(_ hits: inout [EvidenceHit], id: String, to cls: EvidenceClass) {
        guard let idx = hits.firstIndex(where: { $0.id == id }) else { return }
        let h = hits[idx]
        let order: [EvidenceClass: Int] = [.unknown: 0, .abweichung: 1, .indiz: 2, .nachweis: 3]
        guard (order[cls] ?? 0) > (order[h.evidenceClass] ?? 0) else { return }
        hits[idx] = EvidenceHit(
            id: h.id,
            title: h.title,
            volatility: h.volatility,
            evidenceClass: cls,
            observed: h.observed,
            stockExpected: h.stockExpected,
            sourceBoard: h.sourceBoard,
            sourceRegister: h.sourceRegister,
            rawHex: h.rawHex,
            interpretation: h.interpretation,
            correlatedWith: h.correlatedWith,
            resetsOnPowerOff: h.resetsOnPowerOff
        )
    }

    private static func demoteIsolatedLimit(_ hits: inout [EvidenceHit]) {
        guard let idx = hits.firstIndex(where: { $0.id == "speed.limit" }) else { return }
        let h = hits[idx]
        hits[idx] = EvidenceHit(
            id: h.id,
            title: h.title,
            volatility: h.volatility,
            evidenceClass: .abweichung,
            observed: h.observed,
            stockExpected: h.stockExpected,
            sourceBoard: h.sourceBoard,
            sourceRegister: h.sourceRegister,
            rawHex: h.rawHex,
            interpretation: h.interpretation + " (isoliert → geringe Gewichtung)",
            correlatedWith: h.correlatedWith,
            resetsOnPowerOff: h.resetsOnPowerOff
        )
    }

    private static func status(for cls: EvidenceClass) -> FactStatus {
        switch cls {
        case .nachweis: return .erheblichAbweichend
        case .indiz: return .abweichend
        case .abweichung: return .abweichend
        case .unknown: return .nichtFeststellbar
        }
    }

    private static func computeScore(hits: [EvidenceHit], trackBonus: Int) -> Int {
        var score = 100 + trackBonus
        // Nachweis zählt voll; isolierte Abweichungen nur leicht.
        var seen = Set<String>()
        for hit in hits {
            if seen.insert(hit.id).inserted {
                score -= hit.evidenceClass.scorePenalty
            }
        }
        // Persistente Nachweise zusätzlich leicht gewichten
        let persistentNachweis = hits.filter { $0.volatility == .persistent && $0.evidenceClass == .nachweis }.count
        score -= persistentNachweis * 3
        return min(100, max(0, score))
    }

    private static func suggestedVerdict(
        hits: [EvidenceHit],
        nachweis: Int,
        indiz: Int,
        score: Int,
        correlations: [String]
    ) -> VerdictLevel {
        let persistentIndizOrHigher = hits.filter {
            $0.volatility == .persistent && ($0.evidenceClass == .indiz || $0.evidenceClass == .nachweis)
        }.count

        // Getunt nur bei Nachweis oder starker Korrelation mehrerer persistenter Indizien.
        if nachweis >= 1 { return .tuned }
        if correlations.contains(where: { $0.contains("Manipulationsnachweis") }) { return .tuned }
        if persistentIndizOrHigher >= 3 && indiz >= 2 { return .tuned }
        if score < 40 && indiz >= 2 { return .tuned }

        if !hits.isEmpty || score < 85 { return .watch }
        return .stock
    }

    private static func buildSummary(
        nachweis: Int,
        indiz: Int,
        abweichung: Int,
        persistentHits: Int,
        correlations: [String],
        verdict: VerdictLevel
    ) -> String {
        var parts = [
            "\(nachweis) Nachweis, \(indiz) Indiz, \(abweichung) Abweichung",
            "\(persistentHits)× persistent"
        ]
        if let first = correlations.first {
            parts.append(first)
        }
        parts.append("Urteilvorschlag: \(verdict.label)")
        return parts.joined(separator: " · ")
    }

    static func crossBoardIssues(reading: IntegrityReading, profile: ScooterProfile) -> [CrossBoardIssue] {
        var issues: [CrossBoardIssue] = []

        let vehicle = reading.serialDisplay ?? reading.serialVcu
        let pairs: [(String, String?)] = [
            ("VCU", reading.serialVcu),
            ("MCU", reading.serialMcu),
            ("BLE", reading.serialBle),
            ("BMS", reading.serialBms),
            ("DIS", reading.serialDisplay)
        ]
        if let vehicle {
            for (board, sn) in pairs {
                guard let sn, !sn.isEmpty else { continue }
                if TrackClassifier.looksLikeModuleSerial(sn) { continue }
                if TrackClassifier.serialsMismatch(sn, vehicle) {
                    issues.append(CrossBoardIssue(
                        id: "cross.serial.\(board.lowercased())",
                        title: "SN \(board) ≠ Fahrzeug",
                        detail: "\(board)-SN \(sn) weicht von Fahrzeug-SN \(vehicle) ab",
                        boards: [board, "Fahrzeug"]
                    ))
                }
            }
        }

        // Region aus verschiedenen SN-Quellen
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

        let fws = [
            ("MCU", reading.fwMcu),
            ("BLE", reading.fwBle),
            ("BMS", reading.fwBms),
            ("VCU", reading.fwVcu)
        ].compactMap { name, ver -> (String, String)? in
            guard let ver, !ver.isEmpty else { return nil }
            return (name, ver)
        }
        if profile.family == .maxG3, fws.count >= 2 {
            // Nur flaggen wenn Katalog sagt inkonsistent — hier: leere vs. gesetzte Mischlage schon in CustomFirmwareDiff
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
            let left = a ?? "—"
            let right = b ?? "—"
            guard left != right else { return }
            deltas.append(TemporalDelta(
                id: "history.delta.\(id)",
                title: title,
                previous: left,
                current: right,
                priorProtocol: proto
            ))
        }

        let prevRegion = TrackClassifier.serialRegion(for: prior.serialDisplay ?? prior.serialVcu).label
        let curRegion = TrackClassifier.serialRegion(for: current.serialDisplay ?? current.serialVcu).label
        add("region", "Region", prevRegion, curRegion)
        add("fw.mcu", "MCU-FW", prior.fwMcu, current.fwMcu)
        add("fw.vcu", "VCU-FW", prior.fwVcu, current.fwVcu)
        add("fw.ble", "BLE-FW", prior.fwBle, current.fwBle)
        add(
            "limit",
            "Limit",
            prior.speedLimitKmh.map { Format.kmh.format(Optional($0)) },
            current.speedLimitKmh.map { Format.kmh.format(Optional($0)) }
        )
        add(
            "peak",
            "Trip-Peak",
            prior.peakSpeedKmh.map { Format.kmh.format(Optional($0)) },
            current.peakSpeedKmh.map { Format.kmh.format(Optional($0)) }
        )
        add(
            "gear",
            "Max-Gang",
            prior.gearMax.map(String.init),
            current.gearMax.map(String.init)
        )
        return deltas
    }

    static func baselineFingerprint(reading: IntegrityReading, profile: ScooterProfile) -> BaselineFingerprint {
        let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
        var fields: [String: String] = [
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
        let digest = sha256Hex(canonical)
        return BaselineFingerprint(profileId: profile.id, digestSHA256: digest, fields: fields)
    }

    /// Register ohne Deutung: leerer Decoded-Wert und kein bekannter Spec-Name.
    static func unknownRegisters(in reading: IntegrityReading) -> [RawRegister] {
        let knownPrefixes = [
            "dis_", "ble_", "vcu_", "mcu_", "bms_", "g3_", "tft_", "esc_"
        ]
        return reading.rawRegisters.filter { reg in
            let decodedEmpty = (reg.valueDecoded == nil || reg.valueDecoded?.isEmpty == true)
            let name = reg.name.lowercased()
            let looksKnown = knownPrefixes.contains { name.hasPrefix($0) }
            // Unbekannt: kein Decoded ODER Name nicht in bekannter Map — und Note „unbekannt“
            if let note = reg.note?.lowercased(), note.contains("unbekannt") || note.contains("unknown") {
                return true
            }
            return decodedEmpty && !looksKnown && !reg.valueHex.isEmpty
        }
    }

    private static func rawHex(forNames names: [String], in reading: IntegrityReading) -> String? {
        for name in names {
            if let reg = reading.rawRegisters.last(where: { $0.name == name || $0.name.hasSuffix(name) }) {
                return "\(reg.name) \(reg.address)=\(reg.valueHex)"
            }
        }
        // Fallback: address contains register hint
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

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
