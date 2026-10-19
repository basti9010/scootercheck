import Foundation
import CoreLocation
import CoreBluetooth
import Combine
import UserNotifications

/// Aggregiert BLE-Empfänge zu Sichtungen und speichert optional den Smartphone-Standort.
@MainActor
final class RadarMapRecorder: NSObject, ObservableObject {
    static let shared = RadarMapRecorder()

    @Published private(set) var lastLocation: RadarLocationSample?
    @Published private(set) var locationAuthorized = false

    private let store = RadarMapStore.shared
    private let locationManager = CLLocationManager()
    private var openSightings: [UUID: UUID] = [:] // peripheralId → sightingId
    private var activeMapSessionId: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var lastRepeatNotifyAt: [UUID: Date] = [:]

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 25
    }

    func attach(radar: BLERadarService) {
        // Radar-Hits als Beobachtungen (auch unter Alarmschwelle speichern, wenn aktiviert).
        // Zusätzlich Geräte aus dem Scan, die radar-eligible sind.
    }

    func beginMapSessionIfNeeded() {
        guard store.settings.storeSightings else { return }
        if let id = activeMapSessionId,
           store.sessions.contains(where: { $0.id == id && $0.endedAt == nil }) {
            return
        }
        let session = RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil)
        activeMapSessionId = session.id
        store.upsertSession(session)
    }

    func endMapSession() {
        if let id = activeMapSessionId {
            store.endSession(id: id)
        }
        activeMapSessionId = nil
        openSightings.removeAll()
    }

    func updateLocationAuthorization() {
        let status = locationManager.authorizationStatus
        locationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        if store.settings.storeLocation, locationAuthorized {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
        }
    }

    func requestLocationIfNeeded() {
        guard store.settings.storeLocation else { return }
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            updateLocationAuthorization()
        }
    }

    /// Wird für jedes gescannte, speicherwürdige Gerät aufgerufen (Radar-Session aktiv).
    func observe(
        device: ScannedDevice,
        confidence: BLEScooterConfidence,
        approval: GermanVehicleApprovalStatus?,
        now: Date = Date()
    ) {
        guard store.settings.storeSightings else { return }
        beginMapSessionIfNeeded()
        guard let sessionId = activeMapSessionId else { return }

        let fp = BLEDeviceFingerprint.from(device: device)
        let fpKey = fingerprintKey(fp)
        let match = resolveIdentity(device: device, fingerprint: fp, fingerprintKey: fpKey)
        let identityId = match.identity?.id

        // Ausgeblendet?
        if let hidden = store.hiddenEntry(identityId: identityId, peripheralId: device.id) {
            let retain = hidden.retainFutureSightings || store.settings.retainSightingsWhileHidden
            if !retain { return }
            // Speichern möglich, aber keine Repeat-Notification und nicht auf der normalen Karte
        } else if store.settings.notifyRepeatSightings,
                  let identityId,
                  match.confidence.allowsHistoryMerge {
            maybeNotifyRepeat(identityId: identityId, deviceName: device.bleListDisplayName, now: now)
        }

        let gap = TimeInterval(store.settings.sightingGapMinutes * 60)
        let kind = deviceKind(device: device, confidence: confidence)
        let idConf: RadarIdentificationConfidence = {
            switch confidence {
            case .high: return .high
            case .medium: return .medium
            case .low: return .unknown
            }
        }()

        let loc: RadarLocationSample? = {
            guard store.settings.storeLocation else { return nil }
            return lastLocation?.isUsable == true ? lastLocation : nil
        }()

        if let openId = openSightings[device.id],
           var existing = store.sightings.first(where: { $0.id == openId }),
           now.timeIntervalSince(existing.lastSeenAt) <= gap {
            // Fortsetzung derselben Sichtung
            existing.lastSeenAt = now
            existing.observationCount += 1
            if let rssi = Optional(device.rssi) {
                existing.strongestRSSI = max(existing.strongestRSSI ?? rssi, rssi)
                let prevAvg = existing.averageRSSI ?? Double(rssi)
                let n = Double(existing.observationCount)
                existing.averageRSSI = prevAvg + (Double(rssi) - prevAvg) / n
            }
            if existing.location == nil, let loc { existing.location = loc }
            if let m = match.identity?.manufacturer ?? ExtendedScooterModelHint.recognize(bleName: device.cryptoName)?.brand {
                existing.manufacturer = m
            }
            if let model = device.modelLabel ?? ExtendedScooterModelHint.recognize(bleName: device.cryptoName)?.title {
                existing.model = model
            }
            existing.approvalStatusRaw = approval?.rawValue ?? existing.approvalStatusRaw
            store.upsertSighting(existing)
            return
        }

        // Neue Sichtung
        var identity = match.identity
        if identity == nil, match.confidence.allowsHistoryMerge || match.confidence == .unknown {
            let created = RadarDeviceIdentity(
                id: UUID(),
                primaryPeripheralId: device.id,
                fingerprintKey: fpKey,
                displayName: device.bleListDisplayName,
                manufacturer: ExtendedScooterModelHint.recognize(bleName: device.cryptoName)?.brand,
                model: device.modelLabel ?? ExtendedScooterModelHint.recognize(bleName: device.cryptoName)?.title,
                firstSeenAt: now,
                lastSeenAt: now,
                sightingCount: 0,
                deviceKind: kind,
                approvalStatusRaw: approval?.rawValue
            )
            store.upsertIdentity(created)
            identity = created
        } else if var id = identity {
            id.lastSeenAt = now
            id.displayName = device.bleListDisplayName
            store.upsertIdentity(id)
            identity = id
        }

        let sighting = RadarSighting(
            id: UUID(),
            sessionId: sessionId,
            deviceIdentityId: identity?.id,
            peripheralId: device.id,
            fingerprintKey: fpKey,
            displayName: device.bleListDisplayName,
            manufacturer: identity?.manufacturer,
            model: identity?.model ?? device.modelLabel,
            identificationConfidence: idConf,
            identityMatchConfidence: match.confidence,
            firstSeenAt: now,
            lastSeenAt: now,
            observationCount: 1,
            strongestRSSI: device.rssi,
            averageRSSI: Double(device.rssi),
            smoothedRSSI: nil,
            location: loc,
            serviceUUIDs: device.serviceUUIDs,
            manufacturerDataHex: device.manufacturerDataHex,
            approvalStatusRaw: approval?.rawValue,
            deviceKind: kind
        )
        openSightings[device.id] = sighting.id
        store.upsertSighting(sighting)
    }

    // MARK: - Identity

    private struct IdentityResolution {
        var identity: RadarDeviceIdentity?
        var confidence: RadarIdentityMatchConfidence
    }

    private func resolveIdentity(
        device: ScannedDevice,
        fingerprint: BLEDeviceFingerprint,
        fingerprintKey: String
    ) -> IdentityResolution {
        // 1) Exakte Peripheral-ID
        if let byPeripheral = store.identities.first(where: { $0.primaryPeripheralId == device.id }) {
            return .init(identity: byPeripheral, confidence: .confirmed)
        }
        // Offene Sightings derselben Peripheral → confirmed über bestehende Identity
        if let openId = openSightings[device.id],
           let s = store.sightings.first(where: { $0.id == openId }),
           let iid = s.deviceIdentityId,
           let id = store.identity(id: iid) {
            return .init(identity: id, confidence: .confirmed)
        }

        // 2) Fingerprint — nur high score → confirmed; medium → possible (kein Merge für Repeat-Filter)
        var best: (RadarDeviceIdentity, Int)?
        for id in store.identities {
            let other = reconstructFingerprint(from: id)
            let score = BLEFingerprintService.compare(fingerprint, other).score
            if best == nil || score > best!.1 {
                best = (id, score)
            }
        }
        guard let best else {
            return .init(identity: nil, confidence: .unknown)
        }
        if best.1 >= 70 {
            return .init(identity: best.0, confidence: .confirmed)
        }
        if best.1 >= 45 {
            return .init(identity: best.0, confidence: .possible)
        }
        if best.1 >= 25 {
            return .init(identity: nil, confidence: .similarOnly)
        }
        return .init(identity: nil, confidence: .unknown)
    }

    private func reconstructFingerprint(from identity: RadarDeviceIdentity) -> BLEDeviceFingerprint {
        // FingerprintKey speichert strukturierte Merkmale; Name allein reicht nicht für Merge.
        let parts = identity.fingerprintKey.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let name = parts.count > 0 && !parts[0].isEmpty ? parts[0] : identity.displayName
        let mfg = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        let services = parts.count > 2 && !parts[2].isEmpty
            ? parts[2].split(separator: ",").map(String.init)
            : []
        let structure = parts.count > 3 ? parts[3] : ""
        return BLEDeviceFingerprint(
            localName: name,
            manufacturerDataHex: mfg,
            manufacturerId: nil,
            serviceUUIDs: services,
            serviceDataHexByUUID: [:],
            advertisingStructureKey: structure,
            txPower: nil,
            isConnectable: nil
        )
    }

    private func fingerprintKey(_ fp: BLEDeviceFingerprint) -> String {
        [
            fp.localName ?? "",
            fp.manufacturerDataHex ?? "",
            fp.serviceUUIDs.sorted().joined(separator: ","),
            fp.advertisingStructureKey
        ].joined(separator: "|")
    }

    private func deviceKind(device: ScannedDevice, confidence: BLEScooterConfidence) -> RadarDeviceKind {
        if let id = BLEIdentificationService.shared.result(for: device.id), id.radarEligibleScooter {
            return confidence == .high ? .confirmedScooter : .possibleScooter
        }
        if device.looksLikeScooter {
            return confidence == .high ? .confirmedScooter : .possibleScooter
        }
        return .unknownBLE
    }

    private func maybeNotifyRepeat(identityId: UUID, deviceName: String, now: Date) {
        let count = store.sightings.filter {
            $0.deviceIdentityId == identityId && $0.identityMatchConfidence.allowsHistoryMerge
        }.count
        guard count >= 1 else { return } // vor dem Anlegen der neuen Sichtung
        if let last = lastRepeatNotifyAt[identityId], now.timeIntervalSince(last) < 900 { return }
        lastRepeatNotifyAt[identityId] = now

        let content = UNMutableNotificationContent()
        content.title = "Bekannter Scooter erneut erkannt"
        content.body = "Zu „\(deviceName)“ liegen bereits \(count) frühere Sichtungen vor."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "radar-map-repeat-\(identityId.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

extension RadarMapRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.updateLocationAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = RadarLocationSample(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                horizontalAccuracy: loc.horizontalAccuracy,
                timestamp: loc.timestamp
            )
        }
    }
}
