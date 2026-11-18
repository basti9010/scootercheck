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

    static let currentSchemaVersion = 1

    static var standardCaveats: [String] {
        [
            "Code-/Katalogbefunde beweisen nicht, dass dieses Image aktuell im Controller steckt.",
            "ENC ohne Entschlüsselung: nur Meta, Hash und bekannte Signaturen — keine neuen Limit-Konstanten aus dem Ciphertext.",
            "KI-Auswertung (falls Server) darf nur dieses Schema füllen; Freitext ist kein Beweismittel.",
            "Physische Tastennamen (Gas/Bremse) kommen aus Signatur/Forum/Live-Test, nicht aus garantierten Symbolnamen im Decompile."
        ]
    }
}

enum FirmwareDeepAnalysisSource: String, Codable, Sendable {
    case localDeterministic
    case knownCatalog
    case serverDecompile
    case serverLLM
    case liveVehicleContext

    var label: String {
        switch self {
        case .localDeterministic: return "Lokal deterministisch"
        case .knownCatalog: return "Bekannte CFW-Signatur"
        case .serverDecompile: return "Server-Decompile"
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
