import Foundation
import ARKit
import AVFoundation
import SceneKit

/// Zustand der kamera-gestützten Indoor-Bewegung (ARKit World Tracking).
enum IndoorVisualTrackingState: String, Sendable {
    case off
    case requestingPermission
    case starting
    case tracking
    case limited
    case unavailable

    var label: String {
        switch self {
        case .off: return "Kamera aus"
        case .requestingPermission: return "Kamera-Freigabe…"
        case .starting: return "Kamera-Tracking startet…"
        case .tracking: return "Kamera-Tracking aktiv"
        case .limited: return "Kamera eingeschränkt — weiterlaufen"
        case .unavailable: return "Kamera-Tracking nicht verfügbar"
        }
    }

    /// Grünes Kamerasymbol nur bei stabilem Tracking.
    var isHealthy: Bool { self == .tracking }
}

/// ARKit World Tracking → relative Meter auf der Bodenebene (East/North).
/// Eine gemeinsame `ARSession` für Pose-Tracking und AR Signal-Finder (kein zweiter Scanner).
@MainActor
final class IndoorVisualTracker: NSObject, ObservableObject {
    @Published private(set) var state: IndoorVisualTrackingState = .off
    @Published private(set) var statusText: String = IndoorVisualTrackingState.off.label
    /// Steigt bei Tracking-Reset / Neustart — AR-Samples verschiedener Epochen nicht mischen.
    @Published private(set) var sessionEpoch: Int = 0
    /// Geschätzte Bodenhöhe in AR-Weltkoordinaten (Y), sobald eine horizontale Fläche erkannt wurde.
    @Published private(set) var floorWorldY: Float?

    private(set) var session: ARSession?
    private var origin: SIMD3<Float>?
    private var lastPose: (east: Double, north: Double)?
    private(set) var east: Double = 0
    private(set) var north: Double = 0
    private(set) var headingDegrees: Double?
    private(set) var traveledMeters: Double = 0
    private(set) var lastCameraTransform: simd_float4x4?
    /// AR-Ansicht an die bestehende Session binden (eine Session für alles).
    private weak var boundSceneView: ARSCNView?
    private var wantsPlaneDetection = false

    /// Wird bei jeder brauchbaren Pose aufgerufen (East, North, Heading°).
    var onPoseUpdate: ((Double, Double, Double?) -> Void)?

