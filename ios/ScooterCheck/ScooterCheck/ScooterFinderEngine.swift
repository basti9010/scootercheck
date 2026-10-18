import Foundation
import CoreLocation
import CoreMotion
import Combine

// MARK: - Public types

enum FinderSignalTier: String, Sendable {
    case weak
    case medium
    case strong
    case veryStrong
    case veryNear

    var label: String {
        switch self {
        case .weak: return "Schwach"
        case .medium: return "Mittel"
        case .strong: return "Stark"
        case .veryStrong: return "Sehr stark"
        case .veryNear: return "Sehr nah"
        }
    }

    static func from(rssi: Double) -> FinderSignalTier {
        switch rssi {
        case -48...0: return .veryNear
        case -58 ..< -48: return .veryStrong
        case -68 ..< -58: return .strong
        case -80 ..< -68: return .medium
        default: return .weak
        }
    }
}

enum FinderDirectionQuality: String, Sendable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "Gering"
        case .medium: return "Mittel"
        case .high: return "Hoch"
        }
    }
}

enum ScooterFinderPhase: Equatable, Sendable {
    case idle
    case calibrating
    case directing
    case proximity
}

struct FinderSample: Equatable, Sendable {
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let heading: Double?
    let headingAccuracy: Double?
    let rssiRaw: Int
    let rssiSmoothed: Double
    let stepCount: Int?
    let distanceMeters: Double?
}

/// Stabile Scan-Listen-Reihenfolge: RSSI-Werte dürfen zucken, die Zeilen nicht dauernd tauschen.
/// Sortierung für BLE-Gerätelisten (Gerätesuche, Signal-Finder, Auslesen).
enum BleDeviceListSort: String, CaseIterable, Identifiable, Sendable {
    case signal
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signal: return "Signal"
        case .name: return "Name"
        }
    }
}

enum BleDeviceListOrdering {
    /// Gerät hat einen nutzbaren Advertisement-Namen (nicht nur UUID-/Platzhalter).
    static func hasAdvertisedName(cryptoName: String, name: String) -> Bool {
        let crypto = cryptoName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !crypto.isEmpty { return true }
        let ui = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if ui.isEmpty { return false }
        if ui.hasPrefix("Ohne Namen") { return false }
        if ui.hasPrefix("Verbunden (") { return false }
        if ui.localizedCaseInsensitiveContains("Unbekannt") { return false }
        return true
    }

    static func hasAdvertisedName(_ device: ScannedDevice) -> Bool {
        hasAdvertisedName(cryptoName: device.cryptoName, name: device.name)
    }

    static func displaySortName(_ device: ScannedDevice) -> String {
        if let label = device.modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        return device.bleListDisplayName
    }

    static func prepare(
        _ devices: [ScannedDevice],
        sort: BleDeviceListSort,
        hideNameless: Bool
    ) -> [ScannedDevice] {
        var list = devices
        if hideNameless {
            list = list.filter(hasAdvertisedName)
        }
        switch sort {
        case .signal:
            return list.sorted { a, b in
                if a.isStale != b.isStale { return !a.isStale && b.isStale }
                if a.rssi != b.rssi { return a.rssi > b.rssi }
                return displaySortName(a).localizedCaseInsensitiveCompare(displaySortName(b)) == .orderedAscending
            }
        case .name:
            return list.sorted { a, b in
                let cmp = displaySortName(a).localizedCaseInsensitiveCompare(displaySortName(b))
                if cmp != .orderedSame { return cmp == .orderedAscending }
                if a.isStale != b.isStale { return !a.isStale && b.isStale }
                return a.rssi > b.rssi
            }
        }
    }
}

enum BleScanListStabilizer {
    /// Erst umsortieren, wenn der Nachbar klar stärker ist (dBm).
    static let hysteresisDb = 8
    /// Mindestabstand zwischen Umsortierungen.
    static let minReorderInterval: TimeInterval = 1.8

    struct Item: Equatable, Sendable {
        let id: UUID
        let rssi: Int
        let isStale: Bool
    }

