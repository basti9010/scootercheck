import SwiftUI

/// Cycle-8 end-to-end flow:
/// pick → integrity (SHA-256/MD5) → optional server job → status → findings → save.
struct FirmwareForensicsAnalysisView: View {
    var mode: FirmwareForensicsMode = .fileOnly
    var vehicleContext: FirmwareVehicleContext? = nil
    var onBackToHub: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onReportProduced: ((FirmwareForensicReport, Data?) -> Void)? = nil
    var preloadedReport: FirmwareForensicReport? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var report: FirmwareForensicReport?
    @State private var originalData: Data?
    @State private var uiStatus: FirmwareAnalysisJobUIStatus?
    @State private var serverJob: FirmwareAnalysisJobStatus?
    @State private var errorText: String?
    @State private var isBusy = false
    @State private var isServerBusy = false
    @State private var lastFileName: String = ""
    @State private var pollTask: Task<Void, Never>?
    @State private var savedNote: String?

    private var combinesWithReadout: Bool { mode == .withReadout }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    intro
                    Button {
                        openPicker()
                    } label: {
                        Text(report == nil ? "Firmware-Datei wählen" : "Andere Datei wählen")
                            .font(Theme.buttonSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isBusy || isServerBusy)

                    if combinesWithReadout, vehicleContext == nil {
                        Text("Keine Auslese im Kontext — Dual-Source-Zuordnung entfällt. Du kannst die Datei trotzdem lokal/am Server prüfen.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isBusy {
                        ProgressView("Integrität & lokale Analyse…")
                            .font(Theme.caption)
                            .tint(Theme.accent)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let uiStatus {
                        statusBadge(uiStatus)
                    }

                    if let report {
                        integritySection(report)
                        findingsSection(report)
                        serverSection(report)
                        saveSection(report)
                    }

                    if let savedNote {
                        Text(savedNote)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.accent)
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
                        pollTask?.cancel()
                        if let onBackToHub {
                            onBackToHub()
                        } else if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if report == nil, let preloadedReport {
                    report = preloadedReport
                    lastFileName = preloadedReport.originalFileName
                    uiStatus = FirmwareAnalysisJobUIStatusMapper.resolve(
                        job: nil,
                        crypto: preloadedReport.crypto,
                        localOnlyFallback: .completed
                    )
                }
            }
            .onDisappear {
                pollTask?.cancel()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Firmware prüfen")
                .font(Theme.sectionTitle)
                .foregroundStyle(.white)
            Text("Ablauf: Datei wählen → SHA-256/MD5 → lokale Crypto-Prüfung → optional Server-Job → Befunde. Verschlüsselte Images werden nie als erfolgreich decompiliert angezeigt.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: FirmwareAnalysisJobUIStatus) -> some View {
        HStack(spacing: 8) {
            Text(status.token)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(statusColor(status))
            Text(status.labelDE)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusColor(_ status: FirmwareAnalysisJobUIStatus) -> Color {
        switch status {
        case .queued, .processing: return Theme.accent
        case .completed: return Theme.accent
        case .failed: return Theme.danger
        case .unsupported, .incomplete: return Theme.warn
        }
    }

    @ViewBuilder
    private func integritySection(_ report: FirmwareForensicReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Integrität")
                .font(Theme.sectionTitle)
                .foregroundStyle(.white)
            metaRow("Datei", report.originalFileName)
            metaRow("Archiv SHA-256", report.archiveDigest.sha256)
            metaRow("Archiv MD5", report.archiveDigest.md5)
            if let primary = report.entries.first(where: {
                $0.role == .firmPlain || $0.role == .firmEncrypted
            }) {
                metaRow("Payload SHA-256", primary.digest.sha256)
                metaRow("Payload MD5", primary.digest.md5)
            }
            metaRow("Crypto", report.crypto.status.label)
            metaRow("Format", report.crypto.detectedFormat)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func findingsSection(_ report: FirmwareForensicReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Befunde")
                .font(Theme.sectionTitle)
                .foregroundStyle(.white)
            Text(report.summary)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(report.verdictRationale)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if uiStatus == .incomplete || uiStatus == .unsupported {
                Text("Kein erfolgreiches Decompile: Status \(uiStatus?.token ?? "—"). Ciphertext/Unsupported wird nicht als COMPLETED dargestellt.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(report.evidence.prefix(12)) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(item.detail)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func serverSection(_ report: FirmwareForensicReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Server-Analyse")
                .font(Theme.sectionTitle)
                .foregroundStyle(.white)

            let client = FirmwareServerAnalysisClient.fromAppSettings()
            if !client.isConfigured {
                Text("Kein Analyse-Server konfiguriert (URL in Einstellungen). Lokale Ergebnisse bleiben gültig.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            } else if !client.hasAuthCredential {
                Text("Server-URL gesetzt, aber kein API-Token (Einstellungen). Job-Submit übersprungen.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.warn)
            } else {
                Button {
                    Task { await submitServerJob(for: report) }
                } label: {
                    Text(isServerBusy ? "Job läuft…" : "Analyse-Job starten")
                        .font(Theme.buttonSecondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isServerBusy || originalData == nil)

                if isServerBusy {
                    ProgressView(value: Double(serverJob?.progressPercent ?? 0), total: 100)
                        .tint(Theme.accent)
                }
                if let job = serverJob {
                    metaRow("Job", job.jobId)
                    metaRow("Wire-State", job.state.rawValue)
                    metaRow("Meldung", job.message)
                    if let err = job.errorCode, !err.isEmpty {
                        metaRow("Fehlercode", err)
                    }
                }
            }

            Text("Token/URL kommen aus App-Einstellungen — kein AuthSession-Secret in diesem Build.")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func saveSection(_ report: FirmwareForensicReport) -> some View {
        Button {
            onReportProduced?(report, originalData)
            savedNote = "Analyse an Untersuchung übergeben."
        } label: {
            Text("In Untersuchung speichern")
                .font(Theme.buttonSecondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
        .disabled(onReportProduced == nil)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openPicker() {
        FirmwareDocumentPickerPresenter.present(
            contentTypes: FirmwareDocumentTypes.subject
        ) { url in
            ingest(url: url)
        }
    }

    private func ingest(url: URL) {
        errorText = nil
        savedNote = nil
        serverJob = nil
        uiStatus = nil
        isBusy = true
        pollTask?.cancel()

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            isBusy = false
        }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            lastFileName = name
            originalData = data
            let outcome = FirmwareLocalAnalysisPipeline.analyze(
                fileName: name,
                data: data,
                vehicleContext: combinesWithReadout ? vehicleContext : nil
            )
            report = outcome.report
            uiStatus = outcome.uiStatus
        } catch {
            errorText = error.localizedDescription
            report = nil
        }
    }

    @MainActor
    private func submitServerJob(for report: FirmwareForensicReport) async {
        guard let originalData else {
            errorText = "Keine Originalbytes für Upload."
            return
        }
        let client = FirmwareServerAnalysisClient.fromAppSettings()
        guard client.isConfigured else {
            errorText = FirmwareServerAnalysisError.notConfigured.localizedDescription
            return
        }
        isServerBusy = true
        errorText = nil
        uiStatus = .queued
        defer { isServerBusy = false }

        let req = FirmwareAnalysisJobRequest(
            clientReportId: report.id,
            originalFileName: report.originalFileName,
            archiveSHA256: report.archiveDigest.sha256,
            payloadSHA256: report.deepAnalysis?.subjectSHA256,
            infoJSON: report.meta.rawInfoJSON,
            models: report.meta.models,
            controllerType: report.meta.type,
            allowDecrypt: true,
            allowLLM: appSettings.firmwareAnalysisAllowLLM
        )

        do {
            var status = try await client.submit(req, archiveData: originalData)
            serverJob = status
            uiStatus = FirmwareAnalysisJobUIStatusMapper.resolve(job: status, crypto: report.crypto)
            // Poll until terminal.
            while true {
                let mapped = FirmwareAnalysisJobUIStatusMapper.resolve(job: status, crypto: report.crypto)
                uiStatus = mapped
                switch mapped {
                case .queued, .processing:
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    status = try await client.poll(jobId: status.jobId)
                    serverJob = status
                    continue
                case .completed, .failed, .unsupported, .incomplete:
                    let merged = FirmwareLocalAnalysisPipeline.mergingServerResult(
                        into: report,
                        job: status
                    )
                    self.report = merged
                    // Re-resolve after merge (completeness / artifacts).
                    uiStatus = FirmwareAnalysisJobUIStatusMapper.resolve(
                        job: status,
                        crypto: merged.crypto
                    )
                    return
                }
            }
        } catch {
            errorText = error.localizedDescription
            uiStatus = .failed
        }
    }
}
