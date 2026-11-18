import Foundation

/// Plain-language briefing for Deep Analysis — keeps hex/path noise out of the first screen.
struct FirmwareDeepAnalysisBriefing: Equatable, Sendable {
    var headline: String
    var bullets: [String]
    /// Human-readable combo lines (Gas/Bremse/Power…), not bitfield dumps.
    var actionableCombos: [String]
    /// Remaining technical combo lines for advanced disclosure.
    var technicalCombos: [String]
    var humanModeTransitions: [FirmwareModeTransitionFinding]
    var technicalModeTransitions: [FirmwareModeTransitionFinding]
    var humanInputHints: [FirmwareInputHintFinding]
    var technicalInputHints: [FirmwareInputHintFinding]

    static func build(from deep: FirmwareDeepAnalysisResult) -> FirmwareDeepAnalysisBriefing {
        let (actionable, technical) = splitCombos(deep.comboSummaries)
        let (humanT, techT) = splitTransitions(deep.modeTransitions)
        let (humanI, techI) = splitInputs(deep.inputHints)

        var bullets: [String] = []

        if let stock = deep.stockDiff {
            switch stock.outcome {
            case .identical:
                bullets.append("Stock-Vergleich: Byte-identisch mit bekannter Referenz\(stock.referenceLabel.map { " („\($0)“)" } ?? "").")
            case .different:
                bullets.append("Stock-Vergleich: weicht von der Referenz ab\(stock.differingBytes.map { " (\($0) Bytes)" } ?? "").")
            case .noReference:
                bullets.append("Stock-Vergleich: keine passende Referenz in der Bibliothek.")
            case .skipped:
                break
            }
        }

        if let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode {
            bullets.append("Im Klartext-Image: Legal-nah ~\(Int(legal)) km/h und offen bis ~\(Int(maxK)) km/h — Soft-Unlock-typisch.")
        } else if let maxK = deep.maxSpeedKmhInCode {
            bullets.append("Höchste im Code gefundene Stufe: ~\(Int(maxK)) km/h.")
        }

        let speedRoles = Dictionary(grouping: deep.speedLimits, by: \.role)
        let openCount = (speedRoles[.openCap] ?? []).count
        let legalCount = (speedRoles[.legalCap] ?? []).count
        if openCount > 0, legalCount > 0 {
            bullets.append("\(legalCount) Legal-/StVZO-nahe und \(openCount) offene Speed-Stufen im Image.")
        }

        if deep.sources.contains(.serverLLM) {
            bullets.append("KI hat Combos/Modi ergänzt (schema-geprüft) — kein Beweis am Fahrzeug.")
        }

        if !actionable.isEmpty {
            bullets.append("Vermutete Bedienung: siehe „Vermutete Tastenfolge“ unten — Live-Test nötig.")
        } else if !humanT.isEmpty {
            bullets.append("Moduswechsel im Code angedeutet — genaue Tastenfolge unbestätigt.")
        }

        if bullets.isEmpty {
            bullets.append("Server-/Kataloganalyse ohne klare Kurz-Aussage — Details unten.")
        }

        let headline: String
        if deep.stockDiff?.outcome == .identical {
            headline = "Klartext ausgewertet: Image entspricht Stock-Referenz"
        } else if deep.legalCapKmhInCode != nil, deep.maxSpeedKmhInCode != nil,
                  (deep.maxSpeedKmhInCode ?? 0) > (deep.legalCapKmhInCode ?? 0) + 5 {
            headline = "Klartext ausgewertet: Legal- und Open-Limits im selben Image"
        } else if deep.sources.contains(where: { $0 == .serverDecompile || $0 == .serverR2 }) {
            headline = "Klartext ausgewertet — siehe Kurzfassung"
        } else {
            headline = "Deep Analysis — begrenzte Aussage"
        }

        return FirmwareDeepAnalysisBriefing(
            headline: headline,
            bullets: Array(bullets.prefix(6)),
            actionableCombos: Array(actionable.prefix(4)),
            technicalCombos: technical,
            humanModeTransitions: Array(humanT.prefix(4)),
            technicalModeTransitions: techT,
            humanInputHints: Array(humanI.prefix(4)),
            technicalInputHints: techI
        )
    }

