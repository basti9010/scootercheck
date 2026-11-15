import Foundation

/// Führt Katalog-, Binär-/Decompile- und spätere Server-Ergebnisse zusammen (deterministisch vor LLM).
enum FirmwareDeepAnalysisMerger {

    static func merge(_ parts: [FirmwareDeepAnalysisResult]) -> FirmwareDeepAnalysisResult? {
        guard let first = parts.first else { return nil }
        guard parts.count > 1 else { return first }

        let sources = Set(parts.flatMap(\.sources))
        var speeds = first.speedLimits
        for p in parts.dropFirst() {
            mergeSpeeds(&speeds, p.speedLimits)
        }
        var transitions = parts.flatMap(\.modeTransitions)
        dedupeTransitions(&transitions)
        var inputs = parts.flatMap(\.inputHints)
        dedupeInputs(&inputs)
        let combos = Array(Set(parts.flatMap(\.comboSummaries))).sorted()
        let notes = parts.flatMap(\.notes)
        let hasDet = parts.contains { $0.quality.hasDeterministicBasis }
        let llmOk = parts.contains { $0.sources.contains(.serverLLM) && $0.quality.llmSchemaValidated }

        return FirmwareDeepAnalysisResult(
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
            )
        )
    }

    /// Validiert Server-/LLM-JSON: Schema-Version + mindestens ein Speed oder Transition/Combo.
    static func validateServerResult(_ result: FirmwareDeepAnalysisResult) -> FirmwareDeepAnalysisResult? {
        guard result.schemaVersion == FirmwareDeepAnalysisResult.currentSchemaVersion else { return nil }
        let meaningful = !result.speedLimits.isEmpty
            || !result.modeTransitions.isEmpty
            || !result.comboSummaries.isEmpty
        guard meaningful else { return nil }
        var copy = result
        if result.sources.contains(.serverLLM) {
            copy.quality.llmSchemaValidated = true
            if copy.quality.summary.isEmpty {
                copy.quality.summary = "KI-Ergebnis schema-validiert."
            }
        }
        copy.caveats = FirmwareDeepAnalysisResult.standardCaveats
        return copy
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