    static func reconcile(
        previousOrder: [UUID],
        devices: [ScannedDevice],
        lastReorderAt: Date,
        now: Date = Date(),
        hysteresisDb: Int = hysteresisDb,
        minInterval: TimeInterval = minReorderInterval
    ) -> (order: [UUID], reorderAt: Date) {
        reconcile(
            previousOrder: previousOrder,
            items: devices.map { Item(id: $0.id, rssi: $0.rssi, isStale: $0.isStale) },
            lastReorderAt: lastReorderAt,
            now: now,
            hysteresisDb: hysteresisDb,
            minInterval: minInterval
        )
    }

    static func reconcile(
        previousOrder: [UUID],
        items: [Item],
        lastReorderAt: Date,
        now: Date = Date(),
        hysteresisDb: Int = hysteresisDb,
        minInterval: TimeInterval = minReorderInterval
    ) -> (order: [UUID], reorderAt: Date) {
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var order = previousOrder.filter { byId[$0] != nil }
        let known = Set(order)
        let newcomers = items
            .map(\.id)
            .filter { !known.contains($0) }
            .sorted { (byId[$0]?.rssi ?? -120) > (byId[$1]?.rssi ?? -120) }

        for id in newcomers {
            let rssi = byId[id]?.rssi ?? -120
            if let idx = order.firstIndex(where: { (byId[$0]?.rssi ?? -120) < rssi }) {
                order.insert(id, at: idx)
            } else {
                order.append(id)
            }
        }

        let live = order.filter { !(byId[$0]?.isStale ?? true) }
        let stale = order.filter { byId[$0]?.isStale ?? true }
        guard live.count > 1, now.timeIntervalSince(lastReorderAt) >= minInterval else {
            return (live + stale, lastReorderAt)
        }

        var mutable = live
        var changed = false
        for _ in 0..<mutable.count {
            var swapped = false
            var i = 0
            while i < mutable.count - 1 {
                let ra = byId[mutable[i]]?.rssi ?? -120
                let rb = byId[mutable[i + 1]]?.rssi ?? -120
                if rb >= ra + hysteresisDb {
                    mutable.swapAt(i, i + 1)
                    swapped = true
                    changed = true
                }
                i += 1
            }
            if !swapped { break }
        }
        return (mutable + stale, changed ? now : lastReorderAt)
    }

    static func apply(order: [UUID], to devices: [ScannedDevice]) -> [ScannedDevice] {
        let byId = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        var result = order.compactMap { byId[$0] }
        let seen = Set(order)
        for device in devices where !seen.contains(device.id) {
            result.append(device)
        }
        return result
    }
}

