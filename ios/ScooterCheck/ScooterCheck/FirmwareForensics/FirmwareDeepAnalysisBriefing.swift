import Foundation

/// Kurze, verständliche Auswertung der Deep Analysis für die UI (ohne Hex-Salat).
enum FirmwareDeepAnalysisBriefing {
    struct Result: Equatable, Sendable {
        var headline: String
        var bullets: [String]
        /// Nur validierte (Live-/Belegt-) Zeilen — für die Haupt-UI.
        var actionableCombos: [String]
        /// Technische Restzeilen (Hex, Decompile) — eingeklappt.
        var technicalCombos: [String]
        var humanModeTransitions: [FirmwareModeTransitionFinding]
        var technicalModeTransitions: [FirmwareModeTransitionFinding]
        var humanInputHints: [FirmwareInputHintFinding]
        var technicalInputHints: [FirmwareInputHintFinding]
    }

    static func build(from deep: FirmwareDeepAnalysisResult) -> Result {
        let validated = FirmwareComboPolicy.sanitizeComboSummaries(deep.comboSummaries)
        let leftover = deep.comboSummaries.filter { line in
            !validated.contains { $0.caseInsensitiveCompare(line) == .orderedSame }
        }
        let (humanT, techT) = splitTransitions(deep.modeTransitions)
        let (humanI, techI) = splitInputs(deep.inputHints)

        var bullets: [String] = []

        if let stock = deep.stockDiff {
            let trust = FirmwareEvidenceClassifier.referenceTrust(for: stock)
            switch stock.outcome {
            case .identical:
                let ref = stock.referenceLabel.map { " „\($0)“" } ?? ""
                if trust.allowsGreenIdentity {
                    bullets.append("Identisch mit verifizierter OEM-Referenz\(ref).")
                } else {
                    bullets.append(
                        "SHA-identisch mit Bibliotheksreferenz\(ref) — \(trust.label). Kein automatisches GRÜN."
                    )
                }
            case .different:
                var diffLine = "Weicht von Referenz ab\(stock.differingBytes.map { " (\($0) Bytes)" } ?? "")"
                if let label = stock.referenceLabel, !label.isEmpty {
                    diffLine += " — Ref „\(label)“"
                }
                var tags: [String] = []
                if stock.limitRegionAffected == true { tags.append("Limit-Region") }
                if stock.panicRegionAffected == true { tags.append("Panic-Region") }
                if !tags.isEmpty {
                    diffLine += " (\(tags.joined(separator: ", ")))"
                }
                bullets.append(diffLine + ". Byte-Diff allein ist kein Manipulationsnachweis.")
            case .noReference:
                bullets.append("Kein passendes Stock-/OEM-Referenzbild — kein Cross-Model-Fallback.")
            case .skipped:
                break
            }
            bullets.append("Referenzvertrauen: \(trust.label).")
        }

        if let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode {
            bullets.append("Im Klartext-Image: Legal-nah ~\(Int(legal)) km/h und offen bis ~\(Int(maxK)) km/h — Soft-Unlock-typisch (STATISCH/MUSTER).")
        } else if let maxK = deep.maxSpeedKmhInCode {
            bullets.append("Höchste im Code gefundene Stufe: ~\(Int(maxK)) km/h.")
        }

        if !deep.yaraMatches.isEmpty {
            bullets.append(
                "YARA: \(deep.yaraMatches.count) Muster-Treffer (Evidenzstufe MUSTER — kein Live-Nachweis)."
            )
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

        let verdictPreview = refreshedVerdict(current: .gray, rationale: "", deep: deep)
        let headline: String
        switch verdictPreview.0 {
        case .green: headline = "Klartext: identisch mit verifizierter OEM-Referenz"
        case .red: headline = "Klartext: funktional bedeutsame Manipulation indiziert"
        case .yellow: headline = "Klartext ausgewertet — Auffälligkeiten, Ursache offen"
        case .gray: headline = "Unzureichende Datenlage für Ampel-Aussage"
        }

        return Result(
            headline: headline,
            bullets: Array(bullets.prefix(8)),
            actionableCombos: Array(validated.prefix(4)),
            technicalCombos: leftover.filter { looksTechnical($0) },
            humanModeTransitions: Array(humanT.prefix(4)),
            technicalModeTransitions: techT,
            humanInputHints: Array(humanI.prefix(4)),
            technicalInputHints: techI
        )
    }

    /// Ampel nach Server-Analyse — Byte-Diff allein → kein ROT.
    static func refreshedVerdict(
        current: FirmwareForensicVerdict,
        rationale: String,
        deep: FirmwareDeepAnalysisResult
    ) -> (FirmwareForensicVerdict, String) {
        let stock = deep.stockDiff
        let trust = stock.map { FirmwareEvidenceClassifier.referenceTrust(for: $0) } ?? .unknown
        let functional = hasFunctionalManipulationEvidence(deep)

        if let stock, stock.outcome == .identical {
            if trust.allowsGreenIdentity {
                let ref = stock.referenceLabel.map { " („\($0)“)" } ?? ""
                return (
                    .green,
                    "SHA-256 identisch mit nachweislich authentischer OEM-Referenz\(ref). Aussage gilt nur für diese Referenzversion — nicht als Installationsnachweis."
                )
            }
            let ref = stock.referenceLabel.map { " („\($0)“)" } ?? ""
            return (
                .yellow,
                "SHA-identisch mit Bibliotheksreferenz\(ref) (\(trust.label)). Identität ja — Herstellerursprung der Referenz nicht bestätigt; daher kein GRÜN."
            )
        }

        if let stock, stock.outcome == .different {
            let d = stock.differingBytes.map(String.init) ?? "?"
            if functional {
                return (
                    .red,
                    "Abweichung zur Referenz (\(d) Bytes) plus zusätzliche funktionale Indizien (Limit-/Panic-Region und/oder CFW-Muster mit Kontext). Keine automatische Rechtsaussage."
                )
            }
            return (
                .yellow,
                "Byte-Abweichung zur Referenz (\(d) Bytes) ohne abgeschlossenen funktionalen Manipulationsnachweis. Kann OEM-Update, Rebuild oder Patch sein — weitere Prüfung nötig."
            )
        }

        if stock?.outcome == .noReference || stock == nil {
            if let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode, maxK > legal + 5 {
                return (
                    .yellow,
                    "Klartext: Legal ~\(Int(legal)) und offen bis ~\(Int(maxK)) km/h. Keine passende Referenz — Ursache offen (GELB)."
                )
            }
            if deep.sources.contains(where: {
                switch $0 {
                case .serverDecompile, .serverR2, .serverCapstone, .serverYara,
                     .serverEmulation, .serverAngr, .serverIvt, .serverLLM:
                    return true
                default: return false
                }
            }) {
                if current == .gray || !deep.yaraMatches.isEmpty {
                    return (
                        .yellow,
                        "Server hat Klartext ausgewertet; Referenz fehlt oder ungeeignet. Auffälligkeiten möglich, Ursache nicht abschließend geklärt."
                    )
                }
            }
            if current == .gray {
                return (
                    .gray,
                    "Unzureichende Datenlage (keine geeignete Referenz / begrenzte Auswertung)."
                )
            }
        }

        if functional {
            return (
                .red,
                "Funktional bedeutsame Manipulationsindizien (CFW-Muster + Limit/Panic-Kontext) ohne entlastende Identitätsaussage."
            )
        }

        if let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode, maxK > legal + 5 {
            return (
                .yellow,
                "Legal-nahe ~\(Int(legal)) km/h und offene Stufe bis ~\(Int(maxK)) km/h im Image. Tastenfolge nicht aus dem Image belegt."
            )
        }

        if deep.sources.contains(where: {
            switch $0 {
            case .serverDecompile, .serverR2, .serverCapstone, .serverYara,
                 .serverEmulation, .serverAngr, .serverIvt:
                return true
            default: return false
            }
        }), current == .gray {
            return (
                .yellow,
                "Server hat die Payload entschlüsselt und ausgewertet. Offline-GRAU entfällt; Ursache etwaiger Auffälligkeiten offen."
            )
        }

        return (current, rationale)
    }

    /// ROT nur mit funktionalem Mehr als reinem Byte-Diff / einzelnem YARA.
    static func hasFunctionalManipulationEvidence(_ deep: FirmwareDeepAnalysisResult) -> Bool {
        let stock = deep.stockDiff
        let regionHit = (stock?.limitRegionAffected == true) && (stock?.panicRegionAffected == true)
        let yaraCFW = deep.yaraMatches.contains { m in
            let fam = (m.family ?? m.rule).lowercased()
            let hot = ["panicsystem", "soft-unlock", "softunlock", "scooterhacking", "esc-cfw", "cfw"]
            return hot.contains { fam.contains($0) }
        }
        let catalog = deep.sources.contains(.knownCatalog)
        let legalOpen: Bool = {
            guard let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode else { return false }
            return maxK > legal + 5
        }()

        // Mindestens zwei unabhängige Signalarten
        var score = 0
        if regionHit { score += 2 }
        else if stock?.limitRegionAffected == true || stock?.panicRegionAffected == true { score += 1 }
        if yaraCFW { score += 1 }
        if catalog { score += 1 }
        if legalOpen && (yaraCFW || regionHit || catalog) { score += 1 }
        if deep.sources.contains(.liveVehicleContext) && (yaraCFW || catalog) { score += 1 }
        return score >= 2
    }

    // MARK: - Splitters

    private static func looksTechnical(_ s: String) -> Bool {
        let low = s.lowercased()
        if low.contains("0x") || low.contains("puvar") || low.contains("ghidra") { return true }
        if low.contains("capstone") || low.contains("decompile") || low.contains("r2 ") { return true }
        return false
    }

    private static func splitTransitions(
        _ items: [FirmwareModeTransitionFinding]
    ) -> ([FirmwareModeTransitionFinding], [FirmwareModeTransitionFinding]) {
        var human: [FirmwareModeTransitionFinding] = []
        var tech: [FirmwareModeTransitionFinding] = []
        for t in items {
            let blob = (t.title + t.trigger + t.effect).lowercased()
            if looksTechnical(blob) || t.trigger.contains("0x") {
                tech.append(t)
            } else {
                human.append(t)
            }
        }
        return (human, tech)
    }

    private static func splitInputs(
        _ items: [FirmwareInputHintFinding]
    ) -> ([FirmwareInputHintFinding], [FirmwareInputHintFinding]) {
        var human: [FirmwareInputHintFinding] = []
        var tech: [FirmwareInputHintFinding] = []
        for h in items {
            if looksTechnical(h.detail) {
                tech.append(h)
            } else {
                human.append(h)
            }
        }
        return (human, tech)
    }
}
