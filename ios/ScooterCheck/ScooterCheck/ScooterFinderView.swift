import SwiftUI

/// Geräteauswahl + professionelle BLE-Heatmap-Suche („Scooter finden“).
struct ScooterFinderView: View {
    @ObservedObject var ble: BleClient
    @StateObject private var searchEngine = BLESearchEngine()
    @StateObject private var multiMonitor = BLEMultiDeviceMonitor()
    @ObservedObject private var radar = BLERadarService.shared
    @State private var selected: ScannedDevice?
    @State private var showInfo = false
    @State private var showMultiPicker = false
    @State private var multiSelectedIds: Set<UUID> = []
    @State private var radarBrowseMode = false
    /// Eigenständiger Modus — speichert kein Gerät als Scooter.
    @State private var showOnlyScooters = true
    /// Stabile Listenreihenfolge (RSSI darf zucken, Zeilen nicht dauernd tauschen).
    @State private var stableOrderIds: [UUID] = []
    @State private var lastStableReorderAt = Date.distantPast

    private var isFinding: Bool { selected != nil && searchEngine.isActive }
    private var isObserving: Bool { multiMonitor.isActive }
    private var isRadarBrowsing: Bool { radarBrowseMode && radar.isEnabled && !isFinding && !isObserving }

    private var filteredDevices: [ScannedDevice] {
        showOnlyScooters
            ? ble.devices.filter(\.looksLikeScooter)
            : ble.devices
    }

    private var listedDevices: [ScannedDevice] {
        BleScanListStabilizer.apply(order: stableOrderIds, to: filteredDevices)
    }

    var body: some View {
        Group {
            if isFinding {
                BLESearchScreen(engine: searchEngine) {
                    endFinding()
                }
            } else if isObserving {
                BLEMultiDeviceScreen(monitor: multiMonitor) {
                    multiSelectedIds = []
                }
            } else if isRadarBrowsing {
                radarBrowseContent
            } else {
                selectionContent
            }
        }
        .onAppear {
            if ble.phase != .scanning {
                ble.startScan()
            }
            BLERadarService.shared.attach(ble: ble)
            reconcileStableOrder(force: true)
        }
        .onDisappear {
            if searchEngine.isActive {
                searchEngine.stop(discardSession: true)
            }
            if multiMonitor.isActive {
                multiMonitor.stop()
            }
            if radarBrowseMode {
                radar.endSession()
                radarBrowseMode = false
            }
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
        .sheet(isPresented: $showMultiPicker) {
            BLEMultiDevicePicker(
                devices: listedDevices,
                selectedIds: $multiSelectedIds,
                onStart: {
                    let picked = listedDevices.filter { multiSelectedIds.contains($0.id) }
                    showMultiPicker = false
                    guard picked.count >= 2 else { return }
                    if ble.phase != .scanning { ble.startScan() }
                    multiMonitor.start(devices: picked, ble: ble)
                },
                onCancel: {
                    showMultiPicker = false
                    multiSelectedIds = []
                }
            )
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
                         ? "Wähle einen Scooter. ScooterCheck baut während du gehst eine Signal-Heatmap auf — ohne falsche Richtungsversprechen."
                         : "Wähle ein BLE-Signal. Die Suche speichert das Gerät nicht als Scooter und zeigt relative Signalstärke als Heatmap.")
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
                    Text("Zeigt alle erkannten BLE-Signale. Tippe ein Gerät an, um die Heatmap-Suche zu starten.")
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
                    .accessibilityLabel("Hinweise zur Heatmap-Suche")
                }

                Button {
                    startRadarBrowse()
                } label: {
                    Label("Radar starten", systemImage: "dot.radiowaves.left.and.right")
                        .font(Theme.secondary.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Startet die BLE-Suche und meldet plausible E-Scooter mit ausreichendem Signal.")

                if listedDevices.count >= 2 {
                    Button {
                        multiSelectedIds = []
                        showMultiPicker = true
                    } label: {
                        Label("Geräte beobachten", systemImage: "eyeglasses")
                            .font(Theme.secondary.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Theme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Mehrere BLE-Geräte gleichzeitig beobachten, ohne sie als Scooter zu speichern.")
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
                                    .overlay(alignment: .topTrailing) {
                                        if radar.highlightDeviceIds.contains(device.id) {
                                            BLERadarHitBadge()
                                                .padding(10)
                                        }
                                    }
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

    // MARK: - Actions

    /// Startet Heatmap-Suche — speichert das Gerät nie als bekannten Scooter.
    private func startFinding(_ device: ScannedDevice) {
        radarBrowseMode = false
        selected = device
        if ble.phase != .scanning {
            ble.startScan()
        }
        radar.startSession(enableRadar: radar.isEnabled)
        searchEngine.start(device: device, ble: ble)
        BLESearchLiveActivityController.shared.start(deviceName: device.bleListDisplayName)
    }

    private func endFinding() {
        selected = nil
        radar.endSession()
        BLESearchLiveActivityController.shared.end()
        if ble.phase != .scanning {
            ble.startScan()
        }
    }

    private func startRadarBrowse() {
        selected = nil
        radarBrowseMode = true
        if ble.phase != .scanning {
            ble.startScan()
        }
        showOnlyScooters = true
        radar.startSession(enableRadar: true)
        Task { _ = await BLENotificationService.shared.requestAuthorization() }
    }

    private var radarBrowseContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    Button {
                        radar.endSession()
                        radarBrowseMode = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scooter-Radar")
                            .font(Theme.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Aktive Suche · kein Zielgerät nötig")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                }

                if let banner = radar.banner {
                    BLERadarBannerView(text: banner)
                }

                BLERadarControlsCard(radar: radar)

                Text("Nur hinreichend plausible E-Scooter lösen einen Alarm aus — nicht jedes BLE-Gerät.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if listedDevices.isEmpty {
                    Text("Warte auf Scooter-Signale…")
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(listedDevices) { device in
                        Button {
                            startFinding(device)
                        } label: {
                            finderDeviceRow(device)
                                .overlay(alignment: .topTrailing) {
                                    if radar.highlightDeviceIds.contains(device.id) {
                                        BLERadarHitBadge()
                                            .padding(10)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScootOutlineButton(title: "Radar beenden", systemImage: "xmark") {
                    radar.endSession()
                    radarBrowseMode = false
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.bottom, Theme.Space.xl)
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
                    Text("ScooterCheck baut aus geglätteten Bluetooth-Signalstärken und deiner Bewegung eine Heatmap. Bereiche ohne Messung bleiben dunkel — das ist Absicht.")
                        .font(.body)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Es gibt keine exakte Richtung oder Meterangabe. Nutze Grobsuche für die Fläche und Feinsuche für die letzten Meter (wärmer / kälter).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Unter „Alle BLE-Geräte“ kannst du jedes Signal verfolgen. Das speichert das Gerät nicht als Scooter.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("„Geräte beobachten“ erlaubt 1–5 Signale parallel in der aktiven Sitzung. Auch hier erfolgt keine Scooter-Speicherung. BLE-Wächter ist davon getrennt (Hintergrundüberwachung einzelner bekannter Geräte).")
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
