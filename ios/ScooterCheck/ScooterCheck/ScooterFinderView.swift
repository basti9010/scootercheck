import SwiftUI

/// Geräteauswahl + Finder für „Scooter finden“.
struct ScooterFinderView: View {
    @ObservedObject var ble: BleClient
    @StateObject private var engine = ScooterFinderEngine()
    @State private var selected: ScannedDevice?
    @State private var showInfo = false
    /// Eigenständiger Modus — speichert kein Gerät als Scooter.
    @State private var showOnlyScooters = true
    /// Stabile Listenreihenfolge (RSSI darf zucken, Zeilen nicht dauernd tauschen).
    @State private var stableOrderIds: [UUID] = []
    @State private var lastStableReorderAt = Date.distantPast

    private var isFinding: Bool { selected != nil }

    private var filteredDevices: [ScannedDevice] {
        showOnlyScooters
            ? ble.devices.filter(\.looksLikeScooter)
            : ble.devices
    }

    /// Alle gescannten Advertiser bzw. nur Scooter-Heuristik — Reihenfolge hysterese-stabil.
    private var listedDevices: [ScannedDevice] {
        BleScanListStabilizer.apply(order: stableOrderIds, to: filteredDevices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selected, isFinding {
                finderContent(for: selected)
            } else {
                selectionContent
            }
        }
        .onAppear {
            if ble.phase != .scanning {
                ble.startScan()
            }
            reconcileStableOrder(force: true)
        }
        .onDisappear {
            engine.stop()
        }
        .onChange(of: ble.devices) { _ in
            reconcileStableOrder(force: false)
        }
        .onChange(of: showOnlyScooters) { _ in
            stableOrderIds = []
            lastStableReorderAt = .distantPast
            reconcileStableOrder(force: true)
        }
        .sheet(isPresented: $showInfo) {
            finderInfoSheet
        }
    }

    private func reconcileStableOrder(force: Bool) {
        let devices = filteredDevices
        let now = Date()
        let result = BleScanListStabilizer.reconcile(
            previousOrder: stableOrderIds,
            devices: devices,
            lastReorderAt: force ? .distantPast : lastStableReorderAt,
            now: now
        )
        stableOrderIds = result.order
        lastStableReorderAt = result.reorderAt
    }

    // MARK: - Selection

    private var selectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    PageTitle(text: "Scooter finden")
                    Text(showOnlyScooters
                         ? "Wähle einen Scooter. Anschließend schätzt ScooterCheck die bessere Signalrichtung anhand deiner Bewegung."
                         : "Wähle ein BLE-Signal zur Annäherung. Nicht jedes Gerät ist ein Scooter — es wird nichts als bekannter Scooter gespeichert.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textBody)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Suchmodus", selection: $showOnlyScooters) {
                    Text("Scooter").tag(true)
                    Text("Alle BLE-Geräte").tag(false)
                }
                .pickerStyle(.segmented)
                .font(Theme.segment)

