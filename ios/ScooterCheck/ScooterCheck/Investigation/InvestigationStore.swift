import Foundation
import Combine

/// Lokale Persistenz für Unified Investigations (Application Support JSON + Packs).
@MainActor
final class InvestigationStore: ObservableObject {
    static let shared = InvestigationStore()

    @Published private(set) var records: [InvestigationRecord] = []
    @Published private(set) var lastLoadError: String?

    private let fileURL: URL
    private let packsDir: URL
    private var saveTask: Task<Void, Never>?
    /// Test-only alternate root.
    private let rootDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ScooterCheck/Investigations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        rootDir = dir
        packsDir = dir.appendingPathComponent("packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: packsDir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("index.json")
        load()
    }

    /// Isolierter Store für Unit-Tests (eigene Index-/Pack-Verzeichnisse).
    init(testRoot: URL) {
        rootDir = testRoot
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        packsDir = testRoot.appendingPathComponent("packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: packsDir, withIntermediateDirectories: true)
        fileURL = testRoot.appendingPathComponent("index.json")
        lastLoadError = nil
        load()
    }

    func record(id: String) -> InvestigationRecord? {
        records.first { $0.id == id }
    }

    var resumableRecords: [InvestigationRecord] {
        records.filter(\.isResumable)
    }

    @discardableResult
    func create(
        title: String = "Untersuchung",
        progress: InvestigationProgress = .selectScooter
    ) -> InvestigationRecord {
        let now = Date()
        let rec = InvestigationRecord(
            id: UUID().uuidString,
            createdAt: now,
            updatedAt: now,
            title: title,
            readout: nil,
            firmwareRefs: [],
            notes: [],
            progress: progress,
            comparisonStale: false,
            comparisonNotes: []
        )
        records.insert(rec, at: 0)
        scheduleSave()
        return rec
    }

    func upsert(_ record: InvestigationRecord) {
        // Erlaube leere In-Progress-Records (nur Progress gesetzt).
        let allowEmpty = record.progress != nil
        guard record.isValid || allowEmpty || record.readout != nil || !record.firmwareRefs.isEmpty else {
            return
        }
        var copy = record
        copy.updatedAt = Date()
        if let idx = records.firstIndex(where: { $0.id == copy.id }) {
            records[idx] = copy
        } else {
            records.insert(copy, at: 0)
        }
        scheduleSave()
    }

    func setProgress(_ progress: InvestigationProgress, for id: String) {
        guard var rec = record(id: id) else { return }
        // Nie hinter gesicherte Artefakte zurückfallen — Ausnahme:
        // Auslesung vorhanden, noch keine Firmware → selectFirmware/analyzeFirmware
        // ist ein gültiger Combined-Warteschritt (auch nach temporärem showResults).
        if rec.readout != nil, rec.firmwareRefs.isEmpty,
           progress == .selectFirmware || progress == .analyzeFirmware {
            rec.progress = progress
            upsert(rec)
            return
        }
        if rec.readout != nil, !rec.firmwareRefs.isEmpty {
            // Beide Artefakte vorhanden → höchstens showResults.
            rec.progress = .showResults
            upsert(rec)
            return
        }
        let floor = rec.reconciledProgress
        rec.progress = maxProgress(floor, progress)
        upsert(rec)
    }

    func attachReadout(
        _ summary: InvestigationReadoutSummary,
        to id: String,
        allowIdentityChange: Bool = false
    ) -> InvestigationIdentity.Outcome? {
        guard var rec = record(id: id) else { return nil }
        if let existing = rec.readout {
            let outcome = InvestigationIdentity.compare(existing: existing, candidate: summary)
            switch outcome {
            case .compatible:
                break
            case .uncertain:
                if !allowIdentityChange { return outcome }
            case .conflict:
                if !allowIdentityChange { return outcome }
                rec.comparisonStale = true
                rec.comparisonNotes.append(
                    "Scooter-Zuordnung geändert · \(Self.stamp(Date())) — Vergleich als veraltet markiert."
                )
            }
        }
        // Original-Auslesung nicht überschreiben, wenn gleiche Identität und bereits vorhanden —
        // außer allowIdentityChange oder kompatible Aktualisierung der Metadaten.
        if let existing = rec.readout,
           case .compatible = InvestigationIdentity.compare(existing: existing, candidate: summary),
           !allowIdentityChange {
            // Behalte Original-ID/Zeit; aktualisiere nur fehlende Felder.
            var merged = existing
            if merged.serial == nil { merged.serial = summary.serial }
            if merged.fwVcu == nil { merged.fwVcu = summary.fwVcu }
            if merged.fwMcu == nil { merged.fwMcu = summary.fwMcu }
            if merged.fwBle == nil { merged.fwBle = summary.fwBle }
            if merged.blePeripheralId == nil { merged.blePeripheralId = summary.blePeripheralId }
            if merged.historyEntryId == nil { merged.historyEntryId = summary.historyEntryId }
            if merged.protocolNumber == nil { merged.protocolNumber = summary.protocolNumber }
            rec.readout = merged
        } else {
            rec.readout = summary
        }
        if rec.title == "Untersuchung" || rec.title.isEmpty || rec.title == "Kombinierte Untersuchung"
            || rec.title == "Scooter-Auslesung" || rec.title == "Firmwareanalyse" {
            rec.title = summary.shortLabel
        }
        rec.notes.append("Scooter-Auslesung ergänzt · \(Self.stamp(summary.savedAt))")
        if !rec.firmwareRefs.isEmpty {
            rec.progress = .showResults
        } else if rec.progress == .selectFirmware || rec.progress == .analyzeFirmware {
            // Combined: Auslesung da, Firmware noch offen — Fortschritt behalten.
        } else if rec.progress == .selectScooter || rec.progress == .readScooter {
            // Wird vom Combined-Flow anschließend auf selectFirmware gesetzt.
            rec.progress = .readScooter
        } else {
            rec.progress = .showResults
        }
        upsert(rec)
        return .compatible
    }

    /// Ersetzt die Scooter-Zuordnung bewusst (nach Bestätigung).
    func replaceReadout(_ summary: InvestigationReadoutSummary, to id: String) {
        _ = attachReadout(summary, to: id, allowIdentityChange: true)
    }

    @discardableResult
    func attachFirmwareReport(
        _ report: FirmwareForensicReport,
        originalData: Data?,
        to id: String
    ) throws -> InvestigationFirmwareRef {
        guard var rec = record(id: id) else {
            throw StoreError.missingInvestigation
        }
        let pack = packsDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)

        let sha = report.deepAnalysis?.subjectSHA256 ?? report.archiveDigest.sha256
        // Gleiche Datei in derselben Untersuchung: Report aktualisieren, Binary nicht doppelt speichern.
        if let existingIdx = rec.firmwareRefs.firstIndex(where: {
            ($0.subjectSHA256?.lowercased() == sha.lowercased() && !sha.isEmpty)
                || $0.reportId == report.id
        }) {
            var existing = rec.firmwareRefs[existingIdx]
            let fileName = existing.reportFileName.isEmpty
                ? "firmware-\(report.id).json"
                : existing.reportFileName
            let url = pack.appendingPathComponent(fileName)
            let data = try FirmwareForensicPDF.jsonData(report)
            try data.write(to: url, options: .atomic)
            existing.reportId = report.id
            existing.reportFileName = fileName
            existing.analyzedAt = report.analyzedAt
            existing.subjectSHA256 = sha
            existing.byteCount = report.archiveByteCount
            existing.containerKind = String(describing: report.containerKind)
            existing.analysisCompleteness = report.deepAnalysis?.analysisCompleteness
            existing.packageDisplayName = report.deepAnalysis?.packageDisplayName ?? report.meta.displayName
            existing.referenceTrust = report.deepAnalysis?.referenceMetadata?.referenceTrust
            existing.serverJobId = report.serverArtifacts?.jobId ?? existing.serverJobId
            if let originalData, existing.archivedBinaryFileName == nil {
                let archive = archiveBinary(
                    originalData,
                    preferredName: report.originalFileName,
                    sha: sha,
                    pack: pack
                )
                existing.archivedBinaryFileName = archive.fileName
                existing.archiveStatus = archive.status
                existing.archiveError = archive.error
            }
            rec.firmwareRefs[existingIdx] = existing
            rec.notes.append("Firmwareanalyse aktualisiert · \(report.originalFileName)")
            rec.progress = rec.readout != nil ? .showResults : .showResults
            upsert(rec)
            return existing
        }

        let reportFileName = "firmware-\(report.id).json"
        let reportURL = pack.appendingPathComponent(reportFileName)
        let json = try FirmwareForensicPDF.jsonData(report)
        try json.write(to: reportURL, options: .atomic)

        var archiveFileName: String?
        var archiveStatus = "missing"
        var archiveError: String?
        if let originalData {
            let archive = archiveBinary(
                originalData,
                preferredName: report.originalFileName,
                sha: sha,
                pack: pack
            )
            archiveFileName = archive.fileName
            archiveStatus = archive.status
            archiveError = archive.error
            if archive.status != "ok" {
                rec.notes.append("Firmware-Archivierung fehlgeschlagen: \(archive.error ?? "unbekannt")")
            }
        } else {
            archiveStatus = "missing"
            archiveError = "Originalbytes nicht übergeben — nur Analyse-JSON gespeichert."
            rec.notes.append("Warnung: Firmware-Originaldatei nicht archiviert.")
        }

        let ref = InvestigationFirmwareRef(
            id: UUID().uuidString,
            addedAt: Date(),
            analyzedAt: report.analyzedAt,
            originalFileName: report.originalFileName,
            subjectSHA256: sha,
            byteCount: report.archiveByteCount,
            containerKind: String(describing: report.containerKind),
            reportId: report.id,
            reportFileName: reportFileName,
            archivedBinaryFileName: archiveFileName,
            archiveStatus: archiveStatus,
            archiveError: archiveError,
            serverJobId: report.serverArtifacts?.jobId,
            analysisCompleteness: report.deepAnalysis?.analysisCompleteness,
            packageDisplayName: report.deepAnalysis?.packageDisplayName ?? report.meta.displayName,
            referenceTrust: report.deepAnalysis?.referenceMetadata?.referenceTrust
        )
        rec.firmwareRefs.append(ref)
        rec.notes.append("Firmware „\(report.originalFileName)“ ergänzt · \(Self.stamp(ref.addedAt))")
        if rec.title == "Untersuchung" || rec.title.isEmpty || rec.title == "Firmwareanalyse"
            || rec.title == "Kombinierte Untersuchung" {
            if let readout = rec.readout {
                rec.title = readout.shortLabel
            } else {
                rec.title = report.originalFileName
            }
        }
        rec.progress = .showResults
        upsert(rec)
        return ref
    }

