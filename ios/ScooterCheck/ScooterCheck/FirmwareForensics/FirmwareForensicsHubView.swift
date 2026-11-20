import SwiftUI

/// Einstieg Firmware-Forensik: Datei allein oder mit Scooter-Auslese kombinieren.
enum FirmwareForensicsMode: Equatable, Sendable {
    /// Nur Datei / Server-Analyse, ohne Fahrzeugkontext.
    case fileOnly
    /// Datei + Live-Auslese (Dual-Source / Fahrzeugkontext).
    case withReadout
}

struct FirmwareForensicsHubView: View {
    var vehicleContext: FirmwareVehicleContext?
    /// `nil` = Hub zeigen; sonst direkt in den gewählten Modus.
    var initialMode: FirmwareForensicsMode? = nil
    var onClose: () -> Void
    var onReportProduced: ((FirmwareForensicReport, Data?) -> Void)? = nil
    var preloadedReport: FirmwareForensicReport? = nil

    @State private var mode: FirmwareForensicsMode?

    var body: some View {
        Group {
            if let mode {
                FirmwareZipInspectorView(
                    mode: mode,
                    vehicleContext: mode == .withReadout ? vehicleContext : nil,
                    onBackToHub: initialMode == nil ? { self.mode = nil } : nil,
                    onReportProduced: onReportProduced,
                    preloadedReport: preloadedReport
                )
            } else {
                NavigationStack {
                    hubContent
                }
            }
        }
        .onAppear {
            if mode == nil, let initialMode {
                mode = initialMode
            }
        }
    }

    private var hubContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                VStack(alignment: .leading, spacing: Theme.Space.titleStack) {
                    PageTitle(text: "Firmware-Forensik")
                    Text("Direktzugriff auf die vorhandene Analyse. Der empfohlene Einstieg ist „E-Scooter untersuchen“.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Space.listGap) {
                    ScootFunctionCard(
                        title: "Datei allein auswerten",
                        subtitle: "ZIP/ENC/BIN lokal und optional auf dem Server (Decrypt + Ghidra). Ohne Fahrzeugbezug.",
                        systemImage: "doc.text.magnifyingglass"
                    ) {
                        mode = .fileOnly
                    }

                    ScootFunctionCard(
                        title: "Mit Scooter-Auslese kombinieren",
                        subtitle: vehicleContext != nil
                            ? "Aktuelle Auslese ist vorhanden — Datei wird dem Fahrzeugkontext zugeordnet (Dual-Source)."
                            : "Zuerst einen E-Scooter auslesen, dann Firmware-Datei dazu legen.",
                        systemImage: "link"
                    ) {
                        mode = .withReadout
                    }
                }

                if vehicleContext == nil {
                    Text("Tipp: Für die Kombination unter „E-Scooter untersuchen“ den kombinierten Ablauf starten.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Auslese bereit: \(vehicleContext?.modelLabel ?? "Scooter") · \(vehicleContext?.serial ?? "ohne Seriennr.")")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AppCopyrightFooter()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Space.sm)
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
                Button("Schließen") { onClose() }
                    .foregroundStyle(Theme.accent)
            }
        }
        .preferredColorScheme(.dark)
    }
}
