import Foundation

// MARK: - Deep analysis (local deterministic + optional server / LLM)

/// Einheitliches Ergebnisformat — lokal, Ghidra-Server und KI müssen dasselbe Schema füllen.
/// Qualität: deterministic findings zuerst; LLM nur ergänzend und schema-validiert.
struct FirmwareDeepAnalysisResult: Equatable, Codable, Sendable {
    /// Schema-Version für App ↔ Server-Kompatibilität.
    var schemaVersion: Int
    var producedAt: Date
    var sources: [FirmwareDeepAnalysisSource]
    /// SHA-256 der ENC/Klartext-Payload oder des Archivs.
    var subjectSHA256: String
    var packageDisplayName: String?
    var models: [String]
    var controllerType: String?

    var speedLimits: [FirmwareSpeedLimitFinding]
    /// Höchste im Code/Katalog belegte km/h-Stufe (nicht Live-Auslese).
    var maxSpeedKmhInCode: Double?
    /// Niedrigste „legal/StVZO“-nahe Stufe (typisch 20/22), falls gefunden.
    var legalCapKmhInCode: Double?
    var modeTransitions: [FirmwareModeTransitionFinding]
    var inputHints: [FirmwareInputHintFinding]
    var comboSummaries: [String]
    var notes: [String]
    var caveats: [String]
    var quality: FirmwareDeepAnalysisQuality
    /// Server Stock-Diff gegen Referenzbibliothek (nach Decrypt).
    var stockDiff: FirmwareStockDiffResult? = nil
    /// Stichprobe interessanter Strings aus radare2 (`izz`).
    var r2StringsSample: [String] = []
    /// YARA-Treffer vom Server (investigativ).
    var yaraMatches: [FirmwareYaraMatch] = []
    /// Cortex-M Vektortabelle (Server-Heuristik).
    var cortexMIvt: FirmwareCortexMIvt? = nil
    /// Board-/Pinout-Heuristik vom Server (investigativ).
    var boardPinout: FirmwareBoardPinoutHint? = nil
    /// Klassifizierte Evidenzfunde (optional, abwärtskompatibel).
    var classifiedFindings: [FirmwareClassifiedFinding]? = nil
    /// Phase-2: kompakte Funktionsanalyse (Poll-Summary; Vollartefakt separat).
    var functionAnalysis: FirmwareFunctionAnalysisSummary? = nil
    /// Phase-2: funktionsbasierter Diff gegen Referenz (kein Manipulationsnachweis).
    var functionDiff: FirmwareFunctionDiffSummary? = nil
    /// Phase-2: Callgraph-Summary.
    var callGraph: FirmwareCallGraphSummary? = nil
    /// Phase-2: erweiterte Referenz-Metadaten.
    var referenceMetadata: FirmwareReferenceMetadata? = nil
    /// Phase-2: technische Einschränkungen der Analyse.
    var analysisLimitations: [String]? = nil
    /// Phase 2.2C: multi-stage Function Matching (optional).
    var functionMatching: FirmwareFunctionMatchingSummary? = nil
    /// Phase 2.2C: Input Behavior Analysis (optional).
    var inputBehaviorAnalysis: FirmwareInputBehaviorSummary? = nil
    /// Phase 2.2C: State Machine Analysis (optional; often nested under inputBehavior).
    var stateMachineAnalysis: FirmwareStateMachineAnalysisSummary? = nil
    /// Phase 2.2C: Input Behavior Diff vs reference (optional).
    var inputBehaviorDiff: FirmwareInputBehaviorDiffSummary? = nil

    static let currentSchemaVersion = 1

