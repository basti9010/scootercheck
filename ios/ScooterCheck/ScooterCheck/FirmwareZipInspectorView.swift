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
    @State private var serverProgress: Double = 0
    @State private var lastServerJobId: String?
    @State private var decompilePreview: FirmwareDecompilePreview?
    @State private var showDecompilePreview = false
    @State private var showAnalysisSession = false
    @State private var serverPlaintextData: Data?
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    intro
                    Button {
                        openSubjectPicker()
                    } label: {
                        Text("Datei wählen")
                            .font(Theme.buttonSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isBusy)

                    if isBusy {
                        ProgressView("Datei wird lokal geprüft…")
                            .font(Theme.caption)
                            .tint(Theme.accent)
                    }
                    if let errorText, !showAnalysisSession {
                        Text(errorText)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                    }
                    if combinesWithReadout, vehicleContext == nil {
                        missingReadoutBanner
                    }
                    Text("Nach der Auswahl: Server-Entschlüsselung ist der Standardweg für Klartext-Limits, Combos und Ampel. PDF/JSON erscheinen erst danach.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
            .fullScreenCover(isPresented: $showAnalysisSession) {
                analysisSessionScreen
            }
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

    private var analysisSessionScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if let report {
                        let decrypted = reportHasServerDeep(report)
                        if decrypted {
                            laypersonHeader(report)
                            if isServerBusy || serverProgress > 0 {
                                serverProgressCard
                            }
                            if let errorText {
                                Text(errorText)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            deepAnalysisSection(report)
                            if combinesWithReadout {
                                readoutMatchSection(report)
                                dualSourceSection(report)
                                vehicleSection(report)
                            }
                            exportSection(report)
                            offlineFindingsSection(report)
                            decryptActionCard(report)
                            limitsSection(report)
                        } else {
                            preDecryptSummary(report)
                            decryptActionCard(report)
                            if isServerBusy || serverProgress > 0 {
                                serverProgressCard
                            }
                            if let errorText {
                                Text(errorText)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            offlineFindingsSection(report)
                            if combinesWithReadout {
                                vehicleSection(report)
                            }
                        }
                    } else if isBusy {
                        ProgressView("Lokale Auswertung…")
                            .tint(Theme.accent)
                    }
                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(lastFileName.isEmpty ? "Auswertung" : lastFileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { showAnalysisSession = false }
                        .foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Andere Datei") { openSubjectPicker() }
                        .foregroundStyle(Theme.accent)
                        .disabled(isBusy || isServerBusy)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func reportHasServerDeep(_ r: FirmwareForensicReport) -> Bool {
        r.deepAnalysis?.sources.contains(where: {
            switch $0 {
            case .serverDecompile, .serverR2, .serverCapstone, .serverYara, .serverEmulation, .serverAngr, .serverIvt, .serverLLM:
                return true
            default: return false
            }
        }) == true
    }

    private func laypersonHeader(_ r: FirmwareForensicReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Ergebnis: Server-Klartext ausgewertet")
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            verdictBanner(r)
        }
    }

    /// Slim first screen after file pick — server decrypt/analyse is the primary path.
    private func preDecryptSummary(_ r: FirmwareForensicReport) -> some View {
        let isPlain = r.crypto.status == .plaintext
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Datei bereit")
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(r.originalFileName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTitle)
                    .lineLimit(2)
                Text("Lokal geprüft · \(r.crypto.status.label) · \(formatKind(r.containerKind))")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(isPlain
                     ? "Klartext erkannt. Als Nächstes auf dem Server analysieren (Limits, Combos, Ampel). Export erscheint danach."
                     : "Für Ampel, Limits und Combos: als Nächstes auf dem Server entschlüsseln. Export erscheint danach.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func decryptActionCard(_ r: FirmwareForensicReport) -> some View {
        let serverReady = FirmwareServerAnalysisClient.fromAppSettings().isConfigured
        let hasServerDeep = reportHasServerDeep(r)
        let isPlain = r.crypto.status == .plaintext
        return sectionCard(hasServerDeep ? "Erneut analysieren" : "Server-Analyse") {
            Text(hasServerDeep
                 ? (isPlain
                    ? "Optional erneut auf dem Server analysieren (Klartext — kein erneutes Entschlüsseln nötig)."
                    : "Optional erneut auf dem Server entschlüsseln und analysieren.")
                 : (isPlain
                    ? "Klartext-Datei: auf dem Server analysieren — Limits, Combos und Ampel (ohne TEA/XTEA)."
                    : "Standardweg: Datei auf dem Server entschlüsseln — Klartext-Limits, Combos und Ampel."))
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if AppSettings.shared.firmwareAnalysisAllowLLM {
                Text("Hinweis: Externe KI ist in den Einstellungen aktiviert. Decompile-Ausschnitte können an einen externen KI-Dienst übertragen werden.")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("KI-Anreicherung ist aus (Standard). Die Server-Analyse läuft ohne externe KI.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if serverReady {
                Button {
                    Task { await uploadToAnalysisServer() }
                } label: {
                    Label(
                        serverAnalyzeButtonTitle(isPlain: isPlain, hasServerDeep: hasServerDeep),
                        systemImage: isPlain ? "cpu" : "lock.open"
                    )
                    .font(Theme.buttonSecondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isServerBusy || lastData == nil)
            } else {
                Text("Kein Analyse-Server in den Einstellungen konfiguriert.")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            }
            if let serverStatusText, !isServerBusy {
                Text(serverStatusText)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func serverAnalyzeButtonTitle(isPlain: Bool, hasServerDeep: Bool) -> String {
        if isServerBusy {
            return isPlain ? "Analyse läuft…" : "Entschlüsselung läuft…"
        }
        if hasServerDeep {
            return isPlain ? "Erneut auf Server analysieren" : "Erneut auf Server entschlüsseln"
        }
        return isPlain ? "Auf Server analysieren" : "Auf Server entschlüsseln"
    }

    private var serverProgressCard: some View {
        sectionCard("Fortschritt") {
            ProgressView(value: min(max(serverProgress, 0), 100), total: 100)
                .tint(Theme.accent)
                .animation(.easeInOut(duration: 0.25), value: serverProgress)
            HStack {
                Text(serverStatusText ?? "Entschlüsselung…")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(Int(serverProgress)) %")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func offlineFindingsSection(_ r: FirmwareForensicReport) -> some View {
        DisclosureGroup("Offline-Befunde (Datei / Verschlüsselung / Technik)") {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Wichtig: Hash, Format und Offline-Einschätzung bleiben auch nach Server-Analyse erhalten.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                packageSection(r)
                contentSection(r)
                cryptoSection(r)
                indicatorsSection(r)
                technicalSection(r)
                comparisonSection(r)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(Theme.accent)
        .padding(.vertical, 4)
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
                 ? "Firmware-Datei mit der Scooter-Auslese kombinieren — lokal prüfen, dann auf dem Server entschlüsseln."
                 : "Firmware-Datei auswerten — lokal prüfen, dann auf dem Server entschlüsseln (Standardweg).")
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

    private func stockDiffColor(_ o: FirmwareStockDiffOutcome) -> Color {
        switch o {
        case .identical: return Theme.accent
        case .different: return Theme.warn
        case .noReference, .skipped: return Theme.textMuted
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
            let brief = FirmwareDeepAnalysisBriefing.build(from: deep)
            let hasServer = deep.sources.contains(where: {
                switch $0 {
                case .serverDecompile, .serverR2, .serverCapstone, .serverYara, .serverEmulation, .serverAngr, .serverIvt, .serverLLM:
                    return true
                default: return false
                }
            })
            sectionCard(hasServer ? "Ergebnis nach Entschlüsselung" : "Lokale Kurzfassung") {
                Text(brief.headline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(brief.bullets, id: \.self) { b in
                    Text("• \(b)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode {
                    HStack(spacing: 12) {
                        Text("Legal ~\(Int(legal))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text("→")
                            .foregroundStyle(Theme.textMuted)
                        Text("Offen ~\(Int(maxK)) km/h")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.warn)
                    }
                    .padding(.top, 4)
                }
                if !brief.actionableCombos.isEmpty {
                    Text("Validierte Tastenfolge")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 8)
                    ForEach(brief.actionableCombos, id: \.self) { c in
                        Text("• \(c)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Nicht bestätigt — nur Hinweis aus Code/Heuristik. Am Fahrzeug gegenprüfen.")
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                } else {
                    Text("Keine klare Tastenfolge im Klartext — oft nur Modus-Register, keine lesbare Kombi.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.top, 4)
                }
                if !brief.humanModeTransitions.isEmpty {
                    Text("Moduswechsel (verständlich)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 8)
                    ForEach(brief.humanModeTransitions) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(t.trigger) → \(t.effect)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !brief.humanInputHints.isEmpty {
                    Text("Eingaben")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 6)
                    ForEach(brief.humanInputHints) { hint in
                        Text("• \(hint.kind.label): \(hint.detail)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                DisclosureGroup("Speed-Stufen (\(deep.speedLimits.count))") {
                    ForEach(deep.speedLimits) { s in
                        Text("• \(Int(s.kmh)) km/h — \(s.role.label)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .foregroundStyle(Theme.accent)
                .padding(.top, 6)

                if !brief.technicalCombos.isEmpty || !brief.technicalModeTransitions.isEmpty || !brief.technicalInputHints.isEmpty {
                    DisclosureGroup("Technik-Details (Hex / Pfade / Decompile)") {
                        ForEach(brief.technicalCombos, id: \.self) { c in
                            Text("• \(c)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        ForEach(brief.technicalModeTransitions) { t in
                            Text("• \(t.title): \(t.trigger)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        ForEach(brief.technicalInputHints) { h in
                            Text("• \(h.kind.label): \(h.detail)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
                }

                if !deep.yaraMatches.isEmpty {
                    DisclosureGroup("YARA (\(deep.yaraMatches.count)) — Evidenzstufe MUSTER") {
                        ForEach(deep.yaraMatches) { m in
                            Text("• \(m.rule): \(m.description)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        Text("YARA erkennt Bytefolgen — kein Live-Fahrzeugnachweis.")
                            .font(.caption2)
                            .foregroundStyle(Theme.warn)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                }

                let findings = deep.classifiedFindings
                    ?? FirmwareEvidenceClassifier.classify(from: deep, fileName: r.originalFileName)
                if !findings.isEmpty {
                    DisclosureGroup("Evidenzstufen (\(findings.count))") {
                        ForEach(findings.prefix(24)) { f in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(f.tier.label)] \(f.category) · \(f.tool)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(f.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(f.limitations)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                }
                if !deep.r2StringsSample.isEmpty {
                    DisclosureGroup("radare2 Strings (\(deep.r2StringsSample.count))") {
                        ForEach(deep.r2StringsSample.prefix(20), id: \.self) { s in
                            Text(s)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                }

                DisclosureGroup("Quellen & Pipeline") {
                    Text(deep.sources.map(\.label).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Text(deep.quality.summary)
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                    Text("Offline sieht nur die ENC — der Server entschlüsselt und liefert Klartext-Befunde. GRAU oben galt vor der Server-Analyse.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)

                if deep.functionAnalysis != nil || deep.functionDiff != nil {
                    advancedCodeAnalysisSection(deep)
                }

                if lastServerJobId != nil {
                    Button {
                        Task { await loadDecompilePreview() }
                    } label: {
                        Label("Ghidra-.c Vorschau", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .disabled(isServerBusy)
                    .padding(.top, 8)
                }
            }
        }
        // Vor Server-Entschlüsselung: CTA steht in `decryptActionCard` — keine Extra-Karte.
    }

    @ViewBuilder
    private func advancedCodeAnalysisSection(_ deep: FirmwareDeepAnalysisResult) -> some View {
        let rows = advancedCodeAnalysisRows(deep)
        let limits = advancedAnalysisLimitationLines(deep)
        let pairs = Array((deep.functionDiff?.samplePairs ?? []).prefix(12))
        let inputs = Array((deep.inputBehaviorAnalysis?.sampleInputFunctions ?? []).prefix(8))
        DisclosureGroup("Erweiterte Codeanalyse") {
            Text("Strukturelle Funktionsunterschiede sind kein Nachweis für Tuning oder Manipulation.")
                .font(.caption2)
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(rows) { row in
                if row.isSectionTitle {
                    Text(row.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, row.topPadding)
                } else if row.isWarning {
                    Text(row.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    metaRow(row.label, row.value)
                }
            }
            if !limits.isEmpty {
                Text("Technische Einschränkungen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
                ForEach(limits, id: \.self) { line in
                    Text("• \(line)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !pairs.isEmpty {
                DisclosureGroup("Funktionsänderungen (Stichprobe)") {
                    ForEach(pairs) { pair in
                        functionDiffPairRow(pair)
                    }
                }
            }
            if !inputs.isEmpty {
                DisclosureGroup("Eingabefunktionen (Stichprobe)") {
                    ForEach(inputs) { item in
                        inputFunctionSampleRow(item)
                    }
                }
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.top, 4)
    }

    private struct AdvancedCodeAnalysisRow: Identifiable {
        let id: String
        let label: String
        let value: String
        let isSectionTitle: Bool
        let isWarning: Bool
        let topPadding: CGFloat

        static func title(_ text: String, top: CGFloat = 4) -> AdvancedCodeAnalysisRow {
            AdvancedCodeAnalysisRow(id: "t:\(text)", label: text, value: "", isSectionTitle: true, isWarning: false, topPadding: top)
        }

        static func warn(_ text: String) -> AdvancedCodeAnalysisRow {
            AdvancedCodeAnalysisRow(id: "w:\(text)", label: text, value: "", isSectionTitle: false, isWarning: true, topPadding: 0)
        }

        static func meta(_ label: String, _ value: String) -> AdvancedCodeAnalysisRow {
            AdvancedCodeAnalysisRow(id: "m:\(label)", label: label, value: value, isSectionTitle: false, isWarning: false, topPadding: 0)
        }
    }

    private func advancedCodeAnalysisRows(_ deep: FirmwareDeepAnalysisResult) -> [AdvancedCodeAnalysisRow] {
        var rows: [AdvancedCodeAnalysisRow] = [.title("Funktionszuordnung")]
        let fa = deep.functionAnalysis
        let counts = deep.functionDiff?.summary
        let matching = deep.functionMatching ?? deep.functionDiff?.functionMatching
        if let n = fa?.functionCount { rows.append(.meta("Funktionen erkannt", "\(n)")) }
        if let matched = matching?.summary?.matched ?? counts?.matched {
            rows.append(.meta("Zugeordnet", "\(matched)"))
        }
        if let identical = counts?.identical { rows.append(.meta("Identisch", "\(identical)")) }
        if let changed = counts?.structurallyChanged { rows.append(.meta("Strukturell verändert", "\(changed)")) }
        if let added = counts?.added { rows.append(.meta("Hinzugefügt", "\(added)")) }
        if let removed = counts?.removed { rows.append(.meta("Entfernt", "\(removed)")) }
        if let uncomp = counts?.uncomparable { rows.append(.meta("Nicht zuordenbar / unklar", "\(uncomp)")) }
        if let amb = matching?.summary?.ambiguous ?? counts?.ambiguous {
            rows.append(.meta("Mehrdeutige Zuordnungen", "\(amb)"))
        }
        if let high = matching?.summary?.high ?? counts?.matchHigh { rows.append(.meta("Matching HIGH", "\(high)")) }
        if let med = matching?.summary?.medium ?? counts?.matchMedium { rows.append(.meta("Matching MEDIUM", "\(med)")) }
        if let low = matching?.summary?.low ?? counts?.matchLow { rows.append(.meta("Matching LOW", "\(low)")) }
        rows.append(.meta(
            "Referenzfirmware",
            deep.referenceMetadata?.referenceLabel ?? deep.stockDiff?.referenceLabel ?? "—"
        ))
        if let trust = deep.referenceMetadata?.referenceTrust ?? deep.stockDiff?.referenceTrust {
            rows.append(.meta("Referenz-Vertrauen", trust))
        }
        if let proc = fa?.processor { rows.append(.meta("Architektur", proc)) }
        rows.append(.meta("Analysequalität", deep.quality.summary))

        // Phase 2.2G: Analyseprofil / Reproduzierbarkeit
        if deep.analysisProfile != nil || deep.analysisProfileHash != nil || deep.ghidraAddressLayout != nil {
            rows.append(.title("Analyseprofil", top: 8))
            if let v = deep.analysisProfile?.analysisProfileVersion {
                rows.append(.meta("Profilversion", v))
            }
            if let h = deep.analysisProfileHash ?? deep.analysisProfile?.analysisProfileHash {
                rows.append(.meta("Profilhash", String(h.prefix(16)) + "…"))
            }
            if let gv = deep.analysisProfile?.ghidraVersion {
                rows.append(.meta("Ghidra-Version", gv))
            }
            if let seed = deep.analysisProfile?.seedCortexMEntryPoints {
                rows.append(.meta("SeedCortexMEntryPoints", seed ? "ja" : "nein"))
            }
            if let layout = deep.ghidraAddressLayout {
                if let r = layout.requestedLoaderBase { rows.append(.meta("requestedLoaderBase", r)) }
                if let a = layout.actualImageBase { rows.append(.meta("actualImageBase", a)) }
                if let m = layout.memoryBlockStart { rows.append(.meta("memoryBlockStart", m)) }
                if let rh = layout.resetHandlerAddress { rows.append(.meta("resetHandler", rh)) }
            }
            if let repro = deep.ghidraReproducibility {
                rows.append(.meta(
                    "Reproduzierbarkeit",
                    repro.reproducible == true ? "semantisch reproduzierbar" : "Abweichungen / nicht geprüft"
                ))
            }
        }

        // Phase 2.2F: Callgraph-Qualität
        let cgq = deep.callGraphQuality ?? deep.callGraph?.callGraphQuality
        if cgq != nil || deep.callGraph != nil {
            rows.append(.title("Callgraph-Qualität", top: 8))
            if let n = deep.callGraph?.edgeCount { rows.append(.meta("Kanten gesamt", "\(n)")) }
            if let n = cgq?.directCalls { rows.append(.meta("Direkte Funktionsaufrufe", "\(n)")) }
            if let n = cgq?.indirectCalls { rows.append(.meta("Indirekte Aufrufe", "\(n)")) }
            if let n = cgq?.internalBranches { rows.append(.meta("Interne Sprünge", "\(n)")) }
            if let n = cgq?.tailCalls { rows.append(.meta("Tail-Calls", "\(n)")) }
            if let n = cgq?.unresolvedCalls ?? deep.callGraph?.unresolvedCount {
                rows.append(.meta("Nicht aufgelöste Aufrufe", "\(n)"))
            }
            if let n = cgq?.unknownControlFlow {
                rows.append(.meta("Unbekannte Kontrollflussreferenzen", "\(n)"))
            }
            rows.append(.warn("Interne Sprünge zählen nicht als ungeklärte Funktionsaufrufe."))
        }

        // Phase 2.2F: Firmwarecontainer
        if let cont = deep.firmwareContainerAnalysis {
            rows.append(.title("Firmwarecontainer", top: 8))
            if let fmt = cont.format { rows.append(.meta("Containerformat", fmt)) }
            if let st = cont.status { rows.append(.meta("Erkannter Firmwaretyp / Status", st)) }
            rows.append(.meta("Container erkannt", cont.containerRecognized == true ? "ja" : "nein"))
            if let arch = cont.architecture {
                rows.append(.meta("Architektur", arch))
            } else {
                rows.append(.meta("Architektur", "unbekannt / nicht erzwungen"))
            }
            let archConf = deep.firmwareArchitectureConfidence ?? cont.architectureConfidence
            if let archConf {
                rows.append(.meta("Architektur-Konfidenz", archConf))
            }
            if let allowed = cont.ghidraImportAllowed {
                rows.append(.meta("Ghidra-Import freigegeben", allowed ? "ja" : "nein"))
            }
            if let base = cont.baseAddr { rows.append(.meta("Ladeadresse (Kandidat)", base)) }
            rows.append(.meta("Image extrahierbar", cont.imageExtractable == true ? "ja" : "nein"))
            if let comps = cont.components, !comps.isEmpty {
                for c in comps.prefix(4) {
                    let off = c.offset.map { String(format: "0x%X", $0) } ?? "—"
                    let size = c.size.map { "\($0)" } ?? "—"
                    rows.append(.meta(
                        c.origin ?? c.role ?? "Komponente",
                        "offset=\(off) size=\(size) sha=\((c.sha256 ?? "—").prefix(12))…"
                    ))
                }
            }
            if let conf = cont.confidence { rows.append(.meta("Analysequalität", conf)) }
        }

        // Phase 2.2E: Analysevollständigkeit
        if deep.analysisCompleteness != nil || deep.firmwareAnalysisCoverage != nil {
            rows.append(.title("Analysevollständigkeit", top: 8))
            if let c = deep.analysisCompleteness {
                rows.append(.meta("Status", c))
            }
            if let cov = deep.firmwareAnalysisCoverage {
                if let n = cov.recognizedFunctionCount {
                    rows.append(.meta("Erkannte Funktionen", "\(n)"))
                }
                if let n = cov.analyzedFunctionCount {
                    rows.append(.meta("Analysierte Funktionen", "\(n)"))
                }
                if let n = cov.unanalyzedFunctionCount {
                    rows.append(.meta("Nicht analysiert (Truncation)", "\(n)"))
                }
                if cov.truncated == true {
                    rows.append(.warn("Analyse gekürzt (Funktionslimit) — Ergebnis unvollständig."))
                }
                if cov.unknownTrueFunctionTotal == true {
                    rows.append(.meta("Tatsächliche Gesamtzahl", "unbekannt"))
                }
            }
            if let cat = deep.referenceCatalogCoverage {
                rows.append(.title("Referenzkatalog", top: 8))
                rows.append(.meta("Verfügbarkeit", cat.present == true ? "vorhanden" : "fehlt"))
                if let st = cat.completenessStatus { rows.append(.meta("Analysevollständigkeit", st)) }
                if let gv = cat.ghidraVersion { rows.append(.meta("Ghidra-Version", gv)) }
                if let ac = cat.analyzerCompat { rows.append(.meta("Analyzer-Version", ac)) }
                if let t = cat.referenceTrust { rows.append(.meta("Vertrauensstatus", t)) }
                if let p = cat.processor { rows.append(.meta("Katalog-Architektur", p)) }
            } else if let meta = deep.referenceMetadata {
                rows.append(.title("Referenzkatalog", top: 8))
                let present = meta.functionCatalog?.present == true
                rows.append(.meta("Verfügbarkeit", present ? "vorhanden" : "fehlt"))
                if let t = meta.referenceTrust { rows.append(.meta("Vertrauensstatus", t)) }
            }

            if let batch = deep.referenceCatalogBatch {
                rows.append(.meta(
                    "Test-Batch",
                    batch.productiveCatalogsModified == true
                        ? "WARNUNG: Produktivkataloge verändert"
                        : "isoliert (Produktiv unverändert)"
                ))
            }
        }

        let input = deep.inputBehaviorAnalysis
        let sm = deep.stateMachineAnalysis ?? input?.stateMachineAnalysis
        let inputDiff = deep.inputBehaviorDiff
        let runtime = deep.runtimeStateMachineValidation
        if input != nil || sm != nil || runtime != nil {
            rows.append(.title("Eingabeverarbeitung / FSM-Validierung", top: 8))
            rows.append(.warn("Heuristische Codeeigenschaften — kein Nachweis realen Fahrzeugverhaltens."))
            if let n = input?.summary?.inputRelevantCount {
                rows.append(.meta("Relevante Funktionen", "\(n)"))
            }
            if let cats = input?.categories, !cats.isEmpty {
                rows.append(.meta("Eingabekategorien", cats.keys.sorted().joined(separator: ", ")))
            }
            if let tier = input?.evidenceTier { rows.append(.meta("Evidenzstufe (statisch)", tier)) }
            if let smCount = sm?.stateMachineCount {
                rows.append(.meta("Statische FSM-Hinweise / Kandidaten", "\(smCount)"))
            }
            if let cand = sm?.candidateCount {
                rows.append(.meta("STATIC_CANDIDATE", "\(cand)"))
            }
            if let structured = sm?.structureIdentifiedCount {
                rows.append(.meta("STATIC_STRUCTURE_IDENTIFIED", "\(structured)"))
            }
            if let tr = sm?.transitionsIdentifiedCount {
                rows.append(.meta("Identifizierte Zustandsstrukturen / Übergänge", "\(tr)"))
            }
            let validation = deep.stateMachineValidation ?? sm?.stateMachineValidation
            let runtimeObserved = runtime?.dynamicRuntimeVerified == true
                || validation?.dynamicRuntimeVerified == true
            if runtimeObserved {
                rows.append(.meta("Kontrollierte Laufzeitvalidierung", "ja (Unicorn-Suite)"))
                if let n = runtime?.runtimeTransitionsObserved ?? validation?.controlledTransitionEvidence {
                    rows.append(.meta("Beobachtete Übergänge (Suite)", "\(n)"))
                }
                if let tier = runtime?.evidenceTier {
                    rows.append(.meta("RUNTIME_TRANSITION_OBSERVED", tier))
                }
                rows.append(.warn("Unicorn-Test ≠ realer Fahrzeugtest."))
            } else if sm != nil || runtime != nil {
                rows.append(.meta("Kontrollierte Laufzeitvalidierung", "nein / nicht verifiziert"))
                rows.append(.meta("Evidenz", "NOT_VERIFIABLE ohne Emulationsdaten"))
            }
            // Never invent state counts — only show verified numbers when present.
            if let states = sm?.totalEstimatedStates {
                rows.append(.meta("Zustände (verifiziert)", "\(states)"))
            } else if (sm?.stateMachineCount ?? 0) > 0 {
                rows.append(.meta(
                    "Zustandszahlen",
                    "nicht verifiziert — zustandsabhängige Verarbeitung nur vermutet"
                ))
            }
            if let trans = sm?.totalEstimatedTransitions {
                rows.append(.meta("Übergänge (verifiziert)", "\(trans)"))
            }
            if let delta = inputDiff?.stateMachineDiff?.delta {
                rows.append(.meta("FSM-Kandidaten Δ zur Referenz", "\(delta)"))
            }
            if let c = inputDiff?.summary?.structurallyChanged {
                rows.append(.meta("Input strukturell verändert", "\(c)"))
            }
            if let a = inputDiff?.summary?.added { rows.append(.meta("Input hinzugefügt", "\(a)")) }
            if let r = inputDiff?.summary?.removed { rows.append(.meta("Input entfernt", "\(r)")) }
        }

        // Phase 2.3 — Versteckte Eingabemechanismen (Activation Forensics)
        if let af = deep.activationForensics, af.ok != false {
            rows.append(.title("Versteckte Eingabemechanismen", top: 8))
            rows.append(.warn(
                "Statische Codeanalyse — kein Nachweis realen Fahrzeugverhaltens; "
                    + "keine Aktivierungssequenzen."
            ))

            rows.append(.title("Eingabeverarbeitung", top: 6))
            if let n = af.summary?.functionsExamined {
                rows.append(.meta("Untersuchte Funktionen", "\(n)"))
            }
            if let n = af.summary?.inputHandlerCount {
                rows.append(.meta("Mögliche Input-Handler", "\(n)"))
            }
            if let cats = af.categoryCounts ?? af.summary?.categories, !cats.isEmpty {
                let label = cats.filter { $0.value > 0 }.keys.sorted().joined(separator: ", ")
                if !label.isEmpty {
                    rows.append(.meta("Eingabekategorien", label))
                }
            }
            let tier = af.activationEvidenceDistribution?.overallEvidenceTier ?? af.evidenceTier
            if let tier {
                rows.append(.meta("Evidenzstufe", tier))
            }
            if let idq = af.inputDetectionQuality {
                let parts = [
                    idq.namedHandlers.map { "benannt: \($0)" },
                    idq.genericNamedHandlers.map { "generisch: \($0)" },
                    idq.structuralMultiSignal.map { "Struktur+: \($0)" },
                    idq.nameOrStringOnly.map { "nur Name/String: \($0)" },
                ].compactMap { $0 }
                if !parts.isEmpty {
                    rows.append(.meta("Erkennungsqualität", parts.joined(separator: " · ")))
                }
                if let note = idq.note, !note.isEmpty {
                    rows.append(.warn(note))
                }
            }
            if let u = af.undocumentedLogic?.summary?.findingCount {
                rows.append(.meta("Undokumentierte / Diff-Befunde", "\(u)"))
            }
            if let fsm = af.fsmIntegration?.fsmCandidateCount {
                rows.append(.meta("Zustandsautomaten-Kandidaten", "\(fsm)"))
            }
            if let linked = af.fsmIntegration?.inputLinkedFsmCount {
                rows.append(.meta("FSM ↔ Input verknüpft", "\(linked)"))
            }
            for h in (af.sampleInputHandlers ?? []).prefix(6) {
                let cats = (h.inputCategories ?? []).joined(separator: ",")
                let title = h.name ?? h.address ?? "Funktion"
                var tags: [String] = []
                if h.genericName == true { tags.append("generischer Name") }
                if h.weakCandidate == true { tags.append("schwach") }
                if h.structuralOnly == true { tags.append("nur Struktur") }
                let suffix = tags.isEmpty ? "" : " · " + tags.joined(separator: ", ")
                rows.append(.meta(
                    title,
                    "\(cats) · \(h.evidenceTier ?? "—")\(suffix)"
                ))
            }

            let condQuality = af.conditionalLogicQuality
            if condQuality != nil || af.conditionalLogicFindings?.summary != nil {
                rows.append(.title("Bedingte Programmlogik", top: 6))
                if let c = af.conditionalLogicFindings?.summary?.functionsWithConditionalLogic {
                    rows.append(.meta("Funktionen mit Verzweigungen", "\(c)"))
                }
                let qc = condQuality ?? [:]
                if !qc.isEmpty {
                    let label = qc.filter { $0.value > 0 }
                        .sorted { $0.key < $1.key }
                        .map { "\(firmwareActivationConditionalQualityLabel($0.key)): \($0.value)" }
                        .joined(separator: ", ")
                    if !label.isEmpty {
                        rows.append(.meta("Qualitätsklassen", label))
                    }
                }
            }

            if let sdf = af.semanticDataFlow, sdf.ok != false {
                rows.append(.title("Datenflussanalyse", top: 6))
                if let n = sdf.functionsAnalyzed {
                    rows.append(.meta("Funktionen", "\(n)"))
                }
                let flowParts = [
                    sdf.withMemoryReads.map { "Reads: \($0)" },
                    sdf.withMemoryWrites.map { "Writes: \($0)" },
                    sdf.withConditionals.map { "Branches: \($0)" },
                    sdf.withCalls.map { "Calls: \($0)" },
                ].compactMap { $0 }
                if !flowParts.isEmpty {
                    rows.append(.meta("Merkmale", flowParts.joined(separator: " · ")))
                }
                let qParts = [
                    sdf.qualityOk.map { "vollständig: \($0)" },
                    sdf.qualityPartial.map { "teilweise: \($0)" },
                    sdf.qualityMissing.map { "fehlend: \($0)" },
                ].compactMap { $0 }
                if !qParts.isEmpty {
                    rows.append(.meta("Datenfluss-Qualität", qParts.joined(separator: " · ")))
                }
                if let src = sdf.source, !src.isEmpty {
                    rows.append(.meta("Quelle", src))
                }
            }

            if af.activationEvidenceDistribution != nil || af.evidenceGraphQuality != nil
                || af.activationEvidenceGraph != nil || af.resultLimits != nil {
                rows.append(.title("Evidenzqualität", top: 6))
                if let dist = af.activationEvidenceDistribution {
                    let parts = [
                        dist.staticConfirmedCount.map { "STATIC: \($0)" },
                        dist.indicativeCount.map { "INDIC: \($0)" },
                        dist.speculativeCount.map { "SPEC: \($0)" },
                        dist.unknownCount.map { "UNK: \($0)" },
                        dist.ambiguousCount.map { "ambig: \($0)" },
                    ].compactMap { $0 }
                    if !parts.isEmpty {
                        rows.append(.meta("Verteilung Handler", parts.joined(separator: " · ")))
                    }
                    if let summary = dist.overallEvidenceSummary, !summary.isEmpty {
                        rows.append(.meta("Gesamteinschätzung", summary))
                    }
                    for lim in (dist.limitations ?? []).prefix(2) {
                        rows.append(.warn(lim))
                    }
                }
                let nodeN = af.evidenceGraphQuality?.nodeCount ?? af.activationEvidenceGraph?.nodeCount
                let edgeN = af.evidenceGraphQuality?.edgeCount ?? af.activationEvidenceGraph?.edgeCount
                if nodeN != nil || edgeN != nil {
                    rows.append(.meta(
                        "Evidence-Graph",
                        "\(nodeN ?? 0) Knoten / \(edgeN ?? 0) Kanten"
                    ))
                }
                if let gq = af.evidenceGraphQuality {
                    let edgeParts = [
                        gq.confirmedEdgeCount.map { "bestätigt: \($0)" },
                        gq.indicativeEdgeCount.map { "indikativ: \($0)" },
                        gq.speculativeEdgeCount.map { "spekulativ: \($0)" },
                        gq.unresolvedEdgeCount.map { "offen: \($0)" },
                    ].compactMap { $0 }
                    if !edgeParts.isEmpty {
                        rows.append(.meta("Kantenqualität", edgeParts.joined(separator: " · ")))
                    }
                }
                for warn in firmwareActivationResultLimitWarnings(af.resultLimits) {
                    rows.append(.warn(warn))
                }
            }

            if af.referenceComparison?.referenceIsCommunity == true {
                rows.append(.warn("Community-Referenz — keine verifizierte Herstellerfirmware."))
            }
            for p in (af.prioritization?.top ?? []).prefix(3) {
                rows.append(.meta(
                    "Priorität \(p.priorityScore.map { String(format: "%.1f", $0) } ?? "—")",
                    "\(p.name ?? p.address ?? "—") — kein Manipulationsnachweis"
                ))
            }
            for lim in (af.analysisLimitations ?? []).prefix(3) {
                rows.append(.warn(lim))
            }
        }
        return rows
    }

    private func advancedAnalysisLimitationLines(_ deep: FirmwareDeepAnalysisResult) -> [String] {
        let matching = deep.functionMatching ?? deep.functionDiff?.functionMatching
        let input = deep.inputBehaviorAnalysis
        let sm = deep.stateMachineAnalysis ?? input?.stateMachineAnalysis
        let cgq = deep.callGraphQuality ?? deep.callGraph?.callGraphQuality
        var all: [String] = []
        all.append(contentsOf: deep.analysisLimitations ?? [])
        all.append(contentsOf: deep.functionAnalysis?.analysisLimitations ?? [])
        all.append(contentsOf: deep.functionDiff?.analysisLimitations ?? [])
        all.append(contentsOf: matching?.analysisLimitations ?? [])
        all.append(contentsOf: input?.analysisLimitations ?? [])
        all.append(contentsOf: deep.activationForensics?.analysisLimitations ?? [])
        all.append(contentsOf: sm?.analysisLimitations ?? [])
        all.append(contentsOf: cgq?.analysisLimitations ?? [])
        all.append(contentsOf: deep.firmwareContainerAnalysis?.analysisLimitations ?? [])
        all.append(contentsOf: deep.runtimeStateMachineValidation?.analysisLimitations ?? [])
        var seen = Set<String>()
        var unique: [String] = []
        for line in all where !line.isEmpty && seen.insert(line).inserted {
            unique.append(line)
            if unique.count >= 12 { break }
        }
        return unique
    }

    @ViewBuilder
    private func functionDiffPairRow(_ pair: FirmwareFunctionDiffPair) -> some View {
        let addr = pair.subject?.address ?? pair.reference?.address ?? "—"
        let name = pair.subject?.name ?? pair.reference?.name ?? ""
        let matchLine: String? = {
            guard let conf = pair.matchConfidence else { return nil }
            if let method = pair.matchMethod { return "Matching: \(conf) · \(method)" }
            return "Matching: \(conf)"
        }()
        let structureLine: String? = {
            guard let diffs = pair.differences, !diffs.isEmpty else { return nil }
            return "Struktur: \(diffs.keys.sorted().joined(separator: ", "))"
        }()
        VStack(alignment: .leading, spacing: 2) {
            Text("\(addr) \(name)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(pair.status?.label ?? "Unbekannt")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            if let matchLine {
                Text(matchLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
            if let notes = pair.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let tier = pair.evidenceTier {
                Text("Evidenzstufe: \(tier)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
            if let structureLine {
                Text(structureLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func inputFunctionSampleRow(_ item: FirmwareInputFunctionFinding) -> some View {
        let evidence = Array((item.evidence ?? []).prefix(3))
        VStack(alignment: .leading, spacing: 2) {
            Text("\(item.address ?? "—") \(item.name ?? "")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text((item.categories ?? []).joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            if let tier = item.evidenceTier {
                Text("Evidenzstufe: \(tier)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
            ForEach(evidence, id: \.self) { ev in
                Text("• \(ev)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 2)
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

    @ViewBuilder
    private func exportSection(_ r: FirmwareForensicReport) -> some View {
        // Export only after successful server decrypt/analysis.
        if reportHasServerDeep(r) {
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
            serverPlaintextData = nil
            serverProgress = 0
            serverStatusText = nil
            if refModel.isEmpty {
                let lower = lastFileName.lowercased()
                if lower.contains("zt3") { refModel = "zt3" }
            }
            reanalyze()
            // Neues Fenster: lokale Auswertung zuerst — Server erst auf Knopfdruck.
            showAnalysisSession = true
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
        guard client.hasBearerJWT else {
            serverStatusText = "Bitte anmelden — Firmware-Jobs brauchen einen JWT (nicht nur Client-Id)."
            errorText = FirmwareServerAnalysisError.loginRequired.localizedDescription
            return
        }
        isServerBusy = true
        serverProgress = 2
        serverStatusText = "Datei wird hochgeladen…"
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
            allowLLM: AppSettings.shared.firmwareAnalysisAllowLLM
        )
        do {
            let status = try await client.submit(req, archiveData: data)
            lastServerJobId = status.jobId.isEmpty ? nil : status.jobId
            serverProgress = max(5, Double(status.progressPercent))
            serverStatusText = status.message.isEmpty ? "Auftrag gestartet…" : status.message
            if status.state == .failed {
                errorText = status.message
                serverProgress = 0
                return
            }
            var final = status
            if status.state != .completed, !status.jobId.isEmpty {
                serverStatusText = "Entschlüsselung / Analyse…"
                // Decrypt + Ghidra (+ optional KI) kann mehrere Minuten dauern.
                for _ in 0..<240 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    final = try await client.poll(jobId: status.jobId)
                    let pct = Double(final.progressPercent)
                    serverProgress = max(serverProgress, pct > 0 ? pct : min(serverProgress + 1, 95))
                    serverStatusText = final.message.isEmpty ? final.state.label : final.message
                    if final.state == .completed || final.state == .failed { break }
                }
            }
            guard final.state == .completed, let remote = final.result,
                  let validated = FirmwareDeepAnalysisMerger.validateServerResult(remote)
                    ?? (remote.quality.hasDeterministicBasis ? remote : nil)
            else {
                errorText = final.message.isEmpty ? "Server lieferte kein verwertbares Ergebnis." : final.message
                serverProgress = 0
                return
            }
            serverProgress = 97
            serverStatusText = "Klartext wird übernommen…"
            mergeServerDeepAnalysis(validated)

            var artifacts = FirmwareServerArtifacts(
                jobId: final.jobId.isEmpty ? lastServerJobId : final.jobId,
                plaintextSaved: final.plaintextSaved,
                plaintextSHA256: final.plaintextSHA256,
                plaintextByteCount: nil,
                decompileSaved: final.decompileSaved,
                decompileExcerpt: nil
            )
            if final.plaintextSaved == true, let jobId = artifacts.jobId {
                if let plain = try? await client.downloadPlaintext(jobId: jobId) {
                    serverPlaintextData = plain
                    artifacts.plaintextByteCount = plain.count
                    if artifacts.plaintextSHA256 == nil || artifacts.plaintextSHA256?.isEmpty == true {
                        artifacts.plaintextSHA256 = FirmwareDigest.sha256Hex(plain)
                    }
                }
            }
            if final.decompileSaved == true {
                await loadDecompilePreview()
                if let preview = decompilePreview?.preview {
                    artifacts.decompileExcerpt = String(preview.prefix(8_000))
                }
            }
            if var current = report {
                current.serverArtifacts = artifacts
                report = current
            }

            serverProgress = 100
            var bits: [String] = []
            if final.plaintextSaved == true { bits.append("Decrypt OK") }
            if final.decompileSaved == true { bits.append("Ghidra .c OK") }
            if validated.sources.contains(.serverLLM) { bits.append("KI") }
            bits.append("\(validated.speedLimits.count) Speed")
            bits.append("\(validated.comboSummaries.count) Kombi(s)")
            serverStatusText = bits.joined(separator: " · ")
        } catch {
            errorText = error.localizedDescription
            serverStatusText = error.localizedDescription
            serverProgress = 0
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
        if let existing = current.deepAnalysis {
            remoteWithLive = FirmwareDeepAnalysisMerger.coalesceOptionals(base: existing, incoming: remoteWithLive)
        }
        let parts = [current.deepAnalysis, remoteWithLive].compactMap { $0 }
        var merged = FirmwareDeepAnalysisMerger.merge(parts) ?? remoteWithLive
        if merged.classifiedFindings == nil {
            merged.classifiedFindings = FirmwareEvidenceClassifier.classify(
                from: merged,
                fileName: current.originalFileName
            )
        }
        current.deepAnalysis = merged
        // Evidence-Zeile für Combos aktualisieren (nur verständliche Zeilen)
        if let deep = current.deepAnalysis {
            let brief = FirmwareDeepAnalysisBriefing.build(from: deep)
            if !brief.actionableCombos.isEmpty {
                let item = FirmwareEvidenceItem(
                    id: "deep-combo",
                    category: .modeHint,
                    title: "Validierte Tastenfolge",
                    detail: brief.actionableCombos.joined(separator: " · "),
                    evidence: deep.notes.first { !$0.contains("0x") && !$0.contains("puVar") } ?? "Live-Vergleich / Belegt",
                    method: deep.sources.map(\.label).joined(separator: " + "),
                    verifiability: .indicative,
                    confirmed: deep.sources.contains(.liveVehicleContext)
                )
                current.evidence.removeAll { $0.id == "deep-combo" }
                current.evidence.append(item)
            }
            let refreshed = FirmwareDeepAnalysisBriefing.refreshedVerdict(
                current: current.verdict,
                rationale: current.verdictRationale,
                deep: deep
            )
            current.verdict = refreshed.0
            current.verdictRationale = refreshed.1
            if deep.stockDiff?.outcome == .identical {
                current.summary = "\(current.summary) · Stock identisch (Server)"
            } else if deep.maxSpeedKmhInCode != nil {
                current.summary = "\(current.summary) · Server-Klartext OK"
            }
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
        let base = FileManager.default.temporaryDirectory
        let pdfURL = base.appendingPathComponent("ScooterCheck-Firmware-Forensik.pdf")
        try? data.write(to: pdfURL)
        var items: [Any] = [pdfURL]
        if let plain = serverPlaintextData, !plain.isEmpty {
            let stem = (lastFileName as NSString).deletingPathExtension
            let binURL = base.appendingPathComponent("\(stem.isEmpty ? "FIRM" : stem).dec.bin")
            try? plain.write(to: binURL)
            items.append(binURL)
        }
        shareItems = items
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

private func firmwareActivationConditionalQualityLabel(_ key: String) -> String {
    switch key {
    case "CONDITIONAL_LOGIC_ONLY": return "nur Verzweigung"
    case "INPUT_RELATED_CONDITIONAL_LOGIC": return "eingabebezogen"
    case "STATE_RELATED_CONDITIONAL_LOGIC": return "zustandsbezogen"
    case "FEATURE_GATE_CANDIDATE": return "Feature-Gate"
    case "NOT_CLASSIFIABLE": return "unklar"
    default: return key
    }
}

private func firmwareActivationResultLimitWarnings(_ limits: FirmwareActivationResultLimits?) -> [String] {
    guard let limits else { return [] }
    var warns: [String] = []
    func append(_ area: String, _ bucket: FirmwareActivationResultLimitBucket?) {
        guard let bucket, bucket.resultTruncated == true else { return }
        let omitted = bucket.omittedCandidates ?? 0
        var detail = "\(omitted) weggelassene Kandidaten"
        if let reason = bucket.truncationReason, !reason.isEmpty {
            detail += " (\(reason))"
        }
        if let lim = bucket.configuredLimit {
            detail += ", Limit \(lim)"
        }
        warns.append("Ergebnis begrenzt (\(area)): \(detail).")
    }
    append("Handler", limits.handlers)
    append("Bedingte Logik", limits.conditionalLogic)
    append("Evidence-Graph", limits.evidenceGraph)
    return warns
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
