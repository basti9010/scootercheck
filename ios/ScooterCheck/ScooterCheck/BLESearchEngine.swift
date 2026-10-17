import Foundation
import CoreLocation
import CoreMotion
import Combine
import UIKit
import AudioToolbox

/// Orchestriert BLE-RSSI, Position und Heatmap-Session — ohne Richtungs-Pfeil als Haupt-UI.
@MainActor
final class BLESearchEngine: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var deviceName: String = ""
    @Published private(set) var rawRssi: Int?
    @Published private(set) var smoothedRssi: Double?
    @Published private(set) var signalClass: BLESignalClass = .lost
    @Published private(set) var trend: BLESignalTrend = .stable
    @Published private(set) var searchMode: BLESearchModeKind = .coarse
    @Published private(set) var heatmap = BLEHeatmapSnapshot.empty
    @Published private(set) var strongestRssi: Double?
    @Published private(set) var strongestLabel: String = "—"
    @Published private(set) var durationText: String = "0:00"
    @Published private(set) var signalStatus: String = "BLE-Suche aktiv"
    @Published private(set) var positionHint: String?
    @Published private(set) var measurementCount: Int = 0
    @Published var hapticsEnabled = false
    @Published var audioEnabled = false

    private(set) var session: BLESearchSession?

    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var processor = BLESignalProcessor()
    private var trackedId: UUID?
    private weak var ble: BleClient?
    private var bleCancellable: AnyCancellable?
    private var tickTimer: Timer?
    private var startedAt: Date?
    private var lastLocation: CLLocation?
    private var lastHeading: CLHeading?
    private var lastPersistedAt: Date?
    private var lastPersistedLocation: CLLocation?
    private var lastPersistedRssi: Double?
    private var lastSeenDeviceAt: Date?
    private var originLocation: CLLocation?
    private var relativeX: Double = 0
    private var relativeY: Double = 0
    private var stepCount = 0
    private var lastHapticAt: Date = .distantPast
    private var lastAudioAt: Date = .distantPast
    private var heatmapDirty = true

    func start(device: ScannedDevice, ble: BleClient) {
        stop(discardSession: true)
        self.ble = ble
        trackedId = device.id
        deviceName = device.bleListDisplayName
        session = BLESearchSession(deviceId: device.id, deviceName: deviceName)
        processor.reset()
        isActive = true
        searchMode = .coarse
        heatmap = .empty
        strongestRssi = nil
        strongestLabel = "—"
        measurementCount = 0
        signalStatus = "BLE-Suche aktiv"
        positionHint = nil
        relativeX = 0
        relativeY = 0
        originLocation = nil
        lastPersistedAt = nil
        lastPersistedLocation = nil
        lastPersistedRssi = nil
        lastSeenDeviceAt = Date()
        startedAt = Date()
        heatmapDirty = true

        startSensors()
        bleCancellable = ble.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.ingestDevices(devices)
            }
        if let match = ble.devices.first(where: { $0.id == device.id }) {
            ingestRssi(match.rssi)
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop(discardSession: Bool) {
        tickTimer?.invalidate()
        tickTimer = nil
        bleCancellable?.cancel()
        bleCancellable = nil
        stopSensors()
        isActive = false
        if discardSession {
            session = nil
        } else if var s = session {
            s.endedAt = Date()
            session = s
        }
        trackedId = nil
        ble = nil
    }

    func setMode(_ mode: BLESearchModeKind) {
        searchMode = mode
        if var s = session {
            s.searchMode = mode.rawValue
            session = s
        }
    }

    func finalizeAndOptionallySave(save: Bool) {
        guard var s = session else { return }
        s.endedAt = Date()
        session = s
        if save {
            BLESearchStore.shared.save(s)
        }
        stop(discardSession: true)
    }

    // MARK: - Sensors

    private func startSensors() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1
        locationManager.headingFilter = 3
        locationManager.activityType = .fitness
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            positionHint = "Standortfreigabe wird benötigt für die Heatmap."
        case .denied, .restricted:
            positionHint = "Positionsgenauigkeit eingeschränkt — relative Bewegung, sofern möglich."
        default:
            positionHint = nil
        }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
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
        pedometer.stopUpdates()
    }

    // MARK: - Ingest

    private func ingestDevices(_ devices: [ScannedDevice]) {
        guard let trackedId,
              let device = devices.first(where: { $0.id == trackedId }) else { return }
        lastSeenDeviceAt = Date()
        ingestRssi(device.rssi)
    }

    private func ingestRssi(_ rssi: Int) {
        rawRssi = rssi
        if let smooth = processor.ingest(rawRssi: rssi) {
            smoothedRssi = smooth
            if strongestRssi == nil || smooth > (strongestRssi ?? -999) {
                strongestRssi = smooth
                strongestLabel = BLESignalClass.from(smoothedRssi: smooth, lost: false).label
            }
            maybePersistMeasurement(force: false)
            feedback(for: smooth)
        }
        updateSignalState()
    }

    private func tick() {
        guard isActive else { return }
        updateSignalState()
        updateDuration()
        maybePersistMeasurement(force: false)
        if heatmapDirty {
            rebuildHeatmap()
        }
    }

    private func updateDuration() {
        guard let startedAt else { return }
        let sec = Int(Date().timeIntervalSince(startedAt))
        durationText = String(format: "%d:%02d", sec / 60, sec % 60)
    }

    private func updateSignalState() {
        let now = Date()
        let since = lastSeenDeviceAt.map { now.timeIntervalSince($0) } ?? 999
        let softLost = since >= BLESignalConfig.signalLostSoftSeconds
        let hardLost = since >= BLESignalConfig.signalLostHardSeconds
        signalClass = BLESignalClass.from(smoothedRssi: smoothedRssi, lost: softLost)
        trend = processor.trend(at: now)
        if hardLost {
            signalStatus = "Signal nicht mehr empfangen"
        } else if softLost {
            signalStatus = "Signal kurzzeitig verloren"
        } else {
            signalStatus = "BLE-Suche aktiv"
        }

        if let loc = lastLocation {
            let q = BLEPositionQuality.from(accuracyMeters: loc.horizontalAccuracy)
            if q == .low || q == .unknown {
                positionHint = "Positionsgenauigkeit eingeschränkt"
            } else if locationManager.authorizationStatus == .authorizedWhenInUse
                        || locationManager.authorizationStatus == .authorizedAlways {
                positionHint = nil
            }
        }
    }

    private func maybePersistMeasurement(force: Bool) {
        guard isActive,
              let raw = rawRssi,
              let smooth = smoothedRssi else { return }
        let now = Date()
        let moved: Bool = {
            guard let last = lastPersistedLocation, let cur = lastLocation else {
                return lastLocation != nil
            }
            return cur.distance(from: last) >= BLESignalConfig.minMoveMeters
        }()
        let timeOK = lastPersistedAt.map { now.timeIntervalSince($0) >= BLESignalConfig.minSampleInterval } ?? true
        let rssiOK = lastPersistedRssi.map { abs(smooth - $0) >= BLESignalConfig.minRssiChangeForSample } ?? true
        guard force || (timeOK && (moved || rssiOK || lastPersistedAt == nil)) else { return }

        updateRelativePosition()
        let accuracy = lastLocation?.horizontalAccuracy
        let quality = BLEPositionQuality.from(accuracyMeters: accuracy)
        let m = BLEMeasurement(
            timestamp: now,
            rawRssi: raw,
            smoothedRssi: smooth,
            latitude: lastLocation?.coordinate.latitude,
            longitude: lastLocation?.coordinate.longitude,
            relativeX: relativeX,
            relativeY: relativeY,
            accuracy: accuracy,
            heading: lastHeading?.trueHeading ?? lastHeading?.magneticHeading,
            motionConfidence: quality.weight,
            positionQuality: quality
        )
        guard var s = session else { return }
        s.measurements.append(m)
        if s.measurements.count > BLESignalConfig.maxStoredMeasurements {
            s.measurements.removeFirst(s.measurements.count - BLESignalConfig.maxStoredMeasurements)
        }
        if s.strongestMeasurementId == nil
            || (s.strongestMeasurement?.smoothedRssi ?? -999) < smooth {
            s.strongestMeasurementId = m.id
        }
        session = s
        measurementCount = s.measurements.count
        lastPersistedAt = now
        lastPersistedLocation = lastLocation
        lastPersistedRssi = smooth
        heatmapDirty = true
    }

    private func updateRelativePosition() {
        guard let loc = lastLocation else { return }
        if originLocation == nil {
            originLocation = loc
            relativeX = 0
            relativeY = 0
            return
        }
        guard let origin = originLocation else { return }
        let (e, n) = ScooterFinderMath.enuDeltaMeters(
            lat0: origin.coordinate.latitude,
            lon0: origin.coordinate.longitude,
            latA: origin.coordinate.latitude,
            lonA: origin.coordinate.longitude,
            latB: loc.coordinate.latitude,
            lonB: loc.coordinate.longitude
        )
        relativeX = e
        relativeY = n
    }

    private func rebuildHeatmap() {
        guard let s = session else { return }
        heatmap = BLEHeatmapProcessor.build(from: s.measurements)
        heatmapDirty = false
    }

    // MARK: - Feedback

    private func feedback(for smooth: Double) {
        let now = Date()
        let level = BLEHeatmapProcessor.normalizedStrength(smooth)
        let interval = max(0.35, 1.35 - level * 1.05)
        if hapticsEnabled, now.timeIntervalSince(lastHapticAt) >= interval {
            lastHapticAt = now
            let style: UIImpactFeedbackGenerator.FeedbackStyle = level > 0.7 ? .medium : .light
            UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: CGFloat(0.35 + level * 0.55))
        }
        if audioEnabled, now.timeIntervalSince(lastAudioAt) >= interval {
            lastAudioAt = now
            playClick(intensity: level)
        }
    }

    private func playClick(intensity: Double) {
        AudioServicesPlaySystemSound(1104)
        _ = intensity
    }
}

extension BLESearchEngine: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = loc
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.lastHeading = newHeading
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.positionHint = "Positionsgenauigkeit eingeschränkt"
            case .authorizedAlways, .authorizedWhenInUse:
                if self.positionHint?.contains("Standortfreigabe") == true {
                    self.positionHint = nil
                }
            default:
                break
            }
        }
    }
}