    static var standardCaveats: [String] {
        [
            "Code-/Katalogbefunde beweisen nicht, dass dieses Image aktuell im Controller steckt.",
            "ENC ohne Entschlüsselung: nur Meta, Hash und bekannte Signaturen — keine neuen Limit-Konstanten aus dem Ciphertext.",
            "KI-Auswertung (falls Server) darf nur dieses Schema füllen; Freitext ist kein Beweismittel.",
            "Tastenkombinationen nur bei Live-Vergleich oder Prefix Belegt:/Validiert: — keine Heuristik-Rätselraten."
        ]
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, producedAt, sources, subjectSHA256, packageDisplayName
        case models, controllerType, speedLimits, maxSpeedKmhInCode, legalCapKmhInCode
        case modeTransitions, inputHints, comboSummaries, notes, caveats, quality
        case stockDiff, r2StringsSample, yaraMatches, cortexMIvt, boardPinout, classifiedFindings
        case functionAnalysis, functionDiff, callGraph, referenceMetadata, analysisLimitations
        case functionMatching, inputBehaviorAnalysis, stateMachineAnalysis, inputBehaviorDiff
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        producedAt = try c.decode(Date.self, forKey: .producedAt)
        let rawSources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        sources = rawSources.compactMap { FirmwareDeepAnalysisSource(rawValue: $0) }
        subjectSHA256 = try c.decode(String.self, forKey: .subjectSHA256)
        packageDisplayName = try c.decodeIfPresent(String.self, forKey: .packageDisplayName)
        models = try c.decodeIfPresent([String].self, forKey: .models) ?? []
        controllerType = try c.decodeIfPresent(String.self, forKey: .controllerType)
        speedLimits = try c.decodeIfPresent([FirmwareSpeedLimitFinding].self, forKey: .speedLimits) ?? []
        maxSpeedKmhInCode = try c.decodeIfPresent(Double.self, forKey: .maxSpeedKmhInCode)
        legalCapKmhInCode = try c.decodeIfPresent(Double.self, forKey: .legalCapKmhInCode)
        modeTransitions = try c.decodeIfPresent([FirmwareModeTransitionFinding].self, forKey: .modeTransitions) ?? []
        inputHints = try c.decodeIfPresent([FirmwareInputHintFinding].self, forKey: .inputHints) ?? []
        comboSummaries = try c.decodeIfPresent([String].self, forKey: .comboSummaries) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        caveats = try c.decodeIfPresent([String].self, forKey: .caveats) ?? []
        quality = try c.decode(FirmwareDeepAnalysisQuality.self, forKey: .quality)
        stockDiff = try c.decodeIfPresent(FirmwareStockDiffResult.self, forKey: .stockDiff)
        r2StringsSample = try c.decodeIfPresent([String].self, forKey: .r2StringsSample) ?? []
        yaraMatches = try c.decodeIfPresent([FirmwareYaraMatch].self, forKey: .yaraMatches) ?? []
        cortexMIvt = try c.decodeIfPresent(FirmwareCortexMIvt.self, forKey: .cortexMIvt)
        boardPinout = try c.decodeIfPresent(FirmwareBoardPinoutHint.self, forKey: .boardPinout)
        classifiedFindings = try c.decodeIfPresent([FirmwareClassifiedFinding].self, forKey: .classifiedFindings)
        functionAnalysis = try c.decodeIfPresent(FirmwareFunctionAnalysisSummary.self, forKey: .functionAnalysis)
        functionDiff = try c.decodeIfPresent(FirmwareFunctionDiffSummary.self, forKey: .functionDiff)
        callGraph = try c.decodeIfPresent(FirmwareCallGraphSummary.self, forKey: .callGraph)
        referenceMetadata = try c.decodeIfPresent(FirmwareReferenceMetadata.self, forKey: .referenceMetadata)
        analysisLimitations = try c.decodeIfPresent([String].self, forKey: .analysisLimitations)
        functionMatching = try c.decodeIfPresent(FirmwareFunctionMatchingSummary.self, forKey: .functionMatching)
        inputBehaviorAnalysis = try c.decodeIfPresent(FirmwareInputBehaviorSummary.self, forKey: .inputBehaviorAnalysis)
        stateMachineAnalysis = try c.decodeIfPresent(FirmwareStateMachineAnalysisSummary.self, forKey: .stateMachineAnalysis)
            ?? inputBehaviorAnalysis?.stateMachineAnalysis
        inputBehaviorDiff = try c.decodeIfPresent(FirmwareInputBehaviorDiffSummary.self, forKey: .inputBehaviorDiff)
    }

