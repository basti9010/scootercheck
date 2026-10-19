import Foundation

/// Ergebnis eines ausschließlich lesenden Diagnoseversuchs — keine simulierten Werte.
struct ReadOnlyDiagnosticSnapshot: Equatable, Sendable {
    var profileId: String?
    var protocolVersion: String?
    var supportLevel: DiagnosticSupportLevel
    var readAt: Date
    var values: [DiagnosticValueRow]
    var blockers: [String]
    var usedNativeBleClientDump: Bool
    var evidenceNotes: [String]

    static func empty(support: DiagnosticSupportLevel, blockers: [String]) -> ReadOnlyDiagnosticSnapshot {
        ReadOnlyDiagnosticSnapshot(
            profileId: nil,
            protocolVersion: nil,
            supportLevel: support,
            readAt: Date(),
            values: [],
            blockers: blockers,
            usedNativeBleClientDump: false,
            evidenceNotes: []
        )
    }
}

struct DiagnosticValueRow: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var value: String
    var source: String
}

/// Orchestriert sichere Diagnose: native BleClient-Dumps oder GATT-DIS — nie Write/Unlock.
@MainActor
final class ReadOnlyDiagnosticEngine: ObservableObject {
    static let shared = ReadOnlyDiagnosticEngine()

    @Published private(set) var lastSnapshot: ReadOnlyDiagnosticSnapshot?
    @Published private(set) var phaseLabel: String = "Bereit"

    private init() {}

    /// Entscheidet, was sicher möglich ist — startet keine Hintergrund-Verbindung allein.
    func plan(for assessment: UniversalScooterDetectionService.PassiveAssessment) -> (canStart: Bool, reason: String) {
        switch assessment.compatibility.supportLevel {
        case .fullNative:
            return (true, "Natives Lesprotokoll verfügbar. Diagnose startet über bestehenden BleClient (nur Lesen).")
        case .verifiedProfile, .gattReadonly:
            return (true, "Nur standardisierte GATT-/DIS-Reads. Proprietäre Schreibbefehle werden nicht gesendet.")
        case .researchHintOnly:
            return (false, "Nur Recherchehinweis — kein validiertes Lesprotokoll. Sichere Diagnose nicht möglich.")
        case .none:
            return (false, assessment.compatibility.blockers.first ?? "Kein kompatibles Protokoll.")
        }
    }

    /// Baut Evidence-taugliche Notizen aus einem erfolgreichen IntegrityReading (nativer Dump).
    func snapshotFromIntegrityReading(
        _ reading: IntegrityReading,
        profile: ScooterDiagnosticProfile?
    ) -> ReadOnlyDiagnosticSnapshot {
        var rows: [DiagnosticValueRow] = []
        func add(_ id: String, _ title: String, _ value: String?) {
            let v = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(DiagnosticValueRow(
                id: id,
                title: title,
                value: (v?.isEmpty == false) ? v! : "Nicht verfügbar",
                source: profile?.id ?? "native-dump"
            ))
        }
        add("serial", "Seriennummer", reading.serialDisplay ?? reading.serialMcu)
        add("fwdrv", "MCU Firmware", reading.fwMcu)
        add("fwbms", "BMS Firmware", reading.fwBms)
        add("fwble", "BLE Firmware", reading.fwBle)
        add("limit", "Geschwindigkeitslimit", reading.speedLimitKmh.map { String(format: "%.1f km/h", $0) })
        add("odo", "Kilometerstand", reading.odometerKm.map { String(format: "%.1f km", $0) })
        add("gear", "Fahrmodus", reading.gearMode.map { "\($0)" })
        add("stack", "BLE-Stack", reading.bleStack)

        return ReadOnlyDiagnosticSnapshot(
            profileId: profile?.id,
            protocolVersion: profile?.protocolVersion,
            supportLevel: .fullNative,
            readAt: Date(),
            values: rows,
            blockers: [],
            usedNativeBleClientDump: true,
            evidenceNotes: [
                "Profil: \(profile?.id ?? "nativ")",
                "Protokoll: \(profile?.protocolVersion ?? reading.bleStack ?? "unbekannt")",
                "Nur tatsächlich empfangene Register — fehlende Werte als „Nicht verfügbar“."
            ]
        )
    }

    /// Snapshot aus GATT-DIS / Deep-Analysis — nur gelesene Felder.
    func snapshotFromGatt(
        analysis: BLEGattDeepAnalysis.Report,
        profile: ScooterDiagnosticProfile?
    ) -> ReadOnlyDiagnosticSnapshot {
        var rows: [DiagnosticValueRow] = []
        if let m = analysis.manufacturerName {
            rows.append(.init(id: "mfg", title: "Hersteller (DIS)", value: m, source: "gatt-dis"))
        }
        if let m = analysis.modelNumber {
            rows.append(.init(id: "model", title: "Modell (DIS)", value: m, source: "gatt-dis"))
        }
        if let s = analysis.serialNumber {
            rows.append(.init(id: "serial", title: "Seriennummer (DIS)", value: s, source: "gatt-dis"))
        }
        if let f = analysis.firmwareRevision {
            rows.append(.init(id: "fw", title: "Firmware (DIS)", value: f, source: "gatt-dis"))
        }
        if let h = analysis.hardwareRevision {
            rows.append(.init(id: "hw", title: "Hardware (DIS)", value: h, source: "gatt-dis"))
        }
        if rows.isEmpty {
            rows.append(.init(
                id: "none",
                title: "Diagnosewerte",
                value: "Nicht verfügbar",
                source: "gatt-dis"
            ))
        }
        var blockers: [String] = []
        if let err = analysis.errorMessage {
            blockers.append(err)
        }
        return ReadOnlyDiagnosticSnapshot(
            profileId: profile?.id ?? "gatt-device-information",
            protocolVersion: profile?.protocolVersion ?? "gatt-dis-1",
            supportLevel: .gattReadonly,
            readAt: Date(),
            values: rows,
            blockers: blockers,
            usedNativeBleClientDump: false,
            evidenceNotes: [
                "Nur Bluetooth-SIG Device Information / sichere Reads.",
                "Kein proprietäres Scooter-Protokoll ausgeführt.",
                "Services: \(analysis.services.prefix(8).joined(separator: ", "))"
            ]
        )
    }

    func apply(_ snapshot: ReadOnlyDiagnosticSnapshot) {
        lastSnapshot = snapshot
        phaseLabel = snapshot.blockers.isEmpty ? "Auslesen abgeschlossen" : "Auslesen mit Einschränkungen"
    }
}

/// Evidence-Hook: schreibt Diagnose-Metadaten in physicalMarks — keine erfundenen Sollwerte.
enum ScooterEvidenceEngineBridge {
    static func annotate(
        reading: inout IntegrityReading,
        snapshot: ReadOnlyDiagnosticSnapshot
    ) {
        let meta = "diag:\(snapshot.profileId ?? "none")@\(snapshot.protocolVersion ?? "-")"
        if !reading.physicalMarks.contains(meta) {
            reading.physicalMarks.append(meta)
        }
        for note in snapshot.evidenceNotes.prefix(3) {
            let tag = "evidence:\(note.prefix(80))"
            if !reading.physicalMarks.contains(where: { $0.hasPrefix("evidence:") && $0.contains(String(note.prefix(20))) }) {
                reading.physicalMarks.append(tag)
            }
        }
    }
}
