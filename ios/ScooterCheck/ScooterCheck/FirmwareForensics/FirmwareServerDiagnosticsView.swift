import SwiftUI
import UniformTypeIdentifiers

/// Settings → Firmwareanalyse → Serverdiagnose.
/// Shows Server / TEA / Ghidra / Worker grades; refresh; admin selftest; export stub.
struct FirmwareServerDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    @State private var status: FirmwareDiagnosticsStatus?
    @State private var lastSelftest: FirmwareDiagnosticsSelftest?
    @State private var isRefreshing = false
    @State private var isStartingSelftest = false
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var exportDocument = DiagnosticsJSONDocument(data: Data())
    @State private var showExporter = false

    private var isAdmin: Bool { settings.isFirmwareDiagnosticsAdmin }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    header
                    componentSection
                    actionsSection
                    lastSelftestSection
                    exportSection
                    footnote
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
                .padding(.bottom, Theme.Space.xxl)
            }
        }
        // Settings root hides the nav bar; restore chrome so push-back works.
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Serverdiagnose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Theme.Icon.compact, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Zurück")
            }
        }
        .preferredColorScheme(.dark)
        .task { await refreshStatus(showBanner: false) }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "scootercheck-serverdiagnose.json"
        ) { result in
            switch result {
            case .success:
                banner = "Diagnosebericht exportiert."
                bannerIsError = false
            case .failure(let err):
                banner = err.localizedDescription
                bannerIsError = true
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Serverdiagnose")
                .font(Theme.pageTitle)
                .foregroundStyle(Theme.textTitle)

            Text("Status von Server, TEA, Ghidra und Worker. Flags allein sind nie VERIFIED — nur Selftest kann verifizieren.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let overall = status?.overallGrade {
                gradeBadge(overall, label: "Gesamt")
            }

            if let banner {
                Text(banner)
                    .font(Theme.caption)
                    .foregroundStyle(bannerIsError ? Theme.danger : Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Komponenten")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)

            let rows = FirmwareDiagnosticsStatusMapper.normalizedComponents(
                from: status ?? FirmwareDiagnosticsStatus()
            )
            ForEach(rows) { row in
                componentRow(row)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Aktionen")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)

            Button {
                Task { await refreshStatus(showBanner: true) }
            } label: {
                Label(
                    isRefreshing ? "Aktualisiere…" : "Status aktualisieren",
                    systemImage: "arrow.clockwise"
                )
                .font(Theme.buttonSecondary)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isRefreshing || isStartingSelftest)

            Button {
                Task { await startSelftest() }
            } label: {
                Label(
                    isStartingSelftest ? "Selftest läuft…" : "Selftest starten",
                    systemImage: "stethoscope"
                )
                .font(Theme.buttonSecondary)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(!isAdmin || isRefreshing || isStartingSelftest)

            if !isAdmin {
                Text("Selftest ist Admin-only. Trage unter Firmwareanalyse den dedizierten ADMIN_API_Token ein (nicht den gemeinsamen API-Token).")
                    .font(Theme.meta)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lastSelftestSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Letzter Selftest")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)

            if let last = lastSelftest {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    metaLine("ID", last.id)
                    if let state = last.state { metaLine("Status", state) }
                    if let grade = last.overallGrade {
                        HStack {
                            Text("Note")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                                .frame(width: 88, alignment: .leading)
                            gradeBadge(grade)
                        }
                    }
                    if let started = last.startedAt {
                        metaLine("Start", Self.dateFormatter.string(from: started))
                    }
                    if let finished = last.finishedAt {
                        metaLine("Ende", Self.dateFormatter.string(from: finished))
                    }
                    if let message = last.message, !message.isEmpty {
                        Text(message)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Space.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.Control.hairline)
                )
            } else {
                Text("Noch kein Selftest geladen. Admin: starten — oder Status aktualisieren, sobald die Route live ist.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Export")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)

            Button {
                Task { await exportReport() }
            } label: {
                Label("Bericht exportieren (Stub)", systemImage: "square.and.arrow.up")
                    .font(Theme.buttonSecondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(status == nil && lastSelftest == nil)
        }
    }

    private var footnote: some View {
        Text("Kein Shell-API, kein Env-Dump, keine Keys. Diagnose-Routen `/v1/diagnostics/*` können bis zur PM-Verdrahtung 404 liefern — dann greift der /health-Fallback.")
            .font(.caption2)
            .foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Rows

    private func componentRow(_ row: FirmwareDiagnosticsComponentStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.component.labelDE)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.sm)
                gradeBadge(row.grade)
            }
            if let detail = row.detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Space.cardPadding)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(row.grade.color.opacity(0.35), lineWidth: Theme.Control.hairline)
        )
    }

    private func gradeBadge(_ grade: FirmwareDiagnosticsGrade, label: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let label {
                Text(label)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
            }
            Text(grade.token)
                .font(Theme.badgeFont)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(grade.color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(grade.labelDE)
                .font(Theme.meta)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityLabel("\(label ?? "Note"): \(grade.labelDE)")
    }

    private func metaLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    @MainActor
    private func refreshStatus(showBanner: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        let client = FirmwareServerAnalysisClient.fromAppSettings()
        do {
            let next = try await client.diagnosticsStatus()
            status = next
            if showBanner {
                banner = next.message ?? "Status aktualisiert."
                bannerIsError = false
            }
        } catch {
            banner = error.localizedDescription
            bannerIsError = true
        }

        do {
            lastSelftest = try await client.diagnosticsLastSelftest()
        } catch FirmwareServerAnalysisError.routeNotAvailable {
            // Expected until PM wires routes — keep prior value.
            if lastSelftest == nil && showBanner == false {
                // silent
            }
        } catch FirmwareServerAnalysisError.adminRequired {
            // Non-admin: status via /health still works; last selftest stays empty.
        } catch {
            if banner == nil {
                banner = error.localizedDescription
                bannerIsError = true
            }
        }
    }

    @MainActor
    private func startSelftest() async {
        guard isAdmin else {
            banner = "Selftest nur mit Admin-Token."
            bannerIsError = true
            return
        }
        isStartingSelftest = true
        defer { isStartingSelftest = false }
        let client = FirmwareServerAnalysisClient.fromAppSettings()
        do {
            let started = try await client.diagnosticsStartSelftest()
            lastSelftest = started
            banner = "Selftest gestartet · \(started.id)"
            bannerIsError = false
        } catch {
            banner = error.localizedDescription
            bannerIsError = true
        }
    }

    @MainActor
    private func exportReport() async {
        let client = FirmwareServerAnalysisClient.fromAppSettings()
        let stub = await client.diagnosticsReportStub(status: status, lastSelftest: lastSelftest)
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(stub)
            exportDocument = DiagnosticsJSONDocument(data: data)
            showExporter = true
        } catch {
            banner = "Export fehlgeschlagen: \(error.localizedDescription)"
            bannerIsError = true
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()
}

// MARK: - File export helper

private struct DiagnosticsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
