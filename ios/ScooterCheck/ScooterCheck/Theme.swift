import SwiftUI
import UIKit

/// Zentrale Design-Tokens — Typografie, Farbe, Spacing, Radien (filigranes Proportionssystem).
enum Theme {
    // MARK: - Colors (Marke)

    /// App-Hintergrund ~#12171C
    static let bg = Color(red: 0.071, green: 0.090, blue: 0.110)
    /// Surface / Card — etwas flacher als zuvor
    static let card = Color(red: 0.115, green: 0.138, blue: 0.165)
    static let surfaceSecondary = Color.white.opacity(0.055)
    /// Mint ~#6BDBC2
    static let accent = Color(red: 0.42, green: 0.86, blue: 0.76)

    static let textPrimary = Color(red: 0.961, green: 0.965, blue: 0.969)
    static let textTitle = Color(red: 0.941, green: 0.949, blue: 0.953)
    static let textBody = Color(red: 0.788, green: 0.808, blue: 0.820)
    static let textSecondary = Color(red: 0.561, green: 0.588, blue: 0.612)
    static let textMuted = Color(red: 0.561, green: 0.588, blue: 0.612).opacity(0.85)

    static let line = Color.white.opacity(0.09)
    static let border = line
    static let danger = Color(red: 0.95, green: 0.42, blue: 0.40)
    static let warn = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let hintOrange = Color(red: 0.98, green: 0.55, blue: 0.22)

    static let muted = textMuted
    static let secondaryText = textSecondary

    // MARK: - Typography (ruhiger, weniger dominant)

