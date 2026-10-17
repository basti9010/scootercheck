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
        /// Kurzer Anzeigename für die Scan-Liste (Kennzeichen / Name).
        var knownLabel: String?
        /// BLE-Peripheral-UUID dieses iPhones — Wiedererkennung auch ohne SN im Advertisement.
        var blePeripheralId: UUID?
        /// Roher Advertisement-Name beim letzten Check (oft = SN).
        var bleAdvertisementName: String?
        /// Nur nach erfolgreicher Protokoll-Validierung `true`. Fehlt bei Legacy-Einträgen (`nil`).
        var wasVerifiedAsScooter: Bool?
        /// Archiviert: Daten bleiben erhalten, erscheinen nur unter „Archiv“.
        var isArchived: Bool

        enum CodingKeys: String, CodingKey {
            case id, protocolNumber, createdAt, profile, verdict, score, serialDisplay, trackId
            case subjectSummary, knownLabel, blePeripheralId, bleAdvertisementName, wasVerifiedAsScooter
            case isArchived
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
            subjectSummary: String? = nil,
            knownLabel: String? = nil,
            blePeripheralId: UUID? = nil,
            bleAdvertisementName: String? = nil,
            wasVerifiedAsScooter: Bool? = nil,
            isArchived: Bool = false
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
            self.knownLabel = knownLabel
            self.blePeripheralId = blePeripheralId
            self.bleAdvertisementName = bleAdvertisementName
            self.wasVerifiedAsScooter = wasVerifiedAsScooter
            self.isArchived = isArchived
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
            knownLabel = try c.decodeIfPresent(String.self, forKey: .knownLabel)
            blePeripheralId = try c.decodeIfPresent(UUID.self, forKey: .blePeripheralId)
            bleAdvertisementName = try c.decodeIfPresent(String.self, forKey: .bleAdvertisementName)
            wasVerifiedAsScooter = try c.decodeIfPresent(Bool.self, forKey: .wasVerifiedAsScooter)
            isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
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
            try c.encodeIfPresent(knownLabel, forKey: .knownLabel)
            try c.encodeIfPresent(blePeripheralId, forKey: .blePeripheralId)
            try c.encodeIfPresent(bleAdvertisementName, forKey: .bleAdvertisementName)
            try c.encodeIfPresent(wasVerifiedAsScooter, forKey: .wasVerifiedAsScooter)
            try c.encode(isArchived, forKey: .isArchived)
        }

        /// Label für die Geräteliste: gespeicherter Name, sonst „bereits geprüft“.
        var scanListAlias: String? {
            guard ScooterVerification.qualifiesAsKnownScooter(self) else { return nil }
            if let knownLabel, !knownLabel.isEmpty { return knownLabel }
            if let subjectSummary, !subjectSummary.isEmpty { return subjectSummary }
            if serialDisplay != nil { return "bereits geprüft" }
            return nil
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
    /// `scannedDevice` merkt BLE-UUID/Advertisement nur bei verifizierter Scooter-Auslese.
    @discardableResult
    func save(_ session: CheckSession, scannedDevice: ScannedDevice? = nil) throws -> ProtocolPack.PackURLs {
        guard let result = session.result else {
            throw HistoryError.missingResult
        }

        let verified = ScooterVerification.isVerifiedScooterReading(result.reading)
            || ScooterVerification.isVerifiedScooterReading(session.reading)
        // Ohne technische Scooter-Validierung kein „bekannter Scooter“ und keine BLE-Verknüpfung.
        guard verified else {
            throw HistoryError.notVerifiedScooter
        }
        let rememberDevice = scannedDevice

        let dir = packDirectory(for: session.protocolNumber)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let sessionURL = dir.appendingPathComponent("session.json")
        try encoder.encode(session).write(to: sessionURL, options: .atomic)

        let pack = try ProtocolPack.makePack(session: session, result: result, directory: dir)

        let serial = result.reading.serialDisplay ?? session.reading.serialDisplay
        let previous = entries.first(where: { $0.id == session.id })
            ?? entries.first(where: { entry in
                guard let serial else { return false }
                return entry.serialDisplay.map { Self.serialsMatch(serial, $0) } ?? false
            })

        let advName: String? = {
            guard let rememberDevice else {
                return previous?.bleAdvertisementName
            }
            let raw = rememberDevice.cryptoName.isEmpty ? rememberDevice.name : rememberDevice.cryptoName
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.hasPrefix("Ohne Namen") ? previous?.bleAdvertisementName : trimmed
        }()

        let bleId: UUID? = {
            if let rememberDevice { return rememberDevice.id }
            // Kein neues Gerät → bestehende UUID behalten (nur bei bereits verifiziertem Eintrag).
            if let previous, ScooterVerification.qualifiesAsKnownScooter(previous) {
                return previous.blePeripheralId
            }
            return previous?.blePeripheralId
        }()

        var next = entries.filter { $0.id != session.id }
        next.insert(
            Entry(
                id: session.id,
                protocolNumber: session.protocolNumber,
                createdAt: session.createdAt,
                profile: session.profile,
                verdict: result.verdict,
                score: result.score,
                serialDisplay: serial,
                trackId: result.trackMatch.trackId.rawValue,
                subjectSummary: session.subject.summaryLine,
                knownLabel: Self.makeKnownLabel(from: session.subject) ?? previous?.knownLabel,
                blePeripheralId: bleId,
                bleAdvertisementName: advName,
                wasVerifiedAsScooter: true,
                isArchived: previous?.isArchived ?? false
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
        delete(ids: [id])
    }

    /// Dauerhaft entfernen (nicht Archivieren).
    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removing = entries.filter { ids.contains($0.id) }
        for entry in removing {
            try? fileManager.removeItem(at: packDirectory(for: entry.protocolNumber))
        }
        entries.removeAll { ids.contains($0.id) }
        try? encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    /// Aktive (nicht archivierte) Prüfungen — Standardliste.
    var activeEntries: [Entry] {
        entries.filter { !$0.isArchived }
    }

    /// Nur archivierte Prüfungen.
    var archivedEntries: [Entry] {
        entries.filter(\.isArchived)
    }

    var activeCount: Int { activeEntries.count }
    var archivedCount: Int { archivedEntries.count }

    /// Archivieren: Daten bleiben, Eintrag verschwindet aus „Aktiv“.
    @discardableResult
    func archive(ids: Set<UUID>) -> Int {
        setArchived(ids, archived: true)
    }

    /// Wiederherstellen: zurück nach „Aktiv“.
    @discardableResult
    func restore(ids: Set<UUID>) -> Int {
        setArchived(ids, archived: false)
    }

    @discardableResult
    private func setArchived(_ ids: Set<UUID>, archived: Bool) -> Int {
        guard !ids.isEmpty else { return 0 }
        var changed = 0
        entries = entries.map { entry in
            guard ids.contains(entry.id), entry.isArchived != archived else { return entry }
            var next = entry
            next.isArchived = archived
            changed += 1
            return next
        }
        if changed > 0 {
            try? encoder.encode(entries).write(to: indexURL, options: .atomic)
        }
        return changed
    }

    /// Pack-Dateien für Share Sheet (eine oder mehrere Prüfungen).
    func shareItems(for ids: Set<UUID>) -> [Any] {
        var items: [Any] = []
        for entry in entries where ids.contains(entry.id) {
            guard let pack = try? ensurePack(for: entry) else { continue }
            items.append(contentsOf: [
                NamedShareFile(
                    url: pack.pdfURL,
                    title: "ScooterCheck \(entry.protocolNumber) Bericht.pdf",
                    utType: "com.adobe.pdf"
                ),
                NamedShareFile(
                    url: pack.jsonURL,
                    title: "ScooterCheck \(entry.protocolNumber) Daten.json",
                    utType: "public.json"
                )
            ])
        }
        return items
    }

    // MARK: - Scan-Listen-Wiedererkennung

    /// Gespeicherter Name / Kennzeichen für ein Gerät in der BLE-Suche.
    /// Nur für technisch verifizierte Scooter (nie nach bloßem Connect/Fehler).
    func knownAlias(for device: ScannedDevice) -> String? {
        knownEntry(for: device)?.scanListAlias
    }

    func knownEntry(for device: ScannedDevice) -> Entry? {
        let keys = Self.scanIdentityKeys(for: device)
        for entry in entries where ScooterVerification.qualifiesAsKnownScooter(entry) {
            if let sn = entry.serialDisplay, Self.identityMatches(sn, keys: keys) {
                return entry
            }
            if let adv = entry.bleAdvertisementName, Self.identityMatches(adv, keys: keys) {
                return entry
            }
            // Peripheral-UUID nur bei verifiziertem Eintrag mit SN (kein TV-Fehllink).
            if entry.wasVerifiedAsScooter == true
                || (entry.wasVerifiedAsScooter == nil && (entry.serialDisplay?.count ?? 0) >= 8),
               let pid = entry.blePeripheralId, pid == device.id {
                return entry
            }
        }
        return nil
    }

    /// Geräte mit bekanntem Alias zuerst, danach stärkeres Signal.
    func sortForScanList(_ devices: [ScannedDevice]) -> [ScannedDevice] {
        devices.sorted { a, b in
            let aKnown = knownAlias(for: a) != nil
            let bKnown = knownAlias(for: b) != nil
            if aKnown != bKnown { return aKnown && !bKnown }
            return a.rssi > b.rssi
        }
    }

    /// Ob Advertisement/Name des Geräts zur ausgelesenen Seriennummer passt.
    static func deviceMatchesSerial(_ device: ScannedDevice, serial: String?) -> Bool {
        guard let serial, !serial.isEmpty else { return false }
        return identityMatches(serial, keys: scanIdentityKeys(for: device))
    }

    static func makeKnownLabel(from subject: ProtocolSubject) -> String? {
        let s = subject.sanitized()
        switch (s.displayName, s.licensePlate) {
        case let (name?, plate?):
            return "\(name) · \(plate)"
        case let (name?, nil):
            return name
        case let (nil, plate?):
            return plate
        default:
            return s.summaryLine
        }
    }

    private static func scanIdentityKeys(for device: ScannedDevice) -> [String] {
        var keys: [String] = []
        let raw = device.cryptoName.isEmpty ? device.name : device.cryptoName
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.hasPrefix("Ohne Namen") {
            keys.append(normalizeSerial(trimmed))
        }
        if let compact = BleModelHint.compactScooterId(from: raw) {
            keys.append(normalizeSerial(compact))
        }
        // Auch UI-Name, falls Advertisement und Anzeige auseinanderlaufen
        let ui = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ui.isEmpty, !ui.hasPrefix("Ohne Namen") {
            keys.append(normalizeSerial(ui))
        }
        return Array(Set(keys.filter { $0.count >= 6 }))
    }

    private static func identityMatches(_ stored: String, keys: [String]) -> Bool {
        let needle = normalizeSerial(stored)
        guard needle.count >= 6 else { return false }
        return keys.contains { key in
            serialsMatch(needle, key) || key.contains(needle) || needle.contains(key)
        }
    }

    private func packDirectory(for protocolNumber: String) -> URL {
        rootURL.appendingPathComponent(protocolNumber, isDirectory: true)
    }

    enum HistoryError: LocalizedError {
        case missingResult
        case notVerifiedScooter

        var errorDescription: String? {
            switch self {
            case .missingResult: return "Protokoll ohne Analyse-Ergebnis"
            case .notVerifiedScooter: return "Kein unterstützter Scooter erkannt — Speicherung übersprungen"
            }
        }
    }
}
