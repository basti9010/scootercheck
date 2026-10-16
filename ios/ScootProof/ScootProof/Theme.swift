import SwiftUI
import UIKit

enum Theme {
    /// Mockup-Hintergrund ~#12171C
    static let bg = Color(red: 0.071, green: 0.090, blue: 0.110)
    /// Kartenfläche, leicht aufgehellt
    static let card = Color(red: 0.12, green: 0.145, blue: 0.175)
    /// Primär Mint ~#6BDBC2
    static let accent = Color(red: 0.42, green: 0.86, blue: 0.76)
    static let muted = Color.white.opacity(0.55)
    static let secondaryText = Color.white.opacity(0.62)
    static let line = Color.white.opacity(0.10)
    static let danger = Color(red: 0.95, green: 0.42, blue: 0.40) // Koralle
    static let warn = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let hintOrange = Color(red: 0.98, green: 0.55, blue: 0.22)

    static let pageTitle = Font.system(size: 30, weight: .bold)
    static let cardTitle = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let meta = Font.system(size: 13, weight: .regular)
    static let badgeFont = Font.system(size: 12, weight: .semibold)

    static func verdict(_ level: VerdictLevel) -> Color {
        switch level {
        case .stock: return accent
        case .auffaellig: return warn
        case .hinweise: return hintOrange
        case .eindeutig: return danger
        }
    }

    static func fact(_ status: FactStatus) -> Color {
        switch status {
        case .regelkonform: return accent
        case .abweichend: return warn
        case .erheblichAbweichend: return danger
        case .nichtFeststellbar: return muted
        }
    }

    /// Kurzes Badge-Label für die Prüfungsübersicht.
    static func verdictBadgeTitle(_ level: VerdictLevel) -> String {
        switch level {
        case .stock: return "Serienzustand"
        case .auffaellig: return "Auffällig"
        case .hinweise: return "Manipulationshinweis"
        case .eindeutig: return "Eindeutige Abweichung"
        }
    }

    /// UIKit-Farben für PDF / UIGraphics
    enum UI {
        static let bg = UIColor(red: 0.071, green: 0.090, blue: 0.110, alpha: 1)
        static let card = UIColor(red: 0.12, green: 0.145, blue: 0.175, alpha: 1)
        static let accent = UIColor(red: 0.42, green: 0.86, blue: 0.76, alpha: 1)
        static let muted = UIColor.white.withAlphaComponent(0.55)
        static let line = UIColor.white.withAlphaComponent(0.12)
        static let text = UIColor.white
        static let danger = UIColor(red: 0.95, green: 0.42, blue: 0.40, alpha: 1)
        static let warn = UIColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 1)

        static func verdict(_ level: VerdictLevel) -> UIColor {
            switch level {
            case .stock: return accent
            case .auffaellig: return warn
            case .hinweise: return UIColor(red: 0.98, green: 0.55, blue: 0.22, alpha: 1)
            case .eindeutig: return danger
            }
        }

        static func fact(_ status: FactStatus) -> UIColor {
            switch status {
            case .regelkonform: return accent
            case .abweichend: return warn
            case .erheblichAbweichend: return danger
            case .nichtFeststellbar: return muted
            }
        }
    }
}

extension View {
    func scootCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }

    func scootField() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
            .font(.body)
    }
}
