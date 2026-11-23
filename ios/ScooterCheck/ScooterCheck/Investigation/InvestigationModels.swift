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

/// Dauerhaft speicherbarer Combined-/Untersuchungsfortschritt.
enum InvestigationProgress: String, Codable, Sendable, Equatable, CaseIterable {
    case selectScooter = "SELECT_SCOOTER"
    case readScooter = "READ_SCOOTER"
    case selectFirmware = "SELECT_FIRMWARE"
    case analyzeFirmware = "ANALYZE_FIRMWARE"
    case showResults = "SHOW_RESULTS"

    var title: String {
        switch self {
        case .selectScooter: return "E-Scooter auswählen"
        case .readScooter: return "E-Scooter auslesen"
        case .selectFirmware: return "Firmwaredatei auswählen"
        case .analyzeFirmware: return "Firmware analysieren"
        case .showResults: return "Ergebnisse"
        }
    }

    var nextStepHint: String {
        switch self {
        case .selectScooter: return "Nächster Schritt: E-Scooter auswählen"
        case .readScooter: return "Nächster Schritt: E-Scooter auslesen"
        case .selectFirmware: return "Nächster Schritt: Firmwaredatei auswählen"
        case .analyzeFirmware: return "Nächster Schritt: Firmwareanalyse abschließen"
        case .showResults: return "Untersuchung abgeschlossen — Ergebnisse verfügbar"
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
    var manufacturer: String?
    var serial: String?
    var fwVcu: String?
    var fwMcu: String?
    var fwBle: String?
    var fwEsc: String?
    var hardwareVersion: String?
    var controllerHint: String?
    var bleAdvertisementName: String?
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
    var analyzedAt: Date?
    var originalFileName: String
    var subjectSHA256: String?
    var byteCount: Int?
    var containerKind: String?
    var reportId: String
    /// Relative path under the investigation pack directory (JSON dump of FirmwareForensicReport).
    var reportFileName: String
    /// Relative path of the archived original binary/zip under the pack directory.
    var archivedBinaryFileName: String?
    var archiveStatus: String?
    var archiveError: String?
    var serverJobId: String?
    var analysisCompleteness: String?
    var packageDisplayName: String?
    var referenceTrust: String?

    var isArchived: Bool {
        archiveStatus == "ok" && archivedBinaryFileName != nil
    }
}

struct InvestigationRecord: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var readout: InvestigationReadoutSummary?
    var firmwareRefs: [InvestigationFirmwareRef]
    var notes: [String]
    /// Explizit gesetzter Fortschritt; wird mit `reconciledProgress` gegen Artefakte abgeglichen.
    var progress: InvestigationProgress?
    /// Vergleichsergebnisse können nach Scooter-Wechsel veraltet sein.
    var comparisonStale: Bool
    var comparisonNotes: [String]

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, title, readout, firmwareRefs, notes
        case progress, comparisonStale, comparisonNotes
    }

    init(
        id: String,
        createdAt: Date,
        updatedAt: Date,
        title: String,
        readout: InvestigationReadoutSummary?,
        firmwareRefs: [InvestigationFirmwareRef],
        notes: [String],
        progress: InvestigationProgress? = nil,
        comparisonStale: Bool = false,
        comparisonNotes: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.readout = readout
        self.firmwareRefs = firmwareRefs
        self.notes = notes
        self.progress = progress
        self.comparisonStale = comparisonStale
        self.comparisonNotes = comparisonNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        title = try c.decode(String.self, forKey: .title)
        readout = try c.decodeIfPresent(InvestigationReadoutSummary.self, forKey: .readout)
        firmwareRefs = try c.decodeIfPresent([InvestigationFirmwareRef].self, forKey: .firmwareRefs) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        progress = try c.decodeIfPresent(InvestigationProgress.self, forKey: .progress)
        comparisonStale = try c.decodeIfPresent(Bool.self, forKey: .comparisonStale) ?? false
        comparisonNotes = try c.decodeIfPresent([String].self, forKey: .comparisonNotes) ?? []
    }

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

