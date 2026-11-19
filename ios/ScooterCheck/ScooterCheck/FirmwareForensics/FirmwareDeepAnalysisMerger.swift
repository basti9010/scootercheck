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

        let functionAnalysis = firstNonNil(parts.map(\.functionAnalysis))
        let functionDiff = firstNonNil(parts.map(\.functionDiff))
        let callGraph = firstNonNil(parts.map(\.callGraph))
        let referenceMetadata = firstNonNil(parts.map(\.referenceMetadata))
        let functionMatching = firstNonNil(parts.map(\.functionMatching))
            ?? firstNonNil(parts.map { $0.functionDiff?.functionMatching })
        let inputBehaviorAnalysis = firstNonNil(parts.map(\.inputBehaviorAnalysis))
        let stateMachineAnalysis = firstNonNil(parts.map(\.stateMachineAnalysis))
            ?? inputBehaviorAnalysis?.stateMachineAnalysis
        let inputBehaviorDiff = firstNonNil(parts.map(\.inputBehaviorDiff))
        let analysisCompleteness = firstNonNil(parts.map(\.analysisCompleteness))
        let firmwareAnalysisCoverage = firstNonNil(parts.map(\.firmwareAnalysisCoverage))
        let referenceCatalogCoverage = firstNonNil(parts.map(\.referenceCatalogCoverage))
        let functionMatchingCoverage = firstNonNil(parts.map(\.functionMatchingCoverage))
        let stateMachineValidation = firstNonNil(parts.map(\.stateMachineValidation))
            ?? stateMachineAnalysis?.stateMachineValidation
        let callGraphQuality = firstNonNil(parts.map(\.callGraphQuality))
            ?? callGraph?.callGraphQuality
        let firmwareContainerAnalysis = firstNonNil(parts.map(\.firmwareContainerAnalysis))
        let referenceCatalogBatch = firstNonNil(parts.map(\.referenceCatalogBatch))
        let runtimeStateMachineValidation = firstNonNil(parts.map(\.runtimeStateMachineValidation))
        let analysisProfile = firstNonNil(parts.map(\.analysisProfile))
        let analysisProfileHash = firstNonNil(parts.map(\.analysisProfileHash))
            ?? analysisProfile?.analysisProfileHash
        let ghidraAddressLayout = firstNonNil(parts.map(\.ghidraAddressLayout))
        let firmwareArchitectureConfidence = firstNonNil(parts.map(\.firmwareArchitectureConfidence))
            ?? firmwareContainerAnalysis?.architectureConfidence
        let runtimeValidationDetails = firstNonNil(parts.map(\.runtimeValidationDetails))
        let ghidraReproducibility = firstNonNil(parts.map(\.ghidraReproducibility))
        let activationForensics = firstNonNil(parts.map(\.activationForensics))
        let limitations = Array(Set(parts.compactMap(\.analysisLimitations).flatMap { $0 }))

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
            classifiedFindings: classified.isEmpty ? nil : classified,
            functionAnalysis: functionAnalysis,
            functionDiff: functionDiff,
            callGraph: callGraph,
            referenceMetadata: referenceMetadata,
            analysisLimitations: limitations.isEmpty ? nil : limitations,
            functionMatching: functionMatching,
            inputBehaviorAnalysis: inputBehaviorAnalysis,
            stateMachineAnalysis: stateMachineAnalysis,
            inputBehaviorDiff: inputBehaviorDiff,
            analysisCompleteness: analysisCompleteness,
            firmwareAnalysisCoverage: firmwareAnalysisCoverage,
            referenceCatalogCoverage: referenceCatalogCoverage,
            functionMatchingCoverage: functionMatchingCoverage,
            stateMachineValidation: stateMachineValidation,
            callGraphQuality: callGraphQuality,
            firmwareContainerAnalysis: firmwareContainerAnalysis,
            referenceCatalogBatch: referenceCatalogBatch,
            runtimeStateMachineValidation: runtimeStateMachineValidation,
            analysisProfile: analysisProfile,
            analysisProfileHash: analysisProfileHash,
            ghidraAddressLayout: ghidraAddressLayout,
            firmwareArchitectureConfidence: firmwareArchitectureConfidence,
            runtimeValidationDetails: runtimeValidationDetails,
            ghidraReproducibility: ghidraReproducibility,
            activationForensics: activationForensics
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
        let phase2Hit = (result.functionAnalysis?.functionCount ?? 0) > 0
            || (result.functionDiff?.summary?.subjectFunctionCount ?? 0) > 0
            || (result.callGraph?.edgeCount ?? 0) > 0
            || (result.callGraphQuality?.directCalls ?? 0) > 0
            || (result.firmwareContainerAnalysis?.ok == true)
            || (result.runtimeStateMachineValidation?.ok == true)
            || (result.inputBehaviorAnalysis?.summary?.inputRelevantCount ?? 0) > 0
            || (result.functionMatching?.summary?.matched ?? 0) > 0
        let meaningful = !result.speedLimits.isEmpty
            || !result.modeTransitions.isEmpty
            || !result.comboSummaries.isEmpty
            || stockHit
            || phase2Hit
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
        if out.functionAnalysis == nil { out.functionAnalysis = base.functionAnalysis }
        if out.functionDiff == nil { out.functionDiff = base.functionDiff }
        if out.callGraph == nil { out.callGraph = base.callGraph }
        if out.referenceMetadata == nil { out.referenceMetadata = base.referenceMetadata }
        if out.analysisLimitations == nil { out.analysisLimitations = base.analysisLimitations }
        if out.functionMatching == nil { out.functionMatching = base.functionMatching }
        if out.inputBehaviorAnalysis == nil { out.inputBehaviorAnalysis = base.inputBehaviorAnalysis }
        if out.stateMachineAnalysis == nil { out.stateMachineAnalysis = base.stateMachineAnalysis }
        if out.inputBehaviorDiff == nil { out.inputBehaviorDiff = base.inputBehaviorDiff }
        if out.analysisCompleteness == nil { out.analysisCompleteness = base.analysisCompleteness }
        if out.firmwareAnalysisCoverage == nil { out.firmwareAnalysisCoverage = base.firmwareAnalysisCoverage }
        if out.referenceCatalogCoverage == nil { out.referenceCatalogCoverage = base.referenceCatalogCoverage }
        if out.functionMatchingCoverage == nil { out.functionMatchingCoverage = base.functionMatchingCoverage }
        if out.stateMachineValidation == nil { out.stateMachineValidation = base.stateMachineValidation }
        if out.callGraphQuality == nil { out.callGraphQuality = base.callGraphQuality }
        if out.firmwareContainerAnalysis == nil { out.firmwareContainerAnalysis = base.firmwareContainerAnalysis }
        if out.referenceCatalogBatch == nil { out.referenceCatalogBatch = base.referenceCatalogBatch }
        if out.runtimeStateMachineValidation == nil {
            out.runtimeStateMachineValidation = base.runtimeStateMachineValidation
        }
        if out.analysisProfile == nil { out.analysisProfile = base.analysisProfile }
        if out.analysisProfileHash == nil { out.analysisProfileHash = base.analysisProfileHash }
        if out.ghidraAddressLayout == nil { out.ghidraAddressLayout = base.ghidraAddressLayout }
        if out.firmwareArchitectureConfidence == nil {
            out.firmwareArchitectureConfidence = base.firmwareArchitectureConfidence
        }
        if out.runtimeValidationDetails == nil {
            out.runtimeValidationDetails = base.runtimeValidationDetails
        }
        if out.ghidraReproducibility == nil { out.ghidraReproducibility = base.ghidraReproducibility }
        if out.activationForensics == nil { out.activationForensics = base.activationForensics }
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
