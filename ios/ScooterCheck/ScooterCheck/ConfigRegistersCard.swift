import SwiftUI

/// Config-Register nur lesen — Zero Start, Gang-Limits, FunBools, EncFlag (kein Schreiben).
struct ConfigRegistersCard: View {
    let result: IntegrityResult

    private var configFacts: [MeasuredFact] {
        result.facts
            .filter { $0.group == .config || $0.id.hasPrefix("config.") }
            .sorted { Self.order($0.id) < Self.order($1.id) }
    }

    var body: some View {
        if configFacts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Konfiguration (nur Lesen)")
                        .font(Theme.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text("read-only")
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }

                Text("SHU-ähnliche Config-Werte dokumentieren — ScooterCheck schreibt keine Limits, Keys oder Flags.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(configFacts) { fact in
                    row(fact)
                }
            }
            .scootCard()
        }
    }

    private func row(_ fact: MeasuredFact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(fact.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 8)
                Text(fact.status.label)
                    .font(.caption2)
                    .foregroundStyle(statusColor(fact.status))
            }
            Text(fact.auslesewert)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if fact.id == "config.bool" || fact.id == "config.fun" || fact.id.hasPrefix("config.fun") || fact.id == "config.custom_key" {
                Text(fact.erlaeuterung)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if fact.status != .regelkonform {
                Text(fact.bewertung)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private func statusColor(_ status: FactStatus) -> Color {
        switch status {
        case .erheblichAbweichend: return Theme.danger
        case .abweichend: return Theme.warn
        case .regelkonform: return Theme.accent
        case .nichtFeststellbar: return Theme.textMuted
        }
    }

    private static func order(_ id: String) -> Int {
        switch id {
        case "config.zero.start": return 0
        case "config.gear.s": return 1
        case "config.gear.e": return 2
        case "config.gear.d": return 3
        case "config.bool": return 4
        case "config.fun": return 5
        case "config.fun2": return 6
        case "config.fun3": return 7
        case "config.encflag": return 8
        case "config.custom_key": return 9
        default: return 50
        }
    }
}
