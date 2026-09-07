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
    @State private var showHistory = false
    @State private var historySharePack: ProtocolPack.PackURLs?
    @State private var showHistoryShare = false
    @State private var busy = false
    @State private var powerCyclePhase: PowerCyclePhase = .idle
    @State private var powerCycleScanA: IntegrityReading? = nil
    @State private var powerCycleDevice: ScannedDevice? = nil

    @State private var powerCycleHint: String? = nil

    private enum PowerCyclePhase: Equatable {
        case idle
        case awaitReboot
        case scanningB
    }
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let err = ble.lastError, ble.phase == .failed {
                        errorBanner(err)
                    }
                    if isBusyPhase {
                        connectingCard
                    } else if let result {
                        resultCard(result)
                    } else if ble.devices.isEmpty {
                        emptyState
                    }
                    // Geräteliste inkl. Filter auch zeigen, wenn „Nur Scooter“ leer filtert —
                    // sonst verschwindet der Umschalter und man kommt nicht zurück.
                    if !ble.devices.isEmpty && !isBusyPhase && result == nil {
                        deviceSection
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
                ToolbarItem(placement: .principal) { Wordmark(size: .headline) }
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
            .sheet(isPresented: $showHistory) { historySheet }
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
                    Text(report.verdict.laymanText)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !report.evidence.summary.isEmpty {
                        Text(report.evidence.summary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let attr = report.evidence.attribution {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vermutete Manipulationsart")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(attr.headline)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Konfidenz: \(attr.confidenceLabel) · heuristisch, nicht urteilsbildend")
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
            if let hint = powerCycleHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Ausgelesene Werte")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Bewertung ausschließlich durch EvidenceEngine (Katalog v\(report.evidence.catalogVersion)).")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            ForEach(FactGroup.allCases, id: \.self) { group in
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

            if result != nil {
                if powerCyclePhase == .idle {
                    Button("Power-Cycle-Test") {
                        startPowerCycleTest()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
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

                Button("Erneut prüfen") {
                    result = nil
                    session = nil
                    powerCyclePhase = .idle
                    powerCycleScanA = nil
                    ble.startScan()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private var primaryTitle: String {
        if result != nil { return "Bericht speichern" }
        if ble.phase == .scanning { return "Suche stoppen" }
        if ble.phase == .done { return "Manipulation prüfen" }
        return "Scooter suchen"
    }

    private var primaryColor: Color {
        if let result { return Theme.verdict(result.verdict) }
        return Theme.accent
    }

    private var primaryInk: Color {
        if result?.verdict == .eindeutig || result?.verdict == .hinweise { return .white }
        return Theme.ink
    }

    private var primaryEnabled: Bool {
        if result != nil { return true }
        if isBusyPhase || busy { return ble.phase == .scanning }
        return true
    }

    private func primaryAction() {
        if result != nil {
            showShare = true
            return
        }
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
            Text("Scan A ist gespeichert. Scooter regulär ausschalten, wieder einschalten, dann „Scan B“. Kein Unlock — nur Persistenzvergleich.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
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
        } catch {
            powerCyclePhase = .awaitReboot
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
                Section("Soft-Unlock") {
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
                    Text(softUnlock.detectionHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Keine Tastenkombinationen werden gesucht oder ausgeführt. Nachweis nach Ausschalten: gespeichertes Protokoll + persistente Marker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Protokollverlauf") {
                    Button {
                        showMenu = false
                        showHistory = true
                    } label: {
                        HStack {
                            Text("Offline-Verlauf")
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
                            showMenu = false
                        }
                    }
                }
                Section {
                    Button("Trennen", role: .destructive) {
                        ble.disconnect()
                        result = nil
                        session = nil
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

    private var historySheet: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Keine Protokolle")
                            .font(.headline)
                        Text("Abgeschlossene Prüfungen werden offline auf diesem Gerät gespeichert.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            historyRow(entry)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                history.delete(id: history.entries[index].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Protokollverlauf")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { showHistory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func historyRow(_ entry: ProtocolHistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.protocolNumber)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let verdict = entry.verdict {
                    Text(verdict.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.verdict(verdict))
                }
            }
            Text(entry.profile.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let serial = entry.serialDisplay, !serial.isEmpty {
                Text(serial)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Button("Öffnen") {
                    openHistoryEntry(entry)
                }
                .buttonStyle(.bordered)

                Button("AirDrop") {
                    shareHistoryEntry(entry)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func openHistoryEntry(_ entry: ProtocolHistoryStore.Entry) {
        guard let stored = history.loadSession(id: entry.id),
              let storedResult = stored.result else { return }
        profile = stored.profile
        session = stored
        result = storedResult
        showHistory = false
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
                if let evidenceClass = fact.evidenceClass {
                    Text("Einordnung: \(evidenceClass.label)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("Einordnung: \(fact.status.rawValue)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.fact(fact.status))
                }
                Text("Festgestellt: \(fact.auslesewert)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Erwartet: \(fact.sollwert)")
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
