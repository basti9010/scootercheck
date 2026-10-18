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
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Space.xl)
            } else {
                List {
                    ForEach(store.targets) { target in
                        watchRow(target)
                            .listRowBackground(Theme.card)
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
            HStack(alignment: .top, spacing: Theme.Space.md) {
                Circle()
                    .fill(target.enabled ? Theme.accent : Theme.textMuted.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.deviceName)
                        .font(Theme.secondary.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(target.watchStatus.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.accent)
                    if let last = target.lastSeenAt {
                        Text("zuletzt \(relative(last))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    if let rssi = target.lastRSSI {
                        let cls = BLESignalClass.from(smoothedRssi: target.lastSmoothedRssi ?? Double(rssi), lost: false)
                        Text("Signal: \(cls.label) · \(rssi) dBm")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(target.enabled ? "Wächter aktiv" : "Pausiert")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { target.enabled },
                    set: { store.setEnabled(id: target.id, enabled: $0); BLEWatchService.shared.updateBackgroundScanIfNeeded() }
                ))
                .labelsHidden()
                .tint(Theme.accent)
            }
            .padding(.vertical, 4)
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

/// Kompakte Statuszeile + Einstellungs-Menü (Radar bleibt minimalistisch).
struct BLERadarControlsCard: View {
    @ObservedObject var radar: BLERadarService
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Circle()
                .fill(radar.isEnabled ? Theme.accent : Theme.textMuted.opacity(0.45))
                .frame(width: 8, height: 8)
            Text(radar.isEnabled ? "Radar aktiv" : "Radar pausiert")
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: Theme.Icon.standard, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: Theme.Control.backHit, height: Theme.Control.backHit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Radar-Einstellungen")
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section {
                        Toggle("Radar aktiv", isOn: Binding(
                            get: { radar.isEnabled },
                            set: { radar.setEnabled($0) }
                        ))
                    }
                    if radar.isEnabled {
                        Section("Alarm ab Signalstärke") {
                            Picker("Signal", selection: $radar.minimumSignalClass) {
                                Text("Mittel").tag(BLESignalClass.medium)
                                Text("Stark").tag(BLESignalClass.strong)
                                Text("Sehr stark").tag(BLESignalClass.veryStrong)
                            }
                            .pickerStyle(.inline)
                        }
                        Section {
                            Toggle("Ton", isOn: $radar.soundEnabled)
                            Toggle("Haptik", isOn: $radar.hapticsEnabled)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .navigationTitle("Radar-Optionen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { showSettings = false }
                            .foregroundStyle(Theme.accent)
                    }
                }
                .preferredColorScheme(.dark)
            }
            .presentationDetents([.medium])
        }
    }
}

struct BLERadarBannerView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: Theme.Icon.standard, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 10)
        .background(Theme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}

struct BLERadarHitBadge: View {
    var body: some View {
        Text("Treffer")
            .font(Theme.badgeFont)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.95))
            .clipShape(Capsule())
    }
}
