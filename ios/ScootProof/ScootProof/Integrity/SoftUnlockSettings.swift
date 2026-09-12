import Foundation
import Combine

/// Konfigurierbare Soft-Unlock-Geste (Bremshebel, Tasten, …) — modellübergreifend.
enum SoftUnlockControl: String, CaseIterable, Identifiable, Codable, Sendable {
    case leftBrake
    case rightBrake
    case bothBrakes
    case powerButton
    case modeButton
    case throttle
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftBrake: return "Linker Bremshebel"
        case .rightBrake: return "Rechter Bremshebel"
        case .bothBrakes: return "Beide Bremshebel"
        case .powerButton: return "Power-Taste"
        case .modeButton: return "Mode-Taste"
        case .throttle: return "Gashebel"
        case .custom: return "Eigene Beschreibung"
        }
    }
}

@MainActor
final class SoftUnlockSettings: ObservableObject {
    static let shared = SoftUnlockSettings()

    private enum Keys {
        static let enabled = "soft_unlock_enabled"
        static let control = "soft_unlock_control"
        static let repetitions = "soft_unlock_repetitions"
        static let customLabel = "soft_unlock_custom_label"
        static let threshold = "soft_unlock_speed_threshold_kmh"
    }

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var control: SoftUnlockControl {
        didSet { UserDefaults.standard.set(control.rawValue, forKey: Keys.control) }
    }

    /// Wie oft die Bedienung wiederholt wird (z. B. 6× Hebel öffnen).
    @Published var repetitions: Int {
        didSet {
            let clamped = min(20, max(1, repetitions))
            if clamped != repetitions {
                repetitions = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.repetitions)
        }
    }

    @Published var customLabel: String {
        didSet { UserDefaults.standard.set(customLabel, forKey: Keys.customLabel) }
    }

    /// Ab diesem Limit (km/h) gilt Soft-Unlock als aktiv (Wirkung der Geste).
    @Published var speedThresholdKmh: Double {
        didSet { UserDefaults.standard.set(speedThresholdKmh, forKey: Keys.threshold) }
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.enabled) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: Keys.enabled)
        }
        if let raw = defaults.string(forKey: Keys.control),
           let kind = SoftUnlockControl(rawValue: raw) {
            control = kind
        } else {
            control = .leftBrake
        }
        let reps = defaults.object(forKey: Keys.repetitions) as? Int ?? 6
        repetitions = min(20, max(1, reps))
        customLabel = defaults.string(forKey: Keys.customLabel) ?? ""
        let thr = defaults.object(forKey: Keys.threshold) as? Double ?? 25
        speedThresholdKmh = thr
    }

    /// Kurzbeschreibung für UI und Protokoll, z. B. „Linker Bremshebel 6×“.
    var gestureSummary: String {
        if control == .custom {
            let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Individuelle Unlock-Geste" : trimmed
        }
        return "\(control.title) \(repetitions)×"
    }

    /// Ermittelte / konfigurierte Geheimkombination (Anzeige in UI und Protokoll).
    var unlockCodeSummary: String { gestureSummary }

    /// Textbaustein für Bewertungen / Erläuterungen.
    var detectionHint: String {
        guard isEnabled else {
            return "Soft-Unlock-Erkennung ist ausgeschaltet."
        }
        return """
        Keine eingebauten Geheimkombinationen. Der Nutzer sucht die Kombination selbst \
        (z. B. „\(unlockCodeSummary)“), trägt sie hier ein, gibt sie am Scooter ein und liest erneut aus. \
        Erfolgreiche Kombinationen werden pro Seriennummer gespeichert und später wieder geladen. \
        Erkannt wird die Wirkung (Limit/Peak ≥ \(Int(speedThresholdKmh.rounded())) km/h).
        """
    }

    nonisolated static func unlockCodeSnapshot() -> String {
        gestureSummarySnapshot()
    }

    nonisolated static func thresholdKmhSnapshot() -> Double {
        let defaults = UserDefaults.standard
        if let thr = defaults.object(forKey: "soft_unlock_speed_threshold_kmh") as? Double { return thr }
        return 25
    }

    nonisolated static func isEnabledSnapshot() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "soft_unlock_enabled") == nil { return true }
        return defaults.bool(forKey: "soft_unlock_enabled")
    }

    nonisolated static func gestureSummarySnapshot() -> String {
        let defaults = UserDefaults.standard
        let controlRaw = defaults.string(forKey: "soft_unlock_control") ?? SoftUnlockControl.leftBrake.rawValue
        let control = SoftUnlockControl(rawValue: controlRaw) ?? .leftBrake
        if control == .custom {
            let label = defaults.string(forKey: "soft_unlock_custom_label")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return label.isEmpty ? "Individuelle Unlock-Geste" : label
        }
        let reps = defaults.object(forKey: "soft_unlock_repetitions") as? Int ?? 6
        return "\(control.title) \(min(20, max(1, reps)))×"
    }
}