    init(
        schemaVersion: Int,
        producedAt: Date,
        sources: [FirmwareDeepAnalysisSource],
        subjectSHA256: String,
        packageDisplayName: String? = nil,
        models: [String],
        controllerType: String? = nil,
        speedLimits: [FirmwareSpeedLimitFinding],
        maxSpeedKmhInCode: Double? = nil,
        legalCapKmhInCode: Double? = nil,
        modeTransitions: [FirmwareModeTransitionFinding],
        inputHints: [FirmwareInputHintFinding],
        comboSummaries: [String],
        notes: [String],
        caveats: [String],
        quality: FirmwareDeepAnalysisQuality,
        stockDiff: FirmwareStockDiffResult? = nil,
        r2StringsSample: [String] = [],
        yaraMatches: [FirmwareYaraMatch] = [],
        cortexMIvt: FirmwareCortexMIvt? = nil,
        boardPinout: FirmwareBoardPinoutHint? = nil,
        classifiedFindings: [FirmwareClassifiedFinding]? = nil,
        functionAnalysis: FirmwareFunctionAnalysisSummary? = nil,
        functionDiff: FirmwareFunctionDiffSummary? = nil,
        callGraph: FirmwareCallGraphSummary? = nil,
        referenceMetadata: FirmwareReferenceMetadata? = nil,
        analysisLimitations: [String]? = nil,
        functionMatching: FirmwareFunctionMatchingSummary? = nil,
        inputBehaviorAnalysis: FirmwareInputBehaviorSummary? = nil,
        stateMachineAnalysis: FirmwareStateMachineAnalysisSummary? = nil,
        inputBehaviorDiff: FirmwareInputBehaviorDiffSummary? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.producedAt = producedAt
        self.sources = sources
        self.subjectSHA256 = subjectSHA256
        self.packageDisplayName = packageDisplayName
        self.models = models
        self.controllerType = controllerType
        self.speedLimits = speedLimits
        self.maxSpeedKmhInCode = maxSpeedKmhInCode
        self.legalCapKmhInCode = legalCapKmhInCode
        self.modeTransitions = modeTransitions
        self.inputHints = inputHints
        self.comboSummaries = comboSummaries
        self.notes = notes
        self.caveats = caveats
        self.quality = quality
        self.stockDiff = stockDiff
        self.r2StringsSample = r2StringsSample
        self.yaraMatches = yaraMatches
        self.cortexMIvt = cortexMIvt
        self.boardPinout = boardPinout
        self.classifiedFindings = classifiedFindings
        self.functionAnalysis = functionAnalysis
        self.functionDiff = functionDiff
        self.callGraph = callGraph
        self.referenceMetadata = referenceMetadata
        self.analysisLimitations = analysisLimitations
        self.functionMatching = functionMatching
        self.inputBehaviorAnalysis = inputBehaviorAnalysis
        self.stateMachineAnalysis = stateMachineAnalysis ?? inputBehaviorAnalysis?.stateMachineAnalysis
        self.inputBehaviorDiff = inputBehaviorDiff
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(producedAt, forKey: .producedAt)
        try c.encode(sources.map(\.rawValue), forKey: .sources)
        try c.encode(subjectSHA256, forKey: .subjectSHA256)
        try c.encodeIfPresent(packageDisplayName, forKey: .packageDisplayName)
        try c.encode(models, forKey: .models)
        try c.encodeIfPresent(controllerType, forKey: .controllerType)
        try c.encode(speedLimits, forKey: .speedLimits)
        try c.encodeIfPresent(maxSpeedKmhInCode, forKey: .maxSpeedKmhInCode)
        try c.encodeIfPresent(legalCapKmhInCode, forKey: .legalCapKmhInCode)
        try c.encode(modeTransitions, forKey: .modeTransitions)
        try c.encode(inputHints, forKey: .inputHints)
        try c.encode(comboSummaries, forKey: .comboSummaries)
        try c.encode(notes, forKey: .notes)
        try c.encode(caveats, forKey: .caveats)
        try c.encode(quality, forKey: .quality)
        try c.encodeIfPresent(stockDiff, forKey: .stockDiff)
        try c.encode(r2StringsSample, forKey: .r2StringsSample)
        try c.encode(yaraMatches, forKey: .yaraMatches)
        try c.encodeIfPresent(cortexMIvt, forKey: .cortexMIvt)
        try c.encodeIfPresent(boardPinout, forKey: .boardPinout)
        try c.encodeIfPresent(classifiedFindings, forKey: .classifiedFindings)
        try c.encodeIfPresent(functionAnalysis, forKey: .functionAnalysis)
        try c.encodeIfPresent(functionDiff, forKey: .functionDiff)
        try c.encodeIfPresent(callGraph, forKey: .callGraph)
        try c.encodeIfPresent(referenceMetadata, forKey: .referenceMetadata)
        try c.encodeIfPresent(analysisLimitations, forKey: .analysisLimitations)
        try c.encodeIfPresent(functionMatching, forKey: .functionMatching)
        try c.encodeIfPresent(inputBehaviorAnalysis, forKey: .inputBehaviorAnalysis)
        try c.encodeIfPresent(stateMachineAnalysis, forKey: .stateMachineAnalysis)
        try c.encodeIfPresent(inputBehaviorDiff, forKey: .inputBehaviorDiff)
    }
}

