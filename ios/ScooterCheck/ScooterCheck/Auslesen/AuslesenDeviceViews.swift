import SwiftUI

/// SHU-ähnliche Gerätezeile: Bild · ID · Modell · Signalbalken.
struct ScooterDeviceCard: View {
    let device: ScannedDevice
    /// Gespeicherter Zuordnungsname / Kennzeichen aus früherem Protokoll.
    var knownAlias: String? = nil
    var isNearest: Bool = false
    /// Zusätzliche BLE-Metadaten (Alle-BLE-Modus).
    var showsExtendedBleInfo: Bool = false

    private var displayId: String {
        if let compact = BleModelHint.compactScooterId(from: device.cryptoName.isEmpty ? device.name : device.cryptoName) {
            return compact
        }
        if showsExtendedBleInfo {
            return device.bleListDisplayName
        }
        return device.name
    }

    private var modelTitle: String {
        if let label = device.modelLabel { return label }
        if device.looksLikeScooter { return "Möglicher Scooter" }
        return showsExtendedBleInfo ? "BLE-Gerät" : "BLE-Gerät"
    }

    private var thumbName: String {
        let id = displayId.uppercased()
        // G3-Serienpräfix 1C… auch ohne erkannten Badge dem Max-G3-Asset zuordnen.
        // F3 Pro (1EF…) nicht fälschlich als Max G3 darstellen.
        if id.hasPrefix("1C") {
            return ScooterThumbnailAsset.maxG3
        }
        return ScooterThumbnailAsset.name(
            profile: device.suggestedProfile,
            family: device.suggestedProfile?.family,
            modelLabel: device.modelLabel,
            modelBadge: device.modelBadge
        )
    }

    var body: some View {
            HStack(spacing: 12) {
            Group {
                if device.looksLikeScooter || device.modelLabel != nil {
                    ScooterModelThumbnail(
                        assetName: thumbName,
                        width: 78,
                        height: 66,
                        cornerRadius: 12
                    )
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 78, height: 66)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.line.opacity(0.7), lineWidth: 1)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayId)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let knownAlias, !knownAlias.isEmpty {
                        Text("· \(knownAlias)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                Text(modelTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)

                if showsExtendedBleInfo {
                    Text("\(device.rssi) dBm · \(device.finderSignalLabel) · ID \(device.bleIdentifierShort)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                    if device.isStale {
                        Text("Zuletzt gesehen · Signal veraltet")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                HStack(spacing: 6) {
                    if knownAlias != nil {
                        Text("bekannt")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.warn.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    if knownAlias == nil, device.looksLikeScooter || device.modelLabel != nil {
                        Text(showsExtendedBleInfo ? "Möglicherweise Scooter" : "Erkannt")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    if isNearest {
                        Text("nächstes")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                SignalStrengthView(rssi: device.rssi, style: .shu)
                HStack(spacing: 6) {
                    if !showsExtendedBleInfo {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(knownAlias == nil ? Theme.line : Theme.accent.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            knownAlias.map { "\(modelTitle), \(displayId), \($0), \(device.signalLabel)" }
                ?? "\(modelTitle), \(displayId), \(device.signalLabel)"
        )
    }
}

/// Technische Detailansicht für allgemeine BLE-Geräte — speichert nichts als Scooter.
struct BleDeviceDetailSheet: View {
    let device: ScannedDevice
    var isKnownScooter: Bool = false
    var onProbeAsScooter: () -> Void
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
                        Text(device.classification == .possibleScooter
                             ? "Hinweis: einzelne Merkmale sprechen für einen möglichen Scooter — keine sichere Erkennung."
                             : "Allgemeines BLE-Gerät. Nicht automatisch ein Scooter.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    detailCard

                    BLEWatcherSettingsCard(device: device, isKnownScooter: isKnownScooter)

                    Text("Ein Fremdgerät wird erst nach erfolgreicher Scooter-Validierung dauerhaft gespeichert.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    ScootPrimaryButton(
                        title: "Als möglichen Scooter prüfen",
                        systemImage: "checkmark.shield"
                    ) {
                        onProbeAsScooter()
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

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            detailRow("Name", device.bleListDisplayName)
            detailRow("RSSI", "\(device.rssi) dBm · \(device.finderSignalLabel)")
            detailRow("BLE-ID", device.id.uuidString)
            detailRow("Zuletzt gesehen", lastSeenText)
            if let mfg = device.manufacturerDataHex, !mfg.isEmpty {
                detailRow("Manufacturer Data", mfg)
            } else {
                detailRow("Manufacturer Data", "—")
            }
            if device.serviceUUIDs.isEmpty {
                detailRow("Service UUIDs", "—")
            } else {
                detailRow("Service UUIDs", device.serviceUUIDs.joined(separator: "\n"))
            }
            if device.looksLikeScooter {
                detailRow("Merkmale", "Advertisement-Heuristik: möglicher Scooter")
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SignalStrengthView: View {
    enum Style {
        case compact
        case shu
    }

    let rssi: Int
    var style: Style = .compact

    private var bars: Int {
        switch rssi {
        case -50...0: return 4
        case -65 ..< -50: return 3
        case -80 ..< -65: return 2
        default: return 1
        }
    }

    private var activeColor: Color {
        switch style {
        case .compact:
            return Theme.accent
        case .shu:
            switch bars {
            case 4: return Theme.accent
            case 3: return Color(red: 0.98, green: 0.62, blue: 0.22) // SHU-Orange
            case 2: return Theme.warn
            default: return Theme.danger
            }
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: style == .shu ? 2.5 : 2) {
            ForEach(1...4, id: \.self) { level in
                let step: CGFloat = style == .shu ? 3.5 : 3
                let base: CGFloat = style == .shu ? 7 : 6
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(level <= bars ? activeColor : Color.white.opacity(style == .shu ? 0.22 : 0.15))
                    .frame(
                        width: style == .shu ? 4.5 : 4,
                        height: base + CGFloat(level) * step
                    )
            }
        }
        .accessibilityLabel("Signalstärke \(bars) von 4")
    }
}
