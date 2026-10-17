import Foundation

// MARK: - Attribution (getrennt vom Haupturteil)

/// Heuristische Vermutung zur Manipulations*methode* — nie urteilsbildend.
enum TuningMethod: String, Codable, CaseIterable, Sendable {
    case customFirmware
    case licensedSoftwareUnlock
    case sessionUnlock
    case regionChange
    case configurationModification
    case hardwareOrModuleSwap
    case unknownSoftwareManipulation

    var label: String {
        switch self {
        case .customFirmware: return "Custom-Firmware / Software-Modifikation"
        case .licensedSoftwareUnlock: return "Lizenzbasiertes Software-Unlock"
        case .sessionUnlock: return "Session-Unlock (temporär)"
        case .regionChange: return "Region-/Marktprofil-Änderung"
        case .configurationModification: return "Konfigurationsänderung"
        case .hardwareOrModuleSwap: return "Hardware-/Modul-Tausch"
        case .unknownSoftwareManipulation: return "Unklare Software-Manipulation"
        }
    }

    /// Defensive Formulierung — keine Tool-Zuordnung als Tatsache.
    var compatiblePhrase: String {
        switch self {
        case .customFirmware:
            return "Manipulationsmuster ist mit Custom-Firmware-/SHU-artigen Eingriffen vereinbar."
        case .licensedSoftwareUnlock:
            return "Manipulationsmuster ist kompatibel mit lizenzbasiertem Software-Unlock."
        case .sessionUnlock:
            return "Technisches Muster spricht für einen sessiongebundenen Unlock."
        case .regionChange:
            return "Muster spricht für eine Region-/Marktprofil-Abweichung ohne stärkere Mod-Firmware."
        case .configurationModification:
            return "Muster entspricht persistenter Konfigurationsänderung bei seriennaher Firmware."
        case .hardwareOrModuleSwap:
            return "Muster ist mit Hardware- oder Modul-Tausch vereinbar (Cross-Board)."
        case .unknownSoftwareManipulation:
            return "Softwareseitige Manipulation denkbar, Methode nicht eindeutig zuordenbar."
        }
    }
}

enum AttributionCatalog {
    /// Eigene Versionierung — unabhängig vom Evidence-Marker-Katalog.
    static let version = "1"
}

struct KnownAttributionPattern: Codable, Hashable, Sendable {
    let id: String
    let catalogVersion: String
    let method: TuningMethod
    let requiredMarkers: [String]
    let optionalMarkers: [String]
    let contradictingMarkers: [String]
    let minimumConfidence: Double
    let description: String
}

struct AttributionAssessment: Codable, Hashable, Sendable {
    let suspectedMethod: TuningMethod?
    let confidence: Double
    let supportingMarkerIds: [String]
    let contradictingMarkerIds: [String]
    let knownPatternId: String?
    let explanation: String
    let catalogVersion: String

    var isDeterminate: Bool {
        suspectedMethod != nil && confidence >= 0.4
    }

    var confidenceLabel: String {
        switch confidence {
        case 0.9...: return "Sehr hoch"
        case 0.7..<0.9: return "Hoch"
        case 0.4..<0.7: return "Mittel"
        default: return "Niedrig"
        }
    }

    var headline: String {
        guard isDeterminate, let method = suspectedMethod else {
            return "Art der Manipulation nicht eindeutig bestimmbar."
        }
        return "\(method.label) wahrscheinlich"
    }

    static let none = AttributionAssessment(
        suspectedMethod: nil,
        confidence: 0,
        supportingMarkerIds: [],
        contradictingMarkerIds: [],
        knownPatternId: nil,
        explanation: "Keine belastbare Methoden-Zuordnung.",
        catalogVersion: AttributionCatalog.version
    )
}

/// Ergebnisarten eines Power-Cycle-Vergleichs (für Attribution).
enum PowerCycleChangeKind: String, Codable, CaseIterable, Sendable {
    case unchanged
    case changed
    case disappeared
    case appeared
    case unavailableAfterRestart

