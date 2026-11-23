import Foundation

// MARK: - Vehicle context (optional BLE / last readout)

struct FirmwareVehicleContext: Equatable, Codable, Sendable {
    var manufacturer: String?
    var modelLabel: String?
    var profileId: String?
    var serial: String?
    var fwVcu: String?
    var fwMcu: String?
    var fwBle: String?
    var fwEsc: String?
    var speedLimitKmh: Double?
    var speedMaxKmh: Double?
    var peakSpeedKmh: Double?
    var protocolNumber: String?
    /// True if context comes from a completed readout — still never proves the imported file is installed.
    var fromLiveReadout: Bool
}

// MARK: - Package / file inventory

enum FirmwareContainerKind: String, Codable, Sendable {
    case zipV3
    case zipGeneric
    case bareBinary
    case bareEncryptedBinary
    case json
    case text
    case unknown
}

enum FirmwarePayloadRole: String, Codable, Sendable {
    case infoJson
    case paramsText
    case firmPlain
    case firmEncrypted
    case other
}

struct FirmwareFileDigest: Equatable, Codable, Sendable {
    var md5: String
    var sha256: String
    var byteCount: Int
    var shannonEntropy: Double
}

struct FirmwarePackageEntry: Identifiable, Equatable, Codable, Sendable {
    var id: String { path }
    var path: String
    var role: FirmwarePayloadRole
    var digest: FirmwareFileDigest
    var analysisStatus: String
    var notes: [String]
}

struct FirmwarePackageMeta: Equatable, Codable, Sendable {
    var schemaVersion: Int?
    var displayName: String?
    var models: [String]
    var type: String?
    var compatible: [String]
    var declaredMd5: String?
    var declaredEncrypted: Bool?
    var rawInfoJSON: String?
}

enum FirmwareEncryptionStatus: String, Codable, Sendable {
    case confirmedByMetadata
    case likelyByStructure
    case plaintext
    case unknownFormat

    var label: String {
        switch self {
        case .confirmedByMetadata: return "Verschlüsselung durch Metadaten bestätigt"
        case .likelyByStructure: return "Verschlüsselung aufgrund der Datenstruktur wahrscheinlich"
        case .plaintext: return "Unverschlüsselte Firmware"
        case .unknownFormat: return "Unbekanntes Format"
        }
    }
}

struct FirmwareCryptoAssessment: Equatable, Codable, Sendable {
    var status: FirmwareEncryptionStatus
    var detectedFormat: String
    var decryptionAvailable: Bool
    var decryptionNote: String
    var evidence: [String]
}

enum FirmwareArchitectureHint: String, Codable, Sendable {
    case armCortexMLikely
    case at32FamilyHint
    case stm32FamilyHint
    case unknown

    var label: String {
        switch self {
        case .armCortexMLikely: return "ARM Cortex-M (Vektor-/Adressmuster)"
        case .at32FamilyHint: return "AT32-Familie (Board-/Stringhinweis)"
        case .stm32FamilyHint: return "STM32-Familie (Board-/Stringhinweis)"
        case .unknown: return "Architektur nicht bestimmbar"
        }
    }
}

struct FirmwareEvidenceItem: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var category: Category
    var title: String
    var detail: String
    /// Concrete technical anchor (offset, field, filename).
    var evidence: String
    var method: String
    var verifiability: Verifiability
    var confirmed: Bool

    enum Category: String, Codable, Sendable {
        case package
        case crypto
        case architecture
        case string
        case limitHint
        case modeHint
        case inputHint
        case diagnosticsHint
        case filenameHint
        case vehicleLink
        case comparison
        case limitation
    }

    enum Verifiability: String, Codable, Sendable {
        case confirmed
        case indicative
        case unverified
        case unavailable

        var label: String {
            switch self {
            case .confirmed: return "bestätigt (Dateiinhalt)"
            case .indicative: return "indikativ"
            case .unverified: return "nicht verifiziert"
            case .unavailable: return "nicht verfügbar"
            }
        }
    }
}

enum FirmwareComparisonOutcome: String, Codable, Sendable {
    case identical
    case different
    case knownAlternate
    case unknown
    case notPossible

    var label: String {
        switch self {
        case .identical: return "Identische Firmware"
        case .different: return "Unterschiedliche Firmware"
        case .knownAlternate: return "Bekannte alternative Firmware"
        case .unknown: return "Unbekannte Firmware"
        case .notPossible: return "Vergleich nicht möglich"
        }
    }
}

