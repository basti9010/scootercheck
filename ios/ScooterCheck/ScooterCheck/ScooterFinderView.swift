import SwiftUI

/// Geräteauswahl + Finder für „Scooter finden“.
struct ScooterFinderView: View {
    @ObservedObject var ble: BleClient
    @StateObject private var engine = ScooterFinderEngine()
    @State private var selected: ScannedDevice?
    @State private var showInfo = false

    private var isFinding: Bool { selected != nil }

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
        }
        .onDisappear {
            engine.stop()
        }
        .sheet(isPresented: $showInfo) {
            finderInfoSheet
        }
    }

    // MARK: - Selection

    private var selectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    PageTitle(text: "Scooter finden")
                    Text("Wähle einen Scooter aus der Gerätesuche. Anschließend schätzt ScooterCheck die bessere Signalrichtung anhand deiner Bewegung.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textBody)
                        .lineSpacing(4)
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

                let devices = ble.visibleDevices.filter(\.looksLikeScooter)
                if devices.isEmpty {
                    emptySelectionCard
                } else {
                    VStack(spacing: 10) {
                        ForEach(devices) { device in
                            Button {
                                startFinding(device)
                            } label: {
                                finderDeviceRow(device)
                            }
                            .buttonStyle(.plain)
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
            Text("Keine Scooter in Reichweite")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Halte das iPhone in der Nähe und warte, bis Geräte in der Gerätesuche erscheinen.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scootCard()
    }

    private func finderDeviceRow(_ device: ScannedDevice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.modelLabel ?? (device.looksLikeScooter ? "Scooter" : device.name))
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
                Text(lastSeenLabel(device.lastSeen))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
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

    // MARK: - Finder

    private func finderContent(for device: ScannedDevice) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text(device.modelLabel ?? "Ausgewählter Scooter")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(finderDisplayId(device))
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.muted)
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
        return device.name
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
