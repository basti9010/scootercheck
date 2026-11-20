import Foundation

/// Abgeleiteter Untersuchungstyp — wird aus vorhandenen Artefakten berechnet, nie fest eingefroren.
enum InvestigationKind: String, Codable, Sendable, Equatable {
    case scooterOnly = "SCOOTER_ONLY"
    case firmwareOnly = "FIRMWARE_ONLY"
    case combined = "COMBINED"

    var label: String {
        switch self {
        case .scooterOnly: return "Nur Scooter-Auslesung"
        case .firmwareOnly: return "Nur Firmwaredatei"
        case .combined: return "Scooter + Firmware"
        }
    }
}

/// Kompakte, persistierbare Zusammenfassung einer BLE-Auslesung (kein Installationsnachweis für Firmware).
struct InvestigationReadoutSummary: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var savedAt: Date
    var protocolNumber: String?
    var profileId: String
    var modelLabel: String
    var serial: String?
    var fwVcu: String?
    var fwMcu: String?
    var fwBle: String?
    var fwEsc: String?
    var speedLimitKmh: Double?
    var blePeripheralId: UUID?
    var historyEntryId: String?

    var shortLabel: String {
        let model = modelLabel.isEmpty ? "Scooter" : modelLabel
        if let serial, !serial.isEmpty { return "\(model) · \(serial)" }
        return model
    }
}

/// Verweis auf eine Firmwareanalyse innerhalb einer Untersuchung.
struct InvestigationFirmwareRef: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var addedAt: Date
    var originalFileName: String
    var subjectSHA256: String?
    var reportId: String
    /// Relative path under the investigation pack directory (JSON dump of FirmwareForensicReport).
    var reportFileName: String
    var analysisCompleteness: String?
    var packageDisplayName: String?
}

struct InvestigationRecord: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var readout: InvestigationReadoutSummary?
    var firmwareRefs: [InvestigationFirmwareRef]
    var notes: [String]

    var kind: InvestigationKind {
        switch (readout != nil, firmwareRefs.isEmpty == false) {
        case (true, true): return .combined
        case (true, false): return .scooterOnly
        case (false, true): return .firmwareOnly
        case (false, false): return .scooterOnly // should not persist empty
        }
    }

    var isValid: Bool {
        readout != nil || !firmwareRefs.isEmpty
    }
}

/// Geführter Combined-Ablauf (UI-Zustand, nicht persistiert).
enum CombinedInvestigationStep: Int, Equatable, Sendable, CaseIterable {
    case selectScooter = 1
    case readScooter = 2
    case pickFirmware = 3
    case results = 4

    var title: String {
        switch self {
        case .selectScooter: return "E-Scooter auswählen"
        case .readScooter: return "E-Scooter auslesen"
        case .pickFirmware: return "Firmwaredatei auswählen"
        case .results: return "Gemeinsame Ergebnisse"
        }
    }

    var progressLabel: String { "Schritt \(rawValue) von 4" }
}

/// Aktiver Untersuchungsmodus in der App-Navigation (UI-Zustand).
enum InvestigationFlowMode: Equatable, Sendable {
    case none
    case scooterOnly
    case firmwareOnly
    case combined(CombinedInvestigationStep)
    /// Nachträgliche Ergänzung an bestehender Untersuchung.
    case appendFirmware(investigationId: String)
    case appendScooter(investigationId: String)
}
