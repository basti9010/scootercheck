import SwiftUI

/// Firmware-Forensik 2.0 — Read-Only, Dark UI (#12161C / #6BDBC2).
struct FirmwareZipInspectorView: View {
    var vehicleContext: FirmwareVehicleContext? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var references = FirmwareReferenceStore.shared

    @State private var report: FirmwareForensicReport?
    @State private var errorText: String?
    @State private var isBusy = false
    @State private var preferredReferenceId: String?
    @State private var lastFileName: String = ""
    @State private var lastData: Data?
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showRefForm = false
    @State private var pendingRefData: Data?
    @State private var pendingRefName: String = ""
    @State private var refManufacturer = "Segway-Ninebot"
    @State private var refModel = ""
    @State private var refController = "VCU"
    @State private var refHW = ""
    @State private var refFW = ""
    @State private var refOrigin = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    intro
                    Button {
                        openSubjectPicker()
                    } label: {
                        Label(report == nil ? "Datei wählen (ZIP/BIN/ENC/JSON/TXT)" : "Andere Datei wählen", systemImage: "doc.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isBusy)

                    if isBusy {
                        ProgressView("Forensische Auswertung…")
                            .font(Theme.caption)
                            .tint(Theme.accent)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                    }
                    if let report {
                        verdictBanner(report)
                        packageSection(report)
                        contentSection(report)
                        cryptoSection(report)
                        technicalSection(report)
                        comparisonSection(report)
                        indicatorsSection(report)
                        if vehicleContext != nil {
                            vehicleSection(report)
                        }
                        exportSection(report)
                        limitsSection(report)
                    }
                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Firmware-Forensik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showRefForm) {
                referenceImportForm
            }
            .sheet(isPresented: $showShare) {
                FirmwareShareSheet(items: shareItems)
            }
        }
    }

    private func openSubjectPicker() {
        errorText = nil
        FirmwareDocumentPickerPresenter.present(
            contentTypes: FirmwareDocumentTypes.subject,
            onPick: { url in
                ingestSubject(url: url)
            },
            onCancel: nil
        )
    }

    private func openReferencePicker() {
        errorText = nil
        FirmwareDocumentPickerPresenter.present(
            contentTypes: FirmwareDocumentTypes.reference,
            onPick: { url in
                prepareReferenceImport(url: url)
            },
            onCancel: nil
        )
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Firmware-Forensik 2.0")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textTitle)
            Text("Statische Analyse lokaler Firmwaredateien (ZIP/BIN/ENC/JSON/TXT). Rein lesend — kein Flashen, keine Fahrzeugänderung. Befunde sind an konkrete Dateibelege gebunden; fehlende Entschlüsselung oder Referenz wird ausdrücklich als nicht verfügbar markiert.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Sections

    private func verdictBanner(_ r: FirmwareForensicReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(r.verdict.label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(verdictColor(r.verdict))
            Text(r.verdictRationale)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(r.summary)
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func packageSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Paketinformationen") {
            metaRow("Datei", r.originalFileName)
            metaRow("Format", formatKind(r.containerKind))
            metaRow("Name", r.meta.displayName ?? "—")
            metaRow("Modell", r.meta.models.joined(separator: ", ").nilIfEmpty ?? "—")
            metaRow("Steuergerät", r.meta.type ?? "—")
            metaRow("Boards", r.meta.compatible.joined(separator: ", ").nilIfEmpty ?? "—")
            metaRow("Archiv", "\(r.archiveByteCount) Byte")
            metaRow("SHA-256", r.archiveDigest.sha256)
            metaRow("MD5", r.archiveDigest.md5)
            metaRow("Entropie", String(format: "%.2f bit/Byte", r.archiveDigest.shannonEntropy))
        }
    }

    private func contentSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Firmwareinhalt") {
            ForEach(r.entries) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.path)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTitle)
                    Text("\(roleLabel(e.role)) · \(e.digest.byteCount) B · H=\(String(format: "%.2f", e.digest.shannonEntropy))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(e.analysisStatus)
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.vertical, 4)
                Divider().overlay(Theme.line)
            }
        }
    }

    private func cryptoSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Verschlüsselung") {
            metaRow("Status", r.crypto.status.label)
            metaRow("Erkanntes Format", r.crypto.detectedFormat)
            metaRow("Entschlüsselung", r.crypto.decryptionAvailable ? "verfügbar" : "nicht verfügbar")
            Text(r.crypto.decryptionNote)
                .font(Theme.caption)
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(r.crypto.evidence, id: \.self) { e in
                Text("• \(e)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func technicalSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Technische Analyse") {
            if r.binary.performed {
                metaRow("Architektur", r.binary.architecture.label)
                metaRow("Vektortabelle", r.binary.vectorTableLikely ? "indikativ ja" : "nicht erkannt")
                if let rh = r.binary.resetHandlerHint {
                    metaRow("Reset/SP", rh)
                }
                ForEach(r.binary.codeDataNotes, id: \.self) { n in
                    Text("• \(n)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !r.binary.stringsSample.isEmpty {
                    DisclosureGroup("String-Stichprobe (\(r.binary.stringsSample.count))") {
                        ForEach(r.binary.stringsSample.prefix(20), id: \.self) { s in
                            Text(s)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .foregroundStyle(Theme.accent)
                }
            } else {
                Text(r.binary.unavailableReason ?? "Analyse nicht verfügbar")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    private func comparisonSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Firmwarevergleich") {
            Button {
                openReferencePicker()
            } label: {
                Label("Referenzfirmware importieren", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)

            if !references.records.isEmpty {
                Picker("Referenz", selection: Binding(
                    get: { preferredReferenceId ?? "" },
                    set: { preferredReferenceId = $0.isEmpty ? nil : $0; reanalyze() }
                )) {
                    Text("Automatisch / erste Treffer").tag("")
                    ForEach(references.records) { rec in
                        Text("\(rec.model) \(rec.controllerType) \(rec.firmwareVersion)").tag(rec.id)
                    }
                }
                .tint(Theme.accent)
            }

            if let cmp = r.comparison {
                metaRow("Ergebnis", cmp.outcome.label)
                Text(cmp.note)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                if let d = cmp.differingBytes {
                    metaRow("Diff-Bytes", "\(d)")
                }
                if let o = cmp.firstDiffOffset {
                    metaRow("Erster Diff", String(format: "0x%X", o))
                }
                ForEach(Array(cmp.segments.prefix(8).enumerated()), id: \.offset) { _, seg in
                    Text(String(format: "Segment @0x%X len %d — %@", seg.offset, seg.length, seg.note))
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    private func indicatorsSection(_ r: FirmwareForensicReport) -> some View {
        let confirmed = r.evidence.filter(\.confirmed)
        let unconfirmed = r.evidence.filter { !$0.confirmed && $0.category != .limitation && $0.category != .package && $0.category != .crypto && $0.category != .comparison }
        return sectionCard("Manipulationsindikatoren") {
            Text("Bestätigt (Dateiinhalt)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            if confirmed.isEmpty {
                Text("Keine bestätigten Abweichungs-/Manipulationsbefunde aus dem Dateiinhalt.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(confirmed) { item in
                    evidenceRow(item)
                }
            }
            Text("Unbestätigt / indikativ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warn)
                .padding(.top, 8)
            if unconfirmed.isEmpty {
                Text("Keine unbestätigten Hinweise.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(unconfirmed) { item in
                    evidenceRow(item)
                }
            }
        }
    }

    private func vehicleSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Fahrzeugkontext (Auslese)") {
            Text("Die importierte Datei wird dem Prüfkontext nur zugeordnet — sie gilt nicht als installierte Firmware.")
                .font(Theme.caption)
                .foregroundStyle(Theme.warn)
            if let ctx = r.vehicleContext ?? vehicleContext {
                metaRow("Modell", ctx.modelLabel ?? "—")
                metaRow("Seriennr.", ctx.serial ?? "—")
                metaRow("VCU", ctx.fwVcu ?? "—")
                metaRow("MCU", ctx.fwMcu ?? "—")
                metaRow("BLE", ctx.fwBle ?? "—")
            }
            ForEach(r.vehicleLinkNotes, id: \.self) { n in
                Text("• \(n)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func exportSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Forensikbericht") {
            Button {
                sharePDF(r)
            } label: {
                Label("PDF exportieren", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button {
                shareJSON(r)
            } label: {
                Label("JSON exportieren", systemImage: "curlybraces")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
    }

    private func limitsSection(_ r: FirmwareForensicReport) -> some View {
        sectionCard("Grenzen") {
            ForEach(r.limits, id: \.self) { lim in
                Text("• \(lim)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    // MARK: - Helpers

    private func evidenceRow(_ item: FirmwareEvidenceItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTitle)
            Text(item.detail)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("\(item.verifiability.label) · \(item.evidence) · \(item.method)")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 4)
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textTitle)
            content()
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(Theme.caption)
                .foregroundStyle(Theme.textBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verdictColor(_ v: FirmwareForensicVerdict) -> Color {
        switch v {
        case .green: return Theme.accent
        case .yellow: return Theme.warn
        case .red: return Theme.danger
        case .gray: return Theme.textMuted
        }
    }

    private func formatKind(_ k: FirmwareContainerKind) -> String {
        switch k {
        case .zipV3: return "ScooterHacking ZIPv3"
        case .zipGeneric: return "ZIP"
        case .bareBinary: return "BIN"
        case .bareEncryptedBinary: return "BIN.ENC"
        case .json: return "JSON"
        case .text: return "TXT"
        case .unknown: return "Unbekannt"
        }
    }

    private func roleLabel(_ r: FirmwarePayloadRole) -> String {
        switch r {
        case .infoJson: return "info.json"
        case .paramsText: return "params/text"
        case .firmPlain: return "Firmware (Klartext)"
        case .firmEncrypted: return "Firmware (verschlüsselt)"
        case .other: return "Sonstiges"
        }
    }

    private func ingestSubject(url: URL) {
        errorText = nil
        isBusy = true
        // asCopy:true liefert meist eine lokale Kopie; Security-Scope trotzdem absichern.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                report = nil
                errorText = "Die gewählte Datei ist leer oder konnte nicht gelesen werden."
                isBusy = false
                return
            }
            lastFileName = url.lastPathComponent
            lastData = data
            if refModel.isEmpty {
                let lower = lastFileName.lowercased()
                if lower.contains("zt3") { refModel = "zt3" }
            }
            reanalyze()
        } catch {
            report = nil
            errorText = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
        }
        isBusy = false
    }

    private func reanalyze() {
        guard let data = lastData else { return }
        isBusy = true
        report = FirmwareForensicOrchestrator.analyze(
            fileName: lastFileName,
            data: data,
            references: references.records,
            preferredReferenceId: preferredReferenceId,
            vehicleContext: vehicleContext
        )
        if let models = report?.meta.models, refModel.isEmpty, let first = models.first {
            refModel = first
        }
        if let t = report?.meta.type, refController.isEmpty || refController == "VCU" {
            refController = t
        }
        isBusy = false
    }

    private func prepareReferenceImport(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingRefData = try Data(contentsOf: url)
            pendingRefName = url.lastPathComponent
            refOrigin = pendingRefName
            showRefForm = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var referenceImportForm: some View {
        NavigationStack {
            Form {
                TextField("Hersteller", text: $refManufacturer)
                TextField("Modell", text: $refModel)
                TextField("Steuergerät", text: $refController)
                TextField("Hardwareversion", text: $refHW)
                TextField("Firmwareversion", text: $refFW)
                TextField("Herkunft", text: $refOrigin)
                Text("Datei: \(pendingRefName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Referenz importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showRefForm = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        guard let data = pendingRefData else { return }
                        let rec = references.importReference(
                            fileName: pendingRefName,
                            data: data,
                            manufacturer: refManufacturer,
                            model: refModel,
                            controllerType: refController,
                            hardwareVersion: refHW,
                            firmwareVersion: refFW,
                            origin: refOrigin
                        )
                        preferredReferenceId = rec.id
                        showRefForm = false
                        reanalyze()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sharePDF(_ r: FirmwareForensicReport) {
        let data = FirmwareForensicPDF.render(r)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScooterCheck-Firmware-Forensik.pdf")
        try? data.write(to: url)
        shareItems = [url]
        showShare = true
    }

    private func shareJSON(_ r: FirmwareForensicReport) {
        guard let data = try? FirmwareForensicPDF.jsonData(r) else {
            errorText = "JSON-Export fehlgeschlagen."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScooterCheck-Firmware-Forensik.json")
        try? data.write(to: url)
        shareItems = [url]
        showShare = true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Einfacher UIActivity-Share-Wrapper für Forensik-Exporte.
struct FirmwareShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
