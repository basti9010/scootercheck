import SwiftUI

/// Detail einer gespeicherten Untersuchung inkl. Nachzügler-Aktionen.
struct InvestigationDetailView: View {
    let recordId: String
    var onAppendFirmware: (InvestigationRecord) -> Void
    var onAppendScooter: (InvestigationRecord) -> Void
    var onClose: () -> Void

    @ObservedObject private var store = InvestigationStore.shared

    private var record: InvestigationRecord? { store.record(id: recordId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if let rec = record {
                        PageTitle(text: rec.title)
                        Text(rec.kind.label)
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)

                        if let r = rec.readout {
                            sectionCard("Scooter-Auslesung") {
                                meta("Modell", r.modelLabel)
                                meta("Seriennr.", r.serial ?? "—")
                                meta("VCU", r.fwVcu ?? "—")
                                meta("MCU", r.fwMcu ?? "—")
                                meta("BLE", r.fwBle ?? "—")
                                meta("Gespeichert", Self.fmt(r.savedAt))
                                if let pn = r.protocolNumber {
                                    meta("Prüfung", pn)
                                }
                            }
                        } else {
                            sectionCard("Scooter-Auslesung") {
                                Text("Noch keine BLE-Auslesung in dieser Untersuchung.")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        sectionCard("Firmwaredateien") {
                            if rec.firmwareRefs.isEmpty {
                                Text("Noch keine Firmwareanalyse.")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                ForEach(rec.firmwareRefs) { ref in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ref.originalFileName)
                                            .font(Theme.cardTitle)
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(ref.subjectSHA256.map { "SHA-256 \($0.prefix(16))…" } ?? "SHA-256 —")
                                            .font(Theme.meta)
                                            .foregroundStyle(Theme.textMuted)
                                        Text(Self.fmt(ref.addedAt))
                                            .font(Theme.meta)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        Text("Eine importierte Firmwaredatei ist nicht automatisch die auf dem Fahrzeug installierte Firmware.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: Theme.Space.sm) {
                            if rec.readout != nil {
                                Button {
                                    onAppendFirmware(rec)
                                } label: {
                                    Label(
                                        rec.firmwareRefs.isEmpty
                                            ? "Firmwaredatei ergänzen"
                                            : "Weitere Firmwaredatei hinzufügen",
                                        systemImage: "doc.badge.plus"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                            } else {
                                Button {
                                    onAppendScooter(rec)
                                } label: {
                                    Label("Scooter-Auslesung ergänzen", systemImage: "antenna.radiowaves.left.and.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                            }
                        }
                    } else {
                        Text("Untersuchung nicht gefunden.")
                            .foregroundStyle(Theme.danger)
                    }

                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Untersuchung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { onClose() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func meta(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.meta).foregroundStyle(Theme.textMuted)
            Spacer()
            Text(v).font(Theme.caption).foregroundStyle(Theme.textPrimary)
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
