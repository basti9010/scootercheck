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
        let validated = FirmwareComboPolicy.sanitizeComboSummaries(deep.comboSummaries)
        let leftover = deep.comboSummaries.filter { !validated.contains($0) }
        let (humanT, techT) = splitTransitions(deep.modeTransitions)
        let (humanI, techI) = splitInputs(deep.inputHints)

        var bullets: [String] = []

        if let stock = deep.stockDiff {
            switch stock.outcome {
            case .identical:
                bullets.append(
                    "Bibliotheks-Vergleich: Byte-identisch mit hinterlegter Referenz\(stock.referenceLabel.map { " („\($0)“)" } ?? "") — nur aussagekräftig, wenn das eine echte OEM-/Serien-Referenz ist (nicht dieselbe Falldatei)."
                )
            case .different:
                var diffLine = "Bibliotheks-Vergleich: weicht von der hinterlegten Referenz ab\(stock.differingBytes.map { " (\($0) Bytes)" } ?? "")"
                if let label = stock.referenceLabel, !label.isEmpty {
                    diffLine += " — Ref „\(label)“"
                }
                var tags: [String] = []
                if stock.limitRegionAffected == true { tags.append("Limit-Region") }
                if stock.panicRegionAffected == true { tags.append("Panic-Region") }
                if !tags.isEmpty {
                    diffLine += " (\(tags.joined(separator: ", ")))"
                }
                bullets.append(diffLine + ".")
            case .noReference:
                bullets.append("Kein passendes Stock-/OEM-Referenzbild für dieses Modell/Typ — kein Cross-Model-Fallback (Hochladen ≠ Referenz).")
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
            bullets.append("KI darf nur Belegt-/Validiert-Zeilen ergänzen — keine geratenen Tastenfolgen.")
        }

        if !validated.isEmpty {
            bullets.append("Validierte Kombination(en) aus Live-Vergleich oder Belegt-Evidenz — siehe unten.")
        } else {
            bullets.append("Keine validierte Tastenkombination aus dem Image ableitbar.")
            if !humanT.isEmpty {
                bullets.append("Limit-/Moduswechsel im Code erkennbar — Tastenfolge nicht belegt.")
            }
        }

        if bullets.isEmpty {
            bullets.append("Server-/Kataloganalyse ohne klare Kurz-Aussage — Details unten.")
        }

        let headline: String
        if deep.stockDiff?.outcome == .noReference,
           deep.legalCapKmhInCode != nil, deep.maxSpeedKmhInCode != nil,
           (deep.maxSpeedKmhInCode ?? 0) > (deep.legalCapKmhInCode ?? 0) + 5 {
            headline = "Klartext ausgewertet — Limits gefunden, kein OEM-Stock hinterlegt"
        } else if deep.stockDiff?.outcome == .identical {
            headline = "Klartext ausgewertet: passt zur hinterlegten Bibliotheks-Referenz"
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
            actionableCombos: Array(validated.prefix(4)),
            technicalCombos: leftover.filter { looksTechnical($0) },
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
                "Server-Klartext: SHA-256 identisch mit Bibliotheks-Referenz\(ref). Aussage nur gültig, wenn diese Referenz echte OEM-/Serien-Firmware ist — nicht dieselbe Falldatei als „Stock“."
            )
        }
        if deep.stockDiff?.outcome == .noReference,
           let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode, maxK > legal + 5 {
            return (
                .yellow,
                "Server hat entschlüsselt: Legal ~\(Int(legal)) und offen bis ~\(Int(maxK)) km/h im Image. Kein OEM-Stock in der Bibliothek — deshalb kein GRÜN/ROT aus Stock-Diff. Hochgeladene Falldatei ist keine Referenz."
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
                "Server-Klartext: Legal-nahe ~\(Int(legal)) km/h und offene Stufe bis ~\(Int(maxK)) km/h im selben Image. Tastenfolge nicht aus dem Image belegt — Live-Vergleich nötig. Offline-GRAU entfällt."
            )
        }
        if deep.sources.contains(where: {
            switch $0 {
            case .serverDecompile, .serverR2, .serverCapstone, .serverYara, .serverEmulation, .serverAngr, .serverIvt, .serverLLM:
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

    private static func splitTransitions(
        _ items: [FirmwareModeTransitionFinding]
    ) -> (human: [FirmwareModeTransitionFinding], technical: [FirmwareModeTransitionFinding]) {
        var h: [FirmwareModeTransitionFinding] = []
        var t: [FirmwareModeTransitionFinding] = []
        for item in items {
            let sanitized = FirmwareModeTransitionFinding(
                id: item.id,
                title: item.title,
                trigger: FirmwareComboPolicy.sanitizeTrigger(item.trigger),
                effect: item.effect,
                evidence: item.evidence,
                source: item.source,
                confidence: item.confidence
            )
            let blob = "\(sanitized.title) \(sanitized.trigger) \(sanitized.effect)"
            if sanitized.title.localizedCaseInsensitiveContains("Pfad zu")
                || sanitized.title.localizedCaseInsensitiveContains("angr")
                || looksTechnical(blob) {
                t.append(sanitized)
            } else {
                h.append(sanitized)
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
