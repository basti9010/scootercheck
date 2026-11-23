import Foundation

// MARK: - Epistemics

/// Epistemischer Status eines Querverweis-Befunds (BLE ↔ Dump ↔ ZIP).
/// `incomplete` = Quelle(n) fehlen — nie als bestätigt werten.
enum CorrelationEpistemics: String, Codable, Sendable, Equatable {
    /// Mehrere Quellen mit hartem Anker stimmen überein.
    case confirmed
    /// Einzelquelle, String-/Heuristik-Treffer oder Konflikt ohne Bestätigung.
    case hypothesis
    /// Mindestens eine nötige Quelle fehlt — kein Falsch-Positiv.
    case incomplete

    var label: String {
        switch self {
        case .confirmed: return "Bestätigt"
        case .hypothesis: return "Hypothese"
        case .incomplete: return "Unvollständig"
        }
    }
}

enum CorrelationKind: String, Codable, Sendable, Equatable {
    case deviceIdentity
    case modelFamily
    case firmwareVersion
    case imageDigestHint
    case speedPicture
    case customFirmwareHint
    case attributionAlign

    var label: String {
        switch self {
        case .deviceIdentity: return "Geräte-Identität"
        case .modelFamily: return "Modellfamilie"
        case .firmwareVersion: return "Firmware-Version"
        case .imageDigestHint: return "Image-Digest (Hinweis)"
        case .speedPicture: return "Geschwindigkeitsbild"
        case .customFirmwareHint: return "Custom-Firmware-Hinweis"
        case .attributionAlign: return "Attribution-Abgleich"
        }
    }
}

enum CorrelationSourceRef: String, Codable, Sendable, Equatable {
    case bleIdentity
    case dump
    case zip
    case evidence
    case attribution
    case forensicStub

    var label: String {
        switch self {
        case .bleIdentity: return "BLE-Identität"
        case .dump: return "Auslese"
        case .zip: return "Firmware-ZIP"
        case .evidence: return "Evidenz"
        case .attribution: return "Attribution"
        case .forensicStub: return "Forensik (Stub)"
        }
    }
}

enum CorrelationConfidence: String, Codable, Sendable, Equatable {
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

// MARK: - Lightweight input DTOs
// Intentionally independent of Investigation Flow / FirmwareForensicReport.
// Later adapters can wrap IntegrityReading, FirmwareZipReport, BLEIdentificationResult.

struct CorrelationBLEDeviceInfo: Codable, Sendable, Equatable {
    var peripheralId: UUID?
    /// z. B. `eScooter`, `unknown` — entspricht `BLEDeviceCategory.rawValue`.
    var categoryRaw: String?
    /// z. B. `high`, `medium`, `low`, `unknown`.
    var confidenceRaw: String?
    var model: String?
    var manufacturer: String?
    var listTitle: String?

    var isEScooterMediumOrHigher: Bool {
        guard categoryRaw == "eScooter" else { return false }
        switch confidenceRaw {
        case "high", "medium": return true
        default: return false
        }
    }
}

struct CorrelationFirmwareVersions: Codable, Sendable, Equatable {
    var fwVcu: String?
    var fwMcu: String?
    var fwBle: String?
    var fwBms: String?
    var fwEsc: String?

    var allNonEmpty: [String] {
        [fwVcu, fwMcu, fwBle, fwBms, fwEsc]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool { allNonEmpty.isEmpty }
}

/// Optionale Forensik-Zusammenfassung (Platzhalter bis FirmwareForensics merged).
struct CorrelationForensicSummaryStub: Codable, Sendable, Equatable {
    var stockDiffNote: String?
    /// Live-/Dump-Image-Hash, falls später verfügbar — nie ZIP-MD5 allein.
    var liveImageDigestHex: String?
    var customFirmwareLevelRaw: String?
}

struct CorrelationDeviceIdTraits: Codable, Sendable, Equatable {
    /// z. B. ScooterProfile.shortLabel / family title.
    var profileLabel: String?
    var modelLabel: String?
    var serialDisplay: String?
    var blePeripheralId: UUID?
}

struct CorrelationZipFindingInput: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kindRaw: String
    var title: String
    var detail: String
    var confidence: CorrelationConfidence
    var source: String
    /// Heuristik-Nadel (falls bekannt) für Softening.
    var needle: String?
}

struct CorrelationZipMeta: Codable, Sendable, Equatable {
    var fileName: String
    var displayName: String?
    var models: [String]
    var compatibleBoards: [String]
    var computedMd5: String?
    var declaredMd5: String?
    var md5Matches: Bool?
    var firmSizeBytes: Int?
    var findings: [CorrelationZipFindingInput]

    var searchableText: String {
        ([displayName].compactMap { $0 } + models + compatibleBoards + [fileName])
            .joined(separator: " ")
    }

    var hasContent: Bool {
        displayName != nil
            || !models.isEmpty
            || !compatibleBoards.isEmpty
            || computedMd5 != nil
            || firmSizeBytes != nil
            || !findings.isEmpty
    }
}

/// Eingabe-Snapshot für den reinen Korrelator (Adapter, kein Engine).
struct CrossSourceSnapshot: Codable, Sendable, Equatable {
    var bleDevice: CorrelationBLEDeviceInfo?
    var firmwareVersions: CorrelationFirmwareVersions?
    var deviceTraits: CorrelationDeviceIdTraits?
    var zipMeta: CorrelationZipMeta?
    var forensicStub: CorrelationForensicSummaryStub?

    static let zipNotInstalledCaveat =
        "ZIP-Datei ≠ installierte Firmware — Dateibefunde allein belegen keinen Fahrzeugzustand."

    init(
        bleDevice: CorrelationBLEDeviceInfo? = nil,
        firmwareVersions: CorrelationFirmwareVersions? = nil,
        deviceTraits: CorrelationDeviceIdTraits? = nil,
        zipMeta: CorrelationZipMeta? = nil,
        forensicStub: CorrelationForensicSummaryStub? = nil
    ) {
        self.bleDevice = bleDevice
        self.firmwareVersions = firmwareVersions
        self.deviceTraits = deviceTraits
        self.zipMeta = zipMeta
        self.forensicStub = forensicStub
    }
}

// MARK: - Output

struct CorrelationItem: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var kind: CorrelationKind
    var epistemics: CorrelationEpistemics
    var title: String
    var detail: String
    var sources: [CorrelationSourceRef]
    var confidence: CorrelationConfidence
}

struct SoftenedZipFinding: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var kindRaw: String
    var title: String
    var detail: String
    var confidence: CorrelationConfidence
    var epistemics: CorrelationEpistemics
    var source: String
    var annotation: String?
}

struct CrossSourceAssessment: Codable, Sendable, Equatable {
    var items: [CorrelationItem]
    var summary: String
    var caveats: [String]
    var softZipFindings: [SoftenedZipFinding]
    /// Nur Nebenkanal — speist EvidenceEngine.verdict nie.
    var attributionHints: [String]

    var confirmedItems: [CorrelationItem] {
        items.filter { $0.epistemics == .confirmed }
    }

    var hypothesisItems: [CorrelationItem] {
        items.filter { $0.epistemics == .hypothesis }
    }

    var incompleteItems: [CorrelationItem] {
        items.filter { $0.epistemics == .incomplete }
    }
}