    var label: String {
        switch self {
        case .unchanged: return "unverändert"
        case .changed: return "geändert"
        case .disappeared: return "verschwunden"
        case .appeared: return "neu erschienen"
        case .unavailableAfterRestart: return "nach Neustart nicht auslesbar"
        }
    }

    /// `unavailableAfterRestart` darf nie als `disappeared` gelten.
    var countsAsSessionClear: Bool {
        self == .disappeared
    }
}

enum AttributionEngine {

    static let patterns: [KnownAttributionPattern] = [
        KnownAttributionPattern(
            id: "ATTR_CUSTOM_FW_GENERIC_V1",
            catalogVersion: AttributionCatalog.version,
            method: .customFirmware,
            requiredMarkers: ["fw.custom"],
            optionalMarkers: ["speed.limit", "speed.peak", "gear.max", "region.sn"],
            contradictingMarkers: [],
            minimumConfidence: 0.75,
            description: "Bekannter Custom-/Mod-Firmware-Fingerprint mit optionalen Tempo-Korrelationen."
        ),
        KnownAttributionPattern(
            id: "ATTR_LICENSED_UNLOCK_GENERIC_V1",
            catalogVersion: AttributionCatalog.version,
            method: .licensedSoftwareUnlock,
            requiredMarkers: ["speed.limit"],
            optionalMarkers: ["gear.max", "safelock", "region.sn", "speed.peak"],
            contradictingMarkers: ["fw.custom", "fw.unknown"],
            minimumConfidence: 0.45,
            description: "Seriennahe Firmware mit persistenter Limit-/Gang-Änderung."
        ),
        KnownAttributionPattern(
            id: "ATTR_SESSION_UNLOCK_POWER_CYCLE_V1",
            catalogVersion: AttributionCatalog.version,
            method: .sessionUnlock,
            requiredMarkers: ["speed.session"],
            optionalMarkers: ["speed.peak", "session.reset"],
            contradictingMarkers: ["fw.custom"],
            minimumConfidence: 0.5,
            description: "Session-Tempo / flüchtige Marker; Power-Cycle kann bestätigen."
        ),
        KnownAttributionPattern(
            id: "ATTR_REGION_CHANGE_V1",
            catalogVersion: AttributionCatalog.version,
            method: .regionChange,
            requiredMarkers: ["region.sn"],
            optionalMarkers: [],
            contradictingMarkers: ["fw.custom", "speed.limit", "gear.max"],
            minimumConfidence: 0.45,
            description: "Region weicht ab, sonst seriennah."
        ),
        KnownAttributionPattern(
            id: "ATTR_CONFIG_MOD_GENERIC_V1",
            catalogVersion: AttributionCatalog.version,
            method: .configurationModification,
            requiredMarkers: ["speed.limit"],
            optionalMarkers: ["gear.max", "safelock", "speed.peak"],
            contradictingMarkers: ["fw.custom"],
            minimumConfidence: 0.4,
            description: "Persistente Parameterabweichung ohne Custom-FW-Fingerprint."
        ),
        KnownAttributionPattern(
            id: "ATTR_MODULE_SWAP_CROSS_BOARD_V1",
            catalogVersion: AttributionCatalog.version,
            method: .hardwareOrModuleSwap,
            requiredMarkers: [], // prefix match serial.cross.*
            optionalMarkers: [],
            contradictingMarkers: [],
            minimumConfidence: 0.55,
            description: "Cross-Board-SN-/Modul-Inkonsistenz."
        )
    ]

