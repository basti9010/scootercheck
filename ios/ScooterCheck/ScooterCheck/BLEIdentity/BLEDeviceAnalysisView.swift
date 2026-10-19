import SwiftUI

/// Technische Geräteanalyse für Signal-Finder / Gerätesuche.
struct BLEDeviceAnalysisView: View {
    let device: ScannedDevice
    var onSignalSearch: (() -> Void)?
    var onWatch: (() -> Void)?

    @ObservedObject private var identity = BLEIdentificationService.shared
    @StateObject private var gatt = BLEGattDeepAnalysis()
    @State private var showOnlineConsent = false
    @State private var expandRaw = false
    @State private var expandEvidence = true
    @State private var expandGatt = false
    @State private var expandFingerprint = false
    @State private var isReanalyzing = false
    @Environment(\.dismiss) private var dismiss

    private var fingerprint: BLEDeviceFingerprint {
        BLEDeviceFingerprint.from(device: device)
    }

    private var result: BLEIdentificationResult {
        identity.result(for: device.id)
            ?? BLEIdentificationResult.unknown(deviceId: device.id, displayName: device.bleListDisplayName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    headerCard
                    signalCard
                    identityCard
                    evidenceCard
                    fingerprintCard
                    observationCard
                    rawFeaturesCard
                    if let report = gatt.report {
                        gattReportCard(report)
                    }
                    if case .failed(let msg) = gatt.phase {
                        Text(msg)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actionsCard
                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Geräteanalyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                identity.ingest(device)
            }
            .onDisappear {
                gatt.cancel()
            }
            .confirmationDialog(
                "Online-Identifikation",
                isPresented: $showOnlineConsent,
                titleVisibility: .visible
            ) {
                Button("Zustimmen und recherchieren") {
                    identity.acceptOnlineConsent()
                    Task { await runOnline() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Es werden nur technische Kennungen übertragen (Company Identifier, Service-UUIDs, Namenspräfix). Keine Standorte, keine Scan-Historie, keine dauerhaften Geräte-IDs. Lokalanalyse bleibt ohne Netz möglich.")
            }
        }
    }

    // MARK: Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(result.listTitle)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textTitle)
            if let sub = result.listSubtitle {
                Text(sub)
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: Theme.Space.md) {
                metaChip("Klasse", result.deviceCategory?.label ?? "Unbekannt")
                metaChip("Zuverlässigkeit", result.confidence.label)
            }
            if let m = result.manufacturer {
                Text("Hersteller: \(m)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            if let model = result.model {
                Text("Modell: \(model)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var signalCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Signal")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Text("RSSI \(device.rssi) dBm")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                SignalStrengthView(rssi: device.rssi, style: .shu)
            }
            Text("Zuletzt \(device.lastSeen.formatted(date: .omitted, time: .shortened))")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Analyseergebnis")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(summaryText)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = result.onlineSourceNote {
                Text(note)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Quelle: \(sourceLabel)")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expandEvidence.toggle() }
            } label: {
                HStack {
                    Text("Warum diese Zuordnung?")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: expandEvidence ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)
            if expandEvidence {
                ForEach(result.evidence) { e in
                    evidenceRow(e, positive: true)
                }
                ForEach(result.contradictions) { e in
                    evidenceRow(e, positive: false)
                }
                if result.evidence.isEmpty, result.contradictions.isEmpty {
                    Text("Keine Evidenz vorhanden.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var fingerprintCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expandFingerprint.toggle() }
            } label: {
                HStack {
                    Text("Fingerprint")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: expandFingerprint ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)
            if expandFingerprint {
                rawLine("Structure Key", fingerprint.advertisingStructureKey.isEmpty ? "—" : fingerprint.advertisingStructureKey)
                rawLine(
                    "Manufacturer ID",
                    fingerprint.manufacturerId.map { String(format: "0x%04X", $0) } ?? "—"
                )
                rawLine(
                    "Services",
                    fingerprint.serviceUUIDs.isEmpty ? "—" : fingerprint.serviceUUIDs.joined(separator: ", ")
                )
                Text("Ähnlicher Fingerprint ist kein Beweis für dasselbe physische Gerät oder Modell.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var observationCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Zeitliche Beobachtung")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            if let obs = identity.observation, obs.deviceId == device.id, obs.isRunning {
                Text(String(format: "Noch %.0f s · %d Payload-Variante(n)", obs.remaining, obs.variantCount))
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.accent)
                ScootOutlineButton(title: "Abbrechen", systemImage: "stop.circle") {
                    identity.cancelTimedObservation()
                }
            } else if let obs = identity.observation, obs.deviceId == device.id, !obs.isRunning {
                Text("Abgeschlossen · \(obs.variantCount) Variante(n) · Analyse aktualisiert")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Advertising-Varianten über 30 s sammeln und Identifikation neu bewerten. Es werden keine Felder erfunden, die iOS nicht liefert.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let variants = identity.payloadVariantCount(for: device.id)
            if variants > 0, identity.observation?.deviceId != device.id || identity.observation?.isRunning != true {
                Text("Bisher \(variants) beobachtete Variante(n) in dieser Session.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var rawFeaturesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expandRaw.toggle() }
            } label: {
                HStack {
                    Text("Identifikationsmerkmale")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: expandRaw ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)
            if expandRaw {
                rawLine("Local Name", device.cryptoName.isEmpty ? "—" : device.cryptoName)
                rawLine(
                    "Company ID",
                    result.manufacturerCompanyId.map { String(format: "0x%04X", $0) } ?? "—"
                )
                rawLine("Manufacturer Data", device.manufacturerDataHex ?? "—")
                rawLine(
                    "Services",
                    device.serviceUUIDs.isEmpty ? "—" : device.serviceUUIDs.joined(separator: "\n")
                )
                if let sd = device.serviceDataHexByUUID, !sd.isEmpty {
                    rawLine(
                        "Service Data",
                        sd.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                    )
                }
                rawLine("TX Power", device.txPower.map(String.init) ?? "—")
                rawLine("Connectable", device.isConnectable.map { $0 ? "ja" : "nein" } ?? "—")
                rawLine("Peripheral ID", String(device.id.uuidString.prefix(8)) + "… (iOS, nicht MAC)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private func gattReportCard(_ report: BLEGattDeepAnalysis.Report) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expandGatt.toggle() }
            } label: {
                HStack {
                    Text("GATT-Analyse")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: expandGatt ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)
            if expandGatt {
                if let n = report.manufacturerName { rawLine("Manufacturer Name", n) }
                if let n = report.modelNumber { rawLine("Model Number", n) }
                if let n = report.firmwareRevision { rawLine("Firmware", n) }
                rawLine("Services", report.services.joined(separator: "\n"))
                ForEach(report.characteristics.prefix(40)) { ch in
                    Text("\(ch.uuid) · \(ch.properties)")
                        .font(Theme.caption.monospaced())
                        .foregroundStyle(Theme.textMuted)
                    if let v = ch.valueText {
                        Text(v)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var actionsCard: some View {
        VStack(spacing: Theme.Space.sm) {
            ScootOutlineButton(
                title: isReanalyzing ? "Analysiere…" : "Erneut analysieren",
                systemImage: "arrow.clockwise"
            ) {
                guard !isReanalyzing else { return }
                Task { await reanalyze(online: false) }
            }
            .opacity(isReanalyzing ? 0.45 : 1)
            ScootOutlineButton(
                title: "Online recherchieren",
                systemImage: "globe"
            ) {
                guard !isReanalyzing else { return }
                if identity.settings.onlineConsentAccepted {
                    Task { await runOnline() }
                } else {
                    showOnlineConsent = true
                }
            }
            ScootOutlineButton(
                title: observationButtonTitle,
                systemImage: "timer"
            ) {
                if identity.observation?.deviceId == device.id, identity.observation?.isRunning == true {
                    identity.cancelTimedObservation()
                } else {
                    identity.startTimedObservation(deviceId: device.id, duration: 30)
                }
            }
            ScootOutlineButton(
                title: gattButtonTitle,
                systemImage: "cable.connector"
            ) {
                guard gatt.phase != .connecting,
                      gatt.phase != .discovering,
                      gatt.phase != .reading else { return }
                gatt.start(device: device)
            }
            if let onSignalSearch {
                ScootOutlineButton(title: "Signal suchen", systemImage: "dot.radiowaves.left.and.right") {
                    onSignalSearch()
                    dismiss()
                }
            }
            if let onWatch {
                ScootOutlineButton(title: "Gerät beobachten", systemImage: "eye") {
                    onWatch()
                    dismiss()
                }
            }
        }
    }

    // MARK: Helpers

    private var observationButtonTitle: String {
        if identity.observation?.deviceId == device.id, identity.observation?.isRunning == true {
            return "Beobachtung abbrechen"
        }
        return "30 Sekunden analysieren"
    }

    private var gattButtonTitle: String {
        switch gatt.phase {
        case .connecting, .discovering, .reading: return "GATT-Analyse läuft…"
        case .failed: return "GATT fehlgeschlagen — erneut"
        case .done: return "GATT erneut analysieren"
        case .idle: return "Vertiefte BLE-Analyse"
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        if let m = result.manufacturer {
            parts.append("Möglicher Hersteller: \(m).")
        } else {
            parts.append("Hersteller nicht identifiziert.")
        }
        if let c = result.deviceCategory, c != .unknown {
            parts.append("Mögliche Geräteklasse: \(c.label).")
        } else {
            parts.append("Geräteklasse nicht eindeutig bestimmbar.")
        }
        if let model = result.model {
            parts.append("Modellhinweis: \(model).")
        } else {
            parts.append("Modell: nicht bestimmbar.")
        }
        return parts.joined(separator: " ")
    }

    private var sourceLabel: String {
        switch result.source {
        case .local: return "Lokal"
        case .online: return "Online"
        case .gatt: return "GATT"
        case .combined: return "Lokal + Online"
        }
    }

    private func metaChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.Control.hairline)
        )
    }

    private func evidenceRow(_ e: IdentificationEvidence, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((positive ? "• " : "− ") + e.title)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(positive ? Theme.textPrimary : Theme.danger)
            Text(e.detail)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func rawLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.caption.monospaced())
                .foregroundStyle(Theme.textMuted)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func reanalyze(online: Bool) async {
        isReanalyzing = true
        _ = await identity.reanalyze(device, includeOnline: online)
        isReanalyzing = false
    }

    private func runOnline() async {
        isReanalyzing = true
        _ = await identity.reanalyze(device, includeOnline: true)
        isReanalyzing = false
    }
}
