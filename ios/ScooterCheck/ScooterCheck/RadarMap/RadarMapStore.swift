import Foundation
import Combine

/// Lokale Persistenz für Radar-Karten-Sichtungen (Application Support JSON).
@MainActor
final class RadarMapStore: ObservableObject {
    static let shared = RadarMapStore()

    @Published private(set) var sessions: [RadarMapSession] = []
    @Published private(set) var identities: [RadarDeviceIdentity] = []
    @Published private(set) var sightings: [RadarSighting] = []
    @Published private(set) var hidden: [HiddenRadarDevice] = []
    @Published var settings: RadarMapSettings {
        didSet { settings.save() }
    }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private let maxSightingsSoftCap = 8000

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ScooterCheck/RadarMap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("store.json")
        settings = RadarMapSettings.load()
        load()
        pruneRetentionIfNeeded()
    }

    // MARK: - Queries

    func identity(id: UUID) -> RadarDeviceIdentity? {
        identities.first { $0.id == id }
    }

    func sightings(forIdentity id: UUID) -> [RadarSighting] {
        sightings
            .filter { $0.deviceIdentityId == id }
            .sorted { $0.firstSeenAt < $1.firstSeenAt }
    }

    func isHidden(identityId: UUID?, peripheralId: UUID) -> Bool {
        hidden.contains { h in
            if let identityId, h.deviceIdentityId == identityId { return true }
            if let pid = h.peripheralId, pid == peripheralId { return true }
            return false
        }
    }

    func hiddenEntry(identityId: UUID?, peripheralId: UUID) -> HiddenRadarDevice? {
        hidden.first { h in
            if let identityId, h.deviceIdentityId == identityId { return true }
            if let pid = h.peripheralId, pid == peripheralId { return true }
            return false
        }
    }

    /// Gefilterte Sichtungen für die Karte.
    func filteredSightings(filter: RadarMapFilter, now: Date = Date()) -> [RadarSighting] {
        let rangeStart = filter.timePreset.startDate(now: now, customStart: filter.customStart)
        let rangeEnd = filter.timePreset == .custom ? (filter.customEnd ?? now) : now

        var list = sightings.filter { s in
            if let rangeStart, s.lastSeenAt < rangeStart { return false }
            if s.firstSeenAt > rangeEnd { return false }
            return true
        }

        // Hidden
        if !filter.showHidden {
            list = list.filter { s in
                !isHidden(identityId: s.deviceIdentityId, peripheralId: s.peripheralId)
            }
        }

        switch filter.deviceFilter {
        case .all: break
        case .confirmedScooter:
            list = list.filter { $0.deviceKind == .confirmedScooter }
        case .possibleScooter:
            list = list.filter { $0.deviceKind == .possibleScooter || $0.deviceKind == .confirmedScooter }
        case .unknownBLE:
            list = list.filter { $0.deviceKind == .unknownBLE }
        }

        if let mfg = filter.manufacturer, !mfg.isEmpty {
            let key = mfg.uppercased()
            list = list.filter { ($0.manufacturer ?? "").uppercased().contains(key) }
        }

        switch filter.approval {
        case .all: break
        case .approved:
            list = list.filter { $0.approvalStatusRaw == GermanVehicleApprovalStatus.approved.rawValue }
        case .unconfirmed:
            list = list.filter {
                $0.approvalStatusRaw == GermanVehicleApprovalStatus.unconfirmed.rawValue
                    || $0.approvalStatusRaw == GermanVehicleApprovalStatus.modelUnidentified.rawValue
                    || $0.approvalStatusRaw == nil
            }
        case .noApproval:
            list = list.filter { $0.approvalStatusRaw == GermanVehicleApprovalStatus.noGermanApprovalDocumented.rawValue }
        }

        switch filter.signal {
        case .all: break
        case .mediumPlus:
            list = list.filter { ($0.strongestRSSI ?? -999) >= -80 }
        case .strong:
            list = list.filter { ($0.strongestRSSI ?? -999) >= -65 }
        case .veryStrong:
            list = list.filter { ($0.strongestRSSI ?? -999) >= -50 }
        }

        if let idConf = filter.identification {
            list = list.filter { $0.identificationConfidence == idConf }
        }

        if filter.onlyRepeated {
            let counts = sightingCounts(
                scope: filter.repeatScope,
                timeFiltered: list,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            )
            list = list.filter { s in
                guard let iid = s.deviceIdentityId else { return false }
                return (counts[iid] ?? 0) >= filter.minSightings
            }
        }

        return list.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    func sightingCounts(
        scope: RadarMapRepeatScope,
        timeFiltered: [RadarSighting],
        rangeStart: Date?,
        rangeEnd: Date
    ) -> [UUID: Int] {
        let source: [RadarSighting]
        switch scope {
        case .withinTimeRange:
            source = timeFiltered
        case .entireHistory:
            source = sightings.filter { s in
                // Still respect hidden unless caller already filtered
                true
            }
        }
        var counts: [UUID: Int] = [:]
        for s in source {
            guard let iid = s.deviceIdentityId,
                  s.identityMatchConfidence.allowsHistoryMerge else { continue }
            counts[iid, default: 0] += 1
        }
        return counts
    }

    func distinctAreaCount(forIdentity id: UUID, precision: Double = 0.001) -> Int {
        var cells = Set<String>()
        for s in sightings(forIdentity: id) {
            guard let loc = s.location, loc.isUsable else { continue }
            let key = "\(Int(loc.latitude / precision)):\(Int(loc.longitude / precision))"
            cells.insert(key)
        }
        return cells.count
    }

    func manufacturersPresent() -> [String] {
        Array(Set(sightings.compactMap(\.manufacturer).filter { !$0.isEmpty })).sorted()
    }

    // MARK: - Mutations

    @discardableResult
    func upsertSession(_ session: RadarMapSession) -> RadarMapSession {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        scheduleSave()
        return session
    }

    func endSession(id: UUID, at date: Date = Date()) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].endedAt = date
        scheduleSave()
    }

    func upsertIdentity(_ identity: RadarDeviceIdentity) {
        if let idx = identities.firstIndex(where: { $0.id == identity.id }) {
            identities[idx] = identity
        } else {
            identities.append(identity)
        }
        scheduleSave()
    }

    func upsertSighting(_ sighting: RadarSighting) {
        if let idx = sightings.firstIndex(where: { $0.id == sighting.id }) {
            sightings[idx] = sighting
        } else {
            sightings.append(sighting)
        }
        if let iid = sighting.deviceIdentityId, let idx = identities.firstIndex(where: { $0.id == iid }) {
            identities[idx].lastSeenAt = max(identities[idx].lastSeenAt, sighting.lastSeenAt)
            identities[idx].sightingCount = sightings.filter { $0.deviceIdentityId == iid }.count
            if let m = sighting.manufacturer { identities[idx].manufacturer = m }
            if let m = sighting.model { identities[idx].model = m }
            identities[idx].displayName = sighting.displayName
        }
        if sightings.count > maxSightingsSoftCap {
            sightings = Array(sightings.suffix(maxSightingsSoftCap))
        }
        scheduleSave()
    }

    func deleteSighting(id: UUID) {
        sightings.removeAll { $0.id == id }
        refreshIdentityCounts()
        scheduleSave()
    }

    func deleteHistory(forIdentity id: UUID) {
        sightings.removeAll { $0.deviceIdentityId == id }
        if let idx = identities.firstIndex(where: { $0.id == id }) {
            identities[idx].sightingCount = 0
        }
        scheduleSave()
    }

    func deleteAllSightings() {
        sightings = []
        for i in identities.indices {
            identities[i].sightingCount = 0
        }
        scheduleSave()
    }

    func hideDevice(
        identityId: UUID,
        peripheralId: UUID?,
        displayName: String,
        manufacturer: String?,
        model: String?
    ) {
        if let existing = hidden.firstIndex(where: { $0.deviceIdentityId == identityId }) {
            hidden[existing].hiddenAt = Date()
            hidden[existing].peripheralId = peripheralId ?? hidden[existing].peripheralId
            scheduleSave()
            return
        }
        hidden.append(
            HiddenRadarDevice(
                id: UUID(),
                deviceIdentityId: identityId,
                peripheralId: peripheralId,
                hiddenAt: Date(),
                reason: nil,
                suppressRadarNotifications: true,
                displayName: displayName,
                manufacturer: manufacturer,
                model: model
            )
        )
        scheduleSave()
    }

    func unhideDevice(identityId: UUID) {
        hidden.removeAll { $0.deviceIdentityId == identityId }
        scheduleSave()
    }

    func pruneRetentionIfNeeded(now: Date = Date()) {
        guard let hours = settings.retentionHours else { return }
        let cutoff = now.addingTimeInterval(-Double(hours) * 3600)
        let before = sightings.count
        sightings.removeAll { $0.lastSeenAt < cutoff }
        if sightings.count != before {
            refreshIdentityCounts()
            scheduleSave()
        }
    }

    // MARK: - Persistence

    private func refreshIdentityCounts() {
        for i in identities.indices {
            let id = identities[i].id
            identities[i].sightingCount = sightings.filter { $0.deviceIdentityId == id }.count
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(RadarMapSnapshotFile.self, from: data) else {
            return
        }
        sessions = file.sessions
        identities = file.identities
        sightings = file.sightings
        hidden = file.hidden
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            persistNow()
        }
    }

    func persistNow() {
        let file = RadarMapSnapshotFile(
            version: 1,
            sessions: sessions,
            identities: identities,
            sightings: sightings,
            hidden: hidden
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