struct FirmwareSegmentDiff: Equatable, Codable, Sendable {
    var offset: Int
    var length: Int
    var note: String
}

struct FirmwareComparisonResult: Equatable, Codable, Sendable {
    /// Vergleichsstatus (comparisonStatus) — Identität / Diff / nicht möglich.
    var outcome: FirmwareComparisonOutcome
    var referenceId: String?
    var referenceLabel: String?
    var differingBytes: Int?
    var firstDiffOffset: Int?
    var segments: [FirmwareSegmentDiff]
    var note: String
    /// `FirmwareReferenceTrust.rawValue` — nie aus `note` ableiten.
    var referenceTrust: String? = nil
    /// Nur true bei explizit verifizierter Referenzherkunft.
    var referenceProvenanceVerified: Bool? = nil
    /// true nur bei belastbarem funktionalem Manipulationsnachweis (nicht Byte-Diff allein).
    var functionalChangeVerified: Bool? = nil

    /// Alias für Ampel-Dokumentation: Vergleichsstatus.
    var comparisonStatus: FirmwareComparisonOutcome { outcome }

    var resolvedReferenceTrust: FirmwareReferenceTrust {
        if let raw = referenceTrust, let parsed = FirmwareReferenceTrust(rawValue: raw) {
            return parsed
        }
        if referenceProvenanceVerified == true {
            return .manufacturerVerified
        }
        return .unknown
    }

    /// GRÜN nur bei Identität + herstellerseitig verifizierter Provenance.
    var allowsGreenIdentity: Bool {
        outcome == .identical
            && referenceProvenanceVerified == true
            && resolvedReferenceTrust.allowsGreenIdentity
    }
}

enum FirmwareForensicVerdict: String, Codable, Sendable {
    case green
    case yellow
    case red
    case gray

    var label: String {
        switch self {
        case .green:
            return "GRÜN — Identisch mit nachweislich authentischer OEM-Referenz"
        case .yellow:
            return "GELB — Technische Abweichung/Auffälligkeit; Ursache noch nicht abschließend geklärt"
        case .red:
            return "ROT — Konkret nachgewiesene, funktional bedeutsame Manipulation (nicht nur Byte-Diff)"
        case .gray:
            return "GRAU — Unzureichende Datenlage, fehlende Referenz oder Analyse nicht möglich"
        }
    }

    var shortLabel: String {
        switch self {
        case .green: return "GRÜN"
        case .yellow: return "GELB"
        case .red: return "ROT"
        case .gray: return "GRAU"
        }
    }
}

struct FirmwareBinaryAnalysis: Equatable, Codable, Sendable {
    var performed: Bool
    var unavailableReason: String?
    var architecture: FirmwareArchitectureHint
    var vectorTableLikely: Bool
    var resetHandlerHint: String?
    var stringsSample: [String]
    var codeDataNotes: [String]
}

/// Artifacts from optional server decrypt / Ghidra — for UI + PDF export.
struct FirmwareServerArtifacts: Equatable, Codable, Sendable {
    var jobId: String?
    var plaintextSaved: Bool?
    var plaintextSHA256: String?
    var plaintextByteCount: Int?
    var decompileSaved: Bool?
    /// Short decompile excerpt for the forensic PDF (not full .c).
    var decompileExcerpt: String?
}

struct FirmwareForensicReport: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var analyzedAt: Date
    var originalFileName: String
    var containerKind: FirmwareContainerKind
    var archiveByteCount: Int
    var archiveDigest: FirmwareFileDigest
    var meta: FirmwarePackageMeta
    var entries: [FirmwarePackageEntry]
    var primaryFirmwarePath: String?
    var crypto: FirmwareCryptoAssessment
    var binary: FirmwareBinaryAnalysis
    var evidence: [FirmwareEvidenceItem]
    var comparison: FirmwareComparisonResult?
    var verdict: FirmwareForensicVerdict
    var verdictRationale: String
    var limits: [String]
    var vehicleContext: FirmwareVehicleContext?
    var vehicleLinkNotes: [String]
    var summary: String
    /// Limits/Combos aus Katalog, Binär-/Decompile-Scan oder Server (einheitliches Schema).
    var deepAnalysis: FirmwareDeepAnalysisResult?
    /// Server decrypt / decompile metadata for export (optional).
    var serverArtifacts: FirmwareServerArtifacts? = nil
}
