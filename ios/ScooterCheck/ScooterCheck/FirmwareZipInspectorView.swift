import SwiftUI

/// Firmware-Forensik 2.0 — Read-Only, Dark UI (#12161C / #6BDBC2).
struct FirmwareZipInspectorView: View {
    var mode: FirmwareForensicsMode = .fileOnly
    var vehicleContext: FirmwareVehicleContext? = nil
    var onBackToHub: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var references = FirmwareReferenceStore.shared

    private var combinesWithReadout: Bool { mode == .withReadout }

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
    @State private var serverStatusText: String?
    @State private var isServerBusy = false
    @State private var lastServerJobId: String?
    @State private var decompilePreview: FirmwareDecompilePreview?
    @State private var showDecompilePreview = false
    @ObservedObject private var appSettings = AppSettings.shared
    /// Nach Dateiauswahl automatisch Server-Analyse starten, wenn konfiguriert.
    private var autoServerAnalyze: Bool { true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    intro
                    Button {
                        openSubjectPicker()
                    } label: {
                        Text(report == nil ? "Datei wählen" : "Andere Datei")
                            .font(Theme.buttonSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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
                    if combinesWithReadout, vehicleContext == nil {
                        missingReadoutBanner
                    }

                    if let report {
                        verdictBanner(report)
                        if combinesWithReadout {
                            readoutMatchSection(report)
                            dualSourceSection(report)
                        }
                        deepAnalysisSection(report)
                        packageSection(report)
                        contentSection(report)
                        cryptoSection(report)
                        technicalSection(report)
                        comparisonSection(report)
                        indicatorsSection(report)
                        if combinesWithReadout {
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
            .navigationTitle(combinesWithReadout ? "Mit Auslese" : "Datei allein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onBackToHub == nil ? "Schließen" : "Zurück") {
                        if let onBackToHub {
                            onBackToHub()
                        } else {
                            dismiss()
                        }
                    }
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
            .sheet(isPresented: $showDecompilePreview) {
                NavigationStack {
                    ScrollView {
                        Text(decompilePreview?.preview ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Theme.bg.ignoresSafeArea())
                    .navigationTitle("Ghidra .c (Vorschau)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showDecompilePreview = false }
                        }
                    }
                }
                .preferredColorScheme(.dark)
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
            Text(combinesWithReadout
                 ? "Firmware-Datei mit der Scooter-Auslese kombinieren — nur lesend."
                 : "Firmware-Datei allein auswerten — lokal und optional per Server, ohne Fahrzeugbezug.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(combinesWithReadout ? "Modus: Kombination" : "Modus: Datei allein")
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    private var missingReadoutBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keine Auslese vorhanden")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.warn)
            Text("Lies zuerst einen E-Scooter aus. Du kannst die Datei trotzdem wählen — der Fahrzeugkontext fehlt dann.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func dualSourceSection(_ r: FirmwareForensicReport) -> some View {
        let reading = makeSyntheticReading(from: r.vehicleContext ?? vehicleContext)
        let assessment = DualSourcePanicCorrelator.assess(
            forensic: r,
            reading: reading,
            profile: nil,
            storedCombo: SoftUnlockComboStore.load(forSerial: (r.vehicleContext ?? vehicleContext)?.serial)
        )
        return DualSourcePanicCard(assessment: assessment)
    }

    @ViewBuilder
    private func readoutMatchSection(_ r: FirmwareForensicReport) -> some View {
        let assessment = FirmwareReadoutMatchCorrelator.assess(
            report: r,
            vehicleContext: r.vehicleContext ?? vehicleContext
        )
        sectionCard("Datei ↔ Scooter-Auslese") {
            HStack {
                Text(assessment.verdict.shortLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(matchColor(assessment.verdict))
                Spacer()
                Text(assessment.verdict.title)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            Text(assessment.summary)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(assessment.checks) { check in
                HStack(alignment: .top, spacing: 8) {
                    Text(matchCheckGlyph(check.status))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(matchCheckColor(check.status))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(check.detail)
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(assessment.caveats, id: \.self) { c in
                Text("• \(c)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func matchColor(_ v: FirmwareReadoutMatchCorrelator.Verdict) -> Color {
        switch v {
        case .likelyMatch: return Theme.accent
        case .partial: return Theme.warn
        case .mismatch: return Theme.danger
        case .inconclusive: return Theme.textMuted
        }
    }

    private func matchCheckColor(_ s: FirmwareReadoutMatchCorrelator.CheckStatus) -> Color {
        switch s {
        case .match: return Theme.accent
        case .mismatch: return Theme.danger
        case .unclear: return Theme.warn
        case .missing: return Theme.textMuted
        }
    }

    private func matchCheckGlyph(_ s: FirmwareReadoutMatchCorrelator.CheckStatus) -> String {
        switch s {
        case .match: return "✓"
        case .mismatch: return "≠"
        case .unclear: return "?"
        case .missing: return "–"
        }
    }

    @ViewBuilder
    private func deepAnalysisSection(_ r: FirmwareForensicReport) -> some View {
        if let deep = r.deepAnalysis {
            sectionCard("Deep Analysis (Limits / Combos)") {
                Text(deep.quality.summary)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                metaRow("Quellen", deep.sources.map(\.label).joined(separator: ", "))
                if let maxK = deep.maxSpeedKmhInCode {
                    metaRow("Max im Code/Katalog", "\(Int(maxK)) km/h")
                }
                if let legal = deep.legalCapKmhInCode {
                    metaRow("Legal-Kappe", "\(Int(legal)) km/h")
                }
                if !deep.speedLimits.isEmpty {
                    Text("Speed-Stufen")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 4)
                    ForEach(deep.speedLimits) { s in
                        Text("• \(Int(s.kmh)) km/h — \(s.role.label) (\(s.confidence.label))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if !deep.comboSummaries.isEmpty {
                    Text("Kombinationen")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 4)
                    ForEach(deep.comboSummaries, id: \.self) { c in
                        Text("• \(c)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("Kombinationen: noch keine — Server-Analyse oder bekannte CFW-Signatur nötig.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.top, 4)
                }
                if !deep.inputHints.isEmpty {
                    Text("Eingaben")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 4)
                    ForEach(deep.inputHints) { hint in
                        Text("• \(hint.kind.label): \(hint.detail)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if !deep.modeTransitions.isEmpty {
                    Text("Moduswechsel")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 4)
                    ForEach(deep.modeTransitions) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Auslöser: \(t.trigger)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                            Text("Wirkung: \(t.effect)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                Text("Server: ninebottea → Klartext, Ghidra → .c (Decompile, kein Neu-Kompilieren). Ergebnis wird mit lokaler Deep Analysis und dem Fahrzeugkontext aus der Auslese zusammengeführt (Dual-Source).")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 4)

                if FirmwareServerAnalysisClient.fromAppSettings().isConfigured {
                    Button {
                        Task { await uploadToAnalysisServer() }
                    } label: {
                        Label(
                            isServerBusy ? "Server analysiert…" : "Auf Server entschlüsseln / analysieren",
                            systemImage: "lock.open.iphone"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isServerBusy || lastData == nil)
                } else {
                    Text("Server nicht erreichbar konfiguriert — URL unter Einstellungen prüfen.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
                if let serverStatusText {
                    Text(serverStatusText)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if lastServerJobId != nil {
                    Button {
                        Task { await loadDecompilePreview() }
                    } label: {
                        Label("Ghidra-.c Vorschau laden", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .disabled(isServerBusy)
                }
            }
        } else if FirmwareServerAnalysisClient.fromAppSettings().isConfigured, lastData != nil {
            sectionCard("Deep Analysis (Server)") {
                Text("Lokal keine Katalog-/Speed-Treffer. Server kann ENC mit eurem Decrypt-Tool öffnen.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    Task { await uploadToAnalysisServer() }
                } label: {
                    Label(
                        isServerBusy ? "Server analysiert…" : "Auf Server entschlüsseln / analysieren",
                        systemImage: "lock.open.iphone"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isServerBusy)
                if let serverStatusText {
                    Text(serverStatusText)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func makeSyntheticReading(from ctx: FirmwareVehicleContext?) -> IntegrityReading? {
        guard let ctx, ctx.fromLiveReadout else { return nil }
        var reading = IntegrityReading()
        reading.serialDisplay = ctx.serial
        reading.fwVcu = ctx.fwVcu
        reading.fwMcu = ctx.fwMcu
        reading.fwBle = ctx.fwBle
        reading.fwEsc = ctx.fwEsc
        reading.speedLimitKmh = ctx.speedLimitKmh
        reading.speedMaxKmh = ctx.speedMaxKmh
        reading.peakSpeedKmh = ctx.peakSpeedKmh
        return reading
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
            lastServerJobId = nil
            decompilePreview = nil
            if refModel.isEmpty {
                let lower = lastFileName.lowercased()
                if lower.contains("zt3") { refModel = "zt3" }
            }
            reanalyze()
            if autoServerAnalyze, FirmwareServerAnalysisClient.fromAppSettings().isConfigured {
                Task { await uploadToAnalysisServer() }
            }
        } catch {
            report = nil
            errorText = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
        }
        isBusy = false
    }

    private func reanalyze() {
        guard let data = lastData else { return }
        isBusy = true
        let analyzed = FirmwareForensicOrchestrator.analyze(
            fileName: lastFileName,
            data: data,
            references: references.records,
            preferredReferenceId: preferredReferenceId,
            vehicleContext: combinesWithReadout ? vehicleContext : nil
        )
        report = analyzed
        if combinesWithReadout {
            DualSourceCaseStore.saveForensic(analyzed)
        }
        if refModel.isEmpty, let first = analyzed.meta.models.first {
            refModel = first
        }
        if let t = analyzed.meta.type, refController.isEmpty || refController == "VCU" {
            refController = t
        }
        isBusy = false
    }

    @MainActor
    private func uploadToAnalysisServer() async {
        guard let data = lastData else { return }
        let client = FirmwareServerAnalysisClient.fromAppSettings()
        guard client.isConfigured else {
            serverStatusText = "Keine Server-URL in den Einstellungen."
            return
        }
        isServerBusy = true
        serverStatusText = "Lade Datei hoch…"
        errorText = nil
        defer { isServerBusy = false }

        let local = report
        let req = FirmwareAnalysisJobRequest(
            clientReportId: local?.id ?? UUID().uuidString,
            originalFileName: lastFileName,
            archiveSHA256: local?.archiveDigest.sha256 ?? FirmwareDigest.sha256Hex(data),
            payloadSHA256: nil,
            infoJSON: local?.meta.rawInfoJSON,
            models: local?.meta.models ?? [],
            controllerType: local?.meta.type,
            allowDecrypt: true,
            allowLLM: true
        )
        do {
            let status = try await client.submit(req, archiveData: data)
            lastServerJobId = status.jobId.isEmpty ? nil : status.jobId
            serverStatusText = status.message
            if status.state == .failed {
                errorText = status.message
                return
            }
            var final = status
            if status.state != .completed, !status.jobId.isEmpty {
                serverStatusText = "Warte auf Job \(status.jobId.prefix(8))…"
                // Decrypt + Ghidra (+ optional KI) kann mehrere Minuten dauern.
                for _ in 0..<240 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    final = try await client.poll(jobId: status.jobId)
                    let pct = final.progressPercent
                    serverStatusText = pct > 0
                        ? "\(final.state.label): \(final.message) (\(pct)%)"
                        : "\(final.state.label): \(final.message)"
                    if final.state == .completed || final.state == .failed { break }
                }
            }
            guard final.state == .completed, let remote = final.result,
                  let validated = FirmwareDeepAnalysisMerger.validateServerResult(remote)
                    ?? (remote.quality.hasDeterministicBasis ? remote : nil)
            else {
                errorText = final.message.isEmpty ? "Server lieferte kein verwertbares Ergebnis." : final.message
                return
            }
            mergeServerDeepAnalysis(validated)
            var bits: [String] = []
            if final.plaintextSaved == true { bits.append("Decrypt OK") }
            if final.decompileSaved == true { bits.append("Ghidra .c OK") }
            if validated.sources.contains(.serverLLM) { bits.append("KI") }
            bits.append("\(validated.speedLimits.count) Speed")
            bits.append("\(validated.comboSummaries.count) Kombi(s)")
            serverStatusText = bits.joined(separator: " · ")
            if final.decompileSaved == true {
                await loadDecompilePreview()
            }
        } catch {
            errorText = error.localizedDescription
            serverStatusText = error.localizedDescription
        }
    }

    @MainActor
    private func loadDecompilePreview() async {
        guard let jobId = lastServerJobId else { return }
        let client = FirmwareServerAnalysisClient.fromAppSettings()
        do {
            decompilePreview = try await client.decompilePreview(jobId: jobId)
            showDecompilePreview = true
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func mergeServerDeepAnalysis(_ remote: FirmwareDeepAnalysisResult) {
        guard var current = report else { return }
        var remoteWithLive = remote
        if combinesWithReadout,
           let serial = (current.vehicleContext ?? vehicleContext)?.serial,
           let stored = SoftUnlockComboStore.load(forSerial: serial) {
            let liveLine = "Live-Kombination (SN): \(stored.displayCode)"
            if !remoteWithLive.comboSummaries.contains(liveLine) {
                remoteWithLive.comboSummaries.insert(liveLine, at: 0)
            }
            if !remoteWithLive.sources.contains(.liveVehicleContext) {
                remoteWithLive.sources.append(.liveVehicleContext)
            }
        }
        let parts = [current.deepAnalysis, remoteWithLive].compactMap { $0 }
        current.deepAnalysis = FirmwareDeepAnalysisMerger.merge(parts) ?? remoteWithLive
        // Evidence-Zeile für Combos aktualisieren
        if let deep = current.deepAnalysis, !deep.comboSummaries.isEmpty {
            let item = FirmwareEvidenceItem(
                id: "deep-combo",
                category: .modeHint,
                title: "Dokumentierte Modus-Combos",
                detail: deep.comboSummaries.joined(separator: " · "),
                evidence: deep.notes.first ?? "Server/Katalog/Live",
                method: deep.sources.map(\.label).joined(separator: " + "),
                verifiability: .indicative,
                confirmed: false
            )
            current.evidence.removeAll { $0.id == "deep-combo" }
            current.evidence.append(item)
        }
        report = current
        if combinesWithReadout {
            DualSourceCaseStore.saveForensic(current)
        }
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
