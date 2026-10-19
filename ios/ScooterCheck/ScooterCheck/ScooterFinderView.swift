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
    @ObservedObject private var identity = BLEIdentificationService.shared
    @State private var selected: ScannedDevice?
    @State private var detailDevice: ScannedDevice?
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
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                findSectionHeader

                if mode != .radar {
                    Picker("Suchmodus", selection: $showOnlyScooters) {
                        Text("E-Scooter").tag(true)
                        Text(mode == .signalPicker ? "Andere BLE" : "Alle BLE").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .font(Theme.segment)
                }

                HStack(alignment: .center, spacing: Theme.Space.sm) {
                    BleDeviceListSortFilterBar(
                        sort: $listSort,
                        hideNameless: $hideNamelessDevices,
                        showsHideNameless: showsHideNamelessFilter
                    )

                    Text(ble.phase == .scanning ? "Suche" : "Pausiert")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)

                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: Theme.Icon.standard, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 36, height: 36)
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
                    .padding(.top, Theme.Space.sm)
                    .padding(.bottom, Theme.Space.xxl)
            }
            .scootPagePadding()
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
                    subtitle: "Session bleibt aktiv beim Verlassen · beenden nur unten",
                    onBack: {
                        // Session bewusst NICHT beenden — Hintergrundsuche fortsetzen.
                        radarBrowseMode = false
                        ble.ensureRadarScanRunning(preferBackgroundFilter: false)
                        onBackToHub?()
                    }
                ) {
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
                            BLERadarHitCard(hit: hit) {
                                radar.showSettingsSheet = true
                            }
                        }
                    }
                }

                if listedDevices.isEmpty {
                    Text("Warte auf Scooter-Signale…")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.top, Theme.Space.sm)
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

/// Detail aus Gerätesuche: Geräte-Wächter + Signal-Finder („Gerät aufspüren“).
struct FinderDeviceDetailSheet: View {
    let device: ScannedDevice
    var onStartSearch: () -> Void
    var onDismiss: () -> Void

    @ObservedObject private var identity = BLEIdentificationService.shared
    @State private var showFullAnalysis = false

    private var lastSeenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: device.lastSeen, relativeTo: Date())
    }

    private var identityResult: BLEIdentificationResult? {
        identity.result(for: device.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text(identity.listTitle(for: device))
                            .font(Theme.sectionTitle)
                            .foregroundStyle(Theme.textPrimary)
                        if let sub = identityResult?.listSubtitle {
                            Text(sub)
                                .font(Theme.secondary)
                                .foregroundStyle(Theme.accent)
                        }
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
                            identityResult?.deviceCategory?.label
                                ?? (device.looksLikeScooter ? "Möglicher E-Scooter" : "Unbekanntes BLE-Gerät")
                        )
                        if let m = identityResult?.manufacturer {
                            detailRow("Hersteller", m)
                        }
                        if let conf = identityResult?.confidence {
                            detailRow("Zuverlässigkeit", conf.label)
                        }
                    }
                    .padding(Theme.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )

                    ScootOutlineButton(title: "Geräteanalyse", systemImage: "magnifyingglass") {
                        showFullAnalysis = true
                    }

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
            .sheet(isPresented: $showFullAnalysis) {
                BLEDeviceAnalysisView(
                    device: device,
                    onSignalSearch: onStartSearch,
                    onWatch: nil
                )
            }
            .onAppear {
                identity.ingest(device)
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
