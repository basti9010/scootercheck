import Foundation
import Combine

/// Orchestriert lokale Identifikation, optional Online-Recherche und Ergebnis-Cache.
/// Nutzt dieselben `ScannedDevice`-Events — kein zweiter BLE-Scan.
@MainActor
final class BLEIdentificationService: ObservableObject {
    static let shared = BLEIdentificationService()

    @Published private(set) var results: [UUID: BLEIdentificationResult] = [:]
    @Published private(set) var observation: TimedObservation?
    @Published var settings: BLEIdentificationSettings {
        didSet { settings.save() }
    }

    private var signatureByDevice: [UUID: String] = [:]
    private var onlineInFlight: Set<UUID> = []
    private var onlineCache: [String: CachedOnline] = [:]
    private var payloadVariants: [UUID: Set<String>] = [:]
    private var observationTask: Task<Void, Never>?
    private let onlineCacheKey = "bleIdentification.onlineCache.v1"
    private let catalog = BluetoothCompanyCatalog.shared

    struct TimedObservation: Equatable {
        var deviceId: UUID
        var endsAt: Date
        var duration: TimeInterval
        var variantCount: Int
        var isRunning: Bool

        var remaining: TimeInterval {
            max(0, endsAt.timeIntervalSinceNow)
        }
    }

    private struct CachedOnline: Codable {
        var result: BLEIdentificationResult
        var cacheKey: String
        var savedAt: Date
    }

    private init() {
        settings = BLEIdentificationSettings.load()
        loadOnlineCache()
    }

    // MARK: - Public API

    func result(for deviceId: UUID) -> BLEIdentificationResult? {
        results[deviceId]
    }

    /// Schnelle lokale Analyse bei jedem relevanten Advertising-Update.
    func ingest(_ device: ScannedDevice) {
        let signature = advSignature(device)
        recordPayloadVariant(deviceId: device.id, signature: signature)

        if signatureByDevice[device.id] == signature, results[device.id] != nil {
            return
        }
        signatureByDevice[device.id] = signature
        let local = BLEIdentificationEngine.analyze(
            BLEIdentificationEngine.input(from: device),
            catalog: catalog
        )
        var merged = local
        if let cached = onlineCache[signature]?.result,
           settings.onlineIdentificationEnabled,
           settings.onlineConsentAccepted {
            merged = IdentificationResultMerger.merge(local: local, online: cached)
        }
        results[device.id] = merged

        if settings.onlineIdentificationEnabled,
           settings.onlineConsentAccepted,
           shouldRequestOnline(local: merged, signature: signature) {
            Task { await refreshOnline(for: device, signature: signature, local: merged) }
        }
    }

    /// Längere Beobachtung: sammelt Advertising-Varianten ohne erfundene iOS-Felder.
    func startTimedObservation(deviceId: UUID, duration: TimeInterval = 30) {
        observationTask?.cancel()
        let ends = Date().addingTimeInterval(duration)
        payloadVariants[deviceId] = payloadVariants[deviceId] ?? []
        observation = TimedObservation(
            deviceId: deviceId,
            endsAt: ends,
            duration: duration,
            variantCount: payloadVariants[deviceId]?.count ?? 0,
            isRunning: true
        )
        observationTask = Task { @MainActor in
            while !Task.isCancelled {
                guard var obs = observation, obs.deviceId == deviceId, obs.isRunning else { return }
                let remaining = obs.endsAt.timeIntervalSinceNow
                if remaining <= 0 { break }
                obs.variantCount = payloadVariants[deviceId]?.count ?? 0
                observation = obs
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return }
            finishTimedObservation(deviceId: deviceId)
        }
    }

    func cancelTimedObservation() {
        observationTask?.cancel()
        observationTask = nil
        if var obs = observation {
            obs.isRunning = false
            observation = obs
        }
    }

