import SwiftUI

/// Einstieg in Gerätesuche / Radar / Signal-Finder (gemeinsame BLE-Basis).
enum ScooterFinderMode: Equatable {
    /// Bluetooth-Geräte entdecken, Details, Wächter, Gerät aufspüren.
    case deviceSearch
    /// Automatische Scooter-Erkennung (Radar).
    case radar
    /// Gerät wählen → Signal-Finder (Heatmap).
    case signalPicker
}

/// Geräteauswahl + Signal-Finder / Radar innerhalb von „E-Scooter finden“.
struct ScooterFinderView: View {
    @ObservedObject var ble: BleClient
    var mode: ScooterFinderMode = .deviceSearch
    var onBackToHub: (() -> Void)?

    @StateObject private var searchEngine = BLESearchEngine()
    @StateObject private var multiMonitor = BLEMultiDeviceMonitor()
    @ObservedObject private var radar = BLERadarService.shared
    @State private var selected: ScannedDevice?
    @State private var detailDevice: ScannedDevice?
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
        if mode == .signalPicker {
            // Explizite Wahl: E-Scooter ODER andere BLE-Geräte (nicht alles gemischt).
            return showOnlyScooters
                ? ble.devices.filter(\.looksLikeScooter)
                : ble.devices.filter { !$0.looksLikeScooter }
        }
        return showOnlyScooters
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
            if mode == .radar, !radarBrowseMode, !isFinding {
                startRadarBrowse()
            }
            if mode == .signalPicker {
                // Signal-Finder startet bei E-Scootern; Umschalten auf andere BLE möglich.
                showOnlyScooters = true
            }
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
                    guard picked.count >= BLEMultiDeviceMonitor.minDevices else { return }
                    if ble.phase != .scanning { ble.startScan() }
                    multiMonitor.start(devices: picked, ble: ble)
                },
                onCancel: {
                    showMultiPicker = false
                    multiSelectedIds = []
                }
            )
        }
        .sheet(item: $detailDevice) { device in
            FinderDeviceDetailSheet(
                device: device,
                onStartSearch: {
                    detailDevice = nil
                    startFinding(device)
                },
                onDismiss: { detailDevice = nil }
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
                findSectionHeader

                if mode != .radar {
                    Picker("Suchmodus", selection: $showOnlyScooters) {
                        Text("E-Scooter").tag(true)
                        Text(mode == .signalPicker ? "Andere BLE-Geräte" : "Alle BLE-Geräte").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .font(Theme.segment)
                }

                if mode == .signalPicker {
                    Text(showOnlyScooters
                         ? "Nur als E-Scooter erkennbare Signale. Tippe ein Gerät an, um den Signal-Finder zu starten."
                         : "Nur sonstige BLE-Geräte (keine E-Scooter-Treffer). Tippe ein Gerät an, um den Signal-Finder zu starten.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if mode == .deviceSearch, !showOnlyScooters {
                    Text("Zeigt alle erkannten BLE-Signale. Tippe ein Gerät an für Details, Geräte-Wächter oder Signal-Finder.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Label(
                        ble.phase == .scanning
                            ? (mode == .signalPicker ? "Signal-Finder · Suche aktiv" : "Gerätesuche aktiv")
                            : (mode == .signalPicker ? "Signal-Finder · pausiert" : "Gerätesuche pausiert"),
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
                    .accessibilityLabel("Hinweise zum Signal-Finder")
                }

                if mode == .deviceSearch, listedDevices.count >= BLEMultiDeviceMonitor.minDevices {
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
                    .accessibilityHint("Ein oder mehrere BLE-Geräte in der Sitzung beobachten, ohne sie als Scooter zu speichern.")
                }

                if listedDevices.isEmpty {
                    emptySelectionCard
                } else {
                    VStack(spacing: 10) {
                        ForEach(listedDevices) { device in
                            Button {
                                if mode == .signalPicker {
                                    startFinding(device)
                                } else {
                                    detailDevice = device
                                }
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
                            .accessibilityHint(
                                mode == .signalPicker
                                    ? "Startet den Signal-Finder für dieses Gerät"
                                    : "Öffnet Details mit Geräte-Wächter und Signal-Finder"
                            )
                        }
                    }
                }

                AppCopyrightFooter()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.sm)
        }
    }

    private var findSectionHeader: some View {
        FindSubpageHeader(
            title: selectionTitle,
            subtitle: selectionSubtitle,
            onBack: onBackToHub
        )
    }

    private var selectionTitle: String {
        switch mode {
        case .signalPicker: return "Signal-Finder"
        case .deviceSearch: return "Gerätesuche"
        case .radar: return "E-Scooter-Radar"
        }
    }

    private var selectionSubtitle: String {
        switch mode {
        case .signalPicker:
            return "Bluetooth-Signalstärken untersuchen."
        case .deviceSearch:
            return "Bluetooth-Geräte entdecken und auslesen."
        case .radar:
            return "Aktive Suche · kein Zielgerät nötig"
        }
    }

    private var emptySelectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptySelectionTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(emptySelectionBody)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showOnlyScooters {
                ScootPrimaryButton(
                    title: mode == .signalPicker ? "Andere BLE-Geräte anzeigen" : "Alle BLE-Geräte anzeigen",
                    systemImage: "list.bullet"
                ) {
                    showOnlyScooters = false
                }
                .padding(.top, 4)
            } else if mode == .signalPicker {
                ScootPrimaryButton(title: "E-Scooter anzeigen", systemImage: "antenna.radiowaves.left.and.right") {
                    showOnlyScooters = true
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private var emptySelectionTitle: String {
        if mode == .signalPicker {
            return showOnlyScooters ? "Keine E-Scooter in Reichweite" : "Keine anderen BLE-Geräte in Reichweite"
        }
        return showOnlyScooters ? "Keine E-Scooter in Reichweite" : "Keine BLE-Geräte in Reichweite"
    }

    private var emptySelectionBody: String {
        if mode == .signalPicker {
            return showOnlyScooters
                ? "Halte das iPhone in der Nähe — oder wechsle zu „Andere BLE-Geräte“, falls die Erkennung unsicher ist."
                : "Hier erscheinen BLE-Signale, die nicht als E-Scooter eingestuft sind. Wechsle zu „E-Scooter“, um Scooter-Treffer zu sehen."
        }
        return showOnlyScooters
            ? "Halte das iPhone in der Nähe — oder wechsle zu „Alle BLE-Geräte“, falls die Erkennung unsicher ist."
            : "Stelle sicher, dass Bluetooth aktiv ist und Geräte in der Nähe werben."
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

    /// Startet Signal-Finder — speichert das Gerät nie als bekannten Scooter.
    private func startFinding(_ device: ScannedDevice) {
        if mode != .radar {
            radarBrowseMode = false
        }
        selected = device
        if ble.phase != .scanning {
            ble.startScan()
        }
        radar.startSession(enableRadar: mode == .radar || radar.isEnabled)
        searchEngine.start(device: device, ble: ble)
        BLESearchLiveActivityController.shared.start(deviceName: device.bleListDisplayName)
    }

    private func endFinding() {
        selected = nil
        BLESearchLiveActivityController.shared.end()
        if mode == .radar {
            radarBrowseMode = true
            radar.startSession(enableRadar: true)
        } else {
            radar.endSession()
        }
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
                FindSubpageHeader(
                    title: "E-Scooter-Radar",
                    subtitle: "Aktive Suche · kein Zielgerät nötig",
                    onBack: {
                        radar.endSession()
                        radarBrowseMode = false
                        onBackToHub?()
                    }
                )

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
                    onBackToHub?()
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.sm)
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
                    Text("Es gibt keine exakte Richtung. Nutze die Heatmap und die Signalstärke (wärmer / kälter), während du dich bewegst.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Unter „Alle BLE-Geräte“ öffnest du die Detailansicht: dort kannst du den Geräte-Wächter aktivieren oder den Signal-Finder starten. Das speichert das Gerät nicht als Scooter.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("„Geräte beobachten“ erlaubt 1–5 Signale parallel in der aktiven Sitzung. Auch hier erfolgt keine Scooter-Speicherung. Der Geräte-Wächter ist davon getrennt (Hintergrundüberwachung einzelner bekannter Geräte).")
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

/// Detail aus Gerätesuche: Geräte-Wächter + Signal-Finder („Gerät aufspüren“).
struct FinderDeviceDetailSheet: View {
    let device: ScannedDevice
    var onStartSearch: () -> Void
    var onDismiss: () -> Void

    private var lastSeenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: device.lastSeen, relativeTo: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text(device.bleListDisplayName)
                            .font(Theme.sectionTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Bluetooth-Gerät. Du kannst den Geräte-Wächter aktivieren oder es mit dem Signal-Finder aufspüren — ohne Speicherung als Scooter.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        detailRow("RSSI", "\(device.rssi) dBm · \(device.finderSignalLabel)")
                        detailRow("BLE-ID", device.bleIdentifierShort)
                        detailRow("Zuletzt gesehen", lastSeenText)
                        detailRow(
                            "Typ",
                            device.looksLikeScooter ? "Möglicher E-Scooter" : "Unbekanntes BLE-Gerät"
                        )
                    }
                    .padding(Theme.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )

                    BLEWatcherSettingsCard(device: device, isKnownScooter: false)

                    ScootPrimaryButton(
                        title: "Gerät aufspüren",
                        systemImage: "viewfinder"
                    ) {
                        onStartSearch()
                    }

                    ScootSecondaryButton(title: "Schließen", systemImage: "xmark") {
                        onDismiss()
                    }
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.sm)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                AppChromeSheetHeader(closeTitle: "Fertig", onClose: onDismiss)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
    }
}
