import Foundation
import CoreLocation
import CoreMotion
import Combine
import UIKit
import AudioToolbox
import MapKit

/// Orchestriert BLE-RSSI, Position, Heatmap und Analyse — ohne Richtungs-Pfeil als BLE-Kompass.
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

    // Pfad / Ansicht
    @Published var surfaceMode: BLESearchSurfaceMode = .relative
    @Published private(set) var pathSnapshot = BLESearchPathSnapshot.empty
    @Published private(set) var mapOverlay = BLEMapOverlayModel.empty
    @Published private(set) var pathLengthText: String = "0.00 m"
    @Published private(set) var breadcrumbs: [BLEBreadcrumb] = []
    @Published private(set) var surfaceHint: String = "Relative Suchfläche – keine exakte Ortung"

    // Analyse / erweiterte Suche
    @Published private(set) var timeline = BLESearchTimeline()
    @Published private(set) var signalHistory = BLESignalHistory()
    @Published private(set) var movementHint = BLEMovementHint.inactive
    @Published private(set) var directionTrend = BLEDirectionTrend.none
    @Published private(set) var searchGrid = BLESearchGrid.empty
    @Published private(set) var fingerprintMatch: BLEFingerprintMatchResult?
    @Published private(set) var baselineFingerprint: BLEDeviceFingerprint?
    @Published private(set) var refoundBanner: String?
    @Published private(set) var lostDurationText: String?
    @Published var userSearchArea: BLESearchArea?

    private(set) var session: BLESearchSession?

    private let locationManager = CLLocationManager()
    private let indoorTracker = IndoorMotionTracker()
    private var processor = BLESignalProcessor()
    private var movementAnalyzer = BLEMovementAnalyzer()
    private var directionService = BLEDirectionTrendService()
    private var trackedId: UUID?
    private var baselineFP: BLEDeviceFingerprint?
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
    private var lostSince: Date?
    private var wasSoftLost = false
    private var wasHardLost = false
    private var sawDeviceOnce = false
    private var originLocation: CLLocation?
    private var relativeX: Double = 0
    private var relativeY: Double = 0
    private var lastHapticAt: Date = .distantPast
    private var lastAudioAt: Date = .distantPast
    private var heatmapDirty = true
    private var pathDirty = true
    private var lastFingerprintCompareAt: Date = .distantPast
    private var lastStrongerEventAt: Date = .distantPast
    private var lastCentroid: (x: Double, y: Double)?
    private var lastAdvSignature: String?
    private var lastLostFeedbackAt: Date = .distantPast
    private var lastRefoundFeedbackAt: Date = .distantPast
    private var followViewport = true
    private var lastPersistedRelative: (x: Double, y: Double)?
    private var userPickedSurfaceMode = false
    private var didAutoPickSurfaceMode = false

    func start(device: ScannedDevice, ble: BleClient) {
        stop(discardSession: true)
        self.ble = ble
        trackedId = device.id
        deviceName = device.bleListDisplayName
        let fp = BLEDeviceFingerprint.from(device: device)
        baselineFP = fp
        baselineFingerprint = fp
        session = BLESearchSession(
            deviceId: device.id,
            deviceName: deviceName,
            baselineFingerprint: fp
        )
        processor.reset()
        movementAnalyzer.reset()
        directionService.reset()
        indoorTracker.reset()
        timeline.reset()
        signalHistory.reset()
        movementHint = .inactive
        directionTrend = .none
        searchGrid = .empty
        pathSnapshot = .empty
        mapOverlay = .empty
        pathLengthText = "0.00 m"
        breadcrumbs = []
        fingerprintMatch = nil
        refoundBanner = nil
        lostDurationText = nil
        isActive = true
        searchMode = .coarse
        surfaceMode = .relative
        followViewport = true
        heatmap = .empty
        strongestRssi = nil
        strongestLabel = "—"
        measurementCount = 0
        signalStatus = "BLE-Suche aktiv"
        positionHint = nil
        surfaceHint = "Relative Suchfläche – keine exakte Ortung"
        relativeX = 0
        relativeY = 0
        originLocation = nil
        lastPersistedAt = nil
        lastPersistedLocation = nil
        lastPersistedRssi = nil
        lastSeenDeviceAt = Date()
        lostSince = nil
        wasSoftLost = false
        wasHardLost = false
        sawDeviceOnce = false
        startedAt = Date()
        heatmapDirty = true
        pathDirty = true
        lastCentroid = nil
        lastPersistedRelative = nil
        userPickedSurfaceMode = false
        didAutoPickSurfaceMode = false
        lastAdvSignature = advSignature(device)
        lastFingerprintCompareAt = .distantPast

        recordEvent(
            type: .searchStarted,
            title: "Suche gestartet",
            description: deviceName,
            minInterval: 0
        )
        recordEvent(type: .coarseMode, title: "Grobsuche aktiviert", minInterval: 0)

        startSensors()
        indoorTracker.start()
        bleCancellable = ble.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.ingestDevices(devices)
            }
        if let match = ble.devices.first(where: { $0.id == device.id }) {
            handleSighting(match, exactId: true)
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop(discardSession: Bool) {
        if isActive {
            recordEvent(type: .searchEnded, title: "Suche beendet", minInterval: 0)
            syncEventsToSession()
        }
        tickTimer?.invalidate()
        tickTimer = nil
        bleCancellable?.cancel()
        bleCancellable = nil
        stopSensors()
        indoorTracker.stop()
        isActive = false
        if discardSession {
            session = nil
        } else if var s = session {
            s.endedAt = Date()
            s.events = timeline.events
            session = s
        }
        trackedId = nil
        ble = nil
    }

    func setMode(_ mode: BLESearchModeKind) {
        guard searchMode != mode else { return }
        searchMode = mode
        if var s = session {
            s.searchMode = mode.rawValue
            session = s
        }
        recordEvent(
            type: mode == .fine ? .fineMode : .coarseMode,
            title: mode == .fine ? "Feinsuche aktiviert" : "Grobsuche aktiviert",
            minInterval: 0
        )
    }

    func setSurfaceMode(_ mode: BLESearchSurfaceMode) {
        userPickedSurfaceMode = true
        applySurfaceMode(mode)
    }

    private func applySurfaceMode(_ mode: BLESearchSurfaceMode) {
        surfaceMode = mode
        surfaceHint = mode == .relative
            ? "Relative Suchfläche – keine exakte Ortung"
            : "Kartenansicht – Heatmap bleibt Orientierung, keine exakte Ortung"
        if var s = session {
            s.mapType = mode == .map ? "appleMapOverlay" : "relativeHeatmap"
            session = s
        }
        pathDirty = true
        heatmapDirty = true
        rebuildPathAndHeatmap(force: true)
    }

    func recenterViewport() {
        followViewport = true
        if let cur = pathSnapshot.current {
            pathSnapshot = BLESearchPathSnapshot(
                points: pathSnapshot.points,
                smoothedPolyline: pathSnapshot.smoothedPolyline,
                pathLengthMeters: pathSnapshot.pathLengthMeters,
                viewport: SearchViewportController.recenter(on: (cur.x, cur.y), span: pathSnapshot.viewport.spanMeters),
                current: pathSnapshot.current
            )
            heatmapDirty = true
            rebuildPathAndHeatmap(force: true)
        }
        if surfaceMode == .map {
            mapOverlay = OutdoorMapTracker.model(
                origin: originLocation,
                path: pathSnapshot.points,
                smoothedPolyline: pathSnapshot.smoothedPolyline,
                measurements: session?.measurements ?? [],
                lastGPS: lastLocation,
                previousRegion: nil,
                softFollow: false
            )
        }
    }

    func finalizeAndOptionallySave(save: Bool) {
        guard var s = session else { return }
        s.endedAt = Date()
        s.events = timeline.events
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
    }

    private func stopSensors() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    // MARK: - Ingest

    private func ingestDevices(_ devices: [ScannedDevice]) {
        guard let trackedId else { return }

        if let device = devices.first(where: { $0.id == trackedId }) {
            handleSighting(device, exactId: true)
            return
        }

        // Signal verloren — weiter per Fingerprint suchen (Session bleibt aktiv).
        guard wasSoftLost || wasHardLost, let baseline = baselineFP else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFingerprintCompareAt) >= 1.8 else { return }
        lastFingerprintCompareAt = now

        var best: (ScannedDevice, BLEFingerprintMatchResult)?
        for d in devices {
            // Keine Geräte, die schon klar andere IDs mit schlechtem Score haben — Score prüfen
            let fp = BLEDeviceFingerprint.from(device: d)
            let match = BLEFingerprintService.compare(baseline, fp)
            if match.similarity == .high || match.similarity == .medium {
                if best == nil || match.score > (best?.1.score ?? 0) {
                    best = (d, match)
                }
            }
        }
        if let best, best.1.similarity == .high || best.1.similarity == .medium {
            fingerprintMatch = best.1
            handleSighting(best.0, exactId: false, fingerprintSimilarity: best.1.similarity)
        }
    }

    private func handleSighting(
        _ device: ScannedDevice,
        exactId: Bool,
        fingerprintSimilarity: BLEFingerprintSimilarity? = nil
    ) {
        let now = Date()
        let previouslyLost = wasSoftLost || wasHardLost
        let lostFor = lostSince.map { now.timeIntervalSince($0) } ?? 0

        lastSeenDeviceAt = now
        deviceName = device.bleListDisplayName

        if !sawDeviceOnce {
            sawDeviceOnce = true
            recordEvent(
                type: .deviceFirstSeen,
                title: "Gerät erstmals gesehen",
                rssi: Double(device.rssi),
                minInterval: 0
            )
        }

        if previouslyLost {
            let possible = !exactId || fingerprintSimilarity == .medium
            let mins = Int(lostFor) / 60
            let secs = Int(lostFor) % 60
            let duration = String(format: "%d:%02d min", mins, secs)
            if possible {
                signalStatus = "Möglicherweise wiedergefunden"
                refoundBanner = "Möglicherweise wiedergefunden nach \(duration)"
                recordEvent(
                    type: .signalPossiblyRefound,
                    title: "Möglicherweise wiedergefunden",
                    description: "Wiedererkennung über Fingerprint-Ähnlichkeit · nach \(duration)",
                    rssi: Double(device.rssi),
                    minInterval: 0
                )
                signalHistory.addMarker(.signalRefound, at: now)
            } else {
                signalStatus = "Signal wiedergefunden"
                refoundBanner = "Wiedergefunden nach \(duration)"
                recordEvent(
                    type: .signalRefound,
                    title: "Signal wiedergefunden",
                    description: "nach \(duration)",
                    rssi: Double(device.rssi),
                    minInterval: 0
                )
                signalHistory.addMarker(.signalRefound, at: now)
            }
            lostDurationText = duration
            lostSince = nil
            wasSoftLost = false
            wasHardLost = false
            if now.timeIntervalSince(lastRefoundFeedbackAt) > 1.5 {
                lastRefoundFeedbackAt = now
                if hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                if audioEnabled {
                    AudioServicesPlaySystemSound(1057)
                }
            }
            // Banner nach kurzer Zeit ausblenden
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                if self.refoundBanner != nil {
                    self.refoundBanner = nil
                }
            }
        }

        // Advertising-Änderung
        let sig = advSignature(device)
        if let prev = lastAdvSignature, prev != sig {
            recordEvent(
                type: .advertisingChanged,
                title: "Advertising-Daten verändert",
                description: "Technische Merkmale haben sich geändert",
                minInterval: 8
            )
            if let baseline = baselineFP {
                let match = BLEFingerprintService.compare(baseline, BLEDeviceFingerprint.from(device: device))
                fingerprintMatch = match
            }
        }
        lastAdvSignature = sig

        if exactId, let baseline = baselineFP, now.timeIntervalSince(lastFingerprintCompareAt) >= 2.5 {
            lastFingerprintCompareAt = now
            fingerprintMatch = BLEFingerprintService.compare(baseline, BLEDeviceFingerprint.from(device: device))
        }

        ingestRssi(device.rssi)
    }

    private func advSignature(_ device: ScannedDevice) -> String {
        let services = device.serviceUUIDs.sorted().joined(separator: ",")
        let serviceData: String = {
            guard let dict = device.serviceDataHexByUUID, !dict.isEmpty else { return "-" }
            return dict.keys.sorted().map { key in
                "\(key):\(dict[key] ?? "")"
            }.joined(separator: "|")
        }()
        let tx = device.txPower.map(String.init) ?? "-"
        let connectable: String = {
            guard let flag = device.isConnectable else { return "?" }
            return flag ? "1" : "0"
        }()
        return [
            device.cryptoName,
            device.manufacturerDataHex ?? "-",
            services,
            serviceData,
            tx,
            connectable
        ].joined(separator: "#")
    }

    private func ingestRssi(_ rssi: Int) {
        rawRssi = rssi
        if let smooth = processor.ingest(rawRssi: rssi) {
            smoothedRssi = smooth
            signalHistory.append(smoothed: smooth, raw: rssi)
            if strongestRssi == nil || smooth > (strongestRssi ?? -999) {
                strongestRssi = smooth
                strongestLabel = BLESignalClass.from(smoothedRssi: smooth, lost: false).label
                signalHistory.addMarker(.strongest)
                recordEvent(
                    type: .strongestAreaUpdated,
                    title: "Stärkster Bereich aktualisiert",
                    rssi: smooth,
                    minInterval: 4
                )
            }
            let now = Date()
            if trend == .stronger, now.timeIntervalSince(lastStrongerEventAt) > 6 {
                lastStrongerEventAt = now
                recordEvent(
                    type: .signalStronger,
                    title: "Signal stärker geworden",
                    rssi: smooth,
                    minInterval: 6
                )
            }
            syncRelativeFromTracker()
            directionService.ingest(date: now, x: relativeX, y: relativeY, rssi: smooth)
            directionTrend = directionService.evaluate(at: now)
            maybePersistMeasurement(force: false)
            feedback(for: smooth)
        }
        updateSignalState()
    }

    private func tick() {
        guard isActive else { return }
        syncRelativeFromTracker()
        updateSignalState()
        updateDuration()
        maybePersistMeasurement(force: false)
        pathDirty = true
        rebuildPathAndHeatmap(force: false)
        evaluateMovement()
    }

    private func syncRelativeFromTracker() {
        let nx = indoorTracker.currentX
        let ny = indoorTracker.currentY
        if hypot(nx - relativeX, ny - relativeY) >= 0.05 {
            relativeX = nx
            relativeY = ny
            pathDirty = true
            heatmapDirty = true
        }
        if let heading = lastHeading {
            applyCompassHeading(heading)
        }
    }

    private func applyCompassHeading(_ heading: CLHeading) {
        let h = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        guard h >= 0 else { return }
        let accuracy = heading.headingAccuracy
        // Gyro führt Indoor; Kompass nur Initial + weiche Ankerung bei brauchbarer Genauigkeit
        indoorTracker.ingestExternalHeading(
            h,
            fromCompass: accuracy >= 0 && accuracy <= BLEPathConfig.compassMaxAccuracyDegrees,
            accuracy: accuracy
        )
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

        if softLost && !wasSoftLost {
            wasSoftLost = true
            if lostSince == nil { lostSince = lastSeenDeviceAt ?? now }
            signalStatus = "Signal verloren"
            signalHistory.addMarker(.signalLost, at: now)
            recordEvent(
                type: .signalLost,
                title: "Signal verloren",
                description: "Suche bleibt aktiv — weiter nach bekannten Merkmalen",
                minInterval: 0
            )
            if now.timeIntervalSince(lastLostFeedbackAt) > 2 {
                lastLostFeedbackAt = now
                if hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }
        }
        if hardLost {
            wasHardLost = true
            signalStatus = "Signal verloren"
            if let lostSince {
                let sec = Int(now.timeIntervalSince(lostSince))
                lostDurationText = String(format: "%d:%02d", sec / 60, sec % 60)
            }
        } else if softLost {
            signalStatus = "Signal verloren"
        } else if refoundBanner == nil {
            signalStatus = "BLE-Suche aktiv"
        }

        wasSoftLost = softLost
        if !softLost {
            wasHardLost = false
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

    private func evaluateMovement() {
        let speed = lastLocation?.speed
        let accuracy = lastLocation?.horizontalAccuracy
        var centroidShift: Double?
        if let s = session {
            let recent = s.measurements.suffix(12)
            let pts = recent.compactMap { m -> (Double, Double)? in
                guard let x = m.relativeX, let y = m.relativeY else { return nil }
                return (x, y)
            }
            if pts.count >= 3 {
                let cx = pts.map(\.0).reduce(0, +) / Double(pts.count)
                let cy = pts.map(\.1).reduce(0, +) / Double(pts.count)
                if let last = lastCentroid {
                    centroidShift = hypot(cx - last.x, cy - last.y)
                }
                lastCentroid = (cx, cy)
            }
        }
        let hint = movementAnalyzer.evaluate(
            now: Date(),
            phoneSpeed: speed,
            accuracy: accuracy,
            smoothedRssi: smoothedRssi,
            signalLostRecently: wasHardLost || (lostSince != nil),
            heatmapCentroidShiftMeters: centroidShift
        )
        if hint.active && !movementHint.active {
            recordEvent(
                type: .devicePossiblyMoved,
                title: "Mögliche Bewegung erkannt",
                description: hint.explanation + " (\(hint.confidence.label))",
                rssi: smoothedRssi,
                minInterval: 12
            )
        }
        movementHint = hint
    }

    private func maybePersistMeasurement(force: Bool) {
        guard isActive,
              let raw = rawRssi,
              let smooth = smoothedRssi,
              signalClass != .lost else { return }
        let now = Date()
        syncRelativeFromTracker()
        let gpsMoved: Bool = {
            guard let last = lastPersistedLocation, let cur = lastLocation else {
                return lastLocation != nil
            }
            return cur.distance(from: last) >= BLESignalConfig.minMoveMeters
        }()
        let relativeMoved: Bool = {
            guard let last = lastPersistedRelative else { return true }
            return hypot(relativeX - last.x, relativeY - last.y) >= BLESignalConfig.minMoveMeters
        }()
        let timeOK = lastPersistedAt.map { now.timeIntervalSince($0) >= BLESignalConfig.minSampleInterval } ?? true
        let rssiOK = lastPersistedRssi.map { abs(smooth - $0) >= BLESignalConfig.minRssiChangeForSample } ?? true
        guard force || (timeOK && (gpsMoved || relativeMoved || rssiOK || lastPersistedAt == nil)) else { return }

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
            heading: lastHeading?.trueHeading ?? lastHeading?.magneticHeading ?? indoorTracker.headingDegrees,
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
        lastPersistedRelative = (relativeX, relativeY)
        lastPersistedRssi = smooth
        heatmapDirty = true
    }

    private func rebuildPathAndHeatmap(force: Bool) {
        guard isActive else { return }
        if pathDirty || force {
            let snap = SearchPathReconstructor.snapshot(
                from: indoorTracker.path,
                previousViewport: followViewport ? pathSnapshot.viewport : nil,
                followSoftly: followViewport
            )
            pathSnapshot = snap
            // Pedometer-kalibrierte Distanz bevorzugen, Polyline als Untergrenze
            let meters = max(snap.pathLengthMeters, indoorTracker.traveledDistanceMeters)
            pathLengthText = String(format: "%.2f m", meters)
            pathDirty = false
            heatmapDirty = true
        }
        guard heatmapDirty || force, let s = session else { return }
        heatmap = HeatmapPlacementEngine.build(
            measurements: s.measurements,
            viewport: pathSnapshot.viewport,
            pathPolyline: pathSnapshot.smoothedPolyline
        )
        breadcrumbs = s.measurements.compactMap { m in
            guard let x = m.relativeX, let y = m.relativeY else { return nil }
            return BLEBreadcrumb(x: x, y: y, rssi: m.smoothedRssi)
        }
        searchGrid = BLESearchGrid.build(from: s.measurements, userArea: userSearchArea)
        mapOverlay = OutdoorMapTracker.model(
            origin: originLocation,
            path: pathSnapshot.points,
            smoothedPolyline: pathSnapshot.smoothedPolyline,
            measurements: s.measurements,
            lastGPS: lastLocation,
            previousRegion: followViewport ? mapOverlay.region : nil,
            softFollow: followViewport
        )
        heatmapDirty = false
    }

    private func recordEvent(
        type: BLESearchEventType,
        title: String,
        description: String? = nil,
        rssi: Double? = nil,
        minInterval: TimeInterval = 1.2
    ) {
        let event = BLESearchEvent(
            timestamp: Date(),
            type: type,
            title: title,
            description: description,
            rssi: rssi,
            latitude: lastLocation?.coordinate.latitude,
            longitude: lastLocation?.coordinate.longitude
        )
        var t = timeline
        if t.append(event, minInterval: minInterval) {
            timeline = t
            syncEventsToSession()
        }
    }

    private func syncEventsToSession() {
        guard var s = session else { return }
        s.events = timeline.events
        session = s
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
            if self.originLocation == nil, loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 40 {
                self.originLocation = loc
            }
            // Nur bei wirklich gutem Outdoor-GPS Karte vorschlagen (Indoor oft 10–25 m „ok“ aber unbrauchbar)
            if !self.userPickedSurfaceMode,
               !self.didAutoPickSurfaceMode,
               loc.horizontalAccuracy > 0,
               loc.horizontalAccuracy <= BLEPathConfig.gpsFusionMaxAccuracy {
                self.didAutoPickSurfaceMode = true
                self.applySurfaceMode(.map)
            }
            if let origin = self.originLocation,
               loc.horizontalAccuracy > 0,
               loc.horizontalAccuracy <= BLEPathConfig.gpsFusionMaxAccuracy {
                let (e, n) = ScooterFinderMath.enuDeltaMeters(
                    lat0: origin.coordinate.latitude,
                    lon0: origin.coordinate.longitude,
                    latA: origin.coordinate.latitude,
                    lonA: origin.coordinate.longitude,
                    latB: loc.coordinate.latitude,
                    lonB: loc.coordinate.longitude
                )
                self.indoorTracker.ingestGPSDelta(east: e, north: n, accuracy: loc.horizontalAccuracy)
                self.pathDirty = true
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.lastHeading = newHeading
            self.applyCompassHeading(newHeading)
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
