import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(red: 0.07, green: 0.09, blue: 0.11)
    static let card = Color(red: 0.11, green: 0.13, blue: 0.16)
    static let accent = Color(red: 0.42, green: 0.86, blue: 0.76) // #6BDBC2
    static let muted = Color.white.opacity(0.55)
    static let line = Color.white.opacity(0.08)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.35)
    static let warn = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)

    static func verdict(_ level: VerdictLevel) -> Color {
        switch level {
        case .stock: return accent
        case .auffaellig: return warn
        case .hinweise: return Color(red: 0.98, green: 0.55, blue: 0.22)
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

    /// UIKit-Farben für PDF / UIGraphics
    enum UI {
        static let bg = UIColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 1)
        static let card = UIColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1)
        static let accent = UIColor(red: 0.42, green: 0.86, blue: 0.76, alpha: 1)
        static let muted = UIColor.white.withAlphaComponent(0.55)
        static let line = UIColor.white.withAlphaComponent(0.12)
        static let text = UIColor.white
        static let danger = UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1)
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
