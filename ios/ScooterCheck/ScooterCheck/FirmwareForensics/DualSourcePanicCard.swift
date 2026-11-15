import SwiftUI

/// Dual-Source-Karte: Handy-Datei × Live-Auslese, inkl. nächster Schritte.
struct DualSourcePanicCard: View {
    let assessment: DualSourcePanicAssessment
    var onOpenForensics: (() -> Void)? = nil
    var onStartComparison: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dual-Source · Panic-/Reset")
                    .font(Theme.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(assessment.pattern.severityLabel)
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(severityColor)
            }

            Text(assessment.pattern.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text(assessment.correlationSummary)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            group("Handy-Datei", assessment.phoneSummary)
            group("Live-Auslese", assessment.liveSummary)
            group("Kombinationen", assessment.comboStatus)

            Text("Nächste Schritte")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)
            ForEach(Array(assessment.nextSteps.enumerated()), id: \.offset) { idx, step in
                Text("\(idx + 1). \(step)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if onOpenForensics != nil || onStartComparison != nil {
                HStack(spacing: 8) {
                    if let onOpenForensics {
                        Button("Firmware-Datei", action: onOpenForensics)
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                    }
                    if let onStartComparison {
                        Button("Vergleichstest", action: onStartComparison)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                    }
                }
                .padding(.top, 4)
            }

            Text(assessment.caveats.first ?? "")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .scootCard()
    }

    private var severityColor: Color {
        switch assessment.pattern {
        case .activeTuningVisible, .bothSuspicious: return Theme.danger
        case .panicResetSuspected: return Theme.warn
        case .phoneOnly, .liveOnly: return Theme.accent
        case .insufficient: return Theme.textMuted
        }
    }

    private func group(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
            Text(body)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
