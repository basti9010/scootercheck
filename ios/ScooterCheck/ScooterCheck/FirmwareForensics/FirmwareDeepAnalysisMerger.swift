import Foundation

/// Führt Katalog-, Binär-/Decompile- und spätere Server-Ergebnisse zusammen (deterministisch vor LLM).
enum FirmwareDeepAnalysisMerger {

    static func merge(_ parts: [FirmwareDeepAnalysisResult]) -> FirmwareDeepAnalysisResult? {
        guard let first = parts.first else { return nil }
        guard parts.count > 1 else {
            var single = first
            if single.classifiedFindings == nil {
                single.classifiedFindings = FirmwareEvidenceClassifier.classify(from: single)
            }
            return single
        }

        let sources = Set(parts.flatMap(\.sources))
        var speeds = first.speedLimits
        for p in parts.dropFirst() {
            mergeSpeeds(&speeds, p.speedLimits)
        }
        var transitions = parts.flatMap(\.modeTransitions).map { t in
            FirmwareModeTransitionFinding(
                id: t.id,
                title: t.title,
                trigger: FirmwareComboPolicy.sanitizeTrigger(t.trigger),
                effect: t.effect,
                evidence: t.evidence,
                source: t.source,
                confidence: t.confidence
            )
        }
        dedupeTransitions(&transitions)
        var inputs = parts.flatMap(\.inputHints)
        dedupeInputs(&inputs)
        let combos = FirmwareComboPolicy.sanitizeComboSummaries(
            Array(Set(parts.flatMap(\.comboSummaries))).sorted()
        )
        let notes = parts.flatMap(\.notes)
        let hasDet = parts.contains { $0.quality.hasDeterministicBasis }
        let llmOk = parts.contains { $0.sources.contains(.serverLLM) && $0.quality.llmSchemaValidated }
        let stock = parts.compactMap(\.stockDiff).first { $0.outcome == .identical || $0.outcome == .different }
            ?? parts.compactMap(\.stockDiff).first
        let r2Strings = Array(Set(parts.flatMap(\.r2StringsSample))).sorted()
        var yara = parts.flatMap(\.yaraMatches)
        var seenYara = Set<String>()
        yara = yara.filter { seenYara.insert($0.rule).inserted }

        // Optionale Server-Felder: vorhandene Werte behalten; fehlende dürfen nichts überschreiben.
        let ivt = firstNonNil(parts.map(\.cortexMIvt))
        let pinout = firstNonNil(parts.map(\.boardPinout))
        var classified = parts.compactMap(\.classifiedFindings).flatMap { $0 }
        if classified.isEmpty {
            classified = []
        }

        var result = FirmwareDeepAnalysisResult(
            schemaVersion: FirmwareDeepAnalysisResult.currentSchemaVersion,
            producedAt: Date(),
            sources: Array(sources).sorted { $0.rawValue < $1.rawValue },
            subjectSHA256: first.subjectSHA256,
            packageDisplayName: parts.compactMap(\.packageDisplayName).first ?? first.packageDisplayName,
            models: Array(Set(parts.flatMap(\.models))).sorted(),
            controllerType: parts.compactMap(\.controllerType).first ?? first.controllerType,
            speedLimits: speeds.sorted { $0.kmh < $1.kmh },
            maxSpeedKmhInCode: speeds.map(\.kmh).max(),
            legalCapKmhInCode: speeds.filter { $0.role == .legalCap }.map(\.kmh).min(),
            modeTransitions: transitions,
            inputHints: inputs,
            comboSummaries: combos,
            notes: notes,
            caveats: FirmwareDeepAnalysisResult.standardCaveats,
            quality: FirmwareDeepAnalysisQuality(
                hasDeterministicBasis: hasDet,
                llmSchemaValidated: llmOk,
                summary: hasDet
                    ? "Zusammengeführt (deterministische Basis\(llmOk ? " + validierte KI" : ""))."
                    : "Zusammengeführt ohne deterministische Basis — vorsichtig werten."
            ),
            stockDiff: stock,
            r2StringsSample: r2Strings,
            yaraMatches: yara,
            cortexMIvt: ivt,
            boardPinout: pinout,
            classifiedFindings: classified.isEmpty ? nil : classified
        )
        if result.classifiedFindings == nil {
            result.classifiedFindings = FirmwareEvidenceClassifier.classify(from: result)
        }
        return result
    }

