import SwiftUI

/// Read-only Auslese eines Pedelec-BLE-Kandidaten (Standard-GATT, kein Bosch-Register-Dump).
struct PedelecReadoutView: View {
    let device: ScannedDevice
    let match: PedelecCandidateMatch
    var onDismiss: () -> Void

    @StateObject private var gatt = BLEGattDeepAnalysis()

    private var advertisement: ScannedPedelecAdvertisement {
        ScannedPedelecAdvertisement(device: device)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    header
                    matchCard
                    capabilityCard
                    gattCard
                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Pedelec auslesen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        gatt.cancel()
                        onDismiss()
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if case .idle = gatt.phase {
                    gatt.start(device: device)
                }
            }
            .onDisappear { gatt.cancel() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(device.name)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textTitle)
            Text("Pilotbezug: \(PedelecEvaluationCore.pilotGhostRiotEN.title) · \(PedelecEvaluationCore.pilotGhostRiotEN.motor) · Kiox 300")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            row("Signal", "\(device.rssi) dBm")
            if let mfg = device.manufacturerDataHex, !mfg.isEmpty {
                row("Manufacturer", mfg)
            }
            if let company = advertisement.manufacturerCompanyId {
                let name = BluetoothCompanyCatalog.shared.name(forCompanyId: company) ?? "unbekannt"
                row("Company-ID", String(format: "0x%04X · %@", company, name))
            }
        }
        .scootCard()
    }

    private var matchCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Erkennung", systemImage: "bicycle")
            Text("\(match.confidence.labelDE) · Score \(match.score)")
                .font(Theme.meta)
                .foregroundStyle(Theme.textSecondary)
            ForEach(match.reasons, id: \.self) { reason in
                Text("· \(reason)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scootCard()
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Was wird ausgelesen?", systemImage: "doc.text.magnifyingglass")
            Text(PedelecEvaluationCore.readoutCapabilitySummary)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scootCard()
    }

    @ViewBuilder
    private var gattCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                SectionHeader(title: "Standard-GATT (nur Lesen)", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                phaseLabel
            }

            if case .failed(let msg) = gatt.phase {
                Text(msg)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                ScootSecondaryButton(
                    title: "Erneut auslesen",
                    systemImage: "arrow.clockwise",
                    showsChevron: false
                ) {
                    gatt.start(device: device)
                }
            } else if let report = gatt.report {
                gattValues(report)
            } else if isBusy {
                Text("Verbinde und lese sichere Characteristics…")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScootSecondaryButton(
                    title: "Auslesen starten",
                    systemImage: "dot.radiowaves.left.and.right",
                    showsChevron: false
                ) {
                    gatt.start(device: device)
                }
            }
        }
        .scootCard()
    }

    private var isBusy: Bool {
        switch gatt.phase {
        case .connecting, .discovering, .reading: return true
        default: return false
        }
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch gatt.phase {
        case .idle:
            EmptyView()
        case .connecting:
            Text("Verbinden…").font(Theme.meta).foregroundStyle(Theme.accent)
        case .discovering:
            Text("Dienste…").font(Theme.meta).foregroundStyle(Theme.accent)
        case .reading:
            Text("Lesen…").font(Theme.meta).foregroundStyle(Theme.accent)
        case .done:
            Text("Fertig").font(Theme.meta).foregroundStyle(Theme.accent)
        case .failed:
            Text("Fehler").font(Theme.meta).foregroundStyle(Theme.danger)
        }
    }

    private func gattValues(_ report: BLEGattDeepAnalysis.Report) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let v = report.deviceName { row("GAP-Name", v) }
            if let v = report.manufacturerName { row("Hersteller", v) }
            if let v = report.modelNumber { row("Modell", v) }
            if let v = report.serialNumber { row("Serie", v) }
            if let v = report.firmwareRevision { row("Firmware", v) }
            if let v = report.hardwareRevision { row("Hardware", v) }
            Text("\(report.services.count) Dienste · \(report.characteristics.count) Characteristics")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 4)
            if report.manufacturerName == nil,
               report.modelNumber == nil,
               report.serialNumber == nil,
               report.firmwareRevision == nil {
                Text("Keine Device-Information freigegeben — typisch für Bosch Smart System ohne App-Pairing. Limit-/Tuning-Register sind so nicht erreichbar.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.meta)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(Theme.meta)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
