import Foundation
import SwiftUI

/// Globale App-Einstellungen — Darstellung, Auslesen-/Finden-Defaults, Über die App.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let textSizeKey = "app.settings.textSize.v1"
    private static let auslesenScootersOnlyKey = "app.settings.auslesen.scootersOnly.v1"
    private static let auslesenSortKey = "app.settings.auslesen.sort.v1"
    private static let auslesenHideNamelessKey = "app.settings.auslesen.hideNameless.v1"
    private static let findAudioKey = "app.settings.find.proximityAudio.v1"
    private static let findHapticsKey = "app.settings.find.proximityHaptics.v1"

    @Published var textSize: AppTextSize {
        didSet {
            UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey)
            Theme.textScale = textSize.scale
        }
    }

    /// Auslesen: Startfilter „nur vermutete E-Scooter“.
    @Published var auslesenShowOnlyScooters: Bool {
        didSet { UserDefaults.standard.set(auslesenShowOnlyScooters, forKey: Self.auslesenScootersOnlyKey) }
    }

    /// Auslesen: Standard-Sortierung der Geräteliste.
    @Published var auslesenListSort: BleDeviceListSort {
        didSet { UserDefaults.standard.set(auslesenListSort.rawValue, forKey: Self.auslesenSortKey) }
    }

    /// Auslesen (Alle BLE): namenlose Geräte standardmäßig ausblenden.
    @Published var auslesenHideNameless: Bool {
        didSet { UserDefaults.standard.set(auslesenHideNameless, forKey: Self.auslesenHideNamelessKey) }
    }

    /// Signal-Finder: Suchton standardmäßig aktiv.
    @Published var findProximityAudioDefault: Bool {
        didSet { UserDefaults.standard.set(findProximityAudioDefault, forKey: Self.findAudioKey) }
    }

    /// Signal-Finder: Haptik standardmäßig aktiv.
    @Published var findProximityHapticsDefault: Bool {
        didSet { UserDefaults.standard.set(findProximityHapticsDefault, forKey: Self.findHapticsKey) }
    }

    var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    private init() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: Self.textSizeKey),
           let stored = AppTextSize(rawValue: raw) {
            textSize = stored
        } else {
            textSize = .standard
        }
        Theme.textScale = textSize.scale

        if defaults.object(forKey: Self.auslesenScootersOnlyKey) != nil {
            auslesenShowOnlyScooters = defaults.bool(forKey: Self.auslesenScootersOnlyKey)
        } else {
            auslesenShowOnlyScooters = true
        }

        if let sortRaw = defaults.string(forKey: Self.auslesenSortKey),
           let sort = BleDeviceListSort(rawValue: sortRaw) {
            auslesenListSort = sort
        } else {
            auslesenListSort = .signal
        }

        auslesenHideNameless = defaults.bool(forKey: Self.auslesenHideNamelessKey)

        if defaults.object(forKey: Self.findAudioKey) != nil {
            findProximityAudioDefault = defaults.bool(forKey: Self.findAudioKey)
        } else {
            findProximityAudioDefault = false
        }

        if defaults.object(forKey: Self.findHapticsKey) != nil {
            findProximityHapticsDefault = defaults.bool(forKey: Self.findHapticsKey)
        } else {
            findProximityHapticsDefault = true
        }
    }
}

enum AppTextSize: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Kompakt"
        case .standard: return "Standard"
        case .large: return "Groß"
        case .extraLarge: return "Sehr groß"
        }
    }

    var subtitle: String {
        switch self {
        case .compact: return "Mehr Inhalt auf dem Screen"
        case .standard: return "Ausgewogene Lesbarkeit"
        case .large: return "Größere Schrift in der ganzen App"
        case .extraLarge: return "Maximale Lesbarkeit"
        }
    }

    /// Multiplikator für Theme-Schriftgrößen.
    var scale: CGFloat {
        switch self {
        case .compact: return 0.92
        case .standard: return 1.0
        case .large: return 1.12
        case .extraLarge: return 1.24
        }
    }
}
