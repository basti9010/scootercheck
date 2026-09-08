import Foundation

/// Offline persistence for check sessions and their PDF/JSON packs.
@MainActor
final class ProtocolHistoryStore: ObservableObject {
    static let shared = ProtocolHistoryStore()

    struct Entry: Identifiable, Codable, Hashable, Sendable {
        let id: UUID
        var protocolNumber: String
        var createdAt: Date
        var profile: ScooterProfile
        var verdict: VerdictLevel?
        var score: Int?
        var serialDisplay: String?
        var trackId: String?
        /// Optionale Kurzzeile (Name / Geburtsdatum / Kennzeichen).
        var subjectSummary: String?

        enum CodingKeys: String, CodingKey {
            case id, protocolNumber, createdAt, profile, verdict, score, serialDisplay, trackId, subjectSummary
        }

        init(
            id: UUID,
            protocolNumber: String,
            createdAt: Date,
            profile: ScooterProfile,
            verdict: VerdictLevel? = nil,
            score: Int? = nil,
            serialDisplay: String? = nil,
            trackId: String? = nil,
            subjectSummary: String? = nil
        ) {
            self.id = id
            self.protocolNumber = protocolNumber
            self.createdAt = createdAt
            self.profile = profile
            self.verdict = verdict
            self.score = score
            self.serialDisplay = serialDisplay
            self.trackId = trackId
            self.subjectSummary = subjectSummary
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            protocolNumber = try c.decode(String.self, forKey: .protocolNumber)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            profile = try c.decode(ScooterProfile.self, forKey: .profile)
            verdict = try c.decodeIfPresent(VerdictLevel.self, forKey: .verdict)
            score = try c.decodeIfPresent(Int.self, forKey: .score)
            serialDisplay = try c.decodeIfPresent(String.self, forKey: .serialDisplay)
            trackId = try c.decodeIfPresent(String.self, forKey: .trackId)
            subjectSummary = try c.decodeIfPresent(String.self, forKey: .subjectSummary)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(protocolNumber, forKey: .protocolNumber)
            try c.encode(createdAt, forKey: .createdAt)
            try c.encode(profile, forKey: .profile)
            try c.encodeIfPresent(verdict, forKey: .verdict)
            try c.encodeIfPresent(score, forKey: .score)
            try c.encodeIfPresent(serialDisplay, forKey: .serialDisplay)
            try c.encodeIfPresent(trackId, forKey: .trackId)
            try c.encodeIfPresent(subjectSummary, forKey: .subjectSummary)
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var rootURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("ScooterCheck/History", isDirectory: true)
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    private init() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? decoder.decode([Entry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    /// Saves session + regenerates durable PDF/JSON pack. Returns pack URLs.
    @discardableResult
    func save(_ session: CheckSession) throws -> ProtocolPack.PackURLs {
        guard let result = session.result else {
            throw HistoryError.missingResult
        }

        let dir = packDirectory(for: session.protocolNumber)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let sessionURL = dir.appendingPathComponent("session.json")
        try encoder.encode(session).write(to: sessionURL, options: .atomic)

        let pack = try ProtocolPack.makePack(session: session, result: result, directory: dir)

        var next = entries.filter { $0.id != session.id }
        next.insert(
            Entry(
                id: session.id,
                protocolNumber: session.protocolNumber,
                createdAt: session.createdAt,
                profile: session.profile,
                verdict: result.verdict,
                score: result.score,
                serialDisplay: result.reading.serialDisplay ?? session.reading.serialDisplay,
                trackId: result.trackMatch.trackId.rawValue,
                subjectSummary: session.subject.summaryLine
            ),
            at: 0
        )
        // Keep a reasonable offline history size.
        if next.count > 100 {
            let removed = next.suffix(from: 100)
            next = Array(next.prefix(100))
            for old in removed {
                try? fileManager.removeItem(at: packDirectory(for: old.protocolNumber))
            }
        }
        entries = next
        try encoder.encode(entries).write(to: indexURL, options: .atomic)
        return pack
    }

    func loadSession(id: UUID) -> CheckSession? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        let url = packDirectory(for: entry.protocolNumber).appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CheckSession.self, from: data)
    }

    /// Letzte frühere Auslese derselben SN mit erhöhtem Tempo / Unlock-Nachweis.
    func priorUnlockEvidence(
        forSerial serial: String?,
        excludingSessionId: UUID? = nil
    ) -> PriorUnlockEvidence? {
        guard let serial else { return nil }
        let needle = Self.normalizeSerial(serial)
        guard needle.count >= 8 else { return nil }
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()

        for entry in entries {
            if let excludingSessionId, entry.id == excludingSessionId { continue }
            guard let entrySN = entry.serialDisplay, Self.serialsMatch(needle, entrySN) else { continue }
            guard let session = loadSession(id: entry.id) else { continue }
            let reading = session.result?.reading ?? session.reading
            let evidence = PriorUnlockEvidence(
                protocolNumber: session.protocolNumber,
                createdAt: session.createdAt,
                peakSpeedKmh: reading.peakSpeedKmh,
                speedLimitKmh: reading.speedLimitKmh,
                speedMaxKmh: reading.speedMaxKmh,
                verdict: session.result?.verdict,
                hiddenTuningDetected: reading.hiddenTuningDetected
            )
            if evidence.showsUnlock(threshold: threshold) {
                return evidence
            }
        }
        return nil
    }

    struct PriorSnapshot: Sendable {
        let protocolNumber: String
        let createdAt: Date
        let reading: IntegrityReading
        let verdict: VerdictLevel?
    }

    /// Letzte frühere Session derselben SN (für zeitliche Deltas / Fingerprint-Vergleich).
    func priorSnapshot(
        forSerial serial: String?,
        excludingSessionId: UUID? = nil
    ) -> PriorSnapshot? {
        guard let serial else { return nil }
        let needle = Self.normalizeSerial(serial)
        guard needle.count >= 8 else { return nil }

        for entry in entries {
            if let excludingSessionId, entry.id == excludingSessionId { continue }
            guard let entrySN = entry.serialDisplay, Self.serialsMatch(needle, entrySN) else { continue }
            guard let session = loadSession(id: entry.id) else { continue }
            let reading = session.result?.reading ?? session.reading
            return PriorSnapshot(
                protocolNumber: session.protocolNumber,
                createdAt: session.createdAt,
                reading: reading,
                verdict: session.result?.verdict
            )
        }
        return nil
    }

    private static func normalizeSerial(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func serialsMatch(_ a: String, _ b: String) -> Bool {
        let left = normalizeSerial(a)
        let right = normalizeSerial(b)
        if left == right { return true }
        // Gleiche Fahrzeug-SN trotz kurzer Anzeigevarianten
        let prefixLen = min(12, min(left.count, right.count))
        guard prefixLen >= 8 else { return false }
        return left.prefix(prefixLen) == right.prefix(prefixLen)
    }

    func packURLs(for entry: Entry) -> ProtocolPack.PackURLs? {
        let dir = packDirectory(for: entry.protocolNumber)
        let base = ProtocolPack.fileBaseName(protocolNumber: entry.protocolNumber)
        let sharePdf = dir.appendingPathComponent("\(base)_Bericht.pdf")
        let shareJson = dir.appendingPathComponent("\(base)_Daten.json")
        let pdf = fileManager.fileExists(atPath: sharePdf.path)
            ? sharePdf
            : dir.appendingPathComponent("\(entry.protocolNumber).pdf")
        let json = fileManager.fileExists(atPath: shareJson.path)
            ? shareJson
            : dir.appendingPathComponent("\(entry.protocolNumber).json")
        guard fileManager.fileExists(atPath: pdf.path),
              fileManager.fileExists(atPath: json.path) else {
            return nil
        }
        return ProtocolPack.PackURLs(pdfURL: pdf, jsonURL: json, directoryURL: dir)
    }

    /// Ensures pack files exist (regenerates from session if needed).
    func ensurePack(for entry: Entry) throws -> ProtocolPack.PackURLs {
        if let existing = packURLs(for: entry) { return existing }
        guard let session = loadSession(id: entry.id), let result = session.result else {
            throw HistoryError.missingResult
        }
        return try ProtocolPack.makePack(
            session: session,
            result: result,
            directory: packDirectory(for: entry.protocolNumber)
        )
    }

    func delete(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        try? fileManager.removeItem(at: packDirectory(for: entry.protocolNumber))
        entries.removeAll { $0.id == id }
        try? encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    private func packDirectory(for protocolNumber: String) -> URL {
        rootURL.appendingPathComponent(protocolNumber, isDirectory: true)
    }

    enum HistoryError: LocalizedError {
        case missingResult

        var errorDescription: String? {
            switch self {
            case .missingResult: return "Protokoll ohne Analyse-Ergebnis"
            }
        }
    }
}