    /// Refresh Ampel after successful server decrypt/analysis (overrides stale GRAU/encrypted).
    static func refreshedVerdict(
        current: FirmwareForensicVerdict,
        rationale: String,
        deep: FirmwareDeepAnalysisResult
    ) -> (FirmwareForensicVerdict, String) {
        if deep.stockDiff?.outcome == .identical {
            let ref = deep.stockDiff?.referenceLabel.map { " („\($0)“)" } ?? ""
            return (
                .green,
                "Server hat entschlüsselt und mit Stock verglichen: SHA-256 identisch\(ref). Keine Byte-Abweichung zur Referenz. (Offline wirkte die Datei nur verschlüsselt — das ist erledigt.)"
            )
        }
        if deep.stockDiff?.outcome == .different {
            let d = deep.stockDiff?.differingBytes.map(String.init) ?? "?"
            return (
                .red,
                "Server-Stock-Diff: konkrete Byte-Abweichung zur Referenz (\(d) Bytes). Keine automatische Rechtsaussage."
            )
        }
        if let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode, maxK > legal + 5 {
            return (
                .yellow,
                "Server-Klartext: Legal-nahe ~\(Int(legal)) km/h und offene Stufe bis ~\(Int(maxK)) km/h im selben Image (Soft-Unlock-typisch). Tastenfolge nur vermutet — Live-Test nötig. Offline-GRAU entfällt."
            )
        }
        if deep.sources.contains(where: {
            switch $0 {
            case .serverDecompile, .serverR2, .serverCapstone, .serverYara, .serverEmulation, .serverAngr, .serverLLM:
                return true
            default:
                return false
            }
        }) {
            if current == .gray {
                return (
                    .yellow,
                    "Server hat die Payload entschlüsselt und ausgewertet. Offline war sie unlesbar — die GRAU-Aussage gilt nicht mehr. Details in der Kurzfassung."
                )
            }
        }
        return (current, rationale)
    }

    // MARK: - Splitters

    private static func looksTechnical(_ s: String) -> Bool {
        let t = s.lowercased()
        if t.contains("puvar") || t.contains("0x") || t.contains("bitfeld") { return true }
        if t.contains("param_") || t.contains("uvar") || t.contains("local_") { return true }
        if t.contains("sub_") || t.contains("vorgänger") || t.contains("capstone") { return true }
        if t.contains("angr") || t.contains("cfg") { return true }
        return false
    }

    private static func looksActionableCombo(_ s: String) -> Bool {
        let t = s.lowercased()
        if looksTechnical(s) { return false }
        return t.contains("gas") || t.contains("bremse") || t.contains("power")
            || t.contains("kombi") || t.contains("taste") || t.contains("soft")
            || t.contains("panic") || t.contains("live-") || t.contains("yara")
    }

    private static func splitCombos(_ lines: [String]) -> (actionable: [String], technical: [String]) {
        var a: [String] = []
        var t: [String] = []
        for line in lines {
            if looksActionableCombo(line) {
                a.append(line)
            } else if looksTechnical(line) {
                t.append(line)
            } else {
                a.append(line)
            }
        }
        return (a, t)
    }

    private static func splitTransitions(
        _ items: [FirmwareModeTransitionFinding]
    ) -> (human: [FirmwareModeTransitionFinding], technical: [FirmwareModeTransitionFinding]) {
        var h: [FirmwareModeTransitionFinding] = []
        var t: [FirmwareModeTransitionFinding] = []
        for item in items {
            let blob = "\(item.title) \(item.trigger) \(item.effect)"
            if item.title.localizedCaseInsensitiveContains("Pfad zu")
                || item.title.localizedCaseInsensitiveContains("angr")
                || looksTechnical(blob) {
                t.append(item)
            } else {
                h.append(item)
            }
        }
        return (h, t)
    }

    private static func splitInputs(
        _ items: [FirmwareInputHintFinding]
    ) -> (human: [FirmwareInputHintFinding], technical: [FirmwareInputHintFinding]) {
        var h: [FirmwareInputHintFinding] = []
        var t: [FirmwareInputHintFinding] = []
        for item in items {
            if looksTechnical(item.detail) {
                t.append(item)
            } else {
                h.append(item)
            }
        }
        return (h, t)
    }
}