enum FirmwareDeepAnalysisSource: String, Codable, Sendable {
    case localDeterministic
    case knownCatalog
    case serverDecompile
    case serverR2
    case serverCapstone
    case serverYara
    case serverEmulation
    case serverAngr
    case serverIvt
    case serverLLM
    case liveVehicleContext

    var label: String {
        switch self {
        case .localDeterministic: return "Lokal deterministisch"
        case .knownCatalog: return "Bekannte CFW-Signatur"
        case .serverDecompile: return "Server-Decompile"
        case .serverR2: return "Server-radare2"
        case .serverCapstone: return "Server-Capstone"
        case .serverYara: return "Server-YARA"
        case .serverEmulation: return "Server-Unicorn"
        case .serverAngr: return "Server-Pfadanalyse"
        case .serverIvt: return "Server-IVT"
        case .serverLLM: return "Server-KI (schema-gebunden)"
        case .liveVehicleContext: return "Live-Fahrzeugkontext"
        }
    }
}

struct FirmwareDeepAnalysisQuality: Equatable, Codable, Sendable {
    /// true, wenn mindestens eine deterministische oder Katalog-Quelle vorliegt.
    var hasDeterministicBasis: Bool
    /// true, wenn LLM-Felder nur nach Schema-Validierung übernommen wurden.
    var llmSchemaValidated: Bool
    var summary: String
}

enum FirmwareStockDiffOutcome: String, Equatable, Codable, Sendable {
    case identical
    case different
    case noReference
    case skipped

    var label: String {
        switch self {
        case .identical: return "Identisch mit Stock"
        case .different: return "Weicht von Stock ab"
        case .noReference: return "Keine Stock-Referenz"
        case .skipped: return "Stock-Diff übersprungen"
        }
    }
}

struct FirmwareStockDiffSegment: Equatable, Codable, Sendable {
    var offset: Int
    var length: Int
    var note: String
}

struct FirmwareYaraMatch: Equatable, Codable, Sendable, Identifiable {
    var rule: String
    var description: String
    var confidence: String
    var family: String? = nil
    var tags: [String]
    var strings: [String]

    var id: String { rule + "|" + description }
}

struct FirmwareStockDiffResult: Equatable, Codable, Sendable {
    var outcome: FirmwareStockDiffOutcome
    var referenceId: String?
    var referenceLabel: String?
    var referenceSHA256: String?
    var referenceSource: String? = nil
    var differingBytes: Int?
    var firstDiffOffset: Int?
    var subjectBytes: Int?
    var referenceBytes: Int?
    var percentDifferent: Double?
    var segments: [FirmwareStockDiffSegment]
    var note: String
    var trustedRefCount: Int? = nil
    var totalRefCount: Int? = nil
    var candidateRefCount: Int? = nil
    var matchedModels: [String]? = nil
    var limitRegionAffected: Bool? = nil
    var panicRegionAffected: Bool? = nil
    var regionNotes: [String]? = nil
    /// `manufacturerVerified` | `communityLibrary` | `serialProduction` | `unknown`
    var referenceTrust: String? = nil
    /// Nur true, wenn Herkunft explizit verifiziert wurde (nicht bloß source=oem).
    var referenceProvenanceVerified: Bool? = nil
}

