import SwiftUI

// MARK: - Watcher settings card (device detail)

struct BLEWatcherSettingsCard: View {
    let device: ScannedDevice
    var isKnownScooter: Bool = false

    @ObservedObject private var store = BLEWatchStore.shared
    @ObservedObject private var notifications = BLENotificationService.shared

    private var target: BLEWatchTarget? { store.target(forDeviceId: device.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("Geräte-Wächter")
                    .font(Theme.secondary.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { target?.enabled == true },
                    set: { on in
                        if on {
                            let t = target
                            BLEWatchService.shared.enableWatcher(
                                for: device,
                                isKnownScooter: isKnownScooter,
                                notify: t?.notifyOnSeen ?? true,
                                sound: t?.soundEnabled ?? true,
                                haptics: t?.hapticsEnabled ?? true,
                                minClass: t?.minClass ?? .weak,
                                cooldown: t?.cooldownSeconds ?? 900
                            )
                        } else {
                            BLEWatchService.shared.disableWatcher(deviceId: device.id)
                        }
                    }
                ))
                .labelsHidden()
                .tint(Theme.accent)
                .accessibilityLabel("Geräte-Wächter aktiv")
            }

            if let t = target, t.enabled {
                toggleRow("Benachrichtigen bei Erkennung", t.notifyOnSeen) { new in
                    store.update({ $0.notifyOnSeen = new }, id: t.id)
                }
                toggleRow("Ton", t.soundEnabled) { new in
                    store.update({ $0.soundEnabled = new }, id: t.id)
                }
                toggleRow("Haptik", t.hapticsEnabled) { new in
                    store.update({ $0.hapticsEnabled = new }, id: t.id)
                }

                labeledMenu("Benachrichtigen ab") {
                    Picker("", selection: Binding(
                        get: { t.minClass },
                        set: { new in store.update({ $0.minClass = new }, id: t.id) }
                    )) {
                        Text("jedes erkannte Signal").tag(BLESignalClass.veryWeak)
                        Text("mindestens schwach").tag(BLESignalClass.weak)
                        Text("mindestens mittel").tag(BLESignalClass.medium)
                        Text("mindestens stark").tag(BLESignalClass.strong)
                    }
                    .labelsHidden()
                    .tint(Theme.accent)
                }

                labeledMenu("Erneut benachrichtigen frühestens nach") {
                    Picker("", selection: Binding(
                        get: { t.cooldownSeconds },
                        set: { new in store.update({ $0.cooldownSeconds = new }, id: t.id) }
                    )) {
                        ForEach(BLEWatchTarget.cooldownOptions, id: \.seconds) { opt in
                            Text(opt.label).tag(opt.seconds)
                        }
                    }
                    .labelsHidden()
                    .tint(Theme.accent)
                }

                if let status = target?.watchStatus {
                    Text(status.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.accent)
                }

                if !notifications.isAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Benachrichtigungen sind deaktiviert.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.warn)
                        Button("Einstellungen öffnen") {
                            notifications.openSystemSettings()
                        }
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }

                Text("Wenn ScooterCheck manuell beendet wird, kann iOS die Hintergrundüberwachung stoppen.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Benachrichtigt dich, wenn dieses Gerät später per Bluetooth erkannt wird — auch im Hintergrund, soweit iOS das zulässt.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .task { await notifications.refreshAuthorization() }
    }

    private func toggleRow(_ title: String, _ value: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: set)) {
            Text(title).font(Theme.secondary)
        }
        .tint(Theme.accent)
    }

    private func labeledMenu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
            content()
        }
    }
}

// MARK: - Watch list screen

