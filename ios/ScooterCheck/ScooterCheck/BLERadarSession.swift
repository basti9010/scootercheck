import Foundation
import UIKit
import Combine

// MARK: - Scan / session state (honest about iOS limits)

enum BLERadarScanState: String, Equatable, Sendable {
    case radarActive
    case bleScanActive
    case backgroundScanLimited
    case restoring
    case bluetoothOff
    case radarPaused
    case radarEnded

    var label: String {
        switch self {
        case .radarActive: return "Radar aktiviert"
        case .bleScanActive: return "BLE-Scan aktiv"
        case .backgroundScanLimited: return "Hintergrundscan eingeschränkt"
        case .restoring: return "Wiederherstellung läuft"
        case .bluetoothOff: return "Bluetooth deaktiviert"
        case .radarPaused: return "Radar pausiert"
        case .radarEnded: return "Radar beendet"
        }
    }

    var detail: String {
        switch self {
        case .radarActive:
            return "Session angefordert — tatsächlicher Scan kann eingeschränkt sein."
        case .bleScanActive:
            return "CoreBluetooth meldet aktive Peripheral-Suche."
        case .backgroundScanLimited:
            return "Im Hintergrund sucht iOS typischerweise nur nach bekannten Service-UUIDs. Eine uneingeschränkte Suche aller BLE-Geräte ist nicht gewährleistet."
        case .restoring:
            return "State Restoration / erneuter Scan-Start."
        case .bluetoothOff:
            return "Kein Scan möglich, bis Bluetooth wieder verfügbar ist."
        case .radarPaused:
            return "Radar pausiert — keine Alarme."
        case .radarEnded:
            return "Keine aktive Radar-Session."
        }
    }
}

enum BLERadarDisplayMode: String, Codable, CaseIterable, Sendable {
    /// iOS darf den Bildschirm sperren; Session bleibt logisch aktiv.
    case allowSleep
    /// Idle-Timer während Vordergrund-Radar deaktivieren.
    case keepAwake

    var label: String {
        switch self {
        case .allowSleep: return "Display darf ausgehen"
        case .keepAwake: return "Display während der Suche eingeschaltet lassen"
        }
    }
}

enum BLERadarNotifyCooldown: Int, Codable, CaseIterable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var label: String {
        switch self {
        case .oneMinute: return "1 Minute"
        case .fiveMinutes: return "5 Minuten"
        case .fifteenMinutes: return "15 Minuten"
        case .thirtyMinutes: return "30 Minuten"
        }
    }
}

struct BLERadarUserSettings: Codable, Equatable, Sendable {
    var displayMode: BLERadarDisplayMode
    var notifyScooterDetections: Bool
    var highlightApprovalWarnings: Bool
    var soundEnabled: Bool
    var hapticsEnabled: Bool
    /// Minimum signal for alarm (medium / strong / veryStrong).
    var minimumSignalClass: String
    var notifyCooldownSeconds: Int

    static let `default` = BLERadarUserSettings(
        displayMode: .allowSleep,
        notifyScooterDetections: true,
        highlightApprovalWarnings: true,
        soundEnabled: true,
        hapticsEnabled: true,
        minimumSignalClass: BLESignalClass.medium.rawValue,
        notifyCooldownSeconds: BLERadarNotifyCooldown.fiveMinutes.rawValue
    )

    private static let key = "bleRadar.userSettings.v1"

    static func load() -> BLERadarUserSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(BLERadarUserSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var minimumSignal: BLESignalClass {
        BLESignalClass(rawValue: minimumSignalClass) ?? .medium
    }
}

/// Persistierte Radar-Session über Navigation / Display-Sperre hinweg.
@MainActor
final class BLERadarSessionStore: ObservableObject {
    static let shared = BLERadarSessionStore()

    @Published private(set) var sessionRequested = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastSightingAt: Date?
    @Published private(set) var lastSightingSummary: String?
    @Published var settings: BLERadarUserSettings {
        didSet {
            settings.save()
            applyDisplayMode()
        }
    }

    private let sessionKey = "bleRadar.session.v1"

    private struct Persisted: Codable {
        var sessionRequested: Bool
        var startedAt: Date?
        var lastSightingAt: Date?
        var lastSightingSummary: String?
    }

    private init() {
        settings = BLERadarUserSettings.load()
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            sessionRequested = p.sessionRequested
            startedAt = p.startedAt
            lastSightingAt = p.lastSightingAt
            lastSightingSummary = p.lastSightingSummary
        }
    }

    func beginSession() {
        sessionRequested = true
        startedAt = Date()
        persist()
        applyDisplayMode()
    }

    func endSession() {
        sessionRequested = false
        startedAt = nil
        persist()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func recordSighting(summary: String, at date: Date = Date()) {
        lastSightingAt = date
        lastSightingSummary = summary
        persist()
    }

    func applyDisplayMode() {
        guard sessionRequested else {
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        // Nur im Vordergrund Keep-Awake setzen; manuelle Sperre wird nie verhindert.
        let active = UIApplication.shared.applicationState == .active
        UIApplication.shared.isIdleTimerDisabled =
            settings.displayMode == .keepAwake && active
    }

    private func persist() {
        let p = Persisted(
            sessionRequested: sessionRequested,
            startedAt: startedAt,
            lastSightingAt: lastSightingAt,
            lastSightingSummary: lastSightingSummary
        )
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }
}
