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

/// Statuszeile + Zahnrad für Radar-Einstellungen (Display, Alarme, Signal).
struct BLERadarControlsCard: View {
    @ObservedObject var radar: BLERadarService
    @ObservedObject private var session = BLERadarSessionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                Circle()
                    .fill(radar.isEnabled ? Theme.accent : Theme.textMuted.opacity(0.45))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(radar.isEnabled ? "Radar aktiv" : "Radar pausiert")
                        .font(Theme.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(radar.scanState.label)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
                Button {
                    radar.showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: Theme.Icon.standard, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.Control.backHit, height: Theme.Control.backHit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Radar-Einstellungen")
            }
            Text(radar.scanStateDetail)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let last = session.lastSightingSummary, let at = session.lastSightingAt {
                Text("Letzte Sichtung: \(last) · \(relative(at))")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .sheet(isPresented: $radar.showSettingsSheet) {
            BLERadarSettingsSheet(radar: radar)
        }
    }

    private func relative(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "vor \(s) s" }
        return "vor \(max(1, s / 60)) Min."
    }
}

struct BLERadarSettingsSheet: View {
    @ObservedObject var radar: BLERadarService
    @ObservedObject private var session = BLERadarSessionStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Radar aktiv", isOn: Binding(
                        get: { radar.isEnabled },
                        set: { radar.setEnabled($0) }
                    ))
                }
                Section("Display") {
                    Picker("Display", selection: Binding(
                        get: { session.settings.displayMode },
                        set: { mode in
                            var s = session.settings
                            s.displayMode = mode
                            session.settings = s
                        }
                    )) {
                        ForEach(BLERadarDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    Text("Manuelle Sperre wird nie verhindert. „Eingeschaltet lassen“ gilt nur im Vordergrund.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                if radar.isEnabled {
                    Section("Benachrichtigungen") {
                        Toggle("Scooter-Erkennung melden", isOn: Binding(
                            get: { session.settings.notifyScooterDetections },
                            set: { v in
                                var s = session.settings
                                s.notifyScooterDetections = v
                                session.settings = s
                            }
                        ))
                        Toggle("Zulassungshinweise hervorheben", isOn: Binding(
                            get: { session.settings.highlightApprovalWarnings },
                            set: { v in
                                var s = session.settings
                                s.highlightApprovalWarnings = v
                                session.settings = s
                            }
                        ))
                        Toggle("Ton aktivieren", isOn: Binding(
                            get: { radar.soundEnabled },
                            set: { v in
                                radar.soundEnabled = v
                                radar.persistSettingsToStore()
                            }
                        ))
                        Toggle("Haptik aktivieren", isOn: Binding(
                            get: { radar.hapticsEnabled },
                            set: { v in
                                radar.hapticsEnabled = v
                                radar.persistSettingsToStore()
                            }
                        ))
                        Text("Haptik nur bei entsperrtem iPhone. Sperrbildschirm: iOS entscheidet über Notification-Ton.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Section("Signalempfindlichkeit") {
                        Picker("Alarm ab", selection: Binding(
                            get: { radar.minimumSignalClass },
                            set: { v in
                                radar.minimumSignalClass = v
                                radar.persistSettingsToStore()
                            }
                        )) {
                            Text("Mittel").tag(BLESignalClass.medium)
                            Text("Stark").tag(BLESignalClass.strong)
                            Text("Sehr stark").tag(BLESignalClass.veryStrong)
                        }
                        .pickerStyle(.inline)
                    }
                    Section("Benachrichtigungswiederholung") {
                        Picker("Wiederholung", selection: Binding(
                            get: {
                                BLERadarNotifyCooldown(rawValue: session.settings.notifyCooldownSeconds)
                                    ?? .fiveMinutes
                            },
                            set: { v in
                                var s = session.settings
                                s.notifyCooldownSeconds = v.rawValue
                                session.settings = s
                            }
                        )) {
                            ForEach(BLERadarNotifyCooldown.allCases, id: \.self) { c in
                                Text(c.label).tag(c)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
                Section("Hintergrund") {
                    Text(radar.scanStateDetail)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Text("Uneingeschränkte Suche aller BLE-Geräte im klassischen Hintergrundmodus ist von iOS nicht zugesichert. Radar filtert dann auf bekannte Service-UUIDs (Ninebot/Xiaomi). Ohne Widget-Extension keine echte Live-Activity-UI.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
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
        .presentationDetents([.medium, .large])
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
