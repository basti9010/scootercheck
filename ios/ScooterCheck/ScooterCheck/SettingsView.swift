import SwiftUI

/// Globale App-Einstellungen — erreichbar über das linke Menü.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                        PageTitle(text: "Einstellungen")

                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text("Darstellung")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                                .textCase(.uppercase)

                            Text("Schriftgröße")
                                .font(Theme.cardTitle)
                                .foregroundStyle(Theme.textPrimary)

                            Text("Gilt für die gesamte App. Feature-Einstellungen (Radar, Karte) bleiben an Ort und Stelle.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(spacing: Theme.Space.sm) {
                                ForEach(AppTextSize.allCases) { size in
                                    textSizeRow(size)
                                }
                            }
                            .padding(.top, Theme.Space.xs)
                        }

                        AppCopyrightFooter()
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, Theme.Space.xxl)
                    }
                    .scootPagePadding()
                    .padding(.top, Theme.Space.sm)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                AppChromeSheetHeader { dismiss() }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func textSizeRow(_ size: AppTextSize) -> some View {
        let selected = settings.textSize == size
        return Button {
            settings.textSize = size
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(size.title)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(size.subtitle)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: Theme.Space.sm)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: Theme.Icon.standard, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.surfaceSecondary : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(
                        selected ? Theme.accent.opacity(0.55) : Theme.border,
                        lineWidth: Theme.Control.hairline
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
