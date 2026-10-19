import SwiftUI
import MapKit

/// Interaktive Radar-Karte: Smartphone-Standorte dokumentierter BLE-Sichtungen.
struct RadarMapView: View {
    var onBack: (() -> Void)?

    @ObservedObject private var store = RadarMapStore.shared
    @State private var filter = RadarMapFilter()
    @State private var showFilters = false
    @State private var showSettings = false
    @State private var showHiddenList = false
    @State private var selectedSighting: RadarSighting?
    @State private var focusIdentityId: UUID?
    @State private var mapStyleStandard = true
    @State private var showHeatmap = false
    @State private var fitToken = 0
    @State private var centerUserToken = 0
    @State private var timelineFraction: Double = 1
    @State private var timelinePlaying = false
    @State private var timelineTask: Task<Void, Never>?
    @State private var confirmDeleteSighting = false
    @State private var confirmDeleteHistory = false
    @State private var confirmHide = false
    /// ⋯ → Löschen + Ausblenden (einziger Verwaltungszugang)
    @State private var showManageSheet = false
    @State private var manageHiddenEntry: HiddenRadarDevice?

    private var visibleSightings: [RadarSighting] {
        var list = store.filteredSightings(filter: filter)
        if let focus = focusIdentityId {
            list = list.filter { $0.deviceIdentityId == focus }
        }
        if timelineFraction < 0.999 {
            let start = list.map(\.firstSeenAt).min()
            let end = list.map(\.lastSeenAt).max()
            if let start, let end, end > start {
                let cutoff = start.addingTimeInterval(end.timeIntervalSince(start) * timelineFraction)
                list = list.filter { $0.firstSeenAt <= cutoff }
            }
        }
        return list
    }

    private var locatedSightings: [RadarSighting] {
        visibleSightings.filter(\.hasLocation)
    }

    private var deviceCount: Int {
        Set(visibleSightings.compactMap(\.deviceIdentityId)).count
    }