    private func finishTimedObservation(deviceId: UUID) {
        let count = payloadVariants[deviceId]?.count ?? 0
        if var obs = observation, obs.deviceId == deviceId {
            obs.isRunning = false
            obs.variantCount = count
            observation = obs
        }
        // Nächstes Advertising erzwingt Neuanalyse mit gesammelten Varianten.
        signatureByDevice.removeValue(forKey: deviceId)
        if var result = results[deviceId] {
            result.evidence.removeAll { $0.id == "timed-obs" }
            result.evidence.append(
                IdentificationEvidence(
                    id: "timed-obs",
                    title: "Zeitliche Beobachtung",
                    detail: count <= 1
                        ? "Über den Beobachtungszeitraum kam nur eine Advertising-Variante an (oder unveränderte Payloads)."
                        : "\(count) unterschiedliche Advertising-Varianten erfasst — Fingerprint/Analyse aktualisiert."
                )
            )
            result.analyzedAt = Date()
            results[deviceId] = result
        }
        objectWillChange.send()
    }

    private func recordPayloadVariant(deviceId: UUID, signature: String) {
        var set = payloadVariants[deviceId] ?? []
        set.insert(signature)
        payloadVariants[deviceId] = set
        if var obs = observation, obs.isRunning, obs.deviceId == deviceId {
            obs.variantCount = set.count
            observation = obs
        }
    }

    func reanalyze(_ device: ScannedDevice, includeOnline: Bool) async -> BLEIdentificationResult {
        signatureByDevice[device.id] = advSignature(device)
        let local = BLEIdentificationEngine.analyze(
            BLEIdentificationEngine.input(from: device),
            catalog: catalog
        )
        var merged = local
        if includeOnline,
           settings.onlineIdentificationEnabled,
           settings.onlineConsentAccepted {
            merged = await refreshOnline(for: device, signature: advSignature(device), local: local)
        }
        results[device.id] = merged
        return merged
    }

    func acceptOnlineConsent() {
        settings.onlineConsentAccepted = true
        settings.onlineConsentAcceptedAt = Date()
        settings.onlineIdentificationEnabled = true
    }

    func setOnlineEnabled(_ enabled: Bool) {
        guard !enabled || settings.onlineConsentAccepted else { return }
        settings.onlineIdentificationEnabled = enabled
    }

    func clearCaches() {
        cancelTimedObservation()
        results.removeAll()
        signatureByDevice.removeAll()
        payloadVariants.removeAll()
        onlineCache.removeAll()
        observation = nil
        UserDefaults.standard.removeObject(forKey: onlineCacheKey)
        objectWillChange.send()
    }

    func payloadVariantCount(for deviceId: UUID) -> Int {
        payloadVariants[deviceId]?.count ?? 0
    }

    func listTitle(for device: ScannedDevice) -> String {
        if let r = results[device.id] {
            return r.listTitle
        }
        if let label = device.modelLabel { return label }
        if device.looksLikeScooter { return "Möglicher Scooter" }
        return device.bleListDisplayName
    }

    func radarEligibleScooter(for device: ScannedDevice) -> Bool {
        if let r = results[device.id] {
            return r.radarEligibleScooter
        }
        // Fallback: bestehende Heuristik, bis erste Analyse läuft
        return device.looksLikeScooter && device.modelLabel != nil
    }

    // MARK: - Online

    @discardableResult
    private func refreshOnline(
        for device: ScannedDevice,
        signature: String,
        local: BLEIdentificationResult
    ) async -> BLEIdentificationResult {
        guard !onlineInFlight.contains(device.id) else { return local }
        onlineInFlight.insert(device.id)
        defer { onlineInFlight.remove(device.id) }

        let query = OnlineIdentificationProvider.Query(
            companyId: local.manufacturerCompanyId,
            serviceUUIDs: device.serviceUUIDs,
            localNamePrefix: device.cryptoName.isEmpty ? nil : String(device.cryptoName.prefix(24)),
            advertisingStructureKey: BLEDeviceFingerprint.from(device: device).advertisingStructureKey
        )
        let online = await OnlineIdentificationProvider.lookup(query)
        switch online {
        case .unavailable(let reason):
            var updated = local
            updated.onlineSourceNote = reason
            results[device.id] = updated
            return updated
        case .result(let remote):
            let merged = IdentificationResultMerger.merge(local: local, online: remote)
            onlineCache[signature] = CachedOnline(result: remote, cacheKey: signature, savedAt: Date())
            persistOnlineCache()
            results[device.id] = merged
            return merged
        }
    }