/// Reine Mathematik für Tests — ohne Sensor-Hardware.
enum ScooterFinderMath {
    /// EMA: höhere alpha = reaktiver. rssi ist negativ (stärker = weniger negativ).
    static func ema(previous: Double?, sample: Double, alpha: Double = 0.28) -> Double {
        guard let previous else { return sample }
        return alpha * sample + (1 - alpha) * previous
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Gleitender Median der letzten `window` Werte, optional mit EMA danach.
    static func smoothRssi(history: [Int], window: Int = 7, emaAlpha: Double = 0.35) -> Double? {
        guard !history.isEmpty else { return nil }
        let slice = history.suffix(window).map(Double.init)
        guard let med = median(Array(slice)) else { return nil }
        // Leichte EMA gegen den letzten Rohwert für Reaktivität
        if let last = slice.last {
            return ema(previous: med, sample: last, alpha: emaAlpha)
        }
        return med
    }

    /// Schätzt Welt-Bearing (0=N, 90=O) der Signalzunahme aus räumlichen Samples.
    /// Rückgabe: (bearingDegrees, confidence 0…1) oder nil.
    static func estimateStrongerBearing(from samples: [FinderSample]) -> (bearing: Double, confidence: Double)? {
        let usable = samples.filter {
            $0.latitude != nil
                && $0.longitude != nil
                && ($0.horizontalAccuracy ?? 999) <= 35
        }
        guard usable.count >= 4 else { return nil }

        // Lokales ENU relativ zum ersten Punkt
        guard let lat0 = usable.first?.latitude, let lon0 = usable.first?.longitude else { return nil }
        var east = 0.0
        var north = 0.0
        var weightSum = 0.0

        for i in 1..<usable.count {
            let a = usable[i - 1]
            let b = usable[i]
            guard let la = a.latitude, let loa = a.longitude,
                  let lb = b.latitude, let lob = b.longitude else { continue }

            let (de, dn) = enuDeltaMeters(lat0: lat0, lon0: lon0, latA: la, lonA: loa, latB: lb, lonB: lob)
            let dist = hypot(de, dn)
            guard dist >= 0.6 else { continue } // zu wenig Bewegung

            let dRssi = b.rssiSmoothed - a.rssiSmoothed // positiv = stärker
            let accA = max(a.horizontalAccuracy ?? 25, 5)
            let accB = max(b.horizontalAccuracy ?? 25, 5)
            let accuracyWeight = 1.0 / ((accA + accB) / 2.0)
            let moveWeight = min(dist / 3.0, 2.0)
            let w = accuracyWeight * moveWeight * abs(dRssi)

            // Bei steigendem Signal: Bewegungsrichtung; bei fallendem: Gegenrichtung
            let ux = de / dist
            let uy = dn / dist
            let signed = dRssi >= 0 ? 1.0 : -1.0
            east += signed * ux * w
            north += signed * uy * w
            weightSum += w
        }

        guard weightSum > 0.15 else { return nil }
        let mag = hypot(east, north)
        guard mag > 1e-6 else { return nil }

        var bearing = atan2(east, north) * 180 / .pi // N=0
        if bearing < 0 { bearing += 360 }
        let confidence = min(1.0, mag / max(weightSum * 0.55, 0.01))
        return (bearing, confidence)
    }

    static func enuDeltaMeters(
        lat0: Double, lon0: Double,
        latA: Double, lonA: Double,
        latB: Double, lonB: Double
    ) -> (east: Double, north: Double) {
        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0 * cos(lat0 * .pi / 180)
        let eA = (lonA - lon0) * mPerDegLon
        let nA = (latA - lat0) * mPerDegLat
        let eB = (lonB - lon0) * mPerDegLon
        let nB = (latB - lat0) * mPerDegLat
        return (eB - eA, nB - nA)
    }

    /// Relative Pfeilrichtung: Welt-Bearing minus Device-Heading → 0 = nach oben auf dem Display.
    static func relativeArrowDegrees(worldBearing: Double, deviceHeading: Double) -> Double {
        var d = worldBearing - deviceHeading
        while d < -180 { d += 360 }
        while d > 180 { d -= 360 }
        return d
    }

    static func pathLengthMeters(_ samples: [FinderSample]) -> Double {
        let pts = samples.compactMap { s -> (Double, Double)? in
            guard let la = s.latitude, let lo = s.longitude,
                  (s.horizontalAccuracy ?? 999) <= 40 else { return nil }
            return (la, lo)
        }
        guard pts.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            let (lat0, lon0) = pts[0]
            let (aLat, aLon) = pts[i - 1]
            let (bLat, bLon) = pts[i]
            let (e, n) = enuDeltaMeters(lat0: lat0, lon0: lon0, latA: aLat, lonA: aLon, latB: bLat, lonB: bLon)
            total += hypot(e, n)
        }
        return total
    }
}

// MARK: - Engine

@MainActor
final class ScooterFinderEngine: NSObject, ObservableObject {
    @Published private(set) var phase: ScooterFinderPhase = .idle
    @Published private(set) var smoothedRssi: Double?
    @Published private(set) var rawRssi: Int?
    @Published private(set) var signalTier: FinderSignalTier = .weak
    @Published private(set) var quality: FinderDirectionQuality = .low
    /// Pfeil relativ zum iPhone (0 = oben), nur bei ausreichender Qualität.
    @Published private(set) var relativeArrowDegrees: Double?
    @Published private(set) var worldBearingDegrees: Double?
    @Published private(set) var headline: String = "Richtung wird ermittelt …"
    @Published private(set) var subtitle: String = "Bitte bewege dich einige Meter."
    @Published private(set) var footnote: String? = "ScooterCheck vergleicht die Bluetooth-Signalstärke während deiner Bewegung."
    @Published private(set) var strongestRssi: Double?
    @Published private(set) var movingAwayFromPeak: Bool = false
    @Published private(set) var sampleCount: Int = 0
    @Published private(set) var authorizationHint: String?
    @Published private(set) var showArrow: Bool = false

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()