struct FirmwareStockRef: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var label: String
    var model: String
    var controllerType: String
    var version: String
    var source: String? = nil
    var region: String? = nil
    var notes: String? = nil
    var trusted: Bool? = nil
    var sha256: String
    var byteCount: Int
    var manufacturer: String? = nil
    var modelAliases: [String]? = nil
    var hardwareVersion: String? = nil
    var firmwareVersion: String? = nil
    var origin: String? = nil
    var addedAt: String? = nil
    var verificationStatus: String? = nil
    var compatibility: String? = nil
    var fileSize: Int? = nil
    var referenceTrust: String? = nil
    var provenanceVerified: Bool? = nil
}

// MARK: - Phase 2 function analysis (optional, backward-compatible)

struct FirmwareFunctionAnalysisSummary: Equatable, Codable, Sendable {
    var ok: Bool?
    var functionCount: Int?
    var truncated: Bool?
    var processor: String?
    var notes: [String]?
    var analysisLimitations: [String]?
    var sampleFunctions: [FirmwareFunctionBrief]?
}

struct FirmwareFunctionBrief: Equatable, Codable, Sendable, Identifiable {
    var address: String?
    var name: String?
    var size: Int?
    var basicBlocks: Int?
    var fingerprint: String?
    var confidence: String?

    var id: String { (address ?? "") + "|" + (name ?? "") }
}

enum FirmwareFunctionDiffStatus: String, Equatable, Codable, Sendable {
    case identical = "IDENTISCH"
    case structurallyChanged = "STRUKTURELL_VERAENDERT"
    case added = "HINZUGEFUEGT"
    case removed = "ENTFERNT"
    case uncomparable = "NICHT_VERGLEICHBAR"

    var label: String {
        switch self {
        case .identical: return "Identisch"
        case .structurallyChanged: return "Strukturell verändert"
        case .added: return "Hinzugefügt"
        case .removed: return "Entfernt"
        case .uncomparable: return "Nicht vergleichbar"
        }
    }
}

struct FirmwareFunctionDiffCounts: Equatable, Codable, Sendable {
    var identical: Int?
    var structurallyChanged: Int?
    var added: Int?
    var removed: Int?
    var uncomparable: Int?
    var subjectFunctionCount: Int?
    var referenceFunctionCount: Int?
    var overall: String?
    /// Phase 2.2C matching stats (optional).
    var matched: Int?
    var ambiguous: Int?
    var matchHigh: Int?
    var matchMedium: Int?
    var matchLow: Int?
}

struct FirmwareFunctionDiffPair: Equatable, Codable, Sendable, Identifiable {
    var status: FirmwareFunctionDiffStatus?
    var subject: FirmwareFunctionBrief?
    var reference: FirmwareFunctionBrief?
    var matchMethod: String?
    var matchConfidence: String?
    var similarityScore: Double?
    var featuresUsed: [String]?
    var evidenceTier: String?
    var notes: String?
    /// Freie Strukturunterschiede (Größe/Blöcke/CFG) — keine Tuning-Aussage.
    var differences: [String: FirmwareJSONValue]? = nil

    var id: String {
        (subject?.address ?? reference?.address ?? "") + "|" + (status?.rawValue ?? "")
    }
}

