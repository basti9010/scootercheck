import SwiftUI

/// SHU-ähnliche Hardware-Forensik-Karte: Region, Rand-Marker, UIDs, Boards, Prior-Diff.
struct HardwareForensicsCard: View {
    let result: IntegrityResult

    private var hardwareFacts: [MeasuredFact] {
        result.facts.filter { fact in
            fact.group == .hardware
                || fact.id == "fw.rand.marker"
                || fact.id.hasPrefix("hw.")
        }
        .sorted { lhs, rhs in
            Self.displayOrder(lhs.id) < Self.displayOrder(rhs.id)
        }
    }

    private var hasSuspicious: Bool {
        hardwareFacts.contains {
            $0.status == .abweichend || $0.status == .erheblichAbweichend
        }
    }

    private var uidChanged: Bool {
        hardwareFacts.contains { $0.id.hasPrefix("hw.diff.uid.") }
    }

    var body: some View {
        if hardwareFacts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hardware-Forensik")
                        .font(Theme.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text(badgeLabel)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(badgeColor)
                }

                Text("SHU-Parität (nur Lesen): Region, Random-Register, Chip-UIDs, Board-Typen.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if uidChanged {
                    Text("UID gewechselt seit Vorprüfung — möglicher Boardtausch.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(hardwareFacts) { fact in
                    row(fact)
                }
            }
            .scootCard()
        }
    }

    private var badgeLabel: String {
        if uidChanged { return "Boardtausch?" }
        if hasSuspicious { return "auffällig" }
        return "dokumentiert"
    }

    private var badgeColor: Color {
        if uidChanged { return Theme.danger }
        if hasSuspicious { return Theme.warn }
        return Theme.accent
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
            if fact.status == .abweichend || fact.status == .erheblichAbweichend {
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

    private static func displayOrder(_ id: String) -> Int {
        switch id {
        case "hw.region": return 0
        case "fw.rand.marker": return 1
        case "hw.uid.vcu": return 2
        case "hw.uid.mcu": return 3
        case "hw.board.types": return 4
        case "hw.diff.uid.vcu": return 5
        case "hw.diff.uid.mcu": return 6
        case "hw.diff.rand": return 7
        default: return 50
        }
    }
}
