import SwiftUI

/// Detail einer gespeicherten Untersuchung inkl. Nachzügler- und Export-Aktionen.
struct InvestigationDetailView: View {
    let recordId: String
    var onAppendFirmware: (InvestigationRecord) -> Void
    var onAppendScooter: (InvestigationRecord) -> Void
    var onResume: ((InvestigationRecord) -> Void)? = nil
    var onSwitchScooter: ((InvestigationRecord) -> Void)? = nil
    var onClose: () -> Void

    @ObservedObject private var store = InvestigationStore.shared
    @State private var exportBusy = false
    @State private var exportError: String?
    @State private var showSwitchConfirm = false

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
                        Text(rec.resumeSubtitle)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if rec.isResumable {
                            Button {
                                onResume?(rec)
                            } label: {
                                Label("Untersuchung fortsetzen", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        }

                        if let r = rec.readout {
                            sectionCard("Scooter-Auslesung") {
                                meta("Modell", r.modelLabel)
                                meta("Hersteller", r.manufacturer ?? "—")
                                meta("Seriennr.", r.serial ?? "—")
                                meta("BLE-Name", r.bleAdvertisementName ?? "—")
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
                                        Text("Archiv: \(ref.archiveStatus ?? "—") · Job: \(ref.serverJobId ?? "—")")
                                            .font(Theme.meta)
                                            .foregroundStyle(Theme.textSecondary)
                                        if let err = ref.archiveError, !err.isEmpty {
                                            Text(err)
                                                .font(Theme.meta)
                                                .foregroundStyle(Theme.warn)
                                        }
                                        Text(Self.fmt(ref.addedAt))
                                            .font(Theme.meta)
                                            .foregroundStyle(Theme.textSecondary)

                                        if store.loadFirmwareReport(ref: ref, investigationId: rec.id) != nil {
                                            Button("Einzelbericht PDF") {
                                                exportSingleFirmwarePDF(ref: ref, investigationId: rec.id)
                                            }
                                            .font(Theme.buttonSecondary)
                                            .foregroundStyle(Theme.accent)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        if rec.comparisonStale {
                            Text("Vergleichsergebnisse sind als veraltet markiert (Scooter-Zuordnung geändert).")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.warn)
                        }

                        Text("Eine importierte Firmwaredatei ist nicht automatisch die auf dem Fahrzeug installierte Firmware.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)

                        if let exportError {
                            Text(exportError)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.danger)
                        }

                        VStack(spacing: Theme.Space.sm) {
                            if rec.kind == .combined || (rec.readout != nil && !rec.firmwareRefs.isEmpty) {
                                Button {
                                    exportCombinedPDF(rec)
                                } label: {
                                    Label("Gesamten Untersuchungsbericht als PDF erstellen", systemImage: "doc.richtext")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                                .disabled(exportBusy)

                                Button {
                                    exportCombinedJSON(rec)
                                } label: {
                                    Label("Gesamten Untersuchungsbericht als JSON", systemImage: "doc.badge.gearshape")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.accent)
                                .disabled(exportBusy)
                            }

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

                                Button {
                                    showSwitchConfirm = true
                                } label: {
                                    Label("E-Scooter wechseln", systemImage: "arrow.triangle.swap")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.warn)
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
            .confirmationDialog(
                "E-Scooter wechseln?",
                isPresented: $showSwitchConfirm,
                titleVisibility: .visible
            ) {
                Button("Abbrechen", role: .cancel) {}
                Button("Neue Untersuchung starten") {
                    if let rec = record {
                        onClose()
                        // Caller starts fresh via append path replacement — use switch with new investigation.
                        onSwitchScooter?(rec)
                    }
                }
                Button("Scooter-Zuordnung ändern", role: .destructive) {
                    if let rec = record {
                        onAppendScooter(rec)
                    }
                }
            } message: {
                Text("Für diese Untersuchung liegen bereits Auslesedaten vor. Wenn du einen anderen Scooter auswählst, muss die Zuordnung der bisherigen Daten erneut überprüft werden.")
            }
            .preferredColorScheme(.dark)
        }
    }

    private func exportCombinedPDF(_ rec: InvestigationRecord) {
        guard !exportBusy else { return }
        exportBusy = true
        defer { exportBusy = false }
        exportError = nil
        let pairs: [(InvestigationFirmwareRef, FirmwareForensicReport)] = rec.firmwareRefs.compactMap { ref in
            guard let report = store.loadFirmwareReport(ref: ref, investigationId: rec.id) else { return nil }
            return (ref, report)
        }
        let dual: DualSourcePanicAssessment? = {
            guard let first = pairs.first?.1 else { return nil }
            return DualSourcePanicCorrelator.assess(
                forensic: first,
                reading: nil,
                profile: nil,
                storedCombo: SoftUnlockComboStore.load(forSerial: rec.readout?.serial)
            )
        }()
        let data = InvestigationCombinedPDF.render(record: rec, reports: pairs, dualSource: dual)
        guard data.count > 500, String(data: data.prefix(5), encoding: .ascii) == "%PDF-" else {
            exportError = "PDF-Export fehlgeschlagen."
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScooterCheck-Untersuchung-\(rec.id.prefix(8))-\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportError = "PDF konnte nicht gespeichert werden: \(error.localizedDescription)"
            return
        }
        FirmwareExportSharePresenter.present(items: [
            NamedShareFile(url: url, title: "ScooterCheck Untersuchungsbericht", utType: "com.adobe.pdf")
        ]) { ok in
            if !ok { exportError = "Teilen-Menü konnte nicht geöffnet werden." }
        }
    }

    private func exportCombinedJSON(_ rec: InvestigationRecord) {
        guard !exportBusy else { return }
        exportBusy = true
        defer { exportBusy = false }
        exportError = nil
        do {
            let data = try store.exportJSON(for: rec.id)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScooterCheck-Untersuchung-\(rec.id.prefix(8))-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            FirmwareExportSharePresenter.present(items: [
                NamedShareFile(url: url, title: "ScooterCheck Untersuchung JSON", utType: "public.json")
            ]) { ok in
                if !ok { exportError = "Teilen-Menü konnte nicht geöffnet werden." }
            }
        } catch {
            exportError = "JSON-Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func exportSingleFirmwarePDF(ref: InvestigationFirmwareRef, investigationId: String) {
        guard let report = store.loadFirmwareReport(ref: ref, investigationId: investigationId) else {
            exportError = "Gespeicherte Firmwareanalyse nicht gefunden."
            return
        }
        let data = FirmwareForensicPDF.render(report)
        guard data.count > 500 else {
            exportError = "Firmware-PDF fehlgeschlagen."
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScooterCheck-Firmware-\(ref.id.prefix(8)).pdf")
        do {
            try data.write(to: url, options: .atomic)
            FirmwareExportSharePresenter.present(items: [
                NamedShareFile(url: url, title: "ScooterCheck Firmware-Forensik", utType: "com.adobe.pdf")
            ])
        } catch {
            exportError = error.localizedDescription
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
