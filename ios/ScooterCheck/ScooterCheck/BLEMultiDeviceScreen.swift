import SwiftUI

/// Separater Modus: mehrere BLE-Geräte gleichzeitig beobachten — speichert nie als Scooter.
struct BLEMultiDeviceScreen: View {
    @ObservedObject var monitor: BLEMultiDeviceMonitor
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if monitor.observed.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Space.md) {
                        Text("Beobachtung ohne Scooter-Klassifikation. Geräte bleiben allgemeine BLE-Signale.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Space.xl)
                            .padding(.top, Theme.Space.sm)

                        ForEach(monitor.observed) { device in
                            observedCard(device)
                                .padding(.horizontal, Theme.Space.xl)
                        }
                    }
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            ScootOutlineButton(title: "Beobachtung beenden", systemImage: "xmark") {
                monitor.stop()
                onClose()
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.bottom, Theme.Space.lg)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Button {
                monitor.stop()
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Geräte beobachten")
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(monitor.observed.count) ausgewählt")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(height: Theme.Chrome.headerHeight)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.md) {
            Spacer()
            Text("Keine Geräte in Beobachtung")
                .font(Theme.secondary)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    private func observedCard(_ device: ObservedBLEDevice) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text(device.displayName)
                    .font(Theme.secondary.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(device.isVisible ? Theme.accent : Theme.hintOrange.opacity(0.8))
                    .frame(width: 8, height: 8)
                Text(device.isVisible ? "aktiv" : "Signal verloren")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            if device.isVisible {
                HStack(spacing: Theme.Space.md) {
                    if let smooth = device.smoothedRssi {
                        Text("\(Int(smooth.rounded())) dBm")
                            .font(Theme.cardTitle.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    } else if let raw = device.rawRssi {
                        Text("\(raw) dBm")
                            .font(Theme.cardTitle.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                    Label(trendLabel(device.trend), systemImage: device.trend.symbol)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            } else if let last = device.lastSeenAt {
                Text("zuletzt vor \(ago(last))")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            if let sim = device.similarity, sim != .none {
                Text(sim.label)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("ID \(device.id.uuidString.prefix(8)) · Beobachtung")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Space.lg)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func trendLabel(_ t: BLESignalTrend) -> String {
        switch t {
        case .stronger: return "stärker"
        case .stable: return "stabil"
        case .weaker: return "schwächer"
        }
    }

    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(s) s" }
        return String(format: "%d:%02d min", s / 60, s % 60)
    }
}

/// Auswahl für Multi-Device-Modus (1–5 Geräte).
struct BLEMultiDevicePicker: View {
    let devices: [ScannedDevice]
    @Binding var selectedIds: Set<UUID>
    var onStart: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wähle 1–\(BLEMultiDeviceMonitor.maxDevices) Geräte. Es erfolgt keine automatische Scooter-Speicherung.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.bg)
                }
                Section {
                    ForEach(devices) { device in
                        Button {
                            toggle(device.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.bleListDisplayName)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(device.rssi) dBm · \(device.bleIdentifierShort)")
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                Image(systemName: selectedIds.contains(device.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIds.contains(device.id) ? Theme.accent : Theme.textMuted)
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Geräte beobachten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                        .foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starten", action: onStart)
                        .foregroundStyle(Theme.accent)
                        .disabled(selectedIds.count < BLEMultiDeviceMonitor.minDevices
                                  || selectedIds.count > BLEMultiDeviceMonitor.maxDevices)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else if selectedIds.count < BLEMultiDeviceMonitor.maxDevices {
            selectedIds.insert(id)
        }
    }
}
