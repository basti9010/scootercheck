import SwiftUI

/// Anzeige für unbekannte / teilweise unterstützte E-Scooter — keine Fake-Diagnose.
struct UniversalDiagnosisView: View {
    let device: ScannedDevice
    var onNativeDump: (() -> Void)?
    var onSignalSearch: (() -> Void)?
    var onWatch: (() -> Void)?

    @ObservedObject private var registry = ScooterProtocolRegistry.shared
    @ObservedObject private var engine = ReadOnlyDiagnosticEngine.shared
    @StateObject private var gatt = BLEGattDeepAnalysis()
    @State private var assessment: UniversalScooterDetectionService.PassiveAssessment?
    @State private var onlineNote: String?
    @State private var showOnlineConsent = false
    @State private var isOnlineBusy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    header
                    if let a = assessment {
                        diagnosisStatus(a)
                        if let approval = a.approval {
                            approvalCard(approval)
                        }
                        stageNotes(a)
                    }
                    if let snap = engine.lastSnapshot {
                        snapshotCard(snap)
                    }
                    if let report = gatt.report {
                        gattSummary(report)
                    }
                    if case .failed(let msg) = gatt.phase {
                        Text(msg)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.danger)
                    }
                    if let onlineNote {
                        Text(onlineNote)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Theme.Space.xxl)
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Universelle Diagnose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear { refresh() }
            .onChange(of: gatt.phase) { _, phase in
                if case .done = phase, let report = gatt.report {
                    let snap = ReadOnlyDiagnosticEngine.shared.snapshotFromGatt(
                        analysis: report,
                        profile: assessment?.compatibility.profile
                    )
                    ReadOnlyDiagnosticEngine.shared.apply(snap)
                }
            }
            .onDisappear { gatt.cancel() }
            .confirmationDialog(
                "Online-Protokollsuche",
                isPresented: $showOnlineConsent,
                titleVisibility: .visible
            ) {
                Button("Zustimmen und suchen") {
                    Task { await runOnline() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Es werden nur technische Kennungen übertragen (Herstellerhinweis, Service-UUIDs, Namenspräfix). Keine vollständigen Gerätekennungen, keine Standorte. Unsignierte Treffer gelten nur als Recherchehinweis.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(assessment?.possibleScooter == true ? "Möglicher E-Scooter erkannt" : "BLE-Gerät")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textTitle)
            row("Hersteller", assessment?.manufacturer ?? "Nicht eindeutig")
            row("Modell", assessment?.model ?? "Nicht eindeutig identifiziert")
            row("Signal", assessment?.signalLabel ?? "—")
            Text(device.bleListDisplayName)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func diagnosisStatus(_ a: UniversalScooterDetectionService.PassiveAssessment) -> some View {
        let level = a.compatibility.supportLevel
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Diagnosestatus")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(level.label)
                .font(Theme.secondary)
                .foregroundStyle(level == .fullNative || level == .gattReadonly ? Theme.accent : Theme.textSecondary)
            if let profile = a.compatibility.profile {
                row("Profil", "\(profile.id) · \(profile.protocolVersion)")
                row("Unterstützung", profile.supportLevelLabel)
                if !profile.verified {
                    Text("Ungeprüfter Online-/Recherchetreffer — keine automatische Diagnose.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
            if !a.compatibility.matchedOn.isEmpty {
                Text("Treffer: \(a.compatibility.matchedOn.joined(separator: ", "))")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            ForEach(a.compatibility.blockers, id: \.self) { b in
                Text(b)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func approvalCard(_ match: VehicleApprovalMatch) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Zulassungsstatus (Katalog)")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(match.entry.germanApproval.label)
                .font(Theme.secondary)
                .foregroundStyle(match.entry.germanApproval.warrantsApprovalAlert ? Theme.danger : Theme.textSecondary)
            Text("\(match.entry.manufacturer) \(match.entry.model) · \(match.matchedOn)")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
            if !match.concreteVariant {
                Text("Modellzuordnung nicht eindeutig — keine pauschale Markeneinstufung.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func stageNotes(_ a: UniversalScooterDetectionService.PassiveAssessment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Analyseverlauf")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            ForEach(a.stageNotes, id: \.self) { n in
                Text("• \(n)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func snapshotCard(_ snap: ReadOnlyDiagnosticSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Ausgelesene Werte")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            ForEach(snap.values) { row in
                HStack {
                    Text(row.title)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text(row.value)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
            }
            ForEach(snap.evidenceNotes, id: \.self) { n in
                Text(n)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func gattSummary(_ report: BLEGattDeepAnalysis.Report) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GATT-Analyse")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("\(report.services.count) Dienste · \(report.characteristics.count) Characteristics")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.sm) {
            Button {
                showOnlineConsent = true
            } label: {
                actionLabel("Online-Protokoll suchen", busy: isOnlineBusy)
            }
            .buttonStyle(.bordered)
            .disabled(isOnlineBusy)

            Button {
                gatt.start(device: device)
            } label: {
                actionLabel("BLE-Daten analysieren (nur Lesen)", busy: false)
            }
            .buttonStyle(.bordered)
            .disabled({
                if case .connecting = gatt.phase { return true }
                if case .discovering = gatt.phase { return true }
                if case .reading = gatt.phase { return true }
                return false
            }())

            if let a = assessment {
                let plan = ReadOnlyDiagnosticEngine.shared.plan(for: a)
                Button {
                    startDiagnosis(a)
                } label: {
                    actionLabel("Diagnose starten / Scooter auslesen", busy: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!plan.canStart)
                Text(plan.reason)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if onWatch != nil {
                Button("Gerät beobachten") { onWatch?() }
                    .buttonStyle(.bordered)
            }
            if onSignalSearch != nil {
                Button("Signal suchen") { onSignalSearch?() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionLabel(_ title: String, busy: Bool) -> some View {
        HStack {
            if busy { ProgressView().tint(Theme.accent) }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.caption).foregroundStyle(Theme.textMuted)
            Spacer()
            Text(v).font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
        }
    }

    private func refresh() {
        _ = registry
        BLEIdentificationService.shared.ingest(device)
        assessment = UniversalScooterDetectionService.shared.assessPassively(device: device)
        if case .done = gatt.phase, let report = gatt.report {
            let profile = assessment?.compatibility.profile
            let snap = ReadOnlyDiagnosticEngine.shared.snapshotFromGatt(analysis: report, profile: profile)
            ReadOnlyDiagnosticEngine.shared.apply(snap)
        }
    }

    private func startDiagnosis(_ a: UniversalScooterDetectionService.PassiveAssessment) {
        switch a.compatibility.supportLevel {
        case .fullNative:
            onNativeDump?()
        case .gattReadonly, .verifiedProfile:
            gatt.start(device: device)
        default:
            onlineNote = a.compatibility.blockers.first ?? "Sichere Diagnose nicht möglich."
        }
    }

    private func runOnline() async {
        isOnlineBusy = true
        defer { isOnlineBusy = false }
        let id = BLEIdentificationService.shared.result(for: device.id)
        let outcome = await OnlineProtocolDiscoveryService.discover(
            .init(
                manufacturerHint: assessment?.manufacturer ?? id?.manufacturer,
                modelHint: assessment?.model ?? id?.model,
                serviceUUIDs: device.serviceUUIDs,
                companyId: id?.manufacturerCompanyId,
                localNamePrefix: String((device.cryptoName.isEmpty ? device.name : device.cryptoName).prefix(24))
            )
        )
        switch outcome {
        case .unavailable(let reason):
            onlineNote = reason
        case .researchHint(let title, let detail, let url):
            onlineNote = "\(title): \(detail)" + (url.map { " · \($0)" } ?? "") + " — nicht für automatische Diagnose freigegeben."
        case .profiles(let data, let signature):
            let requireSig = OnlineProtocolDiscoveryService.configuredEndpoint() != nil
            switch ScooterProtocolRegistry.shared.ingestOnlineProfiles(
                fileData: data,
                signatureHex: signature,
                requireSignature: requireSig
            ) {
            case .success(let n):
                onlineNote = "\(n) signierte Profile übernommen."
                refresh()
            case .failure(let msg):
                onlineNote = msg
            }
        }
    }
}

extension UniversalDiagnosisView {
    /// Nach GATT-Abschluss Snapshot erzeugen.
    func consumeGattIfReady() {
        guard case .done = gatt.phase, let report = gatt.report else { return }
        let snap = ReadOnlyDiagnosticEngine.shared.snapshotFromGatt(
            analysis: report,
            profile: assessment?.compatibility.profile
        )
        ReadOnlyDiagnosticEngine.shared.apply(snap)
    }
}