    /// Fortschritt aus vorhandenen Artefakten — verhindert Rückfall hinter gesicherte Daten.
    var reconciledProgress: InvestigationProgress {
        if readout != nil, !firmwareRefs.isEmpty {
            return .showResults
        }
        if readout != nil, firmwareRefs.isEmpty {
            // Scooter-only abgeschlossen vs. Combined wartet auf Firmware.
            if progress == .selectFirmware || progress == .analyzeFirmware {
                return progress ?? .selectFirmware
            }
            if progress == .showResults {
                return .showResults
            }
            // Default: Auslesung vorhanden ohne expliziten Combined-Warteschritt → fertig (Scooter-only).
            return .showResults
        }
        if readout == nil, !firmwareRefs.isEmpty {
            return .showResults
        }
        return progress ?? .selectScooter
    }

    var isResumable: Bool {
        switch reconciledProgress {
        case .showResults:
            return false
        case .selectScooter, .readScooter, .selectFirmware, .analyzeFirmware:
            return isValid || progress != nil
        }
    }

    var resumeSubtitle: String {
        let scooter = readout?.modelLabel ?? "noch kein Scooter"
        let readoutState = readout == nil ? "offen" : "abgeschlossen"
        return "Scooter: \(scooter) · Auslesung: \(readoutState) · \(reconciledProgress.nextStepHint)"
    }
}

/// Geführter Combined-Ablauf (UI-Zustand).
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

    var asPersisted: InvestigationProgress {
        switch self {
        case .selectScooter: return .selectScooter
        case .readScooter: return .readScooter
        case .pickFirmware: return .selectFirmware
        case .results: return .showResults
        }
    }

    static func from(progress: InvestigationProgress) -> CombinedInvestigationStep {
        switch progress {
        case .selectScooter: return .selectScooter
        case .readScooter: return .readScooter
        case .selectFirmware, .analyzeFirmware: return .pickFirmware
        case .showResults: return .results
        }
    }
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

/// Identitätsabgleich vor Zuordnung unterschiedlicher Auslesungen.
enum InvestigationIdentity {
    enum Outcome: Equatable, Sendable {
        case compatible
        case uncertain(reasons: [String])
        case conflict(reasons: [String])
    }

    static func compare(
        existing: InvestigationReadoutSummary,
        candidate: InvestigationReadoutSummary
    ) -> Outcome {
        var conflicts: [String] = []
        var uncertain: [String] = []

        if let a = normalized(existing.serial), let b = normalized(candidate.serial), a != b {
            conflicts.append("Seriennummer weicht ab (\(a) ≠ \(b)).")
        } else if existing.serial == nil || candidate.serial == nil {
            uncertain.append("Seriennummer nicht auf beiden Seiten verfügbar.")
        }

        if let a = existing.blePeripheralId, let b = candidate.blePeripheralId, a != b {
            conflicts.append("BLE-Geräteidentität weicht ab.")
        } else if existing.blePeripheralId == nil || candidate.blePeripheralId == nil {
            uncertain.append("BLE-Geräteidentität unvollständig.")
        }

        let modelA = existing.modelLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelB = candidate.modelLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !modelA.isEmpty, !modelB.isEmpty, modelA != modelB {
            // Soft conflict — Modelle können Label-Varianten sein.
            if existing.profileId != candidate.profileId {
                conflicts.append("Modell/Profil weicht ab (\(existing.modelLabel) ≠ \(candidate.modelLabel)).")
            } else {
                uncertain.append("Modellbezeichnung weicht ab, Profil-ID gleich.")
            }
        }

        if let a = normalized(existing.manufacturer), let b = normalized(candidate.manufacturer), a != b {
            conflicts.append("Hersteller weicht ab.")
        }

        if !conflicts.isEmpty {
            return .conflict(reasons: conflicts)
        }
        if !uncertain.isEmpty {
            return .uncertain(reasons: uncertain)
        }
        return .compatible
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t.uppercased()
    }
}