struct BLEWatchListScreen: View {
    @ObservedObject private var store = BLEWatchStore.shared
    var onSelect: ((BLEWatchTarget) -> Void)?
    /// Zurück zur Funktionsübersicht „E-Scooter finden“.
    var onBack: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FindSubpageHeader(
                title: "Geräte-Wächter",
                subtitle: "Gespeicherte Geräte automatisch wiedererkennen.",
                onBack: onBack
            )
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.md)

            if store.targets.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Keine Wächter aktiv")
                        .font(Theme.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Aktiviere den Geräte-Wächter in der Geräte-Detailansicht für einen bekannten Scooter oder ein BLE-Gerät.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Maximal \(BLEWatchConfig.maxActiveTargets) gleichzeitig. Manuelles Beenden der App kann die Hintergrundüberwachung stoppen.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scootCard()
                .padding(.horizontal, Theme.Space.xl)
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach(store.targets) { target in
                        watchRow(target)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(
                                top: Theme.Space.listGap / 2,
                                leading: Theme.Space.xl,
                                bottom: Theme.Space.listGap / 2,
                                trailing: Theme.Space.xl
                            ))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.remove(id: target.id)
                                    BLEWatchService.shared.updateBackgroundScanIfNeeded()
                                } label: {
                                    Label("Entfernen", systemImage: "trash")
                                }
                            }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func watchRow(_ target: BLEWatchTarget) -> some View {
        Button {
            onSelect?(target)
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.md) {
                Circle()
                    .fill(target.enabled ? Theme.accent : Theme.textMuted.opacity(0.5))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.deviceName)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(target.watchStatus.label)
                        .font(Theme.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    HStack(spacing: Theme.Space.sm) {
                        if let last = target.lastSeenAt {
                            Text("zuletzt \(relative(last))")
                                .font(Theme.meta)
                                .foregroundStyle(Theme.textMuted)
                        }
                        if let rssi = target.lastRSSI {
                            let cls = BLESignalClass.from(
                                smoothedRssi: target.lastSmoothedRssi ?? Double(rssi),
                                lost: false
                            )
                            if target.lastSeenAt != nil {
                                Text("·")
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Text("\(cls.label) · \(rssi) dBm")
                                .font(Theme.meta)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    Text(target.enabled ? "Wächter aktiv" : "Pausiert")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: Theme.Space.sm)
                Toggle("", isOn: Binding(
                    get: { target.enabled },
                    set: { store.setEnabled(id: target.id, enabled: $0); BLEWatchService.shared.updateBackgroundScanIfNeeded() }
                ))
                .labelsHidden()
                .tint(Theme.accent)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func relative(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "vor \(s) s" }
        if s < 3600 { return "vor \(s / 60) min" }
        return "vor \(s / 3600) h"
    }
}

// MARK: - Radar controls

/// Kompakte Statuszeile — ohne Zahnrad (Einstellungen nur über Header).
struct BLERadarControlsCard: View {
    @ObservedObject var radar: BLERadarService
    @ObservedObject private var session = BLERadarSessionStore.shared

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(radar.scanState.compactTitle)
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(radar.scanState.compactSubtitle)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
            if let last = session.lastSightingSummary, let at = session.lastSightingAt {
                Text(relative(at))
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityLabel("Letzte Sichtung \(last) \(relative(at))")
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $radar.showSettingsSheet) {
            BLERadarSettingsSheet(radar: radar)
        }
    }

    private var statusDotColor: Color {
        switch radar.scanState {
        case .bleScanActive, .radarActive: return Theme.accent
        case .backgroundScanLimited, .restoring: return Theme.accent.opacity(0.7)
        case .radarPaused: return Theme.textMuted.opacity(0.55)
        case .bluetoothOff, .radarEnded: return Theme.danger.opacity(0.85)
        }
    }

    private func relative(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "vor \(s) s" }
        return "vor \(max(1, s / 60)) Min."
    }
}

/// Ruhiger Wartezustand, solange noch keine Scooter erkannt wurden.
struct BLERadarWaitingView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.85))
                .scaleEffect(pulse ? 1.08 : 0.94)
                .opacity(pulse ? 1 : 0.55)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text("Suche nach E-Scootern")
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Noch keine Geräte erkannt")
                .font(Theme.meta)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
        .accessibilityElement(children: .combine)
    }
}

/// Kompaktes Bottom Sheet: nur Displaysteuerung.
struct BLERadarSettingsSheet: View {
    @ObservedObject var radar: BLERadarService
    @ObservedObject private var session = BLERadarSessionStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(BLERadarDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                var s = session.settings
                                s.displayMode = mode
                                session.settings = s
                            }
                        } label: {
                            HStack(spacing: Theme.Space.md) {
                                Text(mode.label)
                                    .font(Theme.secondary)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: 0)
                                if session.settings.displayMode == mode {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                    }
                } header: {
                    Text("Display während der Suche")
                } footer: {
                    Text("Die manuelle Displaysperre bleibt jederzeit möglich.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .background(Theme.bg)
            .navigationTitle("Radar-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        radar.persistSettingsToStore()
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

struct BLERadarBannerView: View {
    let text: String
    var warning: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right")
                .font(.system(size: Theme.Icon.standard, weight: .medium))
                .foregroundStyle(warning ? Theme.danger : Theme.accent)
            Text(text)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 10)
        .background((warning ? Theme.danger : Theme.accent).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}

struct BLERadarHitBadge: View {
    var warning: Bool = false

    var body: some View {
        Text(warning ? "Hinweis" : "Treffer")
            .font(Theme.badgeFont)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((warning ? Theme.danger : Theme.accent).opacity(0.95))
            .clipShape(Capsule())
    }
}

struct BLERadarHitCard: View {
    let hit: BLERadarHit
    var onDetails: (() -> Void)?
    /// Vertiefte Diagnose nur auf Nutzeraktion — Radar bleibt passiv.
    var onDiagnose: (() -> Void)?

    private var warning: Bool { hit.alarmKind.accentWarning }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hit.deviceName)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    if let m = hit.manufacturer {
                        Text(m)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
                Text(hit.signalClass.label)
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(warning ? Theme.danger : Theme.accent)
            }
            Text("Passiv erkannt — keine automatische Diagnoseverbindung.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
            if warning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.approvalStatus?.label ?? "Zulassungshinweis")
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let detail = hit.approvalDetail {
                            Text(detail)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Kein rechtlicher Nachweis fehlender Betriebserlaubnis — Fahrzeugdaten prüfen.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                if onDetails != nil {
                    Button("Zulassungsdetails") { onDetails?() }
                        .font(Theme.buttonSecondary)
                        .foregroundStyle(Theme.accent)
                }
            }
            if onDiagnose != nil {
                Button("Diagnose / Protokoll prüfen") { onDiagnose?() }
                    .font(Theme.buttonSecondary)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(Theme.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(warning ? Theme.danger.opacity(0.45) : Theme.border, lineWidth: Theme.Control.hairline)
        )
    }
}