/// Minimaler JSON-Wert für optionale Diff-Details ohne hartes Schema.
enum FirmwareJSONValue: Equatable, Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: FirmwareJSONValue])
    case array([FirmwareJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: FirmwareJSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([FirmwareJSONValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct FirmwareFunctionDiffSummary: Equatable, Codable, Sendable {
    var ok: Bool?
    var tool: String?
    var toolNote: String?
    var summary: FirmwareFunctionDiffCounts?
    var samplePairs: [FirmwareFunctionDiffPair]?
    var functionMatching: FirmwareFunctionMatchingSummary?
    var analysisLimitations: [String]?
    var notes: [String]?
}

// MARK: - Phase 2.2C Function Matching / Input Behavior

struct FirmwareFunctionMatchingSummary: Equatable, Codable, Sendable {
    var ok: Bool?
    var tool: String?
    var toolNote: String?
    var summary: FirmwareFunctionMatchingCounts?
    var sampleMatches: [FirmwareFunctionMatchSample]?
    var analysisLimitations: [String]?
    var notes: [String]?
}

struct FirmwareFunctionMatchingCounts: Equatable, Codable, Sendable {
    var matched: Int?
    var high: Int?
    var medium: Int?
    var low: Int?
    var ambiguous: Int?
    var unmatched: Int?
    var pairCount: Int?
}

struct FirmwareFunctionMatchSample: Equatable, Codable, Sendable, Identifiable {
    var subject: FirmwareFunctionBrief?
    var reference: FirmwareFunctionBrief?
    var similarityScore: Double?
    var matchConfidence: String?
    var matchMethod: String?
    var featuresUsed: [String]?
    var notes: String?

    var id: String {
        (subject?.address ?? "") + "|" + (reference?.address ?? "") + "|" + (matchMethod ?? "")
    }
}

struct FirmwareInputBehaviorSummary: Equatable, Codable, Sendable {
    var ok: Bool?
    var tool: String?
    var toolNote: String?
    var summary: FirmwareInputBehaviorCounts?
    var categories: [String: Int]?
    var sampleInputFunctions: [FirmwareInputFunctionFinding]?
    var stateMachineAnalysis: FirmwareStateMachineAnalysisSummary?
    var evidenceTier: String?
    var analysisLimitations: [String]?
    var notes: [String]?
}

struct FirmwareInputBehaviorCounts: Equatable, Codable, Sendable {
    var functionCount: Int?
    var inputRelevantCount: Int?
    var confirmedCount: Int?
    var indicativeCount: Int?
    var speculativeCount: Int?
    var categoryCount: Int?
}

struct FirmwareInputFunctionFinding: Equatable, Codable, Sendable, Identifiable {
    var address: String?
    var name: String?
    var categories: [String]?
    var evidenceTier: String?
    var score: Double?
    var evidence: [String]?
    var basicBlocks: Int?
    var cfgEdges: Int?

    var id: String { (address ?? "") + "|" + (name ?? "") }
}

struct FirmwareStateMachineAnalysisSummary: Equatable, Codable, Sendable {
    var ok: Bool?
    var stateMachineCount: Int?
    var totalEstimatedStates: Int?
    var totalEstimatedTransitions: Int?
    var evidenceTier: String?
    var sampleStateMachines: [FirmwareStateMachineFinding]?
    var analysisLimitations: [String]?
    var notes: [String]?
}

struct FirmwareStateMachineFinding: Equatable, Codable, Sendable, Identifiable {
    var functionAddress: String?
    var functionName: String?
    var estimatedStates: Int?
    var estimatedTransitions: Int?
    var analysisQuality: String?
    var uncertainty: String?
    var evidence: [String]?

    var id: String { (functionAddress ?? "") + "|" + (functionName ?? "") }
}

struct FirmwareInputBehaviorDiffSummary: Equatable, Codable, Sendable {
    var ok: Bool?
    var tool: String?
    var summary: FirmwareFunctionDiffCounts?
    var samplePairs: [FirmwareInputBehaviorDiffPair]?
    var stateMachineDiff: FirmwareStateMachineDiffBrief?
    var evidenceTier: String?
    var analysisLimitations: [String]?
    var notes: [String]?
}

struct FirmwareInputBehaviorDiffPair: Equatable, Codable, Sendable, Identifiable {
    var status: String?
    var subject: FirmwareInputFunctionFinding?
    var reference: FirmwareInputFunctionFinding?
    var matchMethod: String?
    var evidenceTier: String?
    var notes: String?

    var id: String {
        (subject?.address ?? reference?.address ?? "") + "|" + (status ?? "")
    }
}

struct FirmwareStateMachineDiffBrief: Equatable, Codable, Sendable {
    var subjectStateMachines: Int?
    var referenceStateMachines: Int?
    var delta: Int?
    var notes: String?
}

struct FirmwareCallGraphSummary: Equatable, Codable, Sendable {
    var ok: Bool?
    var edgeCount: Int?
    var staticEdgeCount: Int?
    var heuristicCount: Int?
    var unresolvedCount: Int?
    var truncated: Bool?
    var notes: [String]?
    var analysisLimitations: [String]?
}

struct FirmwareReferenceMetadata: Equatable, Codable, Sendable {
    var referenceId: String?
    var referenceLabel: String?
    var referenceSHA256: String?
    var referenceSource: String?
    var referenceTrust: String?
    var referenceProvenanceVerified: Bool?
    var matchedModels: [String]?
    var outcome: String?
    var note: String?
    var manufacturer: String?
    var model: String?
    var modelAliases: [String]?
    var controllerType: String?
    var hardwareVersion: String?
    var firmwareVersion: String?
    var fileSize: Int?
    var origin: String?
    var addedAt: String?
    var verificationStatus: String?
    var compatibility: String?
    var candidateRefCount: Int?
    var totalRefCount: Int?
}
struct FirmwareCortexMIvt: Equatable, Codable, Sendable {
    var likely: Bool?
    var flashBase: String?
    var initialSP: String?
    var resetHandler: String?
    var resetFileOffset: Int?
    var resetThumb: Bool?
}

struct FirmwareBoardPinoutHint: Equatable, Codable, Sendable {
    var id: String?
    var notes: String?
    /// Legacy field from older servers — ignored for UI (no button hallucination).
    var defaultComboHypothesis: String? = nil
}
struct FirmwareStockList: Equatable, Codable, Sendable {
    var stockFwDir: String?
    var refs: [FirmwareStockRef]
    var count: Int
}

enum FirmwareSpeedLimitRole: String, Codable, Sendable {
    case legalCap
    case openCap
    case regionOrMode
    case intermediate
    case unknown

    var label: String {
        switch self {
        case .legalCap: return "Legal-/StVZO-nahe Kappe"
        case .openCap: return "Offene / Max-Kappe"
        case .regionOrMode: return "Regions-/Moduslimit"
        case .intermediate: return "Zwischenstufe"
        case .unknown: return "Unklar"
        }
    }
}

struct FirmwareSpeedLimitFinding: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var kmh: Double
    /// Rohes packed u16 (High-Byte = km/h), falls bekannt — z. B. 0x1600.
    var packedU16: UInt16?
    var role: FirmwareSpeedLimitRole
    var evidence: String
    var source: FirmwareDeepAnalysisSource
    var confidence: FirmwareFindingConfidence
}

enum FirmwareFindingConfidence: String, Codable, Sendable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high: return "hoch"
        case .medium: return "mittel"
        case .low: return "niedrig"
        }
    }
}

