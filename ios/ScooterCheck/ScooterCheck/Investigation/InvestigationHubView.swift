import SwiftUI

/// Zentraler Einstieg „E-Scooter untersuchen“ — drei gleichwertige Wege.
struct InvestigationHubView: View {
    var onScooterOnly: () -> Void
    var onFirmwareOnly: () -> Void
    var onCombined: () -> Void
    var onOpenInvestigation: ((InvestigationRecord) -> Void)? = nil

    @ObservedObject private var store = InvestigationStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                VStack(alignment: .leading, spacing: Theme.Space.titleStack) {
                    PageTitle(text: "Was möchtest du untersuchen?")
                    Text("Jeder Weg funktioniert eigenständig. Später kannst du Scooter-Auslesung und Firmwaredateien in derselben Untersuchung ergänzen.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Space.listGap) {
                    ScootFunctionCard(
                        title: "E-Scooter auslesen",
                        subtitle: "Einen E-Scooter über Bluetooth verbinden, technische Daten auslesen und auf Auffälligkeiten untersuchen.",
                        systemImage: "antenna.radiowaves.left.and.right",
                        action: onScooterOnly
                    )

                    ScootFunctionCard(
                        title: "Firmwaredatei untersuchen",
                        subtitle: "Eine ZIP-, BIN- oder ENC-Datei unabhängig von einem E-Scooter analysieren.",
                        systemImage: "doc.text.magnifyingglass",
                        action: onFirmwareOnly
                    )

                    ScootFunctionCard(
                        title: "E-Scooter und Firmware kombinieren",
                        subtitle: "Einen E-Scooter auslesen und die Ergebnisse anschließend mit einer Firmwaredatei gemeinsam untersuchen.",
                        systemImage: "link",
                        action: onCombined
                    )
                }

                if !store.records.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text("Zuletzt")
                            .font(Theme.sectionTitle)
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(store.records.prefix(6)) { rec in
                            Button {
                                onOpenInvestigation?(rec)
                            } label: {
                                HStack(spacing: Theme.Space.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rec.title)
                                            .font(Theme.cardTitle)
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                        Text("\(rec.kind.label) · \(rec.firmwareRefs.count) Firmware")
                                            .font(Theme.meta)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .padding(.horizontal, Theme.Space.cardPadding)
                                .padding(.vertical, 10)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                AppCopyrightFooter()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Space.sm)
                    .padding(.bottom, Theme.Space.xxl)
            }
            .scootPagePadding()
            .padding(.top, Theme.Space.sm)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// Kompakte Schrittanzeige für den Combined-Flow.
struct CombinedInvestigationProgressBar: View {
    var step: CombinedInvestigationStep

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(step.progressLabel)
                .font(Theme.meta.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(step.title)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(CombinedInvestigationStep.allCases, id: \.rawValue) { s in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: s))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color(for: s))
                            .frame(width: 16)
                        Text(s.title)
                            .font(Theme.caption)
                            .foregroundStyle(s == step ? Theme.textPrimary : Theme.textSecondary)
                    }
                }
            }
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func icon(for s: CombinedInvestigationStep) -> String {
        if s.rawValue < step.rawValue { return "checkmark.circle.fill" }
        if s == step { return "largecircle.fill.circle" }
        return "circle"
    }

    private func color(for s: CombinedInvestigationStep) -> Color {
        if s.rawValue < step.rawValue { return Theme.accent }
        if s == step { return Theme.accent }
        return Theme.textMuted
    }
}
