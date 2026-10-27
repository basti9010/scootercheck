import SwiftUI

/// Menübereich „Pedelec auslesen“: Pilotmodell + BLE-Kandidaten + GATT-Auslese.
struct PedelecEvaluationView: View {
    @ObservedObject var ble: BleClient
    var onOpenReadout: (ScannedDevice, PedelecCandidateMatch) -> Void
    var onOpenSignalFinder: () -> Void

    private var pilot: PedelecPilotModel { PedelecEvaluationCore.pilotGhostRiotEN }

    private var ranked: [PedelecRankedDevice] {
        let ads = ble.devices.map(ScannedPedelecAdvertisement.init(device:))
        return PedelecEvaluationCore.rankedCandidates(from: ads)
    }

    private var deviceById: [UUID: ScannedDevice] {
        Dictionary(uniqueKeysWithValues: ble.devices.map { ($0.id, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                VStack(alignment: .leading, spacing: Theme.Space.titleStack) {
                    PageTitle(text: "Pedelec auslesen")
                    Text("Liest Pedelec-/eBike-Bluetooth aus: Erkennung plus Standard-GATT. Assistenz-Limit (DE 25 km/h) und Tuning-Register folgen erst mit Bosch-Protokoll.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                statusCard
                pilotCard
                candidatesSection
                nextStepsCard

                AppCopyrightFooter()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Space.sm)
                    .padding(.bottom, Theme.Space.xxl)
            }
            .scootPagePadding()
            .padding(.top, Theme.Space.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Stand der Auslese", systemImage: "info.circle")
            Text(PedelecEvaluationCore.readoutCapabilitySummary)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.sm) {
                statusChip(title: "BLE-Erkennung", systemImage: "antenna.radiowaves.left.and.right", ok: true)
                statusChip(title: "Standard-GATT", systemImage: "doc.text", ok: true)
                statusChip(title: "Bosch-Register", systemImage: "lock.doc", ok: false)
            }
        }
        .scootCard()
    }

    private func statusChip(title: String, systemImage: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(Theme.meta)
        }
        .foregroundStyle(ok ? Theme.ink : Theme.textMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ok ? Theme.accent.opacity(0.9) : Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    private var pilotCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Pilotmodell", systemImage: "bicycle")
            Text(pilot.title)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(pilot.subtitle)
                .font(Theme.meta)
                .foregroundStyle(Theme.textSecondary)
            if let size = pilot.frameSizeHint {
                Text("Rahmengröße (Foto): \(size)")
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
            }
            VStack(alignment: .leading, spacing: 4) {
                metaRow("Antrieb", pilot.driveSystem)
                metaRow("Motor", pilot.motor)
                metaRow("Display", pilot.displayHint)
                metaRow("Remote", pilot.remoteHint)
            }
            .padding(.top, 2)
            ForEach(pilot.notes, id: \.self) { note in
                Text("· \(note)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scootCard()
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.meta)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(Theme.meta)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                SectionHeader(title: "BLE-Kandidaten in der Nähe", systemImage: "dot.radiowaves.left.and.right")
                Spacer()
                if ble.phase == .scanning {
                    Text("Suche…")
                        .font(Theme.meta)
                        .foregroundStyle(Theme.accent)
                }
            }

            if ranked.isEmpty {
                ScootEmptyStateCard(
                    title: ble.phase == .scanning ? "Noch kein Bosch-/Pedelec-Hinweis" : "Scan starten",
                    message: ble.phase == .scanning
                        ? "Schalte Display und LED-Remote ein und bleibe nah am Ghost RIOT. Ohne Advertisement mit Bosch-ID oder passendem Namen erscheint hier nichts."
                        : "Die Suche läuft über denselben Bluetooth-Scan wie „E-Scooter auslesen“.",
                    actionTitle: ble.phase == .scanning ? nil : "Pedelec suchen",
                    actionSystemImage: "magnifyingglass",
                    action: ble.phase == .scanning ? nil : { ble.startScan() }
                )
            } else {
                VStack(spacing: Theme.Space.listGap) {
                    ForEach(ranked) { row in
                        candidateRow(row)
                    }
                }
            }
        }
    }

    private func candidateRow(_ row: PedelecRankedDevice) -> some View {
        Button {
            if let device = deviceById[row.id] {
                onOpenReadout(device, row.match)
            }
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                Image(systemName: "bicycle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.device.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(row.match.confidence.labelDE) · Score \(row.match.score) · \(row.device.rssi) dBm")
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textSecondary)
                    if let first = row.match.reasons.first {
                        Text(first)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(2)
                    }
                    Text(row.match.deepReadoutAvailable
                         ? "Tiefenauslese verfügbar"
                         : "Tippen → Standard-GATT auslesen")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Pedelec auslesen")
    }

    private var nextStepsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Nächste Schritte mit diesem Ghost", systemImage: "checklist")
            Text("Für den Feldversuch am RIOT EN UNIVERSAL (Kiox 300):")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. System einschalten (Kiox 300 / LED-Remote), nah scannen.")
                Text("2. Treffer tippen → Pedelec auslesen (Standard-GATT, nur Lesen).")
                Text("3. Signal-Finder nutzen, wenn mehrere ähnliche Signale stören.")
                Text("4. Bosch-Limit/Tuning-Register folgen erst mit Protokoll-Anbindung.")
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.textSecondary)

            ScootSecondaryButton(
                title: "Signal-Finder öffnen",
                systemImage: "viewfinder",
                showsChevron: true,
                action: onOpenSignalFinder
            )
            .padding(.top, 4)
        }
        .scootCard()
    }
}