enum FirmwareInputKind: String, Codable, Sendable {
    case throttle
    case brake
    case power
    case customButton
    case dualAnalog
    case unknown

    var label: String {
        switch self {
        case .throttle: return "Gas"
        case .brake: return "Bremse"
        case .power: return "Power"
        case .customButton: return "Custom-Button"
        case .dualAnalog: return "Zwei Analogkanäle (Gas/Bremse-Muster)"
        case .unknown: return "Unbekannter Eingang"
        }
    }
}

struct FirmwareInputHintFinding: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var kind: FirmwareInputKind
    var detail: String
    var evidence: String
    var source: FirmwareDeepAnalysisSource
    var confidence: FirmwareFindingConfidence
}

struct FirmwareModeTransitionFinding: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var trigger: String
    var effect: String
    var evidence: String
    var source: FirmwareDeepAnalysisSource
    var confidence: FirmwareFindingConfidence
}

// MARK: - Server job contract (App ↔ Decrypt/Ghidra/KI)

enum FirmwareAnalysisJobState: String, Codable, Sendable {
    case queued
    case decrypting
    case decompiling
    case extracting
    case llmEnrichment
    case completed
    case failed
    case notConfigured

    var label: String {
        switch self {
        case .queued: return "Warteschlange"
        case .decrypting: return "Decrypt"
        case .decompiling: return "Ghidra"
        case .extracting: return "Auswertung"
        case .llmEnrichment: return "KI"
        case .completed: return "Fertig"
        case .failed: return "Fehler"
        case .notConfigured: return "Nicht konfiguriert"
        }
    }
}

