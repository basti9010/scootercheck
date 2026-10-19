import Foundation
import SwiftUI

/// Globale App-Einstellungen (Darstellung) — unabhängig von Feature-Sheets.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let textSizeKey = "app.settings.textSize.v1"

    @Published var textSize: AppTextSize {
        didSet {
            UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey)
            Theme.textScale = textSize.scale
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.textSizeKey),
           let stored = AppTextSize(rawValue: raw) {
            textSize = stored
        } else {
            textSize = .standard
        }
        Theme.textScale = textSize.scale
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
