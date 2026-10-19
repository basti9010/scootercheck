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
    /// Öffnet die Radar-Karte (nur Radar-Modus) — kein zweiter Hub-Menüpunkt.
    var onOpenRadarMap: (() -> Void)? = nil

    @StateObject private var searchEngine = BLESearchEngine()
    @StateObject private var multiMonitor = BLEMultiDeviceMonitor()
    @ObservedObject private var radar = BLERadarService.shared
    @ObservedObject private var identity = BLEIdentificationService.shared
    @State private var selected: ScannedDevice?
    @State private var detailDevice: ScannedDevice?
    @State private var diagnosisDevice: ScannedDevice?
    @State private var showInfo = false
    @State private var showMultiPicker = false
    @State private var multiSelectedIds: Set<UUID> = []
    @State private var radarBrowseMode = false
    /// Eigenständiger Modus — speichert kein Gerät als Scooter.
    @State private var showOnlyScooters = true
    @State private var listSort: BleDeviceListSort = .signal
    @State private var hideNamelessDevices = false
    /// Stabile Listenreihenfolge nur bei Sortierung nach Signal (weniger Zucken).
    @State private var stableOrderIds: [UUID] = []
    @State private var lastStableReorderAt = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFinding: Bool { selected != nil && searchEngine.isActive }
    private var isObserving: Bool { multiMonitor.isActive }
    private var isRadarBrowsing: Bool { radarBrowseMode && radar.isEnabled && !isFinding && !isObserving }

    private var showsHideNamelessFilter: Bool {
        !showOnlyScooters
    }

    private var filteredDevices: [ScannedDevice] {
        let base: [ScannedDevice]
        if mode == .signalPicker {
            // Explizite Wahl: E-Scooter ODER andere BLE-Geräte (nicht alles gemischt).
            base = showOnlyScooters
                ? ble.devices.filter(\.looksLikeScooter)
                : ble.devices.filter { !$0.looksLikeScooter }
        } else {
            base = showOnlyScooters
                ? ble.devices.filter(\.looksLikeScooter)
                : ble.devices
        }
        if showsHideNamelessFilter, hideNamelessDevices {
            return base.filter(BleDeviceListOrdering.hasAdvertisedName)
        }
        return base
    }

    private var listedDevices: [ScannedDevice] {
        switch listSort {
        case .name:
            return BleDeviceListOrdering.prepare(
                filteredDevices,
                sort: .name,
                hideNameless: false
            )
        case .signal:
            return BleScanListStabilizer.apply(order: stableOrderIds, to: filteredDevices)
        }
    }

    var body: some View {
        ZStack {
            // Basis bleibt gemountet → Zurückwischen zeigt die vorherige Seite (State bleibt erhalten).
            Group {
                if isRadarBrowsing {
                    radarBrowseContent
                        .scootEdgeBackGesture {
                            radar.endSession()
                            radarBrowseMode = false
                            onBackToHub?()
                        }
                } else {
                    selectionContent
                        .scootEdgeBackGesture {
                            onBackToHub?()
                        }
                }
            }

            if isObserving {
                BLEMultiDeviceScreen(monitor: multiMonitor) {
                    endMultiObserve()
                }
                .scootPushTransition(reduceMotion: reduceMotion)
                .scootEdgeBackGesture {
                    endMultiObserve()
                }
                .zIndex(1)
            }

            if isFinding {
                // Edge-Zurück liegt in BLESearchScreen (Speichern-Dialog), nicht hier —
                // sonst würde die Hub-Geste Messungen still verwerfen.
                BLESearchScreen(engine: searchEngine) {
                    endFinding()
                }
                .scootPushTransition(reduceMotion: reduceMotion)
                .zIndex(2)
            }
        }
        .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.page, value: isFinding)
        .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.page, value: isObserving)
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
        .onChange(of: hideNamelessDevices) { _ in
            stableOrderIds = []
            lastStableReorderAt = .distantPast
            reconcileStableOrder(force: true)
        }
        .onChange(of: listSort) { _ in
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
                liveRssi: ble.devices.first(where: { $0.id == device.id })?.rssi ?? device.rssi,
                onStartSearch: { enableProximityAudio in
                    detailDevice = nil
                    startFinding(device, enableProximityAudio: enableProximityAudio)
                },
                onDismiss: { detailDevice = nil }
            )
        }
        .sheet(item: $diagnosisDevice) { device in
            UniversalDiagnosisView(
                device: device,
                onNativeDump: {
                    diagnosisDevice = nil
                    detailDevice = device
                },
                onSignalSearch: {
                    let selected = device
                    diagnosisDevice = nil
                    startFinding(selected)
                },
                onWatch: {
                    BLEWatchService.shared.enableWatcher(
                        for: device,
                        isKnownScooter: device.looksLikeScooter
                    )
                    diagnosisDevice = nil
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
            now: now,
            rankingRssi: { ble.rankingRssi(for: $0) }
        )
        stableOrderIds = result.order
        lastStableReorderAt = result.reorderAt
    }

    // MARK: - Selection

    private var selectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                findSectionHeader

                if mode != .radar {
                    Picker("Suchmodus", selection: $showOnlyScooters) {
                        Text("E-Scooter").tag(true)
                        Text(mode == .signalPicker ? "Andere BLE" : "Alle BLE").tag(false)
                    }
                    .scootSegmented()
                }

                HStack(alignment: .center, spacing: Theme.Space.sm) {
                    BleDeviceListSortFilterBar(
                        sort: $listSort,
                        hideNameless: $hideNamelessDevices,
                        showsHideNameless: showsHideNamelessFilter
                    )

                    Text(ble.phase == .scanning ? "Suche" : "Pausiert")
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textMuted)

                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: Theme.Icon.compact, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Hinweise")
                }

                if mode == .deviceSearch, listedDevices.count >= BLEMultiDeviceMonitor.minDevices {
                    Button {
                        multiSelectedIds = []
                        showMultiPicker = true
                    } label: {
                        Label("Geräte beobachten", systemImage: "eyeglasses")
                            .font(Theme.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ein oder mehrere BLE-Geräte in der Sitzung beobachten, ohne sie als Scooter zu speichern.")
                }

                if listedDevices.isEmpty {
                    emptySelectionCard
                } else {
                    VStack(spacing: Theme.Space.listGap) {
                        ForEach(listedDevices) { device in
                            Button {
                                // Signal-Finder: zuerst Detail mit Identifikationsaktionen (AirTag-ähnlich).
                                detailDevice = device
                            } label: {
                                finderDeviceRow(device)
                                    .overlay(alignment: .topTrailing) {
                                        if radar.highlightDeviceIds.contains(device.id) {
                                            BLERadarHitBadge()
                                                .padding(8)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .opacity(device.isStale ? 0.45 : 1)
                            .accessibilityHint(
                                "Öffnet Details mit Näherungssuche und Geräteaktionen"
                            )
                        }
                    }
                }
            }
            .scootPagePadding()
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, Theme.Space.xxl)
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
        let switchTitle: String? = {
            if showOnlyScooters {
                return mode == .signalPicker ? "Andere BLE-Geräte anzeigen" : "Alle BLE-Geräte anzeigen"
            }
            return mode == .signalPicker ? "E-Scooter anzeigen" : nil
        }()
        let switchIcon: String? = {
            if showOnlyScooters { return "list.bullet" }
            return mode == .signalPicker ? "antenna.radiowaves.left.and.right" : nil
        }()
        return ScootEmptyStateCard(
            title: emptySelectionTitle,
            message: emptySelectionBody,
            actionTitle: switchTitle,
            actionSystemImage: switchIcon,
            action: switchTitle == nil ? nil : {
                showOnlyScooters.toggle()
            }
        )
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
        let idResult = identity.results[device.id]
        return HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle(device))
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let sub = idResult?.listSubtitle, !sub.isEmpty {
                    Text(sub)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(finderDisplayId(device))
                        .font(Theme.meta.monospaced())
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
                HStack(spacing: Theme.Space.sm) {
                    Text(device.finderSignalLabel)
                        .font(Theme.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    Text("·")
                        .foregroundStyle(Theme.textMuted)
                    Text(lastSeenLabel(device.lastSeen))
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textMuted)
                    if let cat = idResult?.deviceCategory, cat != .unknown, cat != .eScooter {
                        Text(cat.label)
                            .font(Theme.badgeFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if device.looksLikeScooter, !showOnlyScooters {
                        Text("E-Scooter?")
                            .font(Theme.badgeFont)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer(minLength: Theme.Space.sm)
            SignalStrengthView(rssi: device.rssi, style: .shu)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Space.cardPadding)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.Control.hairline)
        )
    }

    private func rowTitle(_ device: ScannedDevice) -> String {
        // `identity` ObservedObject → Listen-Titel aktualisieren ohne Zeilen-Duplikate.
        _ = identity.results[device.id]
        return identity.listTitle(for: device)
    }

    // MARK: - Actions

    /// Startet Signal-Finder — speichert das Gerät nie als bekannten Scooter.
    private func startFinding(_ device: ScannedDevice, enableProximityAudio: Bool = false) {
        if mode != .radar {
            radarBrowseMode = false
        }
        selected = device
        if ble.phase != .scanning {
            ble.startScan()
        }
        radar.startSession(enableRadar: mode == .radar || radar.isEnabled)
        searchEngine.start(device: device, ble: ble)
        if enableProximityAudio {
            searchEngine.audioEnabled = true
            searchEngine.hapticsEnabled = true
            searchEngine.arSettings.audioEnabled = true
            searchEngine.arSettings.hapticsEnabled = true
        }
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

    private func endMultiObserve() {
        multiSelectedIds = []
        if multiMonitor.isActive {
            multiMonitor.stop()
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
                    subtitle: radar.scanState.headerCapabilityLine,
                    onBack: {
                        // Session bewusst NICHT beenden — Hintergrundsuche fortsetzen.
                        radarBrowseMode = false
                        ble.ensureRadarScanRunning(preferBackgroundFilter: false)
                        onBackToHub?()
                    }
                ) {
                    // Nur ein Einstellungszahnrad — Karte als eigene Zeile darunter.
                    Button {
                        radar.showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: Theme.Icon.standard, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: Theme.Control.backHit, height: Theme.Control.backHit)
                    }
                    .accessibilityLabel("Radar-Einstellungen")
                }

                BLERadarControlsCard(radar: radar)

                if onOpenRadarMap != nil {
                    Button {
                        onOpenRadarMap?()
                    } label: {
                        HStack(spacing: Theme.Space.md) {
                            Image(systemName: "map")
                                .font(.system(size: Theme.Icon.standard, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, alignment: .center)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Radar-Karte")
                                    .font(Theme.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Gespeicherte Sichtungen auf der Karte")
                                    .font(Theme.meta)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .stroke(Theme.border, lineWidth: Theme.Control.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Radar-Karte öffnen")
                }

                if let banner = radar.banner {
                    BLERadarBannerView(
                        text: banner,
                        warning: banner.contains("Zulassung") || banner.contains("nicht zugelassen")
                    )
                }

                if !radar.recentHits.isEmpty {
                    Text("Erkannte E-Scooter")
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                    VStack(spacing: Theme.Space.listGap) {
                        ForEach(radar.recentHits.prefix(12)) { hit in
                            BLERadarHitCard(
                                hit: hit,
                                onDetails: nil,
                                onDiagnose: {
                                    if let device = ble.devices.first(where: { $0.id == hit.id }) {
                                        diagnosisDevice = device
                                    }
                                }
                            )
                        }
                    }
                }

                if listedDevices.isEmpty {
                    BLERadarWaitingView()
                } else {
                    Text("In Reichweite")
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                    VStack(spacing: Theme.Space.listGap) {
                        ForEach(listedDevices) { device in
                            Button {
                                startFinding(device)
                            } label: {
                                finderDeviceRow(device)
                                    .overlay(alignment: .topTrailing) {
                                        if radar.highlightDeviceIds.contains(device.id) {
                                            BLERadarHitBadge(
                                                warning: radar.recentHits.first(where: { $0.id == device.id })?.alarmKind.accentWarning == true
                                            )
                                            .padding(10)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    radar.endSession()
                    radarBrowseMode = false
                    onBackToHub?()
                } label: {
                    Text("Radar beenden")
                        .font(Theme.caption.weight(.medium))
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.md)
                }
                .buttonStyle(.plain)
            }
            .scootPagePadding()
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.xxl)
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

/// Detail: Fingerprint, Näherungssuche, dokumentierte Geräteaktionen (Piep/Blink).
struct FinderDeviceDetailSheet: View {
    let device: ScannedDevice
    var liveRssi: Int
    /// `true` = Signal-Finder mit Suchton/Haptik starten.
    var onStartSearch: (_ enableProximityAudio: Bool) -> Void
    var onDismiss: () -> Void

    @ObservedObject private var identity = BLEIdentificationService.shared
    @StateObject private var capability = BLECapabilityService()
    @State private var showFullAnalysis = false
    @State private var showProbeConfirm = false
    @State private var alertActive = false
    @State private var ledOn = false

    private var lastSeenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: device.lastSeen, relativeTo: Date())
    }

    private var identityResult: BLEIdentificationResult? {
        identity.result(for: device.id)
    }

    private var fingerprintStatus: BLEFingerprintStatus {
        BLEFingerprintStatus.from(confidence: identityResult?.confidence)
    }

    private var signalBandLabel: String {
        switch liveRssi {
        case -55...0: return "Starkes Signal"
        case -75 ..< -55: return "Mittleres Signal"
        default: return "Schwaches Signal"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    headerBlock
                    statusCard
                    proximityCard
                    deviceActionsCard
                    ScootOutlineButton(title: "Geräteanalyse", systemImage: "magnifyingglass") {
                        showFullAnalysis = true
                    }
                    BLEWatcherSettingsCard(device: device, isKnownScooter: false)
                    ScootSecondaryButton(title: "Schließen", systemImage: "xmark") {
                        capability.disconnect(clearCaps: false)
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
                AppChromeSheetHeader(closeTitle: "Fertig", onClose: {
                    capability.disconnect(clearCaps: false)
                    onDismiss()
                })
            }
            .sheet(isPresented: $showFullAnalysis) {
                BLEDeviceAnalysisView(
                    device: device,
                    onSignalSearch: { onStartSearch(false) },
                    onWatch: nil
                )
            }
            .confirmationDialog(
                "Schnittstellen prüfen?",
                isPresented: $showProbeConfirm,
                titleVisibility: .visible
            ) {
                Button("Verbinden und prüfen") {
                    capability.probe(device: device)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("ScooterCheck stellt eine kurze BLE-Verbindung her und liest dokumentierte GATT-Dienste. Es werden keine zufälligen Schreibbefehle gesendet.")
            }
            .onAppear {
                identity.ingest(device)
            }
            .onDisappear {
                capability.disconnect(clearCaps: false)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(identity.listTitle(for: device))
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            if let sub = identityResult?.listSubtitle {
                Text(sub)
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.accent)
            }
            Text(fingerprintStatus.label)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            detailRow("Signal", "\(liveRssi) dBm · \(signalBandLabel)")
            detailRow("Status", capability.phase == .idle ? "Erkannt" : capability.phase.label)
            detailRow("BLE-ID", device.bleIdentifierShort)
            detailRow("Zuletzt gesehen", lastSeenText)
            detailRow(
                "Typ",
                identityResult?.deviceCategory?.label
                    ?? (device.looksLikeScooter ? "Möglicher E-Scooter" : "Unbekanntes BLE-Gerät")
            )
            if let m = identityResult?.manufacturer {
                detailRow("Hersteller", m)
            }
            ProximitySignalBars(rssi: liveRssi)
                .frame(height: 10)
                .padding(.top, 2)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.Control.hairline)
        )
    }

    private var proximityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Gerät finden")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .textCase(.uppercase)
            Text("Akustische Näherungssuche über das iPhone — steuert das Fremdgerät nicht. RSSI ist keine Meterangabe.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScootPrimaryButton(
                title: "Akustische Näherungssuche",
                systemImage: "waveform"
            ) {
                onStartSearch(true)
            }
            ScootOutlineButton(title: "Nur Heatmap / Live", systemImage: "viewfinder") {
                onStartSearch(false)
            }
        }
    }

    private var deviceActionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Geräteaktionen")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .textCase(.uppercase)

            if !capability.capabilities.probed {
                Text("Prüfe zuerst, welche dokumentierten Schnittstellen das Gerät freigibt.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScootOutlineButton(title: "Schnittstellen prüfen", systemImage: "link") {
                    showProbeConfirm = true
                }
            } else if capability.phase == .probing {
                HStack(spacing: Theme.Space.sm) {
                    ProgressView().tint(Theme.accent)
                    Text(capability.phase.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if !capability.capabilities.hasAnyDeviceAction {
                Text("Keine dokumentierte Alarm- oder LED-Funktion erkannt. Die Näherungssuche bleibt verfügbar.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if capability.capabilities.supportsAlert {
                    if alertActive {
                        ScootOutlineButton(title: "Alarm stoppen", systemImage: "speaker.slash") {
                            capability.stopImmediateAlert()
                            alertActive = false
                        }
                    } else {
                        ScootOutlineButton(title: "Ton am Gerät abspielen", systemImage: "speaker.wave.2") {
                            capability.sendImmediateAlert(level: .high)
                            alertActive = true
                        }
                    }
                }
                if capability.capabilities.supportsVisualIdentification {
                    if ledOn {
                        ScootOutlineButton(title: "Blinken stoppen", systemImage: "lightbulb.slash") {
                            capability.setNordicLed(on: false)
                            ledOn = false
                        }
                    } else {
                        ScootOutlineButton(title: "Gerät blinken lassen", systemImage: "lightbulb") {
                            capability.setNordicLed(on: true)
                            ledOn = true
                        }
                    }
                }
                if let note = capability.lastWriteNote {
                    Text(note)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Ein erfolgreicher BLE-Befehl beweist keinen hörbaren Ton.")
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
            }

            if case .failed(let msg) = capability.phase {
                Text(msg)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

/// Kompakte animierte Signalbalken für die Detailkarte (kein Metermaß).
struct ProximitySignalBars: View {
    let rssi: Int

    private var fill: CGFloat {
        let clamped = min(-30, max(-100, rssi))
        return CGFloat((-30 - clamped) / 70.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceSecondary)
                Capsule()
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: max(8, geo.size.width * (1 - fill)))
                    .animation(Theme.Motion.standard, value: rssi)
            }
        }
        .accessibilityLabel("Signalstärke \(rssi) dBm")
    }
}
