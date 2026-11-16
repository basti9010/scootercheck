import SwiftUI

/// Vorher/Jetzt bei erneutem Scan derselben SN — „Geändert seit letzter Prüfung“.
struct RescanDiffCard: View {
    let deltas: [TemporalDelta]

    var body: some View {
        if deltas.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Geändert seit letzter Prüfung")
                        .font(Theme.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text("\(deltas.count)")
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                }

                if let proto = deltas.first?.priorProtocol {
                    Text("Vergleich mit \(proto) — Limit, Peak, Region, Zero Start, FW, UID u. a.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(orderedDeltas) { delta in
                    row(delta)
                }
            }
            .scootCard()
        }
    }

    private var orderedDeltas: [TemporalDelta] {
        deltas.sorted { Self.order($0.id) < Self.order($1.id) }
    }

    private func row(_ delta: TemporalDelta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(delta.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vorher")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Text(delta.previous)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jetzt")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Text(delta.current)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
    }

    private static func order(_ id: String) -> Int {
        switch id {
        case "history.delta.region": return 0
        case "history.delta.limit": return 1
        case "history.delta.max": return 2
        case "history.delta.peak": return 3
        case "history.delta.zero.start": return 4
        case "history.delta.gear": return 5
        case "history.delta.fw.vcu": return 6
        case "history.delta.fw.mcu": return 7
        case "history.delta.fw.ble": return 8
        case "history.delta.uid.vcu": return 9
        case "history.delta.uid.mcu": return 10
        case "history.delta.rand": return 11
        default: return 50
        }
    }
}
