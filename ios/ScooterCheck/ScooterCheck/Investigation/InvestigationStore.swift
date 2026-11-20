import Foundation
import Combine

/// Lokale Persistenz für Unified Investigations (Application Support JSON).
@MainActor
final class InvestigationStore: ObservableObject {
    static let shared = InvestigationStore()

    @Published private(set) var records: [InvestigationRecord] = []

    private let fileURL: URL
    private let packsDir: URL
    private var saveTask: Task<Void, Never>?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ScooterCheck/Investigations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        packsDir = dir.appendingPathComponent("packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: packsDir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("index.json")
        load()
    }

    func record(id: String) -> InvestigationRecord? {
        records.first { $0.id == id }
    }

    @discardableResult
    func create(title: String = "Untersuchung") -> InvestigationRecord {
        let now = Date()
        let rec = InvestigationRecord(
            id: UUID().uuidString,
            createdAt: now,
            updatedAt: now,
            title: title,
            readout: nil,
            firmwareRefs: [],
            notes: []
        )
        records.insert(rec, at: 0)
        scheduleSave()
        return rec
    }

    func upsert(_ record: InvestigationRecord) {
        guard record.isValid || record.readout != nil || !record.firmwareRefs.isEmpty else { return }
        var copy = record
        copy.updatedAt = Date()
        if let idx = records.firstIndex(where: { $0.id == copy.id }) {
            records[idx] = copy
        } else {
            records.insert(copy, at: 0)
        }
        scheduleSave()
    }

    func attachReadout(_ summary: InvestigationReadoutSummary, to id: String) {
        guard var rec = record(id: id) else { return }
        rec.readout = summary
        if rec.title == "Untersuchung" || rec.title.isEmpty {
            rec.title = summary.shortLabel
        }
        rec.notes.append("Scooter-Auslesung ergänzt · \(Self.stamp(summary.savedAt))")
        upsert(rec)
    }

    @discardableResult
    func attachFirmwareReport(_ report: FirmwareForensicReport, to id: String) throws -> InvestigationFirmwareRef {
        guard var rec = record(id: id) else {
            throw StoreError.missingInvestigation
        }
        let pack = packsDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        let fileName = "firmware-\(report.id).json"
        let url = pack.appendingPathComponent(fileName)
        let data = try FirmwareForensicPDF.jsonData(report)
        try data.write(to: url, options: .atomic)

        let ref = InvestigationFirmwareRef(
            id: UUID().uuidString,
            addedAt: Date(),
            originalFileName: report.originalFileName,
            subjectSHA256: report.deepAnalysis?.subjectSHA256 ?? report.archiveDigest.sha256,
            reportId: report.id,
            reportFileName: fileName,
            analysisCompleteness: report.deepAnalysis?.analysisCompleteness,
            packageDisplayName: report.deepAnalysis?.packageDisplayName ?? report.meta.displayName
        )
        // Replace same report id if re-exported; otherwise append.
        if let existing = rec.firmwareRefs.firstIndex(where: { $0.reportId == report.id }) {
            rec.firmwareRefs[existing] = ref
        } else {
            rec.firmwareRefs.append(ref)
        }
        rec.notes.append("Firmware „\(report.originalFileName)“ ergänzt · \(Self.stamp(ref.addedAt))")
        if rec.title == "Untersuchung" || rec.title.isEmpty {
            rec.title = report.originalFileName
        }
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

    func delete(id: String) {
        records.removeAll { $0.id == id }
        let pack = packsDir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: pack)
        scheduleSave()
    }

    enum StoreError: Error {
        case missingInvestigation
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([InvestigationRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded.sorted { $0.updatedAt > $1.updatedAt }
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
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

extension InvestigationReadoutSummary {
    static func from(result: IntegrityResult, historyEntryId: String?, bleId: UUID?) -> InvestigationReadoutSummary {
        InvestigationReadoutSummary(
            id: UUID().uuidString,
            savedAt: Date(),
            protocolNumber: nil,
            profileId: result.profile.rawValue,
            modelLabel: result.profile.shortLabel,
            serial: result.reading.serialDisplay ?? result.reading.serialVcu,
            fwVcu: result.reading.fwVcu,
            fwMcu: result.reading.fwMcu,
            fwBle: result.reading.fwBle,
            fwEsc: result.reading.fwEsc,
            speedLimitKmh: result.reading.speedLimitKmh,
            blePeripheralId: bleId,
            historyEntryId: historyEntryId
        )
    }
}
