import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BleClient()
    @ObservedObject private var history = ProtocolHistoryStore.shared
    @State private var profile: ScooterProfile = .zt3ProD
    @State private var result: IntegrityResult?
    @State private var session: CheckSession?
    @State private var showMenu = false
    @State private var showShare = false
    @State private var showHistory = false
    @State private var historySharePack: ProtocolPack.PackURLs?
    @State private var showHistoryShare = false
    @State private var busy = false
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
        case .connecting, .handshake, .waitingButton, .dumping: return true
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
            Text("Scooter eingeschaltet lassen. Bei Aufforderung einmal den Power-Knopf drücken.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if ble.phase == .waitingButton {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "power").font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Power-Knopf drücken").font(.subheadline.weight(.semibold))
                        Text("Einmal am Scooter. Die App wartet auf die Freigabe.")
                            .font(.footnote)
                            .foregroundStyle(.black.opacity(0.7))
                    }
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var connectTitle: String {
        switch ble.phase {
        case .waitingButton: return "Power-Knopf drücken"
        case .dumping: return "Diagnosefelder lesen"
        case .handshake: return "Authentifizieren"
        default: return "Verbinden"
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Geräte").font(.headline).foregroundStyle(.white)
                Spacer()
                Text(ble.phase == .scanning ? "sucht · Signal live" : "in der Nähe")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
            if ble.devices.count > 1 {
                Text("Bei mehreren Scootern: Gerät wegschieben — das richtige Signal wird schwächer oder verschwindet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            VStack(spacing: 0) {
                ForEach(Array(ble.devices.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(Theme.line)
                    }
                    Button {
                        Task { await connectAndCheck(item) }
                    } label: {
                        HStack(spacing: 14) {
                            SignalStrengthView(rssi: item.rssi)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(item.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                    if index == 0, ble.devices.count > 1 {
                                        Text("nächstes")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Theme.ink)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.accent)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("\(item.signalLabel) · \(item.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("Verbinden")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 14)
                    }
                    .disabled(busy || isBusyPhase)
                }
            }
            .padding(.horizontal, 4)
            .scootCard()
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
                    Text(report.verdict.laymanText)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Ausgelesene Werte")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Auslesewert, Sollwert, Bewertung und Erläuterung.")
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
                Button("Erneut prüfen") {
                    result = nil
                    session = nil
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
        if result?.verdict == .tuned { return .white }
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
        if let suggested = ScooterProfile.suggested(fromBluetoothName: device.name) {
            profile = suggested
        }
        busy = true
        result = nil
        defer { busy = false }
        do {
            try await ble.connect(to: device, preferXiaomi: !profile.usesNinebotEnc2)
            await ble.handshakeAndDump(profile: profile)
            if ble.phase == .done {
                finalizeAnalysis()
            }
        } catch {
            // lastError already set by BleClient
        }
    }

    private func finalizeAnalysis() {
        var reading = ble.reading
        if reading.serialExpected == nil, let sn = reading.serialDisplay {
            reading.serialExpected = sn
        }
        let analyzed = IntegrityAnalyzer.analyze(reading: reading, profile: profile)
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
                        Picker(family.title, selection: $profile) {
                            ForEach(ScooterProfile.profiles(in: family)) { p in
                                Text(p.shortLabel).tag(p)
                            }
                        }
                    }
                    if !profile.usesNinebotEnc2 {
                        Text("Xiaomi: Klartext-Protokoll (55 AA) über Nordic UART. Neuere Modelle mit 55 AB sind ggf. nicht auslesbar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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

struct SignalStrengthView: View {
    let rssi: Int

    private var bars: Int {
        switch rssi {
        case -50...0: return 4
        case -65 ..< -50: return 3
        case -80 ..< -65: return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(level <= bars ? Theme.accent : Color.white.opacity(0.15))
                    .frame(width: 4, height: CGFloat(6 + level * 3))
            }
        }
        .accessibilityLabel("Signalstärke \(bars) von 4")
    }
}

struct FactRow: View {
    let fact: MeasuredFact
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.fact(fact.status))
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(fact.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Auslesewert: \(fact.auslesewert)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Sollwert: \(fact.sollwert)")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Text("Bewertung: \(fact.status.rawValue)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.fact(fact.status))
                Text(fact.erlaeuterung)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