    /// App-Header Wordmark — Marke
    static let brandWordmark = Font.system(size: 22, weight: .semibold)
    /// Seitenüberschrift — klar, nicht übergroß
    static let pageTitle = Font.system(size: 21, weight: .semibold)
    /// Abschnittsüberschrift
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    /// Kartentitel
    static let cardTitle = Font.system(size: 15, weight: .medium)
    /// Fließtext
    static let body = Font.system(size: 14.5, weight: .regular)
    /// Beschreibung
    static let secondary = Font.system(size: 13, weight: .regular)
    /// Caption
    static let caption = Font.system(size: 12.5, weight: .regular)
    /// Meta / Badge / Copyright
    static let meta = Font.system(size: 11.5, weight: .regular)
    static let badgeFont = Font.system(size: 11, weight: .semibold)
    /// Primär-Button
    static let button = Font.system(size: 15, weight: .semibold)
    /// Sekundär-Button
    static let buttonSecondary = Font.system(size: 14, weight: .medium)
    /// Segment
    static let segment = Font.system(size: 13, weight: .medium)
    static let fieldLabel = Font.system(size: 12.5, weight: .medium)
    static let fieldValue = Font.system(size: 14.5, weight: .regular)

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        /// Karten-Innenabstand (filigraner)
        static let lg: CGFloat = 12
        /// Horizontaler Seitenabstand
        static let xl: CGFloat = 18
        /// Abstand zwischen Abschnitten
        static let xxl: CGFloat = 18
        static let section: CGFloat = 18
        static let hero: CGFloat = 24
        static let page: CGFloat = xl
        static let cardPadding: CGFloat = lg
        static let listGap: CGFloat = 8
        /// Abstand Titel → Inhalt
        static let titleToContent: CGFloat = 10
        /// Abstand Titel ↔ Untertitel
        static let titleStack: CGFloat = 2
    }

    // MARK: - Radius

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 12
        static let large: CGFloat = 14
        static let button: CGFloat = 12
        static let pill: CGFloat = 999
    }

    // MARK: - Icons / Controls

    enum Icon {
        static let compact: CGFloat = 16
        static let standard: CGFloat = 18
        static let nav: CGFloat = 18
        static let function: CGFloat = 20
    }

    enum Control {
        /// Primärbutton — kompakt, aber ≥ 44 pt Touch
        static let buttonMinHeight: CGFloat = 44
        static let secondaryMinHeight: CGFloat = 40
        static let backHit: CGFloat = 44
        static let hairline: CGFloat = 0.33
        static let segmentControlSize: ControlSize = .small
    }

    // MARK: - Motion

    enum Motion {
        static let drawer = Animation.easeInOut(duration: 0.30)
        static let standard = Animation.easeInOut(duration: 0.22)
        static let page = Animation.easeInOut(duration: 0.28)
        static let rootCrossfade = Animation.easeInOut(duration: 0.22)
        static let reduced = Animation.easeInOut(duration: 0.01)
    }

    enum Chrome {
        static let headerHeight: CGFloat = 58
        static let drawerWidthFraction: CGFloat = 0.76

        static func drawerPanelWidth(screenWidth: CGFloat) -> CGFloat {
            max(0, screenWidth * drawerWidthFraction)
        }

        static var brandCenterYInHeader: CGFloat { headerHeight * 0.5 }

        static func brandCenterY(safeAreaTop: CGFloat) -> CGFloat {
            resolvedSafeAreaTop(safeAreaTop) + brandCenterYInHeader
        }

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

    enum UI {
        static let bg = UIColor(red: 0.071, green: 0.090, blue: 0.110, alpha: 1)
        static let card = UIColor(red: 0.115, green: 0.138, blue: 0.165, alpha: 1)
        static let accent = UIColor(red: 0.42, green: 0.86, blue: 0.76, alpha: 1)
        static let muted = UIColor(red: 0.561, green: 0.588, blue: 0.612, alpha: 0.85)
        static let line = UIColor.white.withAlphaComponent(0.10)
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

/// Kompakte Sortier-/Filter-Aktionen (Menu statt großer Segment-Leiste).
struct BleDeviceListSortFilterBar: View {
    @Binding var sort: BleDeviceListSort
    @Binding var hideNameless: Bool
    var showsHideNameless: Bool

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Menu {
                Picker("Sortieren", selection: $sort) {
                    ForEach(BleDeviceListSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                if showsHideNameless {
                    Toggle("Ohne Namen ausblenden", isOn: $hideNameless)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: Theme.Icon.compact, weight: .medium))
                    Text(sort == .signal ? "Signal" : "Name")
                        .font(Theme.meta.weight(.medium))
                    if showsHideNameless, hideNameless {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.surfaceSecondary)
                .clipShape(Capsule())
            }
            .accessibilityLabel("Sortieren und filtern")

            Spacer(minLength: 0)
        }
    }
}

/// Einheitliche Unterseiten-Navigation (Zurück + Titel + optional Untertitel).
struct FindSubpageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = Theme.textSecondary
    /// Default: sectionTitle — weniger dominant als früher pageTitle.
    var titleFont: Font = Theme.sectionTitle
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        subtitleColor: Color = Theme.textSecondary,
        titleFont: Font = Theme.sectionTitle,
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
                        .font(.system(size: Theme.Icon.nav, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.Control.backHit, height: Theme.Control.backHit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück")
            }

            VStack(alignment: .leading, spacing: Theme.Space.titleStack) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.meta)
                        .foregroundStyle(subtitleColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, onBack == nil ? 0 : 11)

            trailing()
        }
    }
}

/// Einheitliche Funktionskarte (Icon · Titel · Beschreibung · Chevron).
struct ScootFunctionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Theme.Space.md) {
                Image(systemName: systemImage)
                    .font(.system(size: Theme.Icon.function, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: Theme.Icon.function + 2, height: Theme.Icon.function + 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Space.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Kompakter Leerzustand — strukturiert, nicht massiv.
struct ScootEmptyStateCard: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var actionSystemImage: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                ScootSecondaryButton(
                    title: actionTitle,
                    systemImage: actionSystemImage,
                    showsChevron: false,
                    action: action
                )
                .padding(.top, 2)
            }
        }
        .scootCard()
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: Theme.Icon.compact, weight: .semibold))
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
    /// Standard-Kartenfläche — flach, weniger Innenabstand.
    func scootCard() -> some View {
        self
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )
    }

    func scootField() -> some View {
        self
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 8)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .foregroundStyle(Theme.textPrimary)
            .font(Theme.fieldValue)
    }

    func scootPagePadding() -> some View {
        self.padding(.horizontal, Theme.Space.page)
    }

    /// Einheitlich schlankes Segment-Control.
    func scootSegmented() -> some View {
        self
            .pickerStyle(.segmented)
            .controlSize(Theme.Control.segmentControlSize)
            .font(Theme.segment)
    }
}
