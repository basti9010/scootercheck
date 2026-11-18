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
        case stockDiff, r2StringsSample, yaraMatches, cortexMIvt, boardPinout
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
        boardPinout: FirmwareBoardPinoutHint? = nil
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