    /// Validiert Server-/LLM-JSON: Schema-Version + mindestens ein Speed, Transition/Combo oder Stock-Diff.
    static func validateServerResult(_ result: FirmwareDeepAnalysisResult) -> FirmwareDeepAnalysisResult? {
        guard result.schemaVersion == FirmwareDeepAnalysisResult.currentSchemaVersion else { return nil }
        let stockHit = result.stockDiff?.outcome == .identical || result.stockDiff?.outcome == .different
        let meaningful = !result.speedLimits.isEmpty
            || !result.modeTransitions.isEmpty
            || !result.comboSummaries.isEmpty
            || stockHit
            || result.cortexMIvt != nil
            || result.boardPinout != nil
            || !result.yaraMatches.isEmpty
        guard meaningful else { return nil }
        var copy = result
        if result.sources.contains(.serverLLM) {
            copy.quality.llmSchemaValidated = true
            if copy.quality.summary.isEmpty {
                copy.quality.summary = "KI-Ergebnis schema-validiert."
            }
        }
        copy.caveats = FirmwareDeepAnalysisResult.standardCaveats
        copy.comboSummaries = FirmwareComboPolicy.sanitizeComboSummaries(copy.comboSummaries)
        copy.modeTransitions = copy.modeTransitions.map { t in
            FirmwareModeTransitionFinding(
                id: t.id,
                title: t.title,
                trigger: FirmwareComboPolicy.sanitizeTrigger(t.trigger),
                effect: t.effect,
                evidence: t.evidence,
                source: t.source,
                confidence: t.confidence
            )
        }
        // Fehlende optionale Felder nicht „löschen“ — validate arbeitet auf einer Kopie.
        if copy.classifiedFindings == nil {
            copy.classifiedFindings = FirmwareEvidenceClassifier.classify(from: copy)
        }
        return copy
    }

    /// Behält vorhandene optionale Felder, wenn `incoming` sie nicht setzt.
    static func coalesceOptionals(
        base: FirmwareDeepAnalysisResult,
        incoming: FirmwareDeepAnalysisResult
    ) -> FirmwareDeepAnalysisResult {
        var out = incoming
        if out.cortexMIvt == nil { out.cortexMIvt = base.cortexMIvt }
        if out.boardPinout == nil { out.boardPinout = base.boardPinout }
        if out.stockDiff == nil { out.stockDiff = base.stockDiff }
        if out.classifiedFindings == nil { out.classifiedFindings = base.classifiedFindings }
        if out.yaraMatches.isEmpty, !base.yaraMatches.isEmpty {
            out.yaraMatches = base.yaraMatches
        }
        if out.r2StringsSample.isEmpty, !base.r2StringsSample.isEmpty {
            out.r2StringsSample = base.r2StringsSample
        }
        return out
    }

    private static func firstNonNil<T>(_ values: [T?]) -> T? {
        for v in values {
            if let v { return v }
        }
        return nil
    }

    private static func mergeSpeeds(_ into: inout [FirmwareSpeedLimitFinding], _ extra: [FirmwareSpeedLimitFinding]) {
        var keys = Set(into.map { speedKey($0) })
        for f in extra {
            let k = speedKey(f)
            if keys.insert(k).inserted {
                into.append(f)
            }
        }
    }

    private static func speedKey(_ f: FirmwareSpeedLimitFinding) -> String {
        if let p = f.packedU16 { return "p\(p)" }
        return "k\(f.kmh)-\(f.role.rawValue)"
    }

    private static func dedupeTransitions(_ items: inout [FirmwareModeTransitionFinding]) {
        var seen = Set<String>()
        items = items.filter { seen.insert($0.title + "|" + $0.trigger).inserted }
    }

    private static func dedupeInputs(_ items: inout [FirmwareInputHintFinding]) {
        var seen = Set<String>()
        items = items.filter { seen.insert($0.kind.rawValue + "|" + $0.detail).inserted }
    }
}