    /// Nur aus bestehenden EvidenceResults / Power-Cycle — nie urteilsbildend.
    static func assess(
        results: [EvidenceResult],
        powerCycle: PowerCycleReport?,
        correlations: [String] = []
    ) -> AttributionAssessment {
        let active = results.filter { !$0.isNeutralized }
        let activeIds = Set(active.map(\.fact.markerID))
        let neutralizedIds = Set(results.filter(\.isNeutralized).map(\.fact.markerID))
        let contributingIds = Set(results.filter(\.contributesToVerdict).map(\.fact.markerID))

        // Neutralisierte Marker zählen nicht als Support.
        guard !contributingIds.isEmpty || active.contains(where: { $0.classification.rank >= EvidenceClass.abweichung.rank })
                || hasCrossBoard(activeIds)
                || sessionClearedByPowerCycle(powerCycle) else {
            return AttributionAssessment(
                suspectedMethod: nil,
                confidence: 0,
                supportingMarkerIds: [],
                contradictingMarkerIds: [],
                knownPatternId: nil,
                explanation: "Art der Manipulation nicht eindeutig bestimmbar — keine relevanten aktiven Marker.",
                catalogVersion: AttributionCatalog.version
            )
        }

        var candidates: [(pattern: KnownAttributionPattern, score: Double, support: [String], contra: [String])] = []

        for pattern in patterns {
            if pattern.id == "ATTR_MODULE_SWAP_CROSS_BOARD_V1" {
                let cross = activeIds.filter { $0.hasPrefix("serial.cross") }
                guard !cross.isEmpty else { continue }
                let score = min(1.0, 0.55 + 0.12 * Double(cross.count))
                candidates.append((pattern, score, Array(cross).sorted(), []))
                continue
            }

            let requiredHit = pattern.requiredMarkers.filter { activeIds.contains($0) && !neutralizedIds.contains($0) }
            guard requiredHit.count == pattern.requiredMarkers.count, !pattern.requiredMarkers.isEmpty else {
                continue
            }

            let optionalHit = pattern.optionalMarkers.filter { activeIds.contains($0) && !neutralizedIds.contains($0) }
            let contraHit = pattern.contradictingMarkers.filter { activeIds.contains($0) }

            var score = pattern.minimumConfidence
            score += 0.08 * Double(optionalHit.count)
            // Qualität: starke Klassen / bekannte Mod-Match-IDs
            for id in requiredHit + optionalHit {
                guard let r = active.first(where: { $0.fact.markerID == id }) else { continue }
                if r.classification == .starkerHinweis { score += 0.08 }
                if r.fact.knownModMatchId != nil { score += 0.05 }
                if r.fact.persistence == .persistent { score += 0.03 }
                if r.fact.knowledgeSource == .verifiedModSample { score += 0.07 }
                if r.fact.knowledgeSource == .heuristic { score -= 0.02 }
            }
            score -= 0.15 * Double(contraHit.count)

            // Einzelmarker ohne spezifische Signatur deckeln — keine sichere Attribution
            if requiredHit.count + optionalHit.count == 1, pattern.method != .customFirmware {
                score = min(score, 0.39)
            }

            candidates.append((pattern, score, requiredHit + optionalHit, contraHit))
        }

        // Power-Cycle-Modifier
        applyPowerCycleModifiers(
            candidates: &candidates,
            powerCycle: powerCycle,
            activeIds: activeIds
        )

        // Widerspruch Custom-FW vs. Session
        if activeIds.contains("fw.custom"),
           let idx = candidates.firstIndex(where: { $0.pattern.method == .sessionUnlock }) {
            candidates[idx].score = min(candidates[idx].score, 0.25)
            candidates[idx].contra.append("fw.custom")
        }

        // Region allein (neutralisiert oder ohne Tempo) nicht hoch bewerten
        if let idx = candidates.firstIndex(where: { $0.pattern.method == .regionChange }) {
            if neutralizedIds.contains("region.sn") {
                candidates[idx].score = 0
            } else if activeIds.contains(where: { $0.hasPrefix("speed.") || $0 == "gear.max" || $0 == "fw.custom" }) {
                candidates[idx].score *= 0.5
                candidates[idx].contra.append(contentsOf: activeIds.filter {
                    $0.hasPrefix("speed.") || $0 == "gear.max" || $0 == "fw.custom"
                })
            }
        }

        // Licensed vs Config: bei seriennaher FW und persistentem Limit bevorzugt licensed wenn mehr Optionals
        _ = correlations

        guard let best = candidates.max(by: { $0.score < $1.score }), best.score >= 0.4 else {
            let weakSupport = Array(contributingIds).sorted()
            let method: TuningMethod? = weakSupport.isEmpty ? nil : .unknownSoftwareManipulation
            let conf = method == nil ? 0.15 : min(0.39, 0.2 + 0.05 * Double(weakSupport.count))
            return AttributionAssessment(
                suspectedMethod: method,
                confidence: conf,
                supportingMarkerIds: weakSupport,
                contradictingMarkerIds: [],
                knownPatternId: nil,
                explanation: method == nil
                    ? "Art der Manipulation nicht eindeutig bestimmbar."
                    : "\(TuningMethod.unknownSoftwareManipulation.compatiblePhrase) Zuordnung mit niedriger Konfidenz.",
                catalogVersion: AttributionCatalog.version
            )
        }

        var confidence = min(1.0, max(0, best.score))
        // Katalogisierter Custom-FW-Fingerprint → hohe Bandbreite
        if best.pattern.method == .customFirmware, activeIds.contains("fw.custom") {
            confidence = max(confidence, 0.9)
            if activeIds.contains("speed.limit") || activeIds.contains("speed.peak") {
                confidence = min(1.0, confidence + 0.05)
            }
        }

        // Widersprüchliche Marker → unknown oder runter
        if best.contra.count >= 2, best.pattern.method != .unknownSoftwareManipulation {
            if confidence < 0.55 {
                return AttributionAssessment(
                    suspectedMethod: .unknownSoftwareManipulation,
                    confidence: min(confidence, 0.45),
                    supportingMarkerIds: Array(Set(best.support)).sorted(),
                    contradictingMarkerIds: Array(Set(best.contra)).sorted(),
                    knownPatternId: nil,
                    explanation: "Mehrere widersprüchliche Marker — \(TuningMethod.unknownSoftwareManipulation.compatiblePhrase)",
                    catalogVersion: AttributionCatalog.version
                )
            }
            confidence = min(confidence, 0.65)
        }

        let method = best.pattern.method
        var lines: [String] = [method.compatiblePhrase, "Zuordnung mit \(confidenceLabel(confidence)) Konfidenz."]
        lines.append("Pattern \(best.pattern.id): \(best.pattern.description)")
        for id in Array(Set(best.support)).sorted() {
            if let r = active.first(where: { $0.fact.markerID == id }) {
                lines.append("• Support \(id): \(r.fact.interpretedValue ?? r.rawValue) [\(r.classification.label)]")
            } else {
                lines.append("• Support \(id)")
            }
        }
        for id in Array(Set(best.contra)).sorted() {
            lines.append("• Gegenbeleg \(id)")
        }
        if let pc = powerCycle {
            let kinds = pc.rows.map { "\($0.markerID)=\($0.changeKind.rawValue)" }.joined(separator: ", ")
            lines.append("Power-Cycle: \(kinds)")
        }

        return AttributionAssessment(
            suspectedMethod: method,
            confidence: confidence,
            supportingMarkerIds: Array(Set(best.support)).sorted(),
            contradictingMarkerIds: Array(Set(best.contra)).sorted(),
            knownPatternId: best.pattern.id,
            explanation: lines.joined(separator: "\n"),
            catalogVersion: AttributionCatalog.version
        )
    }

