import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BleClient()
    @ObservedObject private var history = ProtocolHistoryStore.shared
    @ObservedObject private var softUnlock = SoftUnlockSettings.shared
    @State private var profile: ScooterProfile = .maxG3D
    @State private var result: IntegrityResult?
    @State private var session: CheckSession?
    @State private var showMenu = false
    @State private var showFAQ = false
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
    /// Nach Aktivierungs-Scan automatisch Persistenz-Phase (Power-Cycle) anschließen.
    @State private var comparisonChainsPersistenz = false
    @State private var screen: AppScreen = .home
    @State private var pulse = false
    /// Nach der Auswertung: Kennzeichen/Nutzer erfassen, bevor das Protokoll erscheint.
    @State private var showSubjectPrompt = false
    @State private var pendingUnlockRescanAfterSubject = false
    /// Scooter gewählt → Profil bestätigen, dann auslesen.
    @State private var showProfileConfirm = false
    @State private var pendingDevice: ScannedDevice? = nil
    @State private var identifyBusy = false
    @State private var identifyNote: String? = nil
    /// Kurzer Glow-Boost im Sonar, wenn ein neues BLE-Gerät auftaucht.
    @State private var sonarDiscoveryFlash = false
    @State private var lastSonarDeviceCount = 0

    private enum AppScreen: Equatable {
        case home
        case result
        case overview
        case find
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

    /// Vergleichstest aktiv (Aktivierung und/oder Persistenz-Phase).
    private var isComparisonFlowActive: Bool {
        unlockRescanPhase != .idle || powerCyclePhase != .idle
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

    /// Idle-Start ohne Scan; Geräte-UI sobald gesucht wird oder Geräte da sind.
    private var showsStartLanding: Bool {
        screen == .home
            && !isBusyPhase
            && ble.phase != .scanning
            && ble.phase != .done
            && ble.visibleDevices.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.bg.ignoresSafeArea()

                if screen == .find {
                    ScooterFinderView(ble: ble)
                } else {
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
                            case .find:
                                EmptyView()
                            case .home:
                                if isBusyPhase {
                                    connectingCard
                                } else if showsStartLanding {
                                    startLanding
                                } else {
                                    devicesSearchHeader
                                    devicesSonarStage
                                    if ble.visibleDevices.isEmpty {
                                        searchEmptyCopy
                                    } else {
                                        deviceSection
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, showsStartLanding ? 120 : 28)
                    }
                }

                if showsStartLanding {
                    AnimatedSignalWaves()
                        .frame(height: 110)
                        .mask(
                            LinearGradient(
                                colors: [.clear, .white, .white],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)
                        .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if screen == .result {
                        Button {
                            persistCurrentSession()
                            goToOverview()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .accessibilityLabel("Prüfbericht schließen")
                    } else if !showMenu {
                        MenuGlyphButton {
                            withAnimation(.easeOut(duration: 0.22)) { showMenu = true }
                        }
                        .transition(.opacity)
                    }
                }
                ToolbarItem(placement: .principal) {
                    if screen == .overview {
                        Text("Prüfungen")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    } else if screen == .result {
                        Text("Prüfbericht")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    } else if screen == .find {
                        Text("Scooter finden")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    } else if showsStartLanding {
                        Wordmark(size: .headline)
                    } else if screen == .home {
                        Text("Geräte")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    } else {
                        Wordmark(size: .headline)
                    }
                }
            }
            .animation(.easeOut(duration: 0.22), value: showMenu)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .overlay { sideMenuOverlay }
            .sheet(isPresented: $showSubjectPrompt) { subjectPromptSheet }
            .sheet(isPresented: $showProfileConfirm, onDismiss: {
                if !busy { pendingDevice = nil }
            }) {
                profileConfirmSheet
            }
            .sheet(isPresented: $showFAQ) {
                FAQView()
            }
            .shareIntegrityPack(
                session: session ?? CheckSession(profile: profile),
                result: result ?? IntegrityAnalyzer.demoResult(.stock, profile: profile),
                isPresented: $showShare
            )
            .sharePackURLs(
                $historySharePack,
                subject: historySharePack.map {
                    "ScooterCheck Prüfbericht \($0.pdfURL.deletingPathExtension().lastPathComponent)"
                } ?? "ScooterCheck Prüfbericht",
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

    /// Startscreen laut Mockup: Hero, Statuskarte, Primär/Sekundär-Aktion.
    private var startLanding: some View {
        VStack(spacing: 22) {
            StartHeroGraphic()
                .padding(.top, 12)

            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("Kein Scooter verbunden")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(ble.statusMessage.isEmpty ? "Bereit zum Scan" : ble.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                ScootPrimaryButton(
                    title: "Scooter suchen",
                    systemImage: "magnifyingglass",
                    enabled: primaryEnabled,
                    busy: busy
                ) {
                    primaryAction()
                }

                ScootSecondaryButton(
                    title: "Prüfungen",
                    systemImage: "doc.text",
                    showsChevron: true
                ) {
                    screen = .overview
                }
            }
            .scootCard()

            AppCopyrightFooter()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var devicesSearchHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Geräte")
                    .font(Theme.pageTitle)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if ble.phase == .scanning {
                    HStack(spacing: 8) {
                        Text("Suche aktiv")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        RotatingSonarIcon(size: 22, isScanning: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Suche aktiv")
                }
            }

            Picker("Filter", selection: $ble.showOnlyLikelyScooters) {
                Text("Nur Scooter").tag(true)
                Text("Alle BLE").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }

    /// Zentrales Radar: dreht nur während des BLE-Scans.
    private var devicesSonarStage: some View {
        let scanning = ble.phase == .scanning
        let count = ble.visibleDevices.count
        return VStack(spacing: 12) {
            PulsingSearchGraphic(
                isScanning: scanning,
                deviceCount: max(count, scanning ? 4 : 0),
                discoveryFlash: sonarDiscoveryFlash,
                size: count == 0 ? 220 : 168
            )
            if scanning {
                Text(count == 0
                     ? "ScooterCheck sucht aktiv nach Geräten"
                     : (count == 1
                        ? "1 Gerät in Reichweite"
                        : "\(count) Geräte in Reichweite"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .onChange(of: ble.visibleDevices.count) { newCount in
            guard ble.phase == .scanning, newCount > lastSonarDeviceCount else {
                lastSonarDeviceCount = newCount
                return
            }
            lastSonarDeviceCount = newCount
            sonarDiscoveryFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                sonarDiscoveryFlash = false
            }
        }
        .onChange(of: ble.phase) { phase in
            if phase != .scanning {
                sonarDiscoveryFlash = false
            } else {
                lastSonarDeviceCount = ble.visibleDevices.count
            }
        }
    }

    private var searchEmptyCopy: some View {
        VStack(spacing: 14) {
            Text(ble.showOnlyLikelyScooters
                 ? "Kein kompatibler Scooter gefunden"
                 : "Keine Geräte gefunden")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Stelle sicher, dass dein Scooter eingeschaltet und in der Nähe ist.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if ble.showOnlyLikelyScooters {
                ScootPrimaryButton(title: "Alle BLE anzeigen", systemImage: "list.bullet") {
                    ble.showOnlyLikelyScooters = false
                }
            }
        }
        .frame(maxWidth: .infinity)
        .scootCard()
        .padding(.top, 4)
    }

    private var connectingCard: some View {
        VStack(spacing: 18) {
            SonarRadarView(
                isScanning: false,
                blipCount: 3,
                size: 148,
                style: .search,
                discoveryFlash: pulse
            )
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
        let listed = history.sortForScanList(ble.visibleDevices)
        return VStack(spacing: 10) {
            ForEach(Array(listed.enumerated()), id: \.element.id) { index, item in
                Button {
                    prepareProfileConfirm(for: item)
                } label: {
                    ScooterDeviceCard(
                        device: item,
                        knownAlias: history.knownAlias(for: item),
                        isNearest: index == 0 && listed.count > 1
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy || isBusyPhase)
            }
        }
        .padding(.top, 4)
    }

    private func resultCard(_ report: IntegrityResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                ScoreRing(score: report.score, color: Theme.verdict(report.verdict))
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.verdict.label)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.verdict(report.verdict))
                    Text(scoreCaption(for: report.score))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Text("Evidenz v\(report.evidence.catalogVersion) · FW \(StockFirmwareCatalog.provenanceLabel)")
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
            Text("Oben die Kurzfassung. Darunter nur Messwerte und Zusatzinfos — ohne Wiederholung derselben Auffälligkeit.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            subjectAssignmentCard

            ForEach(detailFactGroups, id: \.self) { group in
                let facts = compactDetailFacts(report.factGroups[group] ?? [])
                if !facts.isEmpty {
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

    /// Popup direkt nach der Auswertung — vor dem Protokoll.
    private var subjectPromptSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Zuordnung für dieses Protokoll. Alle Angaben freiwillig und nicht bewertungsrelevant.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("Fahrzeug / Person") {
                    TextField("Kennzeichen", text: subjectStringBinding(\.licensePlate))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Nachname", text: subjectStringBinding(\.lastName))
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                    TextField("Vorname", text: subjectStringBinding(\.firstName))
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                    Toggle("Geburtsdatum angeben", isOn: birthDateEnabledBinding)
                    if session?.subject.birthDate != nil {
                        DatePicker(
                            "Geburtsdatum",
                            selection: birthDateValueBinding,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }
                }
                if let summary = session?.subject.summaryLine {
                    Section {
                        Text(summary)
                            .font(.footnote.weight(.medium))
                    }
                }
            }
            .navigationTitle("Zuordnung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        abortSubjectPromptToOverview()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Zurück zur Prüfungsübersicht")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter zum Protokoll") { finishSubjectPrompt() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Überspringen") { finishSubjectPrompt() }
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    AppCopyrightFooter()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .interactiveDismissDisabled(true)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    /// Nachträgliche Bearbeitung im Protokoll — nicht bewertungsrelevant.
    private var subjectAssignmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zuordnung")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Kennzeichen / Nutzer — optional, jederzeit änderbar. Fließt nicht in die Bewertung ein.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Kennzeichen", text: subjectStringBinding(\.licensePlate))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .scootField()

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

            if let summary = session?.subject.summaryLine {
                Text(summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    /// Auswertung fertig → zuerst Zuordnungs-Popup, dann Protokoll.
    private func presentResultWithSubjectPrompt(triggerUnlockRescan: Bool = false, forcePrompt: Bool = true) {
        pendingUnlockRescanAfterSubject = triggerUnlockRescan
        let needsPrompt = forcePrompt || (session?.subject.isEmpty ?? true)
        if needsPrompt {
            showSubjectPrompt = true
        } else {
            screen = .result
            if triggerUnlockRescan, let analyzed = result {
                maybeStartUnlockRescanAfterTuning(analyzed)
            }
        }
    }

    private func finishSubjectPrompt() {
        persistCurrentSession()
        showSubjectPrompt = false
        screen = .result
        let shouldRescan = pendingUnlockRescanAfterSubject
        pendingUnlockRescanAfterSubject = false
        if shouldRescan, let analyzed = result {
            maybeStartUnlockRescanAfterTuning(analyzed)
        }
    }

    /// Zurück zur Prüfungsübersicht — vor dem Prüfbericht, Auslese bleibt gespeichert.
    private func abortSubjectPromptToOverview() {
        pendingUnlockRescanAfterSubject = false
        persistCurrentSession()
        showSubjectPrompt = false
        goToOverview()
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
        persistSession(current)
    }

    /// Speichert Protokoll; BLE-Wiedererkennung nur nach verifizierter Scooter-Auslese.
    private func persistSession(_ current: CheckSession) {
        let reading = current.result?.reading ?? current.reading
        guard ScooterVerification.isVerifiedScooterReading(reading) else {
            // Fehlversuch / Fremd-BLE: kein Protokoll, kein „bekannter Scooter“.
            return
        }
        // lastConnectedDevice kann nach einem späteren Fehlversuch (TV o.ä.) auf ein
        // Fremdgerät zeigen — UUID nur verknüpfen, wenn die Session noch authentifiziert
        // ist oder die Geräteidentität zur ausgelesenen SN passt.
        let candidate = ble.lastConnectedDevice ?? unlockRescanDevice ?? powerCycleDevice
        let device: ScannedDevice? = {
            guard let candidate else { return nil }
            if ble.lastConnectedDevice?.id == candidate.id, ble.isAuthenticatedForDump {
                return candidate
            }
            if ProtocolHistoryStore.deviceMatchesSerial(candidate, serial: reading.serialDisplay) {
                return candidate
            }
            if let unlock = unlockRescanDevice, unlock.id == candidate.id { return candidate }
            if let power = powerCycleDevice, power.id == candidate.id { return candidate }
            return nil
        }()
        try? history.save(current, scannedDevice: device)
    }

    /// Auffälligkeiten-Gruppe nur für Meta (Historie, Power-Cycle) — Klartext steht oben.
    private var detailFactGroups: [FactGroup] {
        [.evidence] + FactGroup.allCases.filter { $0 != .evidence }
    }

    /// Keine erneute Spiegelung von Kurzfassung / Attribution / redundanten Diffs.
    private func compactDetailFacts(_ facts: [MeasuredFact]) -> [MeasuredFact] {
        facts.filter { fact in
            switch fact.id {
            case "evidence.summary", "evidence.attribution":
                return false
            default:
                if fact.id.hasPrefix("diff.speed.") || fact.id.hasPrefix("diff.gear.") {
                    return false
                }
                // Positive Einzeiler nur in der Übersicht/PDF — Details bleiben Messwerte.
                if fact.id.hasPrefix("positive.") {
                    return false
                }
                return true
            }
        }
    }

    private func scoreCaption(for score: Int) -> String {
        let band: String
        switch score {
        case 80...100: band = "eher seriennah"
        case 50..<80: band = "gemischt / auffällig"
        default: band = "viele Abweichungen"
        }
        return "Seriennähe \(score)/100 — \(band). Hoch = unauffällig, niedrig = eher getunt. Das Urteil folgt festen Regeln, nicht dem Score."
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
        Group {
            if showsStartLanding || screen == .find {
                EmptyView()
            } else if screen == .result, result != nil {
                resultActionPanel
            } else {
                VStack(spacing: 10) {
                    if screen == .home, ble.phase == .scanning {
                        ScootOutlineButton(title: "Suche stoppen", systemImage: "stop.fill") {
                            primaryAction()
                        }
                    } else if screen == .home, ble.phase == .done {
                        ScootPrimaryButton(
                            title: "Manipulation prüfen",
                            systemImage: "checkmark.shield",
                            enabled: primaryEnabled,
                            busy: busy || isBusyPhase
                        ) {
                            primaryAction()
                        }
                    } else if screen == .overview {
                        ScootPrimaryButton(title: "Neue Prüfung", systemImage: "plus") {
                            primaryAction()
                        }
                    } else if screen == .home {
                        ScootPrimaryButton(
                            title: "Scooter suchen",
                            systemImage: "magnifyingglass",
                            enabled: primaryEnabled,
                            busy: busy || isBusyPhase
                        ) {
                            primaryAction()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(.ultraThinMaterial)
            }
        }
    }

    /// Unterer Aktionsbereich des Prüfberichts (Referenzlayout).
    private var resultActionPanel: some View {
        VStack(spacing: 10) {
            ScootActionPrimaryButton(
                title: "Bericht speichern",
                systemImage: "square.and.arrow.down",
                enabled: primaryEnabled,
                busy: busy && !isComparisonFlowActive
            ) {
                persistCurrentSession()
            }

            if unlockRescanPhase == .awaitUnlock || unlockRescanPhase == .scanningB {
                ScootActionPrimaryButton(
                    title: "Kombination eingegeben — erneut auslesen",
                    systemImage: "arrow.triangle.2.circlepath",
                    enabled: !busy,
                    busy: busy || unlockRescanPhase == .scanningB
                ) {
                    Task { await continueUnlockRescanScanB() }
                }
                Button("Vergleichstest abbrechen") {
                    cancelComparisonTest()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            } else if powerCyclePhase == .awaitReboot || powerCyclePhase == .scanningB {
                ScootActionPrimaryButton(
                    title: "Scooter ist wieder an — weiter",
                    systemImage: "bolt.horizontal.circle",
                    enabled: !busy,
                    busy: busy || powerCyclePhase == .scanningB
                ) {
                    Task { await continuePowerCycleScanB() }
                }
                Button("Persistenzprüfung überspringen") {
                    cancelPersistenzPhaseOnly()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            } else {
                ScootActionFeatureCard(
                    title: "Vergleichstest starten",
                    subtitle: "Ohne und mit Geheimkombination",
                    systemImage: "testtube.2",
                    enabled: !busy
                ) {
                    startComparisonTest()
                }
            }

            HStack(spacing: 10) {
                ScootActionChipButton(
                    title: "Teilen / AirDrop",
                    systemImage: "square.and.arrow.up"
                ) {
                    persistCurrentSession()
                    showShare = true
                }
                ScootActionChipButton(
                    title: "Zur Übersicht",
                    systemImage: "list.bullet.rectangle"
                ) {
                    persistCurrentSession()
                    goToOverview()
                }
            }
        }
        .padding(14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.card.opacity(0.92))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var primaryEnabled: Bool {
        switch screen {
        case .overview: return true
        case .result: return result != nil
        case .find: return true
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
        case .find:
            break
        case .home:
            if ble.phase == .scanning {
                ble.stopScan()
                return
            }
            if ble.phase == .done {
                if ScooterVerification.isVerifiedScooterReading(ble.reading) {
                    finalizeAnalysis()
                } else {
                    ble.markUnsupportedScooter(
                        "Kein unterstützter Scooter erkannt. Das ausgewählte Bluetooth-Gerät unterstützt das ScooterCheck-Protokoll nicht."
                    )
                }
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
            persistSession(current)
        } else {
            let newSession = CheckSession(
                id: result.sessionId,
                profile: profile,
                reading: result.reading,
                result: result
            )
            session = newSession
            persistSession(newSession)
        }
    }

    private func goToOverview() {
        cancelComparisonTest()
        discoveredUnlockCombo = nil
        result = nil
        session = nil
        screen = .overview
        history.reload()
    }

    private func startNewCheck() {
        result = nil
        session = nil
        cancelComparisonTest()
        discoveredUnlockCombo = nil
        ble.disconnect()
        screen = .home
        ble.startScan()
    }

    private func prepareProfileConfirm(for device: ScannedDevice) {
        let suggested = device.suggestedProfile
            ?? ScooterProfile.suggested(
                fromBluetoothName: device.cryptoName.isEmpty ? device.name : device.cryptoName
            )
            ?? profile
        profile = suggested
        pendingDevice = device
        identifyNote = nil
        identifyBusy = false
        showProfileConfirm = true
    }

    /// Bestätigung: erkanntes Modell + Profil, dann Auslese starten.
    private var profileConfirmSheet: some View {
        NavigationStack {
            Form {
                if let device = pendingDevice {
                    Section("Gerät") {
                        Text(deviceDisplayTitle(device))
                            .font(.headline)
                        if let model = device.modelLabel ?? device.modelBadge {
                            LabeledContent("Erkannt") {
                                Text(model)
                            }
                        } else {
                            Text("Modell nicht eindeutig aus dem Bluetooth-Namen erkannt — bitte Profil prüfen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let badge = device.modelBadge {
                            LabeledContent("Kurz") { Text(badge) }
                        }
                    }
                }

                Section {
                    Picker("Profil", selection: $profile) {
                        ForEach(ScooterProfile.allCases) { p in
                            Text(verbatim: "\(p.family.title) · \(p.shortLabel) · \(Int(p.ratedMaxKmh)) km/h")
                                .tag(p)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    LabeledContent("Aktuell") {
                        Text(verbatim: "\(profile.label)")
                    }

                    Text(profile.family.supportNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Vergleichsprofil")
                } footer: {
                    Text("Vorschlag aus Bluetooth-Name/SN. Nur ändern, wenn die Erkennung nicht stimmt — davon hängen Soll-Tempo und Auswertung ab.")
                }

                Section {
                    Button {
                        Task { await identifyPendingDevice() }
                    } label: {
                        HStack {
                            if identifyBusy {
                                ProgressView()
                            }
                            Text("Identifizieren")
                                .fontWeight(.semibold)
                            Spacer(minLength: 0)
                            Text("Piepton")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(pendingDevice == nil || busy || identifyBusy || isBusyPhase)

                    if let identifyNote, !identifyNote.isEmpty {
                        Text(identifyNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        guard let device = pendingDevice else { return }
                        showProfileConfirm = false
                        Task { await connectAndCheck(device) }
                    } label: {
                        Text("Auslesen starten")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(pendingDevice == nil || busy || identifyBusy || isBusyPhase)
                } footer: {
                    Text("Identifizieren verbindet kurz und löst Piep/Blinken aus (falls das Modell das unterstützt). Die Verbindung bleibt für „Auslesen starten“.")
                }
            }
            .navigationTitle("Profil bestätigen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        if identifyBusy || ble.isConnectedToScooter {
                            ble.disconnect()
                        }
                        showProfileConfirm = false
                        pendingDevice = nil
                        identifyNote = nil
                        identifyBusy = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(identifyBusy || busy)
    }

    private func identifyPendingDevice() async {
        guard let device = pendingDevice else { return }
        identifyBusy = true
        identifyNote = nil
        defer { identifyBusy = false }
        await ble.connectAndIdentify(to: device, profile: profile)
        if ble.phase == .failed {
            identifyNote = ble.lastError ?? ble.statusMessage
        } else {
            identifyNote = ble.statusMessage
        }
    }

    private func deviceDisplayTitle(_ device: ScannedDevice) -> String {
        if let compact = BleModelHint.compactScooterId(
            from: device.cryptoName.isEmpty ? device.name : device.cryptoName
        ) {
            return compact
        }
        return device.name
    }

    private func connectAndCheck(_ device: ScannedDevice) async {
        // Profil kommt aus der Bestätigungs-Maske (oder bleibt der letzte Vorschlag).
        // Nach Identifizieren kann die Enc2-Session schon stehen — kein zweites Pairing.
        busy = true
        result = nil
        defer {
            busy = false
            pendingDevice = nil
            identifyNote = nil
        }
        do {
            let reuse = ble.lastConnectedDevice?.id == device.id && ble.isAuthenticatedForDump
            if !reuse {
                try await ble.connect(to: device)
            }
            await ble.handshakeAndDump(profile: profile)
            if ble.phase == .done {
                // Nur nach technisch verifizierter Scooter-Auslese speichern/merken.
                if ScooterVerification.isVerifiedScooterReading(ble.reading) {
                    powerCycleDevice = device
                    finalizeAnalysis()
                } else {
                    // Verbunden, aber keine Scooter-Identität — nicht als bekannt speichern.
                    ble.markUnsupportedScooter(
                        "Kein unterstützter Scooter erkannt. Das ausgewählte Bluetooth-Gerät unterstützt das ScooterCheck-Protokoll nicht."
                    )
                }
            }
        } catch {
            // lastError already set by BleClient
        }
    }

    private var powerCycleBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vergleichstest · Schritt 3 von 3")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text("Neustart / Persistenzprüfung")
                .font(.subheadline.weight(.semibold))
            Text("Ausgangszustand und aktivierte Messung sind erfasst. Scooter regulär ausschalten, wieder einschalten, dann unten „weiter“. So prüft ScooterCheck, ob Änderungen nur temporär oder dauerhaft sind.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .scootCard()
    }

    private var unlockRescanBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vergleichstest · Schritt 2 von 3")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text(discoveredUnlockCombo == nil
                  ? "Aktivierung — Geheimkombination eingeben"
                  : "Gespeicherte Geheimkombination eingeben")
                .font(.subheadline.weight(.semibold))
            Text("Schritt 1 (Ausgangszustand) ist der aktuelle Prüfbericht. Jetzt den Scooter mit Geheimkombination aktivieren und erneut auslesen.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(discoveredUnlockCombo?.displayCode ?? softUnlock.unlockCodeSummary)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.accent)
            if let note = discoveredUnlockCombo?.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if discoveredUnlockCombo == nil {
                Text("Keine gespeicherte Kombination für diese Seriennummer. Kombination selbst am Scooter herausfinden, dann erneut auslesen. Bei Erfolg wird sie für diese SN gespeichert. Mehr dazu in der FAQ unter Soft Unlock.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(discoveredUnlockCombo?.entrySteps
                 ?? "Kombination am Scooter eingeben. Danach unten „erneut auslesen“ tippen. Anschließend folgt die Persistenzprüfung nach Neustart.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .scootCard()
    }

    /// Einstieg in den geführten Vergleichstest (Aktivierung → Persistenz).
    private func startComparisonTest() {
        comparisonChainsPersistenz = true
        startUnlockRescan()
    }

    private func cancelComparisonTest() {
        comparisonChainsPersistenz = false
        unlockRescanPhase = .idle
        unlockRescanScanA = nil
        unlockRescanDevice = nil
        unlockRescanHint = nil
        powerCyclePhase = .idle
        powerCycleScanA = nil
        powerCycleDevice = nil
        powerCycleHint = nil
    }

    /// Persistenz-Phase überspringen, Aktivierungs-Ergebnis behalten.
    private func cancelPersistenzPhaseOnly() {
        comparisonChainsPersistenz = false
        powerCyclePhase = .idle
        powerCycleScanA = nil
        powerCycleDevice = nil
        powerCycleHint = nil
    }

    private func startPowerCycleTest() {
        guard let report = result else { return }
        powerCycleScanA = report.reading
        powerCyclePhase = .awaitReboot
        // Gerät für Reconnect merken (falls noch in Scan-Liste / last connect).
        if let last = ble.visibleDevices.first {
            powerCycleDevice = last
        } else if let unlockDevice = unlockRescanDevice {
            powerCycleDevice = unlockDevice
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
            persistSession(newSession)
            powerCyclePhase = .idle
            powerCycleScanA = nil
            powerCycleDevice = nil
            comparisonChainsPersistenz = false
            presentResultWithSubjectPrompt(forcePrompt: false)
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
            persistSession(newSession)
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
            let shouldChainPersistenz = comparisonChainsPersistenz
            let deviceForPersistenz = device
            unlockRescanPhase = .idle
            unlockRescanScanA = nil
            unlockRescanDevice = nil
            if shouldChainPersistenz {
                // Schritt 3: Persistenz nach Neustart — bestehende Power-Cycle-Logik.
                unlockRescanDevice = deviceForPersistenz
                screen = .result
                startPowerCycleTest()
            } else {
                presentResultWithSubjectPrompt(forcePrompt: false)
            }
        } catch {
            unlockRescanPhase = .awaitUnlock
        }
    }

    private func finalizeAnalysis() {
        var reading = ble.reading
        guard ScooterVerification.isVerifiedScooterReading(reading) else {
            ble.markUnsupportedScooter(
                "Kein unterstützter Scooter erkannt. Das ausgewählte Bluetooth-Gerät unterstützt das ScooterCheck-Protokoll nicht."
            )
            return
        }
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
        persistSession(newSession)
        presentResultWithSubjectPrompt(triggerUnlockRescan: true)
    }

    /// Wenn Tuning erkannt wurde: geführten Vergleichstest (Aktivierung + Persistenz) starten.
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
        startComparisonTest()
    }

    // MARK: - Side menu (über dem aktuellen Bildschirm)

    private var sideMenuOverlay: some View {
        ZStack(alignment: .leading) {
            if showMenu {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.22)) { showMenu = false }
                    }
                    .transition(.opacity)

                sideMenuPanel
                    .frame(maxWidth: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Theme.card.ignoresSafeArea())
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.22), value: showMenu)
        .allowsHitTesting(showMenu)
    }

    private var sideMenuPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark(size: .headline)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.22)) { showMenu = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(8)
                }
                .accessibilityLabel("Menü schließen")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Text("Navigation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                sideNavRow(
                    title: "Geräte",
                    systemImage: "antenna.radiowaves.left.and.right",
                    selected: screen == .home
                ) {
                    navigateFromMenu(to: .home)
                }
                sideNavRow(
                    title: history.entries.isEmpty
                        ? "Prüfungen"
                        : "Prüfungen (\(history.entries.count))",
                    systemImage: "list.bullet.rectangle",
                    selected: screen == .overview
                ) {
                    navigateFromMenu(to: .overview)
                }
                if result != nil {
                    sideNavRow(
                        title: "Aktueller Prüfbericht",
                        systemImage: "doc.text",
                        selected: screen == .result
                    ) {
                        navigateFromMenu(to: .result)
                    }
                }
                sideNavRow(
                    title: "Scooter finden",
                    systemImage: "location.magnifyingglass",
                    selected: screen == .find
                ) {
                    navigateFromMenu(to: .find)
                }
                sideNavRow(
                    title: "FAQ & Wissensbasis",
                    systemImage: "questionmark.circle",
                    selected: false
                ) {
                    openFAQFromMenu()
                }
            }
            .padding(.horizontal, 12)

            Divider().overlay(Theme.line).padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if ble.isConnectedToScooter {
                        Button(role: .destructive) {
                            ble.disconnect()
                            result = nil
                            session = nil
                            navigateFromMenu(to: .home)
                        } label: {
                            Label("Trennen", systemImage: "xmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(Theme.danger)
                    }

                    AppCopyrightFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func openFAQFromMenu() {
        withAnimation(.easeOut(duration: 0.22)) { showMenu = false }
        showFAQ = true
    }

    private func sideNavRow(
        title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 22)
                Text(verbatim: title)
                    .font(.body.weight(selected ? .semibold : .regular))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(selected ? Theme.ink : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? Theme.accent : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func navigateFromMenu(to target: AppScreen) {
        withAnimation(.easeOut(duration: 0.22)) { showMenu = false }
        switch target {
        case .home:
            if screen == .result { persistCurrentSession() }
            screen = .home
            if ble.phase != .scanning, !isBusyPhase {
                ble.startScan()
            }
        case .overview:
            if screen == .result { persistCurrentSession() }
            goToOverview()
        case .result:
            guard result != nil else { return }
            screen = .result
        case .find:
            if screen == .result { persistCurrentSession() }
            // Finder nutzt Scan-only — aktive Diagnoseverbindung trennen.
            if ble.isConnectedToScooter {
                ble.disconnect()
            }
            screen = .find
            if ble.phase != .scanning {
                ble.startScan()
            }
        }
    }

    private var controlsOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prüfungen")
                    .font(Theme.pageTitle)
                    .foregroundStyle(.white)
                Text(
                    history.entries.isEmpty
                        ? "Noch keine gespeicherten Prüfungen"
                        : "\(history.entries.count) gespeicherte Prüfung\(history.entries.count == 1 ? "" : "en")"
                )
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            }

            if history.entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(Theme.muted)
                    Text("Noch keine Prüfungen")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Gespeicherte Prüfberichte erscheinen hier offline auf diesem Gerät.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scootCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(history.entries) { entry in
                        controlRow(entry)
                    }
                }
            }

            AppCopyrightFooter()
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func controlRow(_ entry: ProtocolHistoryStore.Entry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ScooterModelThumbnail(
                assetName: ScooterThumbnailAsset.name(for: entry.profile),
                width: 78,
                height: 70
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.protocolNumber)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    if let verdict = entry.verdict {
                        VerdictBadge(verdict: verdict)
                    }
                }
                Text("\(entry.profile.family.title) · \(Int(entry.profile.ratedMaxKmh)) km/h")
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let serial = entry.serialDisplay, !serial.isEmpty {
                    Text(serial)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if let subject = entry.subjectSummary ?? entry.knownLabel, !subject.isEmpty {
                    Text(subject)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
                HStack {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button {
                        shareHistoryEntry(entry)
                    } label: {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { openHistoryEntry(entry) }
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
        cancelComparisonTest()
        discoveredUnlockCombo = nil
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

}

/// SHU-ähnliche Gerätezeile: Bild · ID · Modell · Signalbalken.
struct ScooterDeviceCard: View {
    let device: ScannedDevice
    /// Gespeicherter Zuordnungsname / Kennzeichen aus früherem Protokoll.
    var knownAlias: String? = nil
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
        // G3-Serienpräfix 1C… auch ohne erkannten Badge dem Max-G3-Asset zuordnen.
        if displayId.uppercased().hasPrefix("1C") {
            return ScooterThumbnailAsset.maxG3
        }
        return ScooterThumbnailAsset.name(
            profile: device.suggestedProfile,
            family: device.suggestedProfile?.family,
            modelLabel: device.modelLabel,
            modelBadge: device.modelBadge
        )
    }

    var body: some View {
            HStack(spacing: 12) {
            Group {
                if device.looksLikeScooter || device.modelLabel != nil {
                    ScooterModelThumbnail(
                        assetName: thumbName,
                        width: 78,
                        height: 66,
                        cornerRadius: 12
                    )
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 78, height: 66)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.line.opacity(0.7), lineWidth: 1)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayId)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let knownAlias, !knownAlias.isEmpty {
                        Text("· \(knownAlias)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                Text(modelTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if knownAlias != nil {
                        Text("bekannt")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.warn.opacity(0.9))
                            .clipShape(Capsule())
                    }
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
                .stroke(knownAlias == nil ? Theme.line : Theme.accent.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            knownAlias.map { "\(modelTitle), \(displayId), \($0), \(device.signalLabel)" }
                ?? "\(modelTitle), \(displayId), \(device.signalLabel)"
        )
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

    private var showsExplanation: Bool {
        let e = fact.erlaeuterung.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return false }
        if e == fact.bewertung || e == fact.auslesewert || e == fact.title { return false }
        // Lange Analyse-Texte nur aufklappen, Messzeilen kurz halten.
        if fact.group == .speed || fact.group == .serial || fact.group == .odometer {
            return false
        }
        return e.count < 160
    }

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
                if showsExplanation {
                    Text(fact.erlaeuterung)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                        if !fact.erlaeuterung.isEmpty, !showsExplanation {
                            Text(fact.erlaeuterung)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                Text("Seriennähe")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityLabel("Seriennähe \(score) von 100")
    }
}

#Preview {
    ContentView()
}