    private func shouldRequestOnline(local: BLEIdentificationResult, signature: String) -> Bool {
        if onlineCache[signature] != nil { return false }
        // Nur wenn lokal unklar oder Hersteller ohne Klasse/Modell
        switch local.confidence {
        case .high:
            return local.model == nil && local.deviceCategory == .unknown
        case .medium, .low, .unknown:
            return true
        }
    }

    private func advSignature(_ device: ScannedDevice) -> String {
        [
            device.manufacturerDataHex ?? "-",
            device.serviceUUIDs.sorted().joined(separator: ","),
            device.cryptoName.uppercased(),
            device.modelLabel ?? ""
        ].joined(separator: "|")
    }

    private func loadOnlineCache() {
        guard let data = UserDefaults.standard.data(forKey: onlineCacheKey),
              let decoded = try? JSONDecoder().decode([String: CachedOnline].self, from: data) else {
            return
        }
        // Älter als 90 Tage verwerfen
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        onlineCache = decoded.filter { $0.value.savedAt > cutoff }
    }

    private func persistOnlineCache() {
        if let data = try? JSONEncoder().encode(onlineCache) {
            UserDefaults.standard.set(data, forKey: onlineCacheKey)
        }
    }
}

// MARK: - Merger

enum IdentificationResultMerger {
    static func merge(local: BLEIdentificationResult, online: BLEIdentificationResult) -> BLEIdentificationResult {
        var out = local
        out.source = .combined
        out.analyzedAt = Date()

        // Online darf lokale Widersprüche nicht überschreiben
        if local.deviceCategory == .eScooter, online.deviceCategory != nil, online.deviceCategory != .eScooter {
            out.contradictions.append(
                IdentificationEvidence(
                    id: "online-vs-local-category",
                    title: "Online weicht ab",
                    detail: "Online schlägt „\(online.deviceCategory!.label)“ vor — lokale Scooter-Hinweise bleiben maßgeblich.",
                    supports: false
                )
            )
        }

        if out.manufacturer == nil { out.manufacturer = online.manufacturer }
        if out.model == nil,
           online.model != nil,
           online.confidence == .high || online.confidence == .medium {
            // Modell nur übernehmen, wenn Online selbst belastbar und lokal kein Widerspruch
            if out.deviceCategory == .unknown || out.deviceCategory == online.deviceCategory {
                out.model = online.model
                out.evidence.append(contentsOf: online.evidence.filter(\.supports))
            }
        }
        if out.deviceCategory == .unknown || out.deviceCategory == nil {
            if let cat = online.deviceCategory, cat != .eScooter {
                out.deviceCategory = cat
            } else if online.deviceCategory == .eScooter, online.confidence == .high {
                // Online-Scooter allein reicht nicht für Radar
                out.deviceCategory = .eScooter
                out.radarEligibleScooter = false
                out.contradictions.append(
                    IdentificationEvidence(
                        id: "online-scooter-unverified",
                        title: "Online-Scooter ohne lokale Bestätigung",
                        detail: "Kein Radar-Alarm allein aufgrund einer Online-Quelle.",
                        supports: false
                    )
                )
            }
        }

        out.onlineSourceNote = online.onlineSourceNote
        out.onlineFetchedAt = online.onlineFetchedAt ?? Date()
        out.confidence = maxConfidence(local.confidence, out.confidence)
        if let model = out.model {
            out.listTitle = model
        } else if let m = out.manufacturer {
            let short = m.replacingOccurrences(of: ", Inc.", with: "")
            if let cat = out.deviceCategory, cat != .unknown {
                out.listTitle = "\(short) – \(cat.label)"
            } else {
                out.listTitle = "\(short) – Modell unbekannt"
            }
        }
        return out
    }

    private static func maxConfidence(
        _ a: BLEIdentificationConfidence,
        _ b: BLEIdentificationConfidence
    ) -> BLEIdentificationConfidence {
        let order: [BLEIdentificationConfidence] = [.unknown, .low, .medium, .high]
        let ia = order.firstIndex(of: a) ?? 0
        let ib = order.firstIndex(of: b) ?? 0
        return order[max(ia, ib)]
    }
}
