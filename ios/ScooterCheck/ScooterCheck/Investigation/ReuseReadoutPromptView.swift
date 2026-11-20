import SwiftUI

/// Auswahl einer vorhandenen Scooter-Auslesung für Combined / Firmware-Ergänzung.
struct ReuseReadoutPromptView: View {
    var candidates: [InvestigationReadoutSummary]
    var onUse: (InvestigationReadoutSummary) -> Void
    var onPickNew: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Text("Eine vorhandene Scooter-Auslesung ist verfügbar.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Bitte bestätige die Zuordnung. Es wird keine Auslesung automatisch gewählt.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(candidates) { c in
                        Button {
                            onUse(c)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(c.shortLabel)
                                    .font(Theme.cardTitle)
                                    .foregroundStyle(Theme.textPrimary)
                                HStack(spacing: 8) {
                                    Text(Self.fmt(c.savedAt))
                                    if let pn = c.protocolNumber {
                                        Text("·")
                                        Text(pn)
                                    }
                                }
                                .font(Theme.meta)
                                .foregroundStyle(Theme.textMuted)
                                HStack(spacing: 10) {
                                    if let v = c.fwVcu { Text("VCU \(v)") }
                                    if let v = c.fwMcu { Text("MCU \(v)") }
                                    if let v = c.fwBle { Text("BLE \(v)") }
                                }
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                                Text("Vorhandene Auslesung verwenden")
                                    .font(Theme.buttonSecondary)
                                    .foregroundStyle(Theme.accent)
                                    .padding(.top, 4)
                            }
                            .padding(Theme.Space.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onPickNew()
                    } label: {
                        Label("Neuen Scooter auswählen", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Auslesung zuordnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { onCancel() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}