    func loadFirmwareReport(ref: InvestigationFirmwareRef, investigationId: String) -> FirmwareForensicReport? {
        let url = packsDir
            .appendingPathComponent(investigationId, isDirectory: true)
            .appendingPathComponent(ref.reportFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FirmwareForensicReport.self, from: data)
    }

    func loadArchivedFirmwareData(ref: InvestigationFirmwareRef, investigationId: String) -> Data? {
        guard let name = ref.archivedBinaryFileName else { return nil }
        let url = packsDir
            .appendingPathComponent(investigationId, isDirectory: true)
            .appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }

    /// Vorhandene Analyse derselben SHA-256 wiederverwenden (keine neue Ghidra-Runde).
    func existingReport(matchingSHA256 sha: String, in investigationId: String) -> (InvestigationFirmwareRef, FirmwareForensicReport)? {
        guard let rec = record(id: investigationId) else { return nil }
        let needle = sha.lowercased()
        guard let ref = rec.firmwareRefs.first(where: { $0.subjectSHA256?.lowercased() == needle }) else {
            return nil
        }
        guard let report = loadFirmwareReport(ref: ref, investigationId: investigationId) else {
            return nil
        }
        return (ref, report)
    }

    func exportJSON(for id: String) throws -> Data {
        guard let rec = record(id: id) else { throw StoreError.missingInvestigation }
        var payload: [String: Any] = [
            "investigationId": rec.id,
            "title": rec.title,
            "kind": rec.kind.rawValue,
            "createdAt": iso(rec.createdAt),
            "updatedAt": iso(rec.updatedAt),
            "progress": rec.reconciledProgress.rawValue,
            "comparisonStale": rec.comparisonStale,
            "comparisonNotes": rec.comparisonNotes,
            "notes": rec.notes,
            "appVersion": ProtocolPDF.appVersion,
            "exportedAt": iso(Date()),
            "sourceVersions": [
                "investigationModel": "1.1",
                "protocolHistory": "unchanged",
                "firmwareReport": "FirmwareForensicReport"
            ]
        ]
        if let readout = rec.readout {
            let data = try JSONEncoder().encode(readout)
            payload["readout"] = try JSONSerialization.jsonObject(with: data)
        }
        var firmwares: [[String: Any]] = []
        for ref in rec.firmwareRefs {
            var entry: [String: Any] = [
                "id": ref.id,
                "originalFileName": ref.originalFileName,
                "subjectSHA256": ref.subjectSHA256 as Any,
                "byteCount": ref.byteCount as Any,
                "addedAt": iso(ref.addedAt),
                "analyzedAt": ref.analyzedAt.map(iso) as Any,
                "serverJobId": ref.serverJobId as Any,
                "archiveStatus": ref.archiveStatus as Any,
                "archiveError": ref.archiveError as Any,
                "reportId": ref.reportId,
                "analysisCompleteness": ref.analysisCompleteness as Any,
                "referenceTrust": ref.referenceTrust as Any
            ]
            if let report = loadFirmwareReport(ref: ref, investigationId: id) {
                let reportData = try FirmwareForensicPDF.jsonData(report)
                entry["report"] = try JSONSerialization.jsonObject(with: reportData)
            }
            firmwares.append(entry)
        }
        payload["firmwareFiles"] = firmwares
        payload["limitations"] = [
            "Eine importierte Firmwaredatei ist nicht automatisch die installierte Fahrzeugfirmware.",
            "Fehlende Felder bedeuten nicht zwingend Manipulation.",
            "Serverartefakte werden nur kompakt referenziert, nicht vollständig neu heruntergeladen."
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    func delete(id: String) {
        records.removeAll { $0.id == id }
        let pack = packsDir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: pack)
        scheduleSave()
    }

    /// Sofort speichern (z. B. vor App-Hintergrund).
    func flush() {
        saveTask?.cancel()
        saveNow()
    }

    enum StoreError: Error, Equatable {
        case missingInvestigation
        case archiveFailed(String)
        case corruptIndex
    }

    // MARK: - Archive

    private func archiveBinary(
        _ data: Data,
        preferredName: String,
        sha: String,
        pack: URL
    ) -> (fileName: String?, status: String, error: String?) {
        guard !data.isEmpty else {
            return (nil, "failed", "Leere Datei — Archivierung abgebrochen.")
        }
        let computed = FirmwareDigest.sha256Hex(data)
        if !sha.isEmpty, computed.lowercased() != sha.lowercased() {
            // Trotzdem speichern, aber Warnung.
        }
        let safeBase = preferredName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let prefix = String(computed.prefix(16))
        let fileName = "original-\(prefix)-\(safeBase)"
        let dest = pack.appendingPathComponent(fileName)
        // Idempotent: gleiche SHA-Datei nicht erneut schreiben.
        if FileManager.default.fileExists(atPath: dest.path) {
            if let existing = try? Data(contentsOf: dest), FirmwareDigest.sha256Hex(existing) == computed {
                return (fileName, "ok", nil)
            }
        }
        do {
            try data.write(to: dest, options: .atomic)
            // Verify
            guard let written = try? Data(contentsOf: dest),
                  FirmwareDigest.sha256Hex(written) == computed else {
                return (fileName, "failed", "Archivierte Datei konnte nicht verifiziert werden.")
            }
            return (fileName, "ok", nil)
        } catch {
            return (nil, "failed", error.localizedDescription)
        }
    }

    // MARK: - Persistence

    private func load() {
        lastLoadError = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            lastLoadError = "Indexdatei nicht lesbar."
            // Bestehende records nicht stillschweigend löschen, wenn schon geladen —
            // beim ersten Init sind sie leer.
            records = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([InvestigationRecord].self, from: data)
            records = decoded.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            lastLoadError = "Index JSON beschädigt: \(error.localizedDescription)"
            // Keine stillschweigende Löschung — behalte Raw-Backup.
            let bak = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? data.write(to: bak, options: .atomic)
            records = []
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            saveNow()
        }
    }

