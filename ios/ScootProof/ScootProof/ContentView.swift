import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BleClient()
    @ObservedObject private var history = ProtocolHistoryStore.shared
    @ObservedObject private var softUnlock = SoftUnlockSettings.shared
    @State private var profile: ScooterProfile = .maxG3D
    @State private var result: IntegrityResult?
    @State private var session: CheckSession?
    @State private var showMenu = false
    @State private var showShare = false
    @State private var historySharePack: ProtocolPack.PackURLs?
    @State private var showHistoryShare = false
    @State private var busy = false
    @State private var powerCyclePhase: PowerCyclePhase = .idle
    @State private var powerCycleScanA: IntegrityReading? = nil
    @State private var powerCycleDevice: ScannedDevice? = nil
    @State private var powerCycleHint: String? = nil
    @State private var unlockRescanPhase: UnlockRescanPhase = .idle
    @State private var unlockRescanScanA: IntegrityReading? = nil
    @State private var unlockRescanDevice: ScannedDevice? = nil
    @State private var unlockRescanHint: String? = nil
    @State private var discoveredUnlockCombo: SoftUnlockCombo? = nil
    @State private var softUnlockStoreRevision = 0
    @State private var screen: AppScreen = .home
    @State private var pulse = false

    private enum AppScreen: Equatable {
        case home
        case result
        case overview
    }

    private enum PowerCyclePhase: Equatable {
        case idle
        case awaitReboot
        case scanningB
    }

    private enum UnlockRescanPhase: Equatable {
        case idle
        case awaitUnlock
        case scanningB
    }

    /// Seriennummer des aktuellen Scooters (Ergebnis oder laufende Auslese).
    private var currentScooterSerial: String? {
        let candidates = [
            result?.reading.serialDisplay,
            result?.reading.serialVcu,
            result?.reading.serialBle,
            session?.reading.serialDisplay,
            ble.reading.serialDisplay,
            ble.reading.serialVcu,
            unlockRescanScanA?.serialDisplay
        ]
        for value in candidates {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let err = ble.lastError, ble.phase == .failed, screen != .overview {
                        errorBanner(err)
                    }
                    switch screen {
                    case .overview:
                        controlsOverview
                    case .result:
                        if let result {
                            resultCard(result)
                        } else {
                            controlsOverview
                        }
                    case .home:
                        if isBusyPhase {
                            connectingCard
                        } else if ble.devices.isEmpty {
                            emptyState
                        }
                        if !ble.devices.isEmpty && !isBusyPhase {
                            deviceSection
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if screen == .overview {
                        Text("Kontrollen")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    } else {
                        Wordmark(size: .headline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showMenu = true } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .sheet(isPresented: $showMenu) { menuSheet }
            .shareIntegrityPack(
                session: session ?? CheckSession(profile: profile),
                result: result ?? IntegrityAnalyzer.demoResult(.stock, profile: profile),
                isPresented: $showShare
            )
            .sharePackURLs(
                $historySharePack,
                subject: historySharePack.map {
                    "ScooterCheck Protokoll \($0.pdfURL.deletingPathExtension().lastPathComponent)"
                } ?? "ScooterCheck Protokoll",
                isPresented: $showHistoryShare
            )
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var isBusyPhase: Bool {
        switch ble.phase {
        case .connecting, .detecting, .handshake, .waitingButton, .dumping: return true
        default: return false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Wordmark(size: .title)
            Text("Kein Scooter verbunden")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(ble.statusMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if !history.entries.isEmpty {
                Button("Kontrollen öffnen") {
                    screen = .overview
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var connectingCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.22), lineWidth: 8)
                    .frame(width: 128, height: 128)
                    .scaleEffect(pulse ? 1.12 : 0.92)
                Image("Logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            Text(connectTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            if ble.phase == .waitingButton {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "power").font(.title3)
                    Text("Power-Knopf drücken").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.black)
                .padding(14)
                .background(Theme.warn)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(ble.statusMessage)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            if ble.detectedStack != .unknown {
                Text("Stack: \(ble.detectedStack.label)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var connectTitle: String {
        switch ble.phase {
        case .waitingButton: return "Power-Knopf drücken"
        case .dumping: return "Diagnosefelder lesen"
        case .detecting: return "Protokoll erkennen"
        case .handshake: return "Authentifizieren"
        default: return "Verbinden"
        }
    }

    private var deviceSection: some View {
        let listed = ble.visibleDevices
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Geräte").font(.headline).foregroundStyle(.white)
                Spacer()
                Text(ble.phase == .scanning ? "sucht · Signal live" : "in der Nähe")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }

            Picker("Filter", selection: $ble.showOnlyLikelyScooters) {
                Text("Nur Scooter").tag(true)
                Text("Alle BLE").tag(false)
            }
            .pickerStyle(.segmented)

            if listed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ble.showOnlyLikelyScooters
                         ? "Kein Scooter gefunden."
                         : "Keine Geräte.")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    if ble.showOnlyLikelyScooters {
                        Button("Alle BLE anzeigen") {
                            ble.showOnlyLikelyScooters = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .scootCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(listed.enumerated()), id: \.element.id) { index, item in
                        Button {
                            Task { await connectAndCheck(item) }
                        } label: {
                            ScooterDeviceCard(
                                device: item,
                                isNearest: index == 0 && listed.count > 1
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || isBusyPhase)
                    }
                }
            }
        }
    }

    private func resultCard(_ report: IntegrityResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                ScoreRing(score: report.score, color: Theme.verdict(report.verdict))
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.verdict.label)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.verdict(report.verdict))
                    if report.trackMatch.trackId != .unknown && report.trackMatch.trackId != .stock {
                        Text(report.trackMatch.trackId.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    if let stackRaw = report.reading.bleStack,
                       let stack = BleStack(rawValue: stackRaw),
                       stack != .unknown {
                        Text("BLE: \(stack.label)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Text("Katalog v\(report.evidence.catalogVersion)")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.verdict == .stock ? "Ergebnis in Klartext" : "Was ist aufgefallen?")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        if report.evidence.problemBullets.isEmpty {
                            Text(report.evidence.problemOverview)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(Array(report.evidence.problemBullets.enumerated()), id: \.offset) { _, bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(Theme.accent)
                                    Text(bullet)
                                        .foregroundStyle(.white.opacity(0.92))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.footnote)
                            }
                            Text(report.verdict.laymanText)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)

                    if let attr = report.evidence.attribution {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vermutete Art der Veränderung")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(attr.headline)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Nur Einschätzung — kein Nachweis eines bestimmten Werkzeugs")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 4)
                    }
                    if let reset = report.facts.first(where: {
                        $0.id == "flag.session.reset"
                            && ($0.status == .abweichend || $0.status == .erheblichAbweichend)
                    }) {
                        Text(reset.bewertung)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if powerCyclePhase == .awaitReboot {
                powerCycleBanner
            }
            if unlockRescanPhase == .awaitUnlock {
                unlockRescanBanner
            }
            if let hint = powerCycleHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hint = unlockRescanHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Details zur Prüfung")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Zuerst die Auffälligkeiten in Klartext, darunter die ausgelesenen Werte. Technik hinter „Technische Details“.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            subjectAssignmentCard

            ForEach(detailFactGroups, id: \.self) { group in
                if let facts = report.factGroups[group], !facts.isEmpty {
                    Text(group.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                            if index > 0 { Divider().overlay(Theme.line) }
                            FactRow(fact: fact)
                        }
                    }
                }
            }
        }
        .scootCard()
    }

    /// Optionale Fahrer-/Kennzeichen-Zuordnung — nicht bewertungsrelevant.
    private var subjectAssignmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zuordnung (optional)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Nur zur Kontrolle / Zuordnung des Protokolls. Alle Felder freiwillig — fließen nicht in die Bewertung ein.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Nachname", text: subjectStringBinding(\.lastName))
                .textContentType(.familyName)
                .textInputAutocapitalization(.words)
                .scootField()

            TextField("Vorname", text: subjectStringBinding(\.firstName))
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .scootField()

            HStack {
                Toggle("Geburtsdatum", isOn: birthDateEnabledBinding)
                    .font(.footnote)
                    .foregroundStyle(.white)
                if session?.subject.birthDate != nil {
                    DatePicker(
                        "",
                        selection: birthDateValueBinding,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .colorScheme(.dark)
                }
            }

            TextField("Kennzeichen", text: subjectStringBinding(\.licensePlate))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .scootField()

            if let summary = session?.subject.summaryLine {
                Text(summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func subjectStringBinding(_ keyPath: WritableKeyPath<ProtocolSubject, String?>) -> Binding<String> {
        Binding(
            get: { session?.subject[keyPath: keyPath] ?? "" },
            set: { newValue in
                updateSubject { subject in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    subject[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    private var birthDateEnabledBinding: Binding<Bool> {
        Binding(
            get: { session?.subject.birthDate != nil },
            set: { enabled in
                updateSubject { subject in
                    if enabled {
                        if subject.birthDate == nil {
                            subject.birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
                        }
                    } else {
                        subject.birthDate = nil
                    }
                }
            }
        )
    }

    private var birthDateValueBinding: Binding<Date> {
        Binding(
            get: {
                session?.subject.birthDate
                    ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())
                    ?? Date()
            },
            set: { date in
                updateSubject { $0.birthDate = date }
            }
        )
    }

    private func updateSubject(_ mutate: (inout ProtocolSubject) -> Void) {
        guard var current = session else { return }
        mutate(&current.subject)
        current.subject = current.subject.sanitized()
        session = current
        try? history.save(current)
    }

    /// Auffälligkeiten zuerst, dann die übrigen Messgruppen.
    private var detailFactGroups: [FactGroup] {
        [.evidence] + FactGroup.allCases.filter { $0 != .evidence }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Fehler").font(.subheadline.weight(.semibold))
                Text(message).font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.danger)
        .scootCard()
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    if busy || isBusyPhase {
                        ProgressView().tint(primaryInk)
                    }
                    Text(primaryTitle).font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .background(primaryColor.opacity(primaryEnabled ? 1 : 0.35))
            .foregroundStyle(primaryInk)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(!primaryEnabled)

            if screen == .result, result != nil {
                if powerCyclePhase == .idle, unlockRescanPhase == .idle {
                    Button("Geheimkombination eingeben & auslesen") {
                        startUnlockRescan()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button("Power-Cycle-Test") {
                        startPowerCycleTest()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                } else if unlockRescanPhase == .awaitUnlock {
                    Button("Kombination eingegeben — erneut auslesen") {
                        Task { await continueUnlockRescanScanB() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(busy)

                    Button("Abbrechen") {
                        unlockRescanPhase = .idle
                        unlockRescanScanA = nil
                        unlockRescanDevice = nil
                        unlockRescanHint = nil
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                } else if powerCyclePhase == .awaitReboot {
                    Button("Scooter ist wieder an — Scan B") {
                        Task { await continuePowerCycleScanB() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(busy)

                    Button("Power-Cycle abbrechen") {
                        powerCyclePhase = .idle
                        powerCycleScanA = nil
                        powerCycleDevice = nil
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                }

                Button("Teilen / AirDrop") {
                    showShare = true
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)

                Button("Zur Übersicht") {
                    persistCurrentSession()
                    goToOverview()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private var primaryTitle: String {
        switch screen {
        case .overview:
            return "Neue Prüfung"
        case .result:
            return "Bericht speichern"
        case .home:
            if ble.phase == .scanning { return "Suche stoppen" }
            if ble.phase == .done { return "Manipulation prüfen" }
            return "Scooter suchen"
        }
    }

    private var primaryColor: Color {
        if screen == .result, let result { return Theme.verdict(result.verdict) }
        return Theme.accent
    }

    private var primaryInk: Color {
        if screen == .result, result?.verdict == .eindeutig || result?.verdict == .hinweise {
            return .white
        }
        return Theme.ink
    }

    private var primaryEnabled: Bool {
        switch screen {
        case .overview: return true
        case .result: return result != nil
        case .home:
            if isBusyPhase || busy { return ble.phase == .scanning }
            return true
        }
    }

    private func primaryAction() {
        switch screen {
        case .overview:
            startNewCheck()
        case .result:
            persistCurrentSession()
            goToOverview()
        case .home:
            if ble.phase == .scanning {
                ble.stopScan()
                return
            }
            if ble.phase == .done {
                finalizeAnalysis()
                return
            }
            result = nil
            session = nil
            ble.startScan()
        }
    }

    private func persistCurrentSession() {
        guard let result else { return }
        if var current = session {
            current.result = result
            current.subject = current.subject.sanitized()
            session = current
            try? history.save(current)
        } else {
            let newSession = CheckSession(
                id: result.sessionId,
                profile: profile,
                reading: result.reading,
                result: result
            )
            session = newSession
            try? history.save(newSession)
        }
    }

    private func goToOverview() {
        powerCyclePhase = .idle
        powerCycleScanA = nil
        powerCycleDevice = nil
        powerCycleHint = nil
        unlockRescanPhase = .idle
        unlockRescanScanA = nil
        unlockRescanDevice = nil
        unlockRescanHint = nil
        discoveredUnlockCombo = nil
        result = nil
        session = nil
        screen = .overview
        history.reload()
    }

    private func startNewCheck() {
        result = nil
        session = nil
        powerCyclePhase = .idle
        powerCycleScanA = nil
        powerCycleDevice = nil
        powerCycleHint = nil
        unlockRescanPhase = .idle
        unlockRescanScanA = nil
        unlockRescanDevice = nil
        unlockRescanHint = nil
        discoveredUnlockCombo = nil
        ble.disconnect()
        screen = .home
        ble.startScan()
    }

    private func connectAndCheck(_ device: ScannedDevice) async {
        if let suggested = device.suggestedProfile
            ?? ScooterProfile.suggested(fromBluetoothName: device.cryptoName.isEmpty ? device.name : device.cryptoName) {
            profile = suggested
        }
        busy = true
        result = nil
        defer { busy = false }
        do {
            try await ble.connect(to: device)
            await ble.handshakeAndDump(profile: profile)
            if ble.phase == .done {
                powerCycleDevice = device
                finalizeAnalysis()
            }
        } catch {
            // lastError already set by BleClient
        }
    }

    private var powerCycleBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Power-Cycle-Test").font(.subheadline.weight(.semibold))
            Text("Scan A ist gespeichert. Scooter regulär ausschalten, wieder einschalten, dann „Scan B“. Nur Persistenzvergleich.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .scootCard()
    }

    private var unlockRescanBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(discoveredUnlockCombo == nil
                  ? "Tuning erkannt — Geheimkombination selbst herausfinden"
                  : "Gespeicherte Geheimkombination eingeben")
                .font(.subheadline.weight(.semibold))
            Text(discoveredUnlockCombo?.displayCode ?? softUnlock.unlockCodeSummary)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.accent)
            if let note = discoveredUnlockCombo?.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if discoveredUnlockCombo == nil {
                Text("Keine gespeicherte Kombination für diese Seriennummer. Kombination selbst am Scooter herausfinden, in Soft-Unlock eintragen, dann erneut auslesen.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(discoveredUnlockCombo?.entrySteps
                 ?? "Kombination am Scooter eingeben. Danach „Kombination eingegeben — erneut auslesen“ tippen. Bei Erfolg wird sie für diese SN gespeichert.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if discoveredUnlockCombo == nil {
                Button("Kombination in Soft-Unlock eintragen…") {
                    showMenu = true
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .foregroundStyle(.white)
        .scootCard()
    }


    private func startPowerCycleTest() {
        guard let report = result else { return }
        powerCycleScanA = report.reading
        powerCyclePhase = .awaitReboot
        // Gerät für Reconnect merken (falls noch in Scan-Liste / last connect).
        if let last = ble.visibleDevices.first {
            powerCycleDevice = last
        }
        ble.disconnect()
        ble.startScan()
    }

    private func continuePowerCycleScanB() async {
        guard let scanA = powerCycleScanA else { return }
        busy = true
        powerCyclePhase = .scanningB
        defer { busy = false }
        do {
            let device: ScannedDevice
            if let chosen = powerCycleDevice ?? ble.visibleDevices.first {
                device = chosen
            } else {
                powerCycleHint = "Kein Scooter für Scan B gefunden — näher heran und erneut versuchen."
                powerCyclePhase = .awaitReboot
                return
            }
            powerCycleHint = nil
            try await ble.connect(to: device)
            await ble.handshakeAndDump(profile: profile)
            guard ble.phase == .done else {
                powerCyclePhase = .awaitReboot
                return
            }
            var readingB = ble.reading
            if readingB.serialExpected == nil {
                readingB.serialExpected = readingB.serialDisplay ?? scanA.serialDisplay
            }
            let pc = PowerCycleAnalyzer.compare(scanA: scanA, scanB: readingB, profile: profile)
            let serial = readingB.serialDisplay ?? readingB.serialVcu ?? scanA.serialDisplay
            let snapshot = history.priorSnapshot(forSerial: serial)
            let priorUnlock = history.priorUnlockEvidence(forSerial: serial)
            let analyzed = IntegrityAnalyzer.analyze(
                reading: readingB,
                profile: profile,
                priorUnlock: priorUnlock,
                priorReading: snapshot?.reading,
                priorProtocolNumber: snapshot?.protocolNumber,
                powerCycle: pc
            )
            result = analyzed
            let newSession = CheckSession(id: analyzed.sessionId, profile: profile, reading: readingB, result: analyzed)
            session = newSession
            try? history.save(newSession)
            powerCyclePhase = .idle
            powerCycleScanA = nil
            powerCycleDevice = nil
            screen = .result
        } catch {
            powerCyclePhase = .awaitReboot
        }
    }


    private func startUnlockRescan() {
        guard let report = result else { return }
        let serial = report.reading.serialDisplay
            ?? report.reading.serialVcu
            ?? report.reading.serialBle
        // Gespeicherte Kombination für diese SN auslesen — kein Katalog.
        if let stored = SoftUnlockComboStore.load(forSerial: serial) {
            discoveredUnlockCombo = stored
            softUnlock.apply(stored)
        } else {
            discoveredUnlockCombo = nil
            // Aktuelle Soft-Unlock-Einstellung bleibt Editier-Vorlage für den Nutzer.
        }
        unlockRescanScanA = report.reading
        unlockRescanPhase = .awaitUnlock
        unlockRescanHint = nil
        if let last = ble.visibleDevices.first {
            unlockRescanDevice = last
        } else if let pc = powerCycleDevice {
            unlockRescanDevice = pc
        }
        ble.disconnect()
        ble.startScan()
    }

    private func continueUnlockRescanScanB() async {
        guard let scanA = unlockRescanScanA else { return }
        busy = true
        unlockRescanPhase = .scanningB
        defer { busy = false }
        do {
            let device: ScannedDevice
            if let chosen = unlockRescanDevice ?? ble.visibleDevices.first {
                device = chosen
            } else {
                unlockRescanHint = "Kein Scooter für die Entsperr-Auslese gefunden — näher heran und erneut versuchen."
                unlockRescanPhase = .awaitUnlock
                return
            }
            unlockRescanHint = nil
            try await ble.connect(to: device)
            await ble.handshakeAndDump(profile: profile)
            guard ble.phase == .done else {
                unlockRescanPhase = .awaitUnlock
                return
            }
            var readingB = ble.reading
            if readingB.serialExpected == nil {
                readingB.serialExpected = readingB.serialDisplay ?? scanA.serialDisplay
            }
            let unlockReport = UnlockRescanReport.make(
                unlockCode: SoftUnlockSettings.unlockCodeSnapshot(),
                thresholdKmh: SoftUnlockSettings.thresholdKmhSnapshot(),
                before: scanA,
                after: readingB
            )
            let serial = readingB.serialDisplay ?? readingB.serialVcu ?? scanA.serialDisplay
            let snapshot = history.priorSnapshot(forSerial: serial)
            let priorUnlock = history.priorUnlockEvidence(forSerial: serial)
            let analyzed = IntegrityAnalyzer.analyze(
                reading: readingB,
                profile: profile,
                priorUnlock: priorUnlock,
                priorReading: snapshot?.reading,
                priorProtocolNumber: snapshot?.protocolNumber,
                unlockRescan: unlockReport
            )
            result = analyzed
            let newSession = CheckSession(id: analyzed.sessionId, profile: profile, reading: readingB, result: analyzed)
            session = newSession
            try? history.save(newSession)
            // Erfolgreiche Freischaltung → Kombination für diese SN speichern.
            let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
            let afterTempo = max(
                readingB.speedLimitKmh ?? 0,
                readingB.speedMaxKmh ?? 0,
                readingB.peakSpeedKmh ?? 0
            )
            if afterTempo >= threshold || readingB.hiddenTuningDetected == true {
                let combo = SoftUnlockCombo.fromSettings(
                    softUnlock,
                    note: "Bestätigt nach Zweitauslese (Limit/Peak ≥ \(Int(threshold)) km/h)."
                )
                SoftUnlockComboStore.save(combo, forSerial: serial)
                discoveredUnlockCombo = combo
                softUnlockStoreRevision += 1
            }
            unlockRescanPhase = .idle
            unlockRescanScanA = nil
            unlockRescanDevice = nil
            screen = .result
        } catch {
            unlockRescanPhase = .awaitUnlock
        }
    }

    private func finalizeAnalysis() {

        var reading = ble.reading
        if reading.serialExpected == nil, let sn = reading.serialDisplay {
            reading.serialExpected = sn
        }
        let serial = reading.serialDisplay ?? reading.serialVcu ?? reading.serialBle
        let snapshot = history.priorSnapshot(forSerial: serial)
        let priorUnlock = history.priorUnlockEvidence(forSerial: serial)
        let analyzed = IntegrityAnalyzer.analyze(
            reading: reading,
            profile: profile,
            priorUnlock: priorUnlock,
            priorReading: snapshot?.reading,
            priorProtocolNumber: snapshot?.protocolNumber
        )
        result = analyzed
        let newSession = CheckSession(id: analyzed.sessionId, profile: profile, reading: reading, result: analyzed)
        session = newSession
        try? history.save(newSession)
        screen = .result
        maybeStartUnlockRescanAfterTuning(analyzed)
    }

    /// Wenn Tuning erkannt wurde: gespeicherte Kombination laden bzw. Nutzer zur Eingabe führen, dann erneut auslesen.
    private func maybeStartUnlockRescanAfterTuning(_ analyzed: IntegrityResult) {
        guard unlockRescanPhase == .idle, powerCyclePhase == .idle else { return }
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let tempo = max(
            analyzed.reading.speedLimitKmh ?? 0,
            analyzed.reading.speedMaxKmh ?? 0,
            analyzed.reading.peakSpeedKmh ?? 0
        )
        let tuned = analyzed.reading.hiddenTuningDetected == true
            || tempo >= threshold
            || analyzed.verdict == .eindeutig
            || analyzed.verdict == .hinweise
        guard tuned else { return }
        startUnlockRescan()
    }

    private var menuSheet: some View {
        NavigationStack {
            List {
                Section("Soll-Profil") {
                    ForEach(ScooterFamily.allCases, id: \.self) { family in
                        VStack(alignment: .leading, spacing: 4) {
                            Picker(family.title, selection: $profile) {
                                ForEach(ScooterProfile.profiles(in: family)) { p in
                                    Text(p.shortLabel).tag(p)
                                }
                            }
                            Text(family.supportNote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section {
                    Toggle("Erkennung aktiv", isOn: $softUnlock.isEnabled)
                    Picker("Bedienung", selection: $softUnlock.control) {
                        ForEach(SoftUnlockControl.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if softUnlock.control == .custom {
                        TextField("Eigene Beschreibung", text: $softUnlock.customLabel)
                    } else {
                        Stepper("Wiederholungen: \(softUnlock.repetitions)×", value: $softUnlock.repetitions, in: 1...20)
                    }
                    Stepper(
                        "Schwelle: \(Int(softUnlock.speedThresholdKmh.rounded())) km/h",
                        value: Binding(
                            get: { softUnlock.speedThresholdKmh },
                            set: { softUnlock.speedThresholdKmh = $0 }
                        ),
                        in: 21...60,
                        step: 1
                    )
                    Text("Aktuell: \(softUnlock.unlockCodeSummary)")
                        .font(.subheadline.weight(.semibold))
                    if let serial = currentScooterSerial {
                        let _ = softUnlockStoreRevision
                        if let stored = SoftUnlockComboStore.load(forSerial: serial) {
                            Text("Gespeichert für \(serial): \(stored.displayCode)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Gespeicherte Kombination laden") {
                                softUnlock.apply(stored)
                                discoveredUnlockCombo = stored
                            }
                            Button("Gespeicherte Kombination löschen", role: .destructive) {
                                SoftUnlockComboStore.delete(forSerial: serial)
                                if discoveredUnlockCombo?.displayCode == stored.displayCode {
                                    discoveredUnlockCombo = nil
                                }
                                softUnlockStoreRevision += 1
                            }
                        } else {
                            Text("Noch keine Kombination für \(serial) gespeichert.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("Aktuelle Kombination für diese SN speichern") {
                            let combo = SoftUnlockCombo.fromSettings(softUnlock)
                            SoftUnlockComboStore.save(combo, forSerial: serial)
                            discoveredUnlockCombo = combo
                            softUnlockStoreRevision += 1
                        }
                    } else {
                        Text("Nach einer Auslese erscheint hier die Speicherung pro Seriennummer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(softUnlock.detectionHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Soft-Unlock / Geheimkombination")
                }
                Section("Kontrollen") {
                    Button {
                        showMenu = false
                        screen = .overview
                    } label: {
                        HStack {
                            Text("Übersicht")
                            Spacer()
                            Text("\(history.entries.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Beispiele") {
                    ForEach(IntegrityAnalyzer.DemoKind.allCases, id: \.rawValue) { kind in
                        Button(demoTitle(kind)) {
                            let reading = IntegrityAnalyzer.fillDemo(kind, profile: profile)
                            let analyzed = IntegrityAnalyzer.analyze(reading: reading, profile: profile)
                            result = analyzed
                            let newSession = CheckSession(
                                id: analyzed.sessionId,
                                profile: profile,
                                reading: reading,
                                result: analyzed
                            )
                            session = newSession
                            try? history.save(newSession)
                            screen = .result
                            showMenu = false
                        }
                    }
                }
                Section {
                    Button("Trennen", role: .destructive) {
                        ble.disconnect()
                        result = nil
                        session = nil
                        screen = .home
                        showMenu = false
                    }
                }
            }
            .navigationTitle("Menü")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { showMenu = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var controlsOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Durchgeführte Kontrollen")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Bericht speichern führt hierher. Tippe eine Kontrolle an, um sie zu öffnen — oder starte unten eine neue Prüfung.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if history.entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(Theme.muted)
                    Text("Noch keine Kontrollen")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Gespeicherte Prüfungen erscheinen hier offline auf diesem Gerät.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(Theme.line) }
                        controlRow(entry)
                    }
                }
            }
        }
        .scootCard()
    }

    @ViewBuilder
    private func controlRow(_ entry: ProtocolHistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.protocolNumber)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let verdict = entry.verdict {
                    Text(verdict.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.verdict(verdict))
                }
            }
            Text(entry.profile.label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            if let serial = entry.serialDisplay, !serial.isEmpty {
                Text(serial)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
            }
            if let subject = entry.subjectSummary, !subject.isEmpty {
                Text(subject)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            HStack {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("Tippen zum Öffnen")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Button {
                    shareHistoryEntry(entry)
                } label: {
                    Text("Teilen")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.leading, 8)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            openHistoryEntry(entry)
        }
        .contextMenu {
            Button("Öffnen") { openHistoryEntry(entry) }
            Button("Teilen") { shareHistoryEntry(entry) }
            Button("Löschen", role: .destructive) {
                history.delete(id: entry.id)
            }
        }
    }

    private func openHistoryEntry(_ entry: ProtocolHistoryStore.Entry) {
        guard let stored = history.loadSession(id: entry.id),
              let storedResult = stored.result else { return }
        profile = stored.profile
        session = stored
        result = storedResult
        powerCyclePhase = .idle
        powerCycleHint = nil
        screen = .result
    }

    private func shareHistoryEntry(_ entry: ProtocolHistoryStore.Entry) {
        do {
            historySharePack = try history.ensurePack(for: entry)
            showHistoryShare = true
        } catch {
            // ignore — pack missing
        }
    }

    private func demoTitle(_ kind: IntegrityAnalyzer.DemoKind) -> String {
        switch kind {
        case .stock: return "Serie"
        case .webapp: return "WebApp + Panic"
        case .shu: return "SHU / SN-Wechsel"
        case .shuDump: return "SHU + Dump"
        }
    }
}

struct Wordmark: View {
    var size: Font = .title
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Theme.accent)
            HStack(spacing: 0) {
                Text("Scooter").foregroundStyle(Theme.accent)
                Text("Check").foregroundStyle(.white)
            }
        }
        .font(size.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// SHU-ähnliche Gerätezeile: Bild · ID · Modell · Signalbalken.
struct ScooterDeviceCard: View {
    let device: ScannedDevice
    var isNearest: Bool = false

    private var displayId: String {
        if let compact = BleModelHint.compactScooterId(from: device.cryptoName.isEmpty ? device.name : device.cryptoName) {
            return compact
        }
        return device.name
    }

    private var modelTitle: String {
        device.modelLabel
            ?? (device.looksLikeScooter ? "Scooter" : "BLE-Gerät")
    }

    private var thumbName: String {
        if device.suggestedProfile?.family == .maxG3
            || device.modelBadge == "Max G3"
            || displayId.uppercased().hasPrefix("1C") {
            return "ScooterMaxG3"
        }
        if device.looksLikeScooter || device.modelLabel != nil {
            return "ScooterGeneric"
        }
        return "ScooterGeneric"
    }

    var body: some View {
            HStack(spacing: 12) {
            Group {
                if device.looksLikeScooter || device.modelLabel != nil {
                    Image(thumbName)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(Theme.muted)
                }
            }
                .frame(width: 64, height: 52)
                .padding(6)
                .background(Color.white.opacity(device.looksLikeScooter || device.modelLabel != nil ? 0.94 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayId)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(modelTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if device.looksLikeScooter || device.modelLabel != nil {
                        Label("Erkannt", systemImage: "bolt.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    if isNearest {
                        Text("nächstes")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                SignalStrengthView(rssi: device.rssi, style: .shu)
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(modelTitle), \(displayId), \(device.signalLabel)")
    }
}

struct SignalStrengthView: View {
    enum Style {
        case compact
        case shu
    }

    let rssi: Int
    var style: Style = .compact

    private var bars: Int {
        switch rssi {
        case -50...0: return 4
        case -65 ..< -50: return 3
        case -80 ..< -65: return 2
        default: return 1
        }
    }

    private var activeColor: Color {
        switch style {
        case .compact:
            return Theme.accent
        case .shu:
            switch bars {
            case 4: return Theme.accent
            case 3: return Color(red: 0.98, green: 0.62, blue: 0.22) // SHU-Orange
            case 2: return Theme.warn
            default: return Theme.danger
            }
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: style == .shu ? 2.5 : 2) {
            ForEach(1...4, id: \.self) { level in
                let step: CGFloat = style == .shu ? 3.5 : 3
                let base: CGFloat = style == .shu ? 7 : 6
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(level <= bars ? activeColor : Color.white.opacity(style == .shu ? 0.22 : 0.15))
                    .frame(
                        width: style == .shu ? 4.5 : 4,
                        height: base + CGFloat(level) * step
                    )
            }
        }
        .accessibilityLabel("Signalstärke \(bars) von 4")
    }
}

struct FactRow: View {
    let fact: MeasuredFact
    @State private var showTechnical = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.fact(fact.status))
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(fact.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(fact.erlaeuterung)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if fact.status != .regelkonform && fact.status != .nichtFeststellbar {
                    Text(statusPhrase)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.fact(fact.status))
                } else if let evidenceClass = fact.evidenceClass, evidenceClass != .info {
                    Text(evidenceClass.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text("Gefunden: \(fact.auslesewert)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Ab Werk erwartet: \(fact.sollwert)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                if fact.raw != nil || fact.sourceBoard != nil || fact.volatility != nil {
                    Button {
                        showTechnical.toggle()
                    } label: {
                        Text(showTechnical ? "Technische Details ausblenden" : "Technische Details")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if showTechnical {
                    VStack(alignment: .leading, spacing: 3) {
                        if let board = fact.sourceBoard {
                            Text("Quelle: \(board)" + (fact.sourceRegister.map { " / \($0)" } ?? ""))
                        }
                        if let hex = fact.rawHex {
                            Text("Rohwert: \(hex)")
                        }
                        Text("Interpretation: \(fact.auslesewert)")
                        Text("Soll: \(fact.sollwert)")
                        if let volatility = fact.volatility {
                            Text("Persistenz: \(volatility.label) · \(volatility.resetsOnPowerOffHint)")
                        }
                        if let evidenceClass = fact.evidenceClass {
                            Text("Technische Klasse: \(evidenceClass.label)")
                        }
                        Text("Status: \(fact.status.rawValue)")
                        if let raw = fact.raw, !raw.isEmpty {
                            Text(raw)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var statusPhrase: String {
        switch fact.status {
        case .abweichend: return "Auffällig"
        case .erheblichAbweichend: return "Deutlich abweichend"
        case .regelkonform: return "Unauffällig"
        case .nichtFeststellbar: return "Nicht feststellbar"
        }
    }

    private var icon: String {
        switch fact.status {
        case .regelkonform: return "checkmark.circle.fill"
        case .abweichend: return "exclamationmark.circle.fill"
        case .erheblichAbweichend: return "xmark.circle.fill"
        case .nichtFeststellbar: return "questionmark.circle"
        }
    }
}

struct ScoreRing: View {
    let score: Int
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("von 100")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 84, height: 84)
    }
}

#Preview {
    ContentView()
}
