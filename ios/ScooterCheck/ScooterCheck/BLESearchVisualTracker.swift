import Foundation
import ARKit
import AVFoundation
import SceneKit
import SwiftUI
import UIKit

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
}

/// ARKit World Tracking → relative Meter auf der Bodenebene (East/North).
/// Das ist der gleiche Ansatz wie bei vielen WLAN-/Indoor-Analyzer-Apps.
@MainActor
final class IndoorVisualTracker: NSObject, ObservableObject {
    @Published private(set) var state: IndoorVisualTrackingState = .off
    @Published private(set) var statusText: String = IndoorVisualTrackingState.off.label

    private var session: ARSession?
    private var origin: SIMD3<Float>?
    private var lastPose: (east: Double, north: Double)?
    private(set) var east: Double = 0
    private(set) var north: Double = 0
    private(set) var headingDegrees: Double?
    private(set) var traveledMeters: Double = 0

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
            beginSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.beginSession()
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
        state = .off
        statusText = state.label
        onPoseUpdate = nil
    }

    /// Für Preview — dieselbe Session wie das Tracking.
    func attachPreview(_ view: ARSCNView) {
        guard let session else { return }
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
    }

    private func stopSessionOnly() {
        session?.pause()
        session?.delegate = nil
        session = nil
    }

    private func beginSession() {
        let session = ARSession()
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // Gravity+Heading: AR-Welt grob nach Norden ausgerichtet → passt zu ENU/Karte
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = []
        config.environmentTexturing = .none
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        self.session = session
        origin = nil
        lastPose = nil
        traveledMeters = 0
        state = .starting
        statusText = state.label
    }

    private func ingest(frame: ARFrame) {
        let t = frame.camera.transform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        if origin == nil {
            origin = pos
        }
        guard let origin else { return }

        // Bodenebene: X = Ost, -Z = Nord (ARKit Y nach oben, gravityAndHeading)
        let east = Double(pos.x - origin.x)
        let north = Double(-(pos.z - origin.z))

        // Kamera schaut lokal entlang -Z; World-Forward = -columns.2
        // north = -worldZ ⇒ forwardNorth = -forwardWorldZ = columns.2.z
        let forwardEast = Double(-t.columns.2.x)
        let forwardNorth = Double(t.columns.2.z)
        var heading = atan2(forwardEast, forwardNorth) * 180 / .pi
        if heading < 0 { heading += 360 }

        if let last = lastPose {
            let step = hypot(east - last.east, north - last.north)
            // Nur echte Bewegung zählen (AR-Rauschen filtern)
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
            // Eingeschränkt weiter nutzen — besser als nichts, PDR bleibt Fallback
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
        case .insufficientFeatures: return "Mehr Struktur filmen (Wände/Möbel)"
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
            // Session läuft weiter; Tracking-State kommt über Frames
            self.statusText = "Kamera fortgesetzt…"
        }
    }
}

// MARK: - Compact camera preview

struct BLESearchCameraPreview: UIViewRepresentable {
    @ObservedObject var tracker: IndoorVisualTracker

    @MainActor
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.backgroundColor = .black
        view.scene = SCNScene()
        view.autoenablesDefaultLighting = false
        view.automaticallyUpdatesLighting = false
        tracker.attachPreview(view)
        return view
    }

    @MainActor
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        tracker.attachPreview(uiView)
    }
}