    private func saveNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(records) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastLoadError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func maxProgress(_ a: InvestigationProgress, _ b: InvestigationProgress) -> InvestigationProgress {
        let order: [InvestigationProgress] = [
            .selectScooter, .readScooter, .selectFirmware, .analyzeFirmware, .showResults
        ]
        let ia = order.firstIndex(of: a) ?? 0
        let ib = order.firstIndex(of: b) ?? 0
        return order[max(ia, ib)]
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

extension InvestigationReadoutSummary {
    static func from(
        result: IntegrityResult,
        historyEntryId: String?,
        bleId: UUID?,
        bleName: String? = nil
    ) -> InvestigationReadoutSummary {
        InvestigationReadoutSummary(
            id: UUID().uuidString,
            savedAt: Date(),
            protocolNumber: nil,
            profileId: result.profile.rawValue,
            modelLabel: result.profile.shortLabel,
            manufacturer: "Segway-Ninebot / Xiaomi",
            serial: result.reading.serialDisplay ?? result.reading.serialVcu,
            fwVcu: result.reading.fwVcu,
            fwMcu: result.reading.fwMcu,
            fwBle: result.reading.fwBle,
            fwEsc: result.reading.fwEsc,
            hardwareVersion: nil,
            controllerHint: result.reading.fwEsc,
            bleAdvertisementName: bleName,
            speedLimitKmh: result.reading.speedLimitKmh,
            blePeripheralId: bleId,
            historyEntryId: historyEntryId
        )
    }
}