                if !showOnlyScooters {
                    Text("Zeigt alle in der Umgebung erkannten BLE-Signale. Tippe ein Gerät an, um die Signalstärke zu verfolgen.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Label(
                        ble.phase == .scanning ? "Gerätesuche aktiv" : "Gerätesuche pausiert",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(Theme.secondary.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    Spacer()
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Hinweise zur Richtungsschätzung")
                }

                if listedDevices.isEmpty {
                    emptySelectionCard
                } else {
                    VStack(spacing: 10) {
                        ForEach(listedDevices) { device in
                            Button {
                                startFinding(device)
                            } label: {
                                finderDeviceRow(device)
                            }
                            .buttonStyle(.plain)
                            .opacity(device.isStale ? 0.45 : 1)
                        }
                    }
                }

                AppCopyrightFooter()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private var emptySelectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(showOnlyScooters
                 ? "Keine Scooter in Reichweite"
                 : "Keine BLE-Geräte in Reichweite")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(showOnlyScooters
                 ? "Halte das iPhone in der Nähe — oder wechsle zu „Alle BLE-Geräte“, falls die Erkennung unsicher ist."
                 : "Stelle sicher, dass Bluetooth aktiv ist und Geräte in der Nähe werben.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showOnlyScooters {
                ScootPrimaryButton(title: "Alle BLE-Geräte anzeigen", systemImage: "list.bullet") {
                    showOnlyScooters = false
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private func finderDeviceRow(_ device: ScannedDevice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle(device))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(finderDisplayId(device))
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(device.rssi) dBm")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Signal: \(device.finderSignalLabel)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                if !showOnlyScooters {
                    Text("ID \(device.bleIdentifierShort) · \(lastSeenLabel(device.lastSeen))")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                } else {
                    Text(lastSeenLabel(device.lastSeen))
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                if device.looksLikeScooter, !showOnlyScooters {
                    Text("Möglicherweise Scooter")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.9))
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 8)
            SignalStrengthView(rssi: device.rssi, style: .shu)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private func rowTitle(_ device: ScannedDevice) -> String {
        if let label = device.modelLabel { return label }
        if device.looksLikeScooter { return "Möglicher Scooter" }
        return device.bleListDisplayName
    }

    // MARK: - Finder

    private func finderContent(for device: ScannedDevice) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text(device.modelLabel
                             ?? (device.looksLikeScooter ? "Ausgewählter Scooter" : device.bleListDisplayName))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(finderDisplayId(device))
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.muted)
                        if !device.looksLikeScooter {
                            Text("Allgemeines BLE-Signal · keine Scooter-Speicherung")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    ZStack {
                        SonarRadarView(
                            isScanning: true,
                            blipCount: 4,
                            size: 230,
                            style: .search
                        )

                        if engine.phase == .proximity {
                            proximityPulse
                        } else if engine.showArrow, let deg = engine.relativeArrowDegrees {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 56, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .rotationEffect(.degrees(deg))
                                .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 2)
                                .accessibilityLabel("Signalrichtung")
                        } else {
                            ProgressView()
                                .tint(Theme.accent)
                                .scaleEffect(1.2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    VStack(spacing: 8) {
                        Text(engine.headline)
                            .font(Theme.sectionTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(engine.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if let footnote = engine.footnote {
                            Text(footnote)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 8)

                    metricsCard

                    if let hint = engine.authorizationHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    Button {
                        showInfo = true
                    } label: {
                        Label("Hinweise zur Richtungsschätzung", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }

            VStack(spacing: 10) {
                ScootOutlineButton(title: "Suche beenden", systemImage: "xmark") {
                    endFinding()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(Theme.bg.opacity(0.92))
        }
    }

    private var proximityPulse: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.35), lineWidth: 3)
                .frame(width: 120, height: 120)
            Circle()
                .fill(Theme.accent.opacity(0.18))
                .frame(width: 72, height: 72)
            Image(systemName: "wave.3.right")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("Sehr nah")
    }

    private var metricsCard: some View {
        VStack(spacing: 12) {
            HStack {
                metric(title: "RSSI", value: engine.rawRssi.map { "\($0) dBm" } ?? "—")
                Divider().overlay(Theme.line)
                metric(title: "Signal", value: engine.signalTier.label)
                Divider().overlay(Theme.line)
                metric(title: "Richtung", value: engine.quality.label)
            }
            .frame(maxWidth: .infinity)

            if let strongest = engine.strongestRssi {
                HStack {
                    Text("Stärkstes Signal bisher")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(Int(strongest.rounded())) dBm")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            if engine.movingAwayFromPeak, engine.phase != .proximity {
                Text("Signal wird schwächer — du entfernst dich vom stärksten bisherigen Signal.")
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .scootCard()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    /// Startet nur die RSSI-/Richtungs-Suche — speichert das Gerät nie als bekannten Scooter.
    private func startFinding(_ device: ScannedDevice) {
        selected = device
        if ble.phase != .scanning {
            ble.startScan()
        }
        engine.start(tracking: device.id, ble: ble)
    }

    private func endFinding() {
        engine.stop()
        selected = nil
        if ble.phase != .scanning {
            ble.startScan()
        }
    }

    private func finderDisplayId(_ device: ScannedDevice) -> String {
        if let compact = BleModelHint.compactScooterId(from: device.cryptoName.isEmpty ? device.name : device.cryptoName) {
            return compact
        }
        if device.cryptoName.isEmpty {
            return "\(device.bleListDisplayName) · \(device.bleIdentifierShort)"
        }
        return device.bleListDisplayName
    }

    private func lastSeenLabel(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 3 { return "Gerade eben" }
        if seconds < 60 { return "Vor \(Int(seconds)) s" }
        return "Zuletzt gesehen"
    }

    private var finderInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Die angezeigte Richtung wird aus Bluetooth-Signalstärke, Bewegung und Sensordaten geschätzt. Bluetooth liefert keine direkte Richtungsinformation.")
                        .font(.body)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("ScooterCheck nutzt Standort und Bewegungsrichtung nur während der aktiven Gerätesuche, um Änderungen der Signalstärke auszuwerten. Es werden keine Meter-Entfernungen angezeigt.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Unter „Alle BLE-Geräte“ kannst du jedes sichtbare BLE-Signal verfolgen. Das speichert das Gerät nicht als Scooter.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Hinweise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { showInfo = false }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