struct FirmwareDecompilePreview: Equatable, Codable, Sendable {
    var jobId: String
    var path: String?
    var totalChars: Int
    var preview: String
    var truncated: Bool
}

struct FirmwareAnalysisJobRequest: Equatable, Codable, Sendable {
    var clientReportId: String
    var originalFileName: String
    var archiveSHA256: String
    var payloadSHA256: String?
    var infoJSON: String?
    var models: [String]
    var controllerType: String?
    /// true = Server darf ENC entschlüsseln (nur mit rechtmäßigem Key-Vault).
    var allowDecrypt: Bool
    /// true = nach deterministic extract optional schema-gebundene KI.
    var allowLLM: Bool
}

struct FirmwareAnalysisJobStatus: Equatable, Codable, Sendable {
    var jobId: String
    var state: FirmwareAnalysisJobState
    var progressPercent: Int
    var message: String
    var result: FirmwareDeepAnalysisResult?
    var errorCode: String?
    var createdBy: String? = nil
    var createdByUserId: String? = nil
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
    var originalFileName: String? = nil
    var archiveSHA256: String? = nil
    /// Server path of saved decrypted BIN (Hetzner store), if decrypt succeeded.
    var plaintextPath: String? = nil
    var plaintextSHA256: String? = nil
    var plaintextSaved: Bool? = nil
    /// Server path of Ghidra-exported decompiled C, if headless succeeded.
    var decompilePath: String? = nil
    var decompileSaved: Bool? = nil
}

struct FirmwareAdminJobsList: Equatable, Codable, Sendable {
    var jobs: [FirmwareAnalysisJobStatus]
    var total: Int
    var returned: Int
}

struct FirmwareAdminUserStats: Equatable, Codable, Sendable, Identifiable {
    var createdBy: String
    var createdByUserId: String?
    var jobs: Int
    var completed: Int
    var failed: Int
    var queuedOrRunning: Int
    var withDecompile: Int

    var id: String { createdBy }
}

struct FirmwareAdminStats: Equatable, Codable, Sendable {
    var totalJobs: Int
    var retentionDays: Int
    var maxStoredJobs: Int
    var users: [FirmwareAdminUserStats]
}

struct FirmwareLlmKeyStatus: Equatable, Codable, Sendable {
    var present: Bool?
    var usable: Bool?
    var kind: String?
    var hint: String?
}

/// Antwort von `GET /health` des Firmware-Workers (ohne Secrets).
struct FirmwareWorkerHealth: Equatable, Codable, Sendable {
    var ok: Bool
    var service: String?
    var decryptConfigured: Bool?
    var ghidraConfigured: Bool?
    var ghidraEnabled: Bool?
    var llmConfigured: Bool?
    var llmKeyStatus: FirmwareLlmKeyStatus?
    var llmProvider: String?
    var llmModel: String?
    var jwtConfigured: Bool?
    var retentionDays: Int?
    var maxStoredJobs: Int?
    var stockFwDir: String?
    var stockRefCount: Int?
    var r2Configured: Bool?
    var capstoneConfigured: Bool?
    var yaraConfigured: Bool?
    var unicornConfigured: Bool?
    var angrLiteConfigured: Bool?
    var angrEngineConfigured: Bool?
    var angrTimeoutSec: Int?
    var angrMemMb: Int?
    var angrCfgDepth: Int?
    var angrSymbolic: Bool?
}
