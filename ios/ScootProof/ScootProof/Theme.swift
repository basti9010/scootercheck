import SwiftUI

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
        case .watch: return warn
        case .tuned: return danger
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