    private var repeatedDeviceCount: Int {
        Dictionary(grouping: visibleSightings.compactMap(\.deviceIdentityId), by: { $0 })
            .mapValues(\.count)
            .values
            .filter { $0 >= filter.minSightings }
            .count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            timeChips
            mapCanvas
            statsBar
            if locatedSightings.count >= 2 {
                timelineBar
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFilters) { filterSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showHiddenList) { hiddenListSheet }
        .sheet(item: $selectedSighting) { sighting in
            sightingSheet(sighting)
        }
        .confirmationDialog("Sichtungen verwalten", isPresented: $showManageSheet, titleVisibility: .visible) {
            Button("Einzelne Sichtung löschen", role: .destructive) { confirmDeleteSighting = true }
            Button("Gesamte Gerätehistorie löschen", role: .destructive) { confirmDeleteHistory = true }
            if let s = selectedSighting,
               !store.isHidden(identityId: s.deviceIdentityId, peripheralId: s.peripheralId) {
                Button("Gerät dauerhaft ausblenden") { confirmHide = true }
            }
            if let s = selectedSighting,
               store.isHidden(identityId: s.deviceIdentityId, peripheralId: s.peripheralId) {
                Button("Wieder einblenden") {
                    if let entry = store.hiddenEntry(identityId: s.deviceIdentityId, peripheralId: s.peripheralId) {
                        store.unhideDevice(hiddenId: entry.id)
                    }
                    selectedSighting = nil
                    fitToken += 1
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Ausgeblendetes Gerät", isPresented: Binding(
            get: { manageHiddenEntry != nil },
            set: { if !$0 { manageHiddenEntry = nil } }
        ), titleVisibility: .visible) {
            Button("Wieder einblenden") {
                if let h = manageHiddenEntry {
                    store.unhideDevice(hiddenId: h.id)
                    fitToken += 1
                }
                manageHiddenEntry = nil
            }
            Button("Gespeicherte Sichtungen löschen", role: .destructive) {
                if let h = manageHiddenEntry {
                    if let iid = h.deviceIdentityId, h.identityBound {
                        store.deleteHistory(forIdentity: iid)
                    } else if let pid = h.peripheralId {
                        store.deleteHistory(forPeripheral: pid)
                    }
                }
                manageHiddenEntry = nil
                fitToken += 1
            }
            Button("Abbrechen", role: .cancel) { manageHiddenEntry = nil }
        }
        .alert("Sichtung löschen?", isPresented: $confirmDeleteSighting) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                if let id = selectedSighting?.id {
                    store.deleteSighting(id: id)
                    selectedSighting = nil
                    fitToken += 1
                }
            }
        } message: {
            if let s = selectedSighting {
                Text("Möchtest du diese Sichtung vom \(Self.format(s.firstSeenAt)) wirklich löschen?")
            } else {
                Text("Möchtest du diese Sichtung wirklich löschen?")
            }
        }
        .alert("Gerätehistorie löschen?", isPresented: $confirmDeleteHistory) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                guard let s = selectedSighting else { return }
                if let iid = s.deviceIdentityId {
                    store.deleteHistory(forIdentity: iid)
                } else {
                    store.deleteHistory(forPeripheral: s.peripheralId)
                }
                selectedSighting = nil
                focusIdentityId = nil
                fitToken += 1
            }
        } message: {
            if let s = selectedSighting {
                let n = store.sightingCount(for: s)
                Text("Alle \(n) gespeicherten Sichtungen dieses Geräts dauerhaft löschen?")
            }
        }
        .alert("Dieses Gerät künftig ausblenden?", isPresented: $confirmHide) {
            Button("Abbrechen", role: .cancel) {}
            Button("Ausblenden") {
                if let s = selectedSighting {
                    store.hideDevice(from: s)
                    selectedSighting = nil
                    fitToken += 1
                }
            }
        } message: {
            if let s = selectedSighting, !s.identityMatchConfidence.allowsHistoryMerge {
                Text("Der Scooter wird weiterhin technisch erkannt, aber nicht mehr auf der Radar-Karte angezeigt und löst keine normalen Radar-Benachrichtigungen mehr aus. Bereits gespeicherte Sichtungen bleiben erhalten.\n\nHinweis: Die Identität ist nicht eindeutig — es wird nur diese lokale Gerätekennung ausgeblendet. Wechselnde BLE-Kennungen können erneut als neues Gerät erscheinen.")
            } else {
                Text("Der Scooter wird weiterhin technisch erkannt, aber nicht mehr auf der Radar-Karte angezeigt und löst keine normalen Radar-Benachrichtigungen mehr aus. Bereits gespeicherte Sichtungen bleiben erhalten.")
            }
        }
        .onAppear {
            RadarMapRecorder.shared.requestLocationIfNeeded()
            store.pruneRetentionIfNeeded()
        }
        .onDisappear {
            timelineTask?.cancel()
            timelinePlaying = false
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            if onBack != nil {
                Button { onBack?() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Theme.Icon.standard, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.Control.backHit, height: Theme.Control.backHit)
                }
                .accessibilityLabel("Zurück")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Radar-Karte")
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Smartphone-Standort bei BLE-Empfang")
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Button { showFilters = true } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: Theme.Icon.standard))
                    .foregroundStyle(Theme.accent)
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: Theme.Icon.standard))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, Theme.Space.sm)
    }

    private var timeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RadarMapTimePreset.allCases.filter { $0 != .custom }) { preset in
                    chip(preset.label, active: filter.timePreset == preset) {
                        filter.timePreset = preset
                    }
                }
                chip("Wiederholt erkannt", active: filter.onlyRepeated) {
                    filter.onlyRepeated.toggle()
                }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.bottom, Theme.Space.sm)
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.meta.weight(.medium))
                .foregroundStyle(active ? Theme.bg : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Theme.accent : Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: active ? 0 : Theme.Control.hairline))
        }
        .buttonStyle(.plain)
    }

    private var mapCanvas: some View {
        ZStack(alignment: .topTrailing) {
            RadarMapKitCanvas(
                sightings: locatedSightings,
                focusIdentityId: focusIdentityId,
                showHeatmap: showHeatmap,
                satellite: !mapStyleStandard,
                fitToken: fitToken,
                centerUserToken: centerUserToken,
                onSelect: { selectedSighting = $0 }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .padding(.horizontal, Theme.Space.page)

            VStack(spacing: 8) {
                mapButton(systemImage: mapStyleStandard ? "globe.europe.africa" : "map") {
                    mapStyleStandard.toggle()
                }
                mapButton(systemImage: "scope") { centerUserToken += 1 }
                mapButton(systemImage: "arrow.up.left.and.arrow.down.right") { fitToken += 1 }
                mapButton(systemImage: showHeatmap ? "flame.fill" : "flame") {
                    showHeatmap.toggle()
                }
            }
            .padding(.trailing, Theme.Space.page + 8)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mapButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.card.opacity(0.92))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var statsBar: some View {
        HStack {
            stat("Sichtungen", "\(visibleSightings.count)")
            Spacer()
            stat("Geräte", "\(deviceCount)")
            Spacer()
            stat("Wiederholt", "\(repeatedDeviceCount)")
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, Theme.Space.sm)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.cardTitle).foregroundStyle(Theme.accent)
            Text(title).font(Theme.caption).foregroundStyle(Theme.textMuted)
        }
    }

    private var timelineBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Zeitverlauf")
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Button {
                    if timelinePlaying {
                        timelineTask?.cancel()
                        timelinePlaying = false
                    } else {
                        timelinePlaying = true
                        timelineTask = Task { @MainActor in
                            while timelineFraction < 1, !Task.isCancelled {
                                timelineFraction = min(1, timelineFraction + 0.02)
                                try? await Task.sleep(nanoseconds: 80_000_000)
                            }
                            timelinePlaying = false
                        }
                    }
                } label: {
                    Image(systemName: timelinePlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            Slider(value: $timelineFraction, in: 0...1)
                .tint(Theme.accent)
            Text("Nur dokumentierte Sichtungen — keine simulierte Fahrzeugbewegung.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.bottom, Theme.Space.md)
    }

    private func sightingSheet(_ sighting: RadarSighting) -> some View {
        let historyCount = store.sightingCount(for: sighting)
        let history = sighting.deviceIdentityId.map { store.sightings(forIdentity: $0) }
            ?? store.sightings.filter { $0.peripheralId == sighting.peripheralId }.sorted { $0.firstSeenAt < $1.firstSeenAt }
        let areas = sighting.deviceIdentityId.map { store.distinctAreaCount(forIdentity: $0) } ?? 0
        let shortId = String(sighting.peripheralId.uuidString.prefix(8)).uppercased()
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sighting.displayName)
                                .font(Theme.cardTitle)
                                .foregroundStyle(Theme.textPrimary)
                            if store.isHidden(identityId: sighting.deviceIdentityId, peripheralId: sighting.peripheralId) {
                                Text("Ausgeblendet")
                                    .font(Theme.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                        Spacer()
                        Button { showManageSheet = true } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Mehr")
                    }
                    if !sighting.identityMatchConfidence.allowsHistoryMerge {
                        Text("Gerätezuordnung unsicher — Ausblenden gilt nur für diese Kennung (\(shortId)).")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    row("Hersteller", sighting.manufacturer ?? "—")
                    row("Modell", sighting.model ?? "—")
                    row("Gerätekennung", shortId)
                    row("Zeitpunkt", Self.format(sighting.firstSeenAt))
                    row("Signal", sighting.signalLabel)
                    row("Sichtungen", "\(historyCount)")
                    row("Identifikation", sighting.identificationConfidence.label)
                    row("Zuordnung", sighting.identityMatchConfidence.label)
                    if let acc = sighting.location?.horizontalAccuracy {
                        row("Standortgenauigkeit", String(format: "±%.0f m (Smartphone)", acc))
                    } else {
                        row("Standort", "Nicht verfügbar")
                    }
                    if let raw = sighting.approvalStatusRaw,
                       let st = GermanVehicleApprovalStatus(rawValue: raw) {
                        row("Zulassung", st.label)
                    }
                    Text("Die Karte zeigt den Empfangsort des Smartphones, nicht die exakte Scooter-Position. Löschen betrifft nur Radar-Sichtungen — nicht bekannte Scooter, Prüfberichte oder Wächter.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)

                    Button("Alle Sichtungen anzeigen") {
                        focusIdentityId = sighting.deviceIdentityId
                        selectedSighting = nil
                        fitToken += 1
                    }
                    .font(Theme.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)

                    if history.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Historie · \(history.count) Sichtungen · \(areas) Bereiche")
                                .font(Theme.caption.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            ForEach(history.reversed()) { h in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.format(h.firstSeenAt))
                                        .font(Theme.caption.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Signal: \(h.signalLabel)")
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if focusIdentityId != nil {
                        Text("Linie verbindet dokumentierte Sichtungsorte — kein Fahrweg.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                        Button("Gerätefokus aufheben") { focusIdentityId = nil }
                            .font(Theme.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .scootPagePadding()
                .padding(.top, Theme.Space.md)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { selectedSighting = nil }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Zeitraum", selection: $filter.timePreset) {
                        ForEach(RadarMapTimePreset.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    Picker("Gerätetyp", selection: $filter.deviceFilter) {
                        ForEach(RadarMapDeviceFilter.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    Toggle("Ausgeblendete anzeigen", isOn: $filter.showHidden)
                    Toggle("Nur wiederholt erkannt", isOn: $filter.onlyRepeated)
                    if filter.onlyRepeated {
                        Picker("Mindestens", selection: $filter.minSightings) {
                            Text("2").tag(2); Text("3").tag(3); Text("5").tag(5); Text("10").tag(10)
                        }
                        Picker("Bezug", selection: $filter.repeatScope) {
                            ForEach(RadarMapRepeatScope.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                    }
                    Picker("Hersteller", selection: Binding(
                        get: { filter.manufacturer ?? "" },
                        set: { filter.manufacturer = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Alle").tag("")
                        ForEach(store.manufacturersPresent(), id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    Picker("Zulassung", selection: $filter.approval) {
                        ForEach(RadarMapApprovalFilter.allCases) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    Picker("Signal", selection: $filter.signal) {
                        ForEach(RadarMapSignalFilter.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                }
            }
            .font(Theme.caption)
            .pickerStyle(.menu)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { showFilters = false }
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sichtungen speichern", isOn: Binding(
                        get: { store.settings.storeSightings },
                        set: { v in var s = store.settings; s.storeSightings = v; store.settings = s }
                    ))
                    Toggle("Standort speichern", isOn: Binding(
                        get: { store.settings.storeLocation },
                        set: { v in
                            var s = store.settings; s.storeLocation = v; store.settings = s
                            if v { RadarMapRecorder.shared.requestLocationIfNeeded() }
                            else { RadarMapRecorder.shared.updateLocationAuthorization() }
                        }
                    ))
                    Toggle("Gerätehistorie speichern", isOn: Binding(
                        get: { store.settings.storeDeviceHistory },
                        set: { v in var s = store.settings; s.storeDeviceHistory = v; store.settings = s }
                    ))
                    Toggle("Wiederholt erkannt melden", isOn: Binding(
                        get: { store.settings.notifyRepeatSightings },
                        set: { v in var s = store.settings; s.notifyRepeatSightings = v; store.settings = s }
                    ))
                } footer: {
                    Text("Standort = Smartphone beim Empfang, nicht Scooter-Position.")
                        .font(Theme.meta)
                }
                Section {
                    Stepper(
                        "Pause bis neuer Eintrag: \(store.settings.sightingGapMinutes) Min.",
                        value: Binding(
                            get: { store.settings.sightingGapMinutes },
                            set: { v in var s = store.settings; s.sightingGapMinutes = v; store.settings = s }
                        ),
                        in: 5...120,
                        step: 5
                    )
                    Picker("Aufbewahrung", selection: Binding(
                        get: { store.settings.retentionChoice },
                        set: { choice in
                            var s = store.settings
                            s.retentionChoice = choice
                            store.settings = s
                            store.pruneRetentionIfNeeded()
                        }
                    )) {
                        ForEach(RadarMapRetentionChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                }
                Section {
                    Button {
                        showSettings = false
                        showHiddenList = true
                    } label: {
                        HStack {
                            Text("Ausgeblendete Geräte")
                            Spacer()
                            Text("\(store.hidden.count)")
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    Toggle("Sichtungen trotz Ausblenden speichern", isOn: Binding(
                        get: { store.settings.retainSightingsWhileHidden },
                        set: { v in var s = store.settings; s.retainSightingsWhileHidden = v; store.settings = s }
                    ))
                }
                Section {
                    Button("Alle Sichtungen löschen", role: .destructive) {
                        store.deleteAllSightings()
                    }
                } footer: {
                    Text("Nur Radar-Karten-Daten. Prüfberichte und Wächter bleiben.")
                        .font(Theme.meta)
                }
            }
            .font(Theme.caption)
            .pickerStyle(.menu)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { showSettings = false }
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var hiddenListSheet: some View {
        NavigationStack {
            List {
                if store.hidden.isEmpty {
                    Text("Keine ausgeblendeten Geräte.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                ForEach(store.hidden) { h in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text({
                                let label = [h.manufacturer, h.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                                return label.isEmpty ? h.displayName : label
                            }())
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            if let pid = h.peripheralId {
                                Text(String(pid.uuidString.prefix(8)).uppercased())
                                    .font(Theme.meta.monospaced())
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Text("Seit \(Self.format(h.hiddenAt))")
                                .font(Theme.meta)
                                .foregroundStyle(Theme.textMuted)
                            let n: Int = {
                                if let iid = h.deviceIdentityId, h.identityBound {
                                    return store.sightings(forIdentity: iid).count
                                }
                                if let pid = h.peripheralId {
                                    return store.sightings.filter { $0.peripheralId == pid }.count
                                }
                                return 0
                            }()
                            Text("\(n) Sichtungen")
                                .font(Theme.meta)
                                .foregroundStyle(Theme.textMuted)
                        }
                        Spacer(minLength: 0)
                        Button("Einblenden") {
                            store.unhideDevice(hiddenId: h.id)
                            fitToken += 1
                        }
                        .font(Theme.meta.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        Button { manageHiddenEntry = h } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .accessibilityLabel("Mehr")
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .font(Theme.caption)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Ausgeblendet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { showHiddenList = false }
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.meta).foregroundStyle(Theme.textMuted)
            Spacer()
            Text(v).font(Theme.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy – HH:mm"
        return f.string(from: date)
    }
}