    // MARK: - Helpers

    private static func hasCrossBoard(_ ids: Set<String>) -> Bool {
        ids.contains { $0.hasPrefix("serial.cross") }
    }

    private static func sessionClearedByPowerCycle(_ report: PowerCycleReport?) -> Bool {
        guard let report else { return false }
        return report.rows.contains {
            ($0.markerID == "speed.session" || $0.markerID == "speed.limit" || $0.markerID == "speed.peak")
                && $0.changeKind.countsAsSessionClear
        }
    }

    private static func applyPowerCycleModifiers(
        candidates: inout [(pattern: KnownAttributionPattern, score: Double, support: [String], contra: [String])],
        powerCycle: PowerCycleReport?,
        activeIds: Set<String>
    ) {
        guard let powerCycle else { return }

        let sessionRow = powerCycle.rows.first { $0.markerID == "speed.session" }
        let limitRow = powerCycle.rows.first { $0.markerID == "speed.limit" }
        let fwRow = powerCycle.rows.first { $0.markerID.hasPrefix("fw.") }

        // Unlock verschwindet → Session-Unlock verstärken
        if let sessionRow, sessionRow.changeKind.countsAsSessionClear {
            if let idx = candidates.firstIndex(where: { $0.pattern.method == .sessionUnlock }) {
                candidates[idx].score = min(1.0, candidates[idx].score + 0.25)
                candidates[idx].support.append("powercycle.session.disappeared")
            } else if !activeIds.contains("fw.custom") {
                // synthetischer Kandidat wenn Session-Marker nur über Power-Cycle sichtbar
                if let pattern = patterns.first(where: { $0.id == "ATTR_SESSION_UNLOCK_POWER_CYCLE_V1" }) {
                    candidates.append((pattern, 0.62, ["powercycle.session.disappeared"], []))
                }
            }
        }

        // unavailableAfterRestart ≠ disappeared
        if let sessionRow, sessionRow.changeKind == .unavailableAfterRestart {
            if let idx = candidates.firstIndex(where: { $0.pattern.method == .sessionUnlock }) {
                candidates[idx].score = min(candidates[idx].score, 0.35)
                candidates[idx].contra.append("powercycle.session.unavailableAfterRestart")
            }
        }

        // Persistentes Limit nach Cycle → gegen Session, für Config/Licensed
        if let limitRow, limitRow.changeKind == .unchanged, limitRow.scanA != "—", limitRow.scanA != "0" {
            if let idx = candidates.firstIndex(where: { $0.pattern.method == .sessionUnlock }) {
                candidates[idx].score *= 0.6
                candidates[idx].contra.append("powercycle.limit.unchanged")
            }
            for method in [TuningMethod.configurationModification, .licensedSoftwareUnlock] {
                if let idx = candidates.firstIndex(where: { $0.pattern.method == method }) {
                    candidates[idx].score = min(1.0, candidates[idx].score + 0.1)
                    candidates[idx].support.append("powercycle.limit.persistent")
                }
            }
        }

        if let fwRow, fwRow.changeKind == .unchanged {
            if let idx = candidates.firstIndex(where: { $0.pattern.method == .customFirmware }) {
                candidates[idx].support.append("powercycle.fw.persistent")
            }
        }
    }

