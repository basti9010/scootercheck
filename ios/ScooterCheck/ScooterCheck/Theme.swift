import SwiftUI
import UIKit

/// Zentrale Design-Tokens — Typografie, Farbe, Spacing, Radien.
enum Theme {
    // MARK: - Colors (bestehende Marke, weichere Textstufen)

    /// App-Hintergrund ~#12171C
    static let bg = Color(red: 0.071, green: 0.090, blue: 0.110)
    /// Surface / Card ~ leicht heller
    static let card = Color(red: 0.12, green: 0.145, blue: 0.175)
    static let surfaceSecondary = Color.white.opacity(0.06)
    /// Mint ~#6BDBC2
    static let accent = Color(red: 0.42, green: 0.86, blue: 0.76)

    /// Primär ~#F5F6F7
    static let textPrimary = Color(red: 0.961, green: 0.965, blue: 0.969)
    /// Card-/Listentitel ~#F0F2F3
    static let textTitle = Color(red: 0.941, green: 0.949, blue: 0.953)
    /// Fließtext ~#C9CED1
    static let textBody = Color(red: 0.788, green: 0.808, blue: 0.820)
    /// Sekundär ~#8F969C
    static let textSecondary = Color(red: 0.561, green: 0.588, blue: 0.612)
    /// Deaktiviert / Meta
    static let textMuted = Color(red: 0.561, green: 0.588, blue: 0.612).opacity(0.85)

    static let line = Color.white.opacity(0.10)
    static let border = line
    static let danger = Color(red: 0.95, green: 0.42, blue: 0.40)
    static let warn = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let hintOrange = Color(red: 0.98, green: 0.55, blue: 0.22)

    // Aliase für bestehende Call-Sites
    static let muted = textMuted
    static let secondaryText = textSecondary

    // MARK: - Typography (System / Dynamic Type–freundlich)

    /// App-Header Wordmark ~22–24 Semibold
    static let brandWordmark = Font.system(size: 23, weight: .semibold)
    /// Seitentitel im Content ~22–24 Semibold
    static let pageTitle = Font.system(size: 23, weight: .semibold)
    /// Abschnittsüberschrift ~18–20 Semibold
    static let sectionTitle = Font.system(size: 19, weight: .semibold)
    /// Card-/Listenüberschrift ~17–18 Medium
    static let cardTitle = Font.system(size: 17, weight: .medium)
    /// Fließtext ~15–16 Regular
    static let body = Font.system(size: 15.5, weight: .regular)
    /// Sekundärtext ~14–15 Regular
    static let secondary = Font.system(size: 14.5, weight: .regular)
    /// Meta / Caption ~13–14 Regular
    static let caption = Font.system(size: 13.5, weight: .regular)
    /// Meta klein (Badge, Copyright)
    static let meta = Font.system(size: 13, weight: .regular)
    static let badgeFont = Font.system(size: 12, weight: .semibold)
    /// Primär-Button ~17–18 Semibold
    static let button = Font.system(size: 17, weight: .semibold)
    /// Sekundär-/Textbutton ~16–17 Medium
    static let buttonSecondary = Font.system(size: 16.5, weight: .medium)
    /// Segment ~15–16 Medium
    static let segment = Font.system(size: 15.5, weight: .medium)
    /// Form-Label
    static let fieldLabel = Font.system(size: 14.5, weight: .medium)
    /// Form-Wert
    static let fieldValue = Font.system(size: 16.5, weight: .regular)

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let section: CGFloat = 32
        static let hero: CGFloat = 40
    }

    // MARK: - Radius

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 22
        static let button: CGFloat = 26
        static let pill: CGFloat = 999
    }

    // MARK: - Motion

    enum Motion {
        static let drawer = Animation.easeInOut(duration: 0.30)
        static let standard = Animation.easeInOut(duration: 0.22)
    }

    /// Gemeinsames App-Chrome (Header / Side-Drawer).
    enum Chrome {
        /// Feste Headerhöhe unterhalb der oberen Safe Area (Logo vertikal mittig darin).
        static let headerHeight: CGFloat = 68
        /// Side-Menü ~76 % der Bildschirmbreite; Wordmark zentriert relativ dazu.
        static let drawerWidthFraction: CGFloat = 0.76

        static func drawerPanelWidth(screenWidth: CGFloat) -> CGFloat {
            max(0, screenWidth * drawerWidthFraction)
        }

        /// Y-Mitte der Wordmark relativ zum Header-Band (nicht zur Statusleiste).
        static var brandCenterYInHeader: CGFloat { headerHeight * 0.5 }

        /// Absolute Y nur wenn ein Full-Screen-Overlay nötig ist.
        static func brandCenterY(safeAreaTop: CGFloat) -> CGFloat {
            resolvedSafeAreaTop(safeAreaTop) + brandCenterYInHeader
        }

        /// GeometryReader in Full-Screen-Overlays meldet oft `safeAreaInsets.top == 0`.
        static func resolvedSafeAreaTop(_ reported: CGFloat) -> CGFloat {
            if reported > 1 { return reported }
            return keyWindowSafeAreaTop
        }

        static var keyWindowSafeAreaTop: CGFloat {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
                ?? scenes.first?.windows.first
            let top = window?.safeAreaInsets.top ?? 0
            // Dynamic Island / Notch typisch ≥ 47; Fallback verhindert Statusleisten-Kollision.
            return top > 1 ? top : 59
        }
    }

    // MARK: - Verdict / Fact

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
        case .nichtFeststellbar: return textMuted
        }
    }

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
        static let muted = UIColor(red: 0.561, green: 0.588, blue: 0.612, alpha: 0.85)
        static let line = UIColor.white.withAlphaComponent(0.12)
        static let text = UIColor(red: 0.961, green: 0.965, blue: 0.969, alpha: 1)
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

// MARK: - Shared chrome

struct PageTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.pageTitle)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Sortieren (Signal/Name) + optional namenlose BLE-Geräte ausblenden.
struct BleDeviceListSortFilterBar: View {
    @Binding var sort: BleDeviceListSort
    @Binding var hideNameless: Bool
    var showsHideNameless: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                Text("Sortieren")
                    .font(Theme.caption.weight(.medium))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 64, alignment: .leading)
                Picker("Sortieren", selection: $sort) {
                    ForEach(BleDeviceListSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .font(Theme.segment)
            }

            if showsHideNameless {
                Toggle(isOn: $hideNameless) {
                    Text("Geräte ohne Namen ausblenden")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .tint(Theme.accent)
                .accessibilityHint("Blendet sonstige BLE-Geräte ohne Advertisement-Namen aus.")
            }
        }
        .padding(.vertical, 2)
    }
}

/// Einheitliche Unterseiten-Navigation (Zurück + Titel + optional Untertitel).
/// Nur die Titelzeile sitzt neben dem Pfeil — übrige Seiteninhalte behalten normale Ränder.
struct FindSubpageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = Theme.textSecondary
    var titleFont: Font = Theme.pageTitle
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        subtitleColor: Color = Theme.textSecondary,
        titleFont: Font = Theme.pageTitle,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.titleFont = titleFont
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.body)
                        .foregroundStyle(subtitleColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    func scootCard() -> some View {
        self
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    func scootField() -> some View {
        self
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 10)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .foregroundStyle(Theme.textPrimary)
            .font(Theme.fieldValue)
    }
}
