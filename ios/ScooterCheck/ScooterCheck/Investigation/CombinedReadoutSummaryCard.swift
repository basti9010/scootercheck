import SwiftUI

/// Kompakte Zusammenfassung nach Combined-Schritt 2 (Auslesung).
struct CombinedReadoutSummaryCard: View {
    var summary: InvestigationReadoutSummary
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Scooter-Auslesung abgeschlossen")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(summary.modelLabel)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                if let v = summary.fwVcu { Text("VCU: \(v)").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                if let v = summary.fwMcu { Text("MCU: \(v)").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                if let v = summary.fwBle { Text("BLE: \(v)").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                if let s = summary.serial { Text("Seriennr.: \(s)").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
            }
            Button(action: onContinue) {
                Text("Weiter zur Firmwaredatei")
                    .font(Theme.button)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}