    private static func confidenceLabel(_ c: Double) -> String {
        switch c {
        case 0.9...: return "sehr hoher"
        case 0.7..<0.9: return "hoher"
        case 0.4..<0.7: return "mittlerer"
        default: return "niedriger"
        }
    }
}

// MARK: - Power-cycle change classification

enum PowerCycleChangeClassifier {
    static func classify(scanA: String, scanB: String) -> PowerCycleChangeKind {
        let aUnavail = isUnavailable(scanA)
        let bUnavail = isUnavailable(scanB)

        if !aUnavail && bUnavail {
            return .unavailableAfterRestart
        }
        if aUnavail && !bUnavail {
            return .appeared
        }
        if aUnavail && bUnavail {
            return .unchanged
        }
        if scanA == scanB {
            return .unchanged
        }
        if isActiveFlag(scanA) && isInactiveFlag(scanB) {
            return .disappeared
        }
        if isInactiveFlag(scanA) && isActiveFlag(scanB) {
            return .appeared
        }
        // Numerischer Rückgang auf Serien-/Nullniveau kann als disappeared gelten (Session)
        if let va = Double(scanA.replacingOccurrences(of: ",", with: ".")
                .split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? ""),
           let vb = Double(scanB.replacingOccurrences(of: ",", with: ".")
                .split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? ""),
           va > 30, vb <= 25 {
            return .disappeared
        }
        return .changed
    }

    private static func isUnavailable(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.isEmpty || t == "—" || t == "-" || t == "n/a" || t == "na" || t == "unavailable"
    }

    private static func isActiveFlag(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "1" || t == "true" || t == "aktiv" || t == "on"
    }

    private static func isInactiveFlag(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "0" || t == "false" || t == "inaktiv" || t == "off"
    }
}
