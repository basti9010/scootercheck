import Combine
import Foundation

struct FirmwareReferenceRecord: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var manufacturer: String
    var model: String
    var controllerType: String
    var hardwareVersion: String
    var firmwareVersion: String
    var sha256: String
    var md5: String?
    var byteCount: Int
    var origin: String
    var verificationStatus: VerificationStatus
    var createdAt: Date
    /// Optional plaintext bytes kept only in memory after import (not persisted).
    var plaintextBytes: Data? = nil

    enum VerificationStatus: String, Codable, Sendable {
        case userImported
        case catalogUnverified
        case verified

        var label: String {
            switch self {
            case .userImported: return "Nutzerimport (unbestätigt)"
            case .catalogUnverified: return "Katalog (nicht unabhängig verifiziert)"
            case .verified: return "Verifiziert"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, manufacturer, model, controllerType, hardwareVersion, firmwareVersion
        case sha256, md5, byteCount, origin, verificationStatus, createdAt
    }
}

@MainActor
final class FirmwareReferenceStore: ObservableObject {
    static let shared = FirmwareReferenceStore()

    @Published private(set) var records: [FirmwareReferenceRecord] = []

    private let defaultsKey = "firmware_reference_records_v1"

    private init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FirmwareReferenceRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    func save() {
        let persisted = records.map { rec -> FirmwareReferenceRecord in
            var r = rec
            r.plaintextBytes = nil
            return r
        }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func importReference(
        fileName: String,
        data: Data,
        manufacturer: String,
        model: String,
        controllerType: String,
        hardwareVersion: String,
        firmwareVersion: String,
        origin: String
    ) -> FirmwareReferenceRecord {
        let digest = FirmwareDigest.make(from: data)
        let record = FirmwareReferenceRecord(
            id: UUID().uuidString,
            manufacturer: manufacturer,
            model: model,
            controllerType: controllerType,
            hardwareVersion: hardwareVersion,
            firmwareVersion: firmwareVersion,
            sha256: digest.sha256,
            md5: digest.md5,
            byteCount: digest.byteCount,
            origin: origin.isEmpty ? fileName : origin,
            verificationStatus: .userImported,
            createdAt: Date(),
            plaintextBytes: data
        )
        records.removeAll { $0.sha256 == record.sha256 && $0.model == record.model && $0.controllerType == record.controllerType }
        records.insert(record, at: 0)
        save()
        return record
    }

    func delete(id: String) {
        records.removeAll { $0.id == id }
        save()
    }

    func matchCandidates(models: [String], controllerType: String?) -> [FirmwareReferenceRecord] {
        let modelSet = Set(models.map { $0.lowercased() })
        return records.filter { rec in
            let modelHit = modelSet.isEmpty || modelSet.contains(rec.model.lowercased())
            let typeHit = controllerType.map { $0.caseInsensitiveCompare(rec.controllerType) == .orderedSame } ?? true
            return modelHit && typeHit
        }
    }
}

enum FirmwareComparer {
    static func compare(
        subjectSHA256: String,
        subjectData: Data?,
        encrypted: Bool,
        references: [FirmwareReferenceRecord],
        preferredId: String?
    ) -> FirmwareComparisonResult {
        guard !encrypted else {
            return FirmwareComparisonResult(
                outcome: .notPossible,
                referenceId: nil,
                referenceLabel: nil,
                differingBytes: nil,
                firstDiffOffset: nil,
                segments: [],
                note: "Vergleich der Image-Bytes wegen Verschlüsselung nicht möglich (nur Metadaten/Prüfsummen des Ciphertexts)."
            )
        }
        guard !references.isEmpty else {
            return FirmwareComparisonResult(
                outcome: .notPossible,
                referenceId: nil,
                referenceLabel: nil,
                differingBytes: nil,
                firstDiffOffset: nil,
                segments: [],
                note: "Keine Referenzfirmware vorhanden — bitte Original-Image importieren."
            )
        }

        if let exact = references.first(where: { $0.sha256 == subjectSHA256 }) {
            return FirmwareComparisonResult(
                outcome: .identical,
                referenceId: exact.id,
                referenceLabel: label(exact),
                differingBytes: 0,
                firstDiffOffset: nil,
                segments: [],
                note: "SHA-256 identisch mit Referenz „\(label(exact))“."
            )
        }

        let preferred = preferredId.flatMap { id in references.first { $0.id == id } } ?? references.first
        guard let ref = preferred else {
            return FirmwareComparisonResult(
                outcome: .unknown,
                referenceId: nil,
                referenceLabel: nil,
                differingBytes: nil,
                firstDiffOffset: nil,
                segments: [],
                note: "Keine passende Referenz ausgewählt."
            )
        }

        if let subjectData, let refData = ref.plaintextBytes {
            let diff = byteDiff(subjectData, refData)
            return FirmwareComparisonResult(
                outcome: .different,
                referenceId: ref.id,
                referenceLabel: label(ref),
                differingBytes: diff.differingBytes,
                firstDiffOffset: diff.firstOffset,
                segments: diff.segments,
                note: "Byte-Vergleich gegen „\(label(ref))“: \(diff.differingBytes) abweichende Bytes."
            )
        }

        // Known alternate if same model/controller but different hash in store
        if references.contains(where: { $0.model.caseInsensitiveCompare(ref.model) == .orderedSame }) {
            return FirmwareComparisonResult(
                outcome: .knownAlternate,
                referenceId: ref.id,
                referenceLabel: label(ref),
                differingBytes: nil,
                firstDiffOffset: nil,
                segments: [],
                note: "SHA-256 weicht von Referenz ab; Byte-Vergleich ohne Klartext-Referenzdaten nicht möglich."
            )
        }

        return FirmwareComparisonResult(
            outcome: .unknown,
            referenceId: ref.id,
            referenceLabel: label(ref),
            differingBytes: nil,
            firstDiffOffset: nil,
            segments: [],
            note: "Firmware-Hash unbekannt in der Referenzdatenbank."
        )
    }

    private static func label(_ r: FirmwareReferenceRecord) -> String {
        "\(r.manufacturer) \(r.model) \(r.controllerType) \(r.firmwareVersion)"
    }

    private static func byteDiff(_ a: Data, _ b: Data) -> (differingBytes: Int, firstOffset: Int?, segments: [FirmwareSegmentDiff]) {
        let n = min(a.count, b.count)
        var differing = abs(a.count - b.count)
        var first: Int?
        var segments: [FirmwareSegmentDiff] = []
        var runStart: Int?
        for i in 0..<n {
            if a[i] != b[i] {
                differing += 1
                if first == nil { first = i }
                if runStart == nil { runStart = i }
            } else if let s = runStart {
                segments.append(.init(offset: s, length: i - s, note: "Byte-Differenz"))
                runStart = nil
                if segments.count >= 12 { break }
            }
        }
        if let s = runStart, segments.count < 12 {
            segments.append(.init(offset: s, length: n - s, note: "Byte-Differenz"))
        }
        if a.count != b.count {
            segments.append(.init(offset: n, length: abs(a.count - b.count), note: "Längenunterschied"))
        }
        return (differing, first, segments)
    }
}