    var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    func start() {
        guard isSupported else {
            state = .unavailable
            statusText = state.label
            return
        }
        stopSessionOnly()
        state = .requestingPermission
        statusText = state.label

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginSession(resetTracking: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.beginSession(resetTracking: true)
                    } else {
                        self.state = .unavailable
                        self.statusText = "Kamera-Zugriff abgelehnt"
                    }
                }
            }
        case .denied, .restricted:
            state = .unavailable
            statusText = "Kamera-Zugriff fehlt — in Einstellungen erlauben"
        @unknown default:
            state = .unavailable
            statusText = state.label
        }
    }

    func stop() {
        stopSessionOnly()
        origin = nil
        lastPose = nil
        east = 0
        north = 0
        headingDegrees = nil
        traveledMeters = 0
        lastCameraTransform = nil
        floorWorldY = nil
        wantsPlaneDetection = false
        boundSceneView = nil
        sessionEpoch = 0
        state = .off
        statusText = state.label
        onPoseUpdate = nil
    }

    /// ARSCNView an die laufende Session anbinden (ohne neuen Bluetooth-/AR-Scan).
    func bindSceneView(_ view: ARSCNView?) {
        boundSceneView = view
        if let session, let view {
            view.session = session
        }
    }

    /// Bodenerkennung nur im AR-Modus — Pose-Tracking bleibt unverändert.
    func setPlaneDetectionEnabled(_ enabled: Bool) {
        wantsPlaneDetection = enabled
        guard session != nil, state != .off, state != .unavailable else { return }
        beginSession(resetTracking: false)
    }

    /// Manuelles Neuausrichten des lokalen Koordinatensystems.
    func realignTracking() {
        guard state != .off, state != .unavailable else {
            start()
            return
        }
        sessionEpoch += 1
        origin = nil
        lastPose = nil
        traveledMeters = 0
        floorWorldY = nil
        beginSession(resetTracking: true)
    }

    /// ENU (East/North) → ARKit Weltposition auf der Bodenebene.
    func worldPosition(east: Double, north: Double) -> SIMD3<Float>? {
        guard let origin else { return nil }
        let y = floorWorldY ?? (origin.y - 1.35)
        return SIMD3<Float>(
            origin.x + Float(east),
            y,
            origin.z - Float(north)
        )
    }

    private func stopSessionOnly() {
        session?.pause()
        session?.delegate = nil
        session = nil
        boundSceneView?.session.pause()
    }

    private func beginSession(resetTracking: Bool) {
        let session = self.session ?? ARSession()
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = wantsPlaneDetection ? [.horizontal] : []
        config.environmentTexturing = .none
        var options: ARSession.RunOptions = []
        if resetTracking {
            options.insert(.resetTracking)
            options.insert(.removeExistingAnchors)
            sessionEpoch += origin == nil && self.session == nil ? 0 : 1
            origin = nil
            lastPose = nil
            traveledMeters = 0
            floorWorldY = nil
        }
        session.run(config, options: options)
        self.session = session
        if let view = boundSceneView {
            view.session = session
        }
        if state == .off || state == .requestingPermission || resetTracking {
            state = .starting
            statusText = state.label
        }
    }

    private func ingest(frame: ARFrame) {
        let t = frame.camera.transform
        lastCameraTransform = t
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        if origin == nil {
            origin = pos
        }
        guard let origin else { return }

        // Bodenebene: X = Ost, -Z = Nord (ARKit Y nach oben, gravityAndHeading)
        let east = Double(pos.x - origin.x)
        let north = Double(-(pos.z - origin.z))

        let forwardEast = Double(-t.columns.2.x)
        let forwardNorth = Double(t.columns.2.z)
        var heading = atan2(forwardEast, forwardNorth) * 180 / .pi
        if heading < 0 { heading += 360 }

        if let last = lastPose {
            let step = hypot(east - last.east, north - last.north)
            if step >= 0.04 {
                traveledMeters += step
                lastPose = (east, north)
            }
        } else {
            lastPose = (east, north)
        }

        self.east = east
        self.north = north
        self.headingDegrees = heading

        switch frame.camera.trackingState {
        case .normal:
            state = .tracking
            statusText = state.label
            onPoseUpdate?(east, north, heading)
        case .limited(let reason):
            state = .limited
            statusText = limitedLabel(reason)
            // Eingeschränkt: Pose für UI weitergeben, Engine speichert keine neuen AR-Punkte wenn ungesund
            onPoseUpdate?(east, north, heading)
        case .notAvailable:
            state = .limited
            statusText = "Kamera-Tracking kurz nicht verfügbar"
        @unknown default:
            break
        }
    }

    private func limitedLabel(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: return "Kamera initialisiert…"
        case .excessiveMotion: return "Zu schnelle Bewegung — langsamer"
        case .insufficientFeatures: return "Zu dunkel oder zu wenig Struktur"
        case .relocalizing: return "Kamera sucht Position…"
        @unknown default: return IndoorVisualTrackingState.limited.label
        }
    }
}

extension IndoorVisualTracker: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.ingest(frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            self.ingestFloor(from: anchors)
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            self.ingestFloor(from: anchors)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .unavailable
            self.statusText = "Kamera-Tracking fehlgeschlagen"
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.state = .limited
            self.statusText = "Kamera unterbrochen"
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.statusText = "Kamera fortgesetzt…"
        }
    }

    @MainActor
    private func ingestFloor(from anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { continue }
            let y = plane.transform.columns.3.y
            if let existing = floorWorldY {
                floorWorldY = existing * 0.85 + y * 0.15
            } else {
                floorWorldY = y
            }
        }
    }
}