    private var trackedId: UUID?
    private var rssiHistory: [Int] = []
    private var samples: [FinderSample] = []
    private var uiTimer: Timer?
    private var lastLocation: CLLocation?
    private var lastHeading: CLHeading?
    private var stepCount: Int = 0
    private var pedometerStart: Date?
    private var peakRssi: Double?
    private var peakLocation: CLLocation?
    private var bleCancellable: AnyCancellable?
    private weak var ble: BleClient?

    private let maxSamples = 80
    private let minSamplesForDirection = 6
    private let minPathMeters: Double = 3.5
    private let proximityRssi: Double = -52

    func start(tracking deviceId: UUID, ble: BleClient) {
        stop(resetUI: false)
        self.ble = ble
        trackedId = deviceId
        phase = .calibrating
        headline = "Richtung wird ermittelt …"
        subtitle = "Bitte bewege dich einige Meter."
        footnote = "ScooterCheck vergleicht die Bluetooth-Signalstärke während deiner Bewegung."
        showArrow = false
        relativeArrowDegrees = nil
        worldBearingDegrees = nil
        quality = .low
        authorizationHint = nil
        rssiHistory = []
        samples = []
        sampleCount = 0
        peakRssi = nil
        peakLocation = nil
        movingAwayFromPeak = false
        stepCount = 0

        startSensors()
        bleCancellable = ble.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.ingestBle(devices)
            }
        if let match = ble.devices.first(where: { $0.id == deviceId }) {
            ingestRssi(match.rssi)
        }

        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop(resetUI: Bool = true) {
        uiTimer?.invalidate()
        uiTimer = nil
        bleCancellable?.cancel()
        bleCancellable = nil
        trackedId = nil
        ble = nil
        stopSensors()
        if resetUI {
            phase = .idle
            headline = "Suche beendet"
            subtitle = ""
            footnote = nil
            showArrow = false
        }
    }

    // MARK: - Sensors

