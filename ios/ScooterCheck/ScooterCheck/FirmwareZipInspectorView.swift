import SwiftUI
import UniformTypeIdentifiers

/// Read-Only-Auswertung einer Firmware-/Flash-ZIP vom Gerät — kein Flashen.
struct FirmwareZipInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var report: FirmwareZipReport?
    @State private var errorText: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    intro
                    Button {
                        showImporter = true
                    } label: {
                        Label(report == nil ? "ZIP-Datei wählen" : "Andere ZIP wählen", systemImage: "doc.zipper")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isBusy)

                    if isBusy {
                        ProgressView("Werte ZIP aus…")
                            .font(Theme.caption)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let report {
                        reportBlock(report)
                    }
                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Firmware-ZIP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zip, .data, .archive],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    ingest(url: url)
                case .failure(let err):
                    errorText = err.localizedDescription
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Flash-ZIP auswerten")
                .font(Theme.sectionTitle)
                .foregroundStyle(.white)
            Text("ScooterCheck liest die ZIP nur aus (Metadaten, params.txt, Strings in FIRM.bin). Es wird nichts geflasht und nichts am Scooter verändert. Treffer zu Tastenkombinationen und Freischaltungen sind Hinweise aus dem Dateiinhalt — Wirkung am Fahrzeug muss per Auslese bestätigt werden.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func reportBlock(_ report: FirmwareZipReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text(report.summary)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            metaRow("Datei", report.fileName)
            metaRow("Format", report.formatLabel)
            if let n = report.displayName { metaRow("Name", n) }
            if let t = report.firmwareType { metaRow("Typ", t) }
            if !report.models.isEmpty { metaRow("Modelle", report.models.joined(separator: ", ")) }
            if !report.compatibleBoards.isEmpty {
                metaRow("Boards", report.compatibleBoards.joined(separator: ", "))
            }
            if let size = report.firmSizeBytes {
                metaRow("FIRM.bin", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            if let md5 = report.computedMd5 {
                let match = report.md5Matches.map { $0 ? " (stimmt mit info.json)" : " (weicht von info.json ab)" } ?? ""
                metaRow("MD5", String(md5.prefix(16)) + "…" + match)
            }

            if !report.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hinweise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                    ForEach(report.warnings, id: \.self) { w in
                        Text("• \(w)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.warn)
                    }
                }
            }

            if !report.findings.isEmpty {
                Text("Befunde")
                    .font(Theme.sectionTitle)
                ForEach(report.findings) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(f.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(f.confidence.label)
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        Text(f.detail)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Quelle: \(f.source) · \(kindLabel(f.kind))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(Theme.textMuted.opacity(0.25))
                }
            }

            if let params = report.paramsText, !params.isEmpty {
                DisclosureGroup("params.txt / Begleittext") {
                    Text(params)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                .foregroundStyle(Theme.accent)
            }
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
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(Theme.caption)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func kindLabel(_ kind: FirmwareZipReport.Finding.Kind) -> String {
        switch kind {
        case .metadata: return "Metadaten"
        case .unlockGesture: return "Geste / Freischaltung"
        case .speedLimit: return "Speed"
        case .featureFlag: return "Funktion"
        case .region: return "Region"
        case .customFirmware: return "Custom-FW"
        case .note: return "Notiz"
        }
    }

    private func ingest(url: URL) {
        errorText = nil
        isBusy = true
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let analyzed = FirmwareZipAnalyzer.analyze(fileName: name, data: data)
            report = analyzed
            if analyzed.findings.isEmpty && !analyzed.warnings.isEmpty {
                errorText = nil
            }
        } catch {
            report = nil
            errorText = error.localizedDescription
        }
        isBusy = false
    }
}