    private func startSensors() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1
        locationManager.headingFilter = 2
        locationManager.activityType = .fitness

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            authorizationHint = "Standortfreigabe wird benötigt, um Signaländerungen während der Bewegung auszuwerten."
        case .denied, .restricted:
            authorizationHint = "Ohne Standort kann die Richtung nur eingeschränkt geschätzt werden. Bitte in den Einstellungen erlauben."
        default:
            authorizationHint = nil
        }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.2
            motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
        }

        if CMPedometer.isStepCountingAvailable() {
            let start = Date()
            pedometerStart = start
            pedometer.startUpdates(from: start) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor in
                    self?.stepCount = data.numberOfSteps.intValue
                }
            }
        }
    }

    private func stopSensors() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
        pedometerStart = nil
    }

    private func ingestBle(_ devices: [ScannedDevice]) {
        guard let trackedId,
              let device = devices.first(where: { $0.id == trackedId }) else { return }
        ingestRssi(device.rssi)
    }

    private func ingestRssi(_ rssi: Int) {
        // Ausreißer filtern (typisch 127 = ungültig)
        guard rssi < 20, rssi > -120 else { return }
        rawRssi = rssi
        rssiHistory.append(rssi)
        if rssiHistory.count > 40 {
            rssiHistory.removeFirst(rssiHistory.count - 40)
        }
        if let smooth = ScooterFinderMath.smoothRssi(history: rssiHistory) {
            smoothedRssi = smooth
            signalTier = FinderSignalTier.from(rssi: smooth)
            if peakRssi == nil || smooth > (peakRssi ?? -999) {
                peakRssi = smooth
                peakLocation = lastLocation
                strongestRssi = smooth
            }
        }
    }

    private func tick() {
        guard phase != .idle, let smooth = smoothedRssi, let raw = rawRssi else { return }

        let sample = FinderSample(
            timestamp: Date(),
            latitude: lastLocation?.coordinate.latitude,
            longitude: lastLocation?.coordinate.longitude,
            horizontalAccuracy: lastLocation?.horizontalAccuracy,
            heading: lastHeading?.trueHeading ?? lastHeading?.magneticHeading,
            headingAccuracy: lastHeading.map { Double($0.headingAccuracy) },
            rssiRaw: raw,
            rssiSmoothed: smooth,
            stepCount: stepCount,
            distanceMeters: nil
        )
        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        sampleCount = samples.count

        // Peak-Abstand
        if let peak = peakRssi {
            movingAwayFromPeak = (peak - smooth) >= 6
        }

        // Nähe-Modus
        if smooth >= proximityRssi {
            phase = .proximity
            showArrow = false
            relativeArrowDegrees = nil
            quality = .high
            headline = "Sehr nah"
            subtitle = "Starkes Signal — Richtung ist hier weniger aussagekräftig."
            footnote = movingAwayFromPeak
                ? "Du entfernst dich vom stärksten bisherigen Signal."
                : "Stärkstes Signal bisher: \(Int(peakRssi?.rounded() ?? smooth.rounded())) dBm"
            return
        }

        let path = ScooterFinderMath.pathLengthMeters(samples)
        let estimate = ScooterFinderMath.estimateStrongerBearing(from: samples)
        let headingOK = (lastHeading?.headingAccuracy ?? 180) >= 0
            && (lastHeading?.headingAccuracy ?? 180) < 35

        if let estimate, path >= minPathMeters, samples.count >= minSamplesForDirection, headingOK {
            let conf = estimate.confidence
            if conf >= 0.55 {
                quality = .high
            } else if conf >= 0.28 {
                quality = .medium
            } else {
                quality = .low
            }

            worldBearingDegrees = estimate.bearing
            if let heading = lastHeading?.trueHeading ?? lastHeading?.magneticHeading {
                relativeArrowDegrees = ScooterFinderMath.relativeArrowDegrees(
                    worldBearing: estimate.bearing,
                    deviceHeading: heading
                )
            }

            if quality == .low {
                phase = .calibrating
                showArrow = false
                headline = "Richtung noch nicht zuverlässig"
                subtitle = "Bitte bewege dich weiter."
                footnote = "ScooterCheck vergleicht die Bluetooth-Signalstärke während deiner Bewegung."
            } else {
                phase = .directing
                showArrow = true
                headline = quality == .high
                    ? "Signal wird in dieser Richtung stärker"
                    : "Beste Signalrichtung"
                subtitle = movingAwayFromPeak
                    ? "Du entfernst dich vom stärksten bisherigen Signal."
                    : "Stärkstes Signal bisher: \(Int(peakRssi?.rounded() ?? smooth.rounded())) dBm"
                footnote = nil
            }
        } else {
            phase = .calibrating
            showArrow = false
            quality = .low
            headline = "Richtung wird ermittelt …"
            if path < 1.2 {
                subtitle = "Bitte bewege dich einige Meter."
            } else {
                subtitle = "Bitte bewege dich weiter."
            }
            footnote = "ScooterCheck vergleicht die Bluetooth-Signalstärke während deiner Bewegung."
            if !headingOK {
                authorizationHint = "Kompass/Heading noch ungenau — iPhone kurz in der Hand bewegen."
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ScooterFinderEngine: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                authorizationHint = nil
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            case .denied, .restricted:
                authorizationHint = "Ohne Standort kann die Richtung nur eingeschränkt geschätzt werden. Bitte in den Einstellungen erlauben."
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            // Schlechte Fixes verwerfen
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 50 else { return }
            lastLocation = loc
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            guard newHeading.headingAccuracy >= 0 else { return }
            lastHeading = newHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            authorizationHint = "Standort derzeit nicht verfügbar."
        }
    }
}
