import SwiftUI

/// Aktive BLE-Suche: Signal-Heatmap + Trend + Grob-/Feinsuche (kein Richtungs-Pfeil als Haupt-UI).
struct BLESearchScreen: View {
    @ObservedObject var engine: BLESearchEngine
    var onClose: () -> Void

    @State private var showEndDialog = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if engine.searchMode == .fine {
                FineSearchPanel(engine: engine)
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.md)
            } else {
                heatmapCard
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.sm)
            }
            Spacer(minLength: Theme.Space.sm)
            bottomPanel
        }
        .background(Theme.bg.ignoresSafeArea())
        .confirmationDialog(
            "Suchverlauf speichern?",
            isPresented: $showEndDialog,
            titleVisibility: .visible
        ) {
            Button("Speichern") {
                engine.finalizeAndOptionallySave(save: true)
                onClose()
            }
            Button("Verwerfen", role: .destructive) {
                engine.finalizeAndOptionallySave(save: false)
                onClose()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Heatmap und Messpunkte können für später behalten werden.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            Button {
                showEndDialog = true
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zurück")

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.deviceName)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(engine.signalStatus)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
            Text(engine.durationText)
                .font(Theme.caption.monospacedDigit())
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(height: Theme.Chrome.headerHeight)
        .background(Theme.bg)
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SignalHeatmapView(snapshot: engine.heatmap)
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )

            HStack {
                Text("Stark")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accent)
                heatmapLegendBar
                Text("Schwach")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.hintOrange)
            }

            HStack {
                Label("Stärkster Bereich bisher", systemImage: "scope")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(engine.strongestLabel)
                    .font(Theme.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if let rssi = engine.strongestRssi {
                    Text("\(Int(rssi.rounded())) dBm")
                        .font(Theme.caption.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }

            if let hint = engine.positionHint {
                Text(hint)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heatmapLegendBar: some View {
        LinearGradient(
            colors: [
                Theme.accent,
                Color(red: 0.92, green: 0.82, blue: 0.28),
                Theme.hintOrange,
                Color(red: 0.75, green: 0.28, blue: 0.28)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 6)
        .clipShape(Capsule())
    }

    private var bottomPanel: some View {
        VStack(spacing: Theme.Space.md) {
            SignalTrendIndicator(
                signalClass: engine.signalClass,
                trend: engine.trend,
                smoothedRssi: engine.smoothedRssi,
                barLevel: engine.signalClass.barLevel
            )

            Picker("Modus", selection: Binding(
                get: { engine.searchMode },
                set: { engine.setMode($0) }
            )) {
                Text("Grobsuche").tag(BLESearchModeKind.coarse)
                Text("Feinsuche").tag(BLESearchModeKind.fine)
            }
            .pickerStyle(.segmented)
            .font(Theme.segment)

            HStack(spacing: Theme.Space.lg) {
                Toggle(isOn: $engine.hapticsEnabled) {
                    Text("Haptik")
                        .font(Theme.secondary)
                }
                .tint(Theme.accent)
                Toggle(isOn: $engine.audioEnabled) {
                    Text("Ton")
                        .font(Theme.secondary)
                }
                .tint(Theme.accent)
            }
            .foregroundStyle(Theme.textSecondary)

            Text("\(engine.measurementCount) Messpunkte · keine exakte Ortung")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScootOutlineButton(title: "Suche beenden", systemImage: "xmark") {
                showEndDialog = true
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.lg)
        .background(Theme.card.opacity(0.55))
    }
}

// MARK: - Heatmap canvas

struct SignalHeatmapView: View {
    let snapshot: BLEHeatmapSnapshot

    var body: some View {
        Canvas { context, size in
            let bg = Path(CGRect(origin: .zero, size: size))
            context.fill(bg, with: .color(Theme.bg))

            let cols = max(snapshot.cols, 1)
            let rows = max(snapshot.rows, 1)
            let cw = size.width / CGFloat(cols)
            let rh = size.height / CGFloat(rows)

            for r in 0..<rows {
                for c in 0..<cols {
                    let idx = r * cols + c
                    guard idx < snapshot.cells.count, let cell = snapshot.cells[idx] else { continue }
                    // Interpolierte Zellen (samples == 0) etwas weicher
                    let conf = cell.samples > 0 ? cell.confidence : max(0.12, cell.confidence * 0.55)
                    guard let color = BLEHeatmapProcessor.color(forRssi: cell.rssi, confidence: conf) else { continue }
                    let rect = CGRect(
                        x: CGFloat(c) * cw,
                        y: size.height - CGFloat(r + 1) * rh,
                        width: cw + 0.6,
                        height: rh + 0.6
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(color))
                }
            }

            // Breadcrumb-Trail
            if snapshot.trail.count >= 2 {
                var path = Path()
                for (i, p) in snapshot.trail.enumerated() {
                    let pt = project(x: p.x, y: p.y, in: size, snapshot: snapshot)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.22)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
            }
            if let last = snapshot.trail.last {
                let pt = project(x: last.x, y: last.y, in: size, snapshot: snapshot)
                let dot = Path(ellipseIn: CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(Theme.accent.opacity(0.9)))
            }

            // Stärkster Bereich
            if let s = snapshot.strongestCell {
                let cx = (CGFloat(s.col) + 0.5) * cw
                let cy = size.height - (CGFloat(s.row) + 0.5) * rh
                var ring = Path()
                ring.addEllipse(in: CGRect(x: cx - 10, y: cy - 10, width: 20, height: 20))
                context.stroke(ring, with: .color(Color.white.opacity(0.7)), lineWidth: 1.5)
            }
        }
        .accessibilityLabel("Signal-Heatmap")
        .accessibilityHint("Dunkle Bereiche sind noch nicht untersucht. Mint bedeutet stärkeres Signal.")
    }

    private func project(x: Double, y: Double, in size: CGSize, snapshot: BLEHeatmapSnapshot) -> CGPoint {
        let nx = (x - snapshot.originEast) / max(snapshot.boundsMeters, 1)
        let ny = (y - snapshot.originNorth) / max(snapshot.boundsMeters, 1)
        return CGPoint(
            x: CGFloat(nx) * size.width,
            y: size.height - CGFloat(ny) * size.height
        )
    }
}

// MARK: - Trend / bars

struct SignalTrendIndicator: View {
    let signalClass: BLESignalClass
    let trend: BLESignalTrend
    let smoothedRssi: Double?
    let barLevel: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Signal")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Label(trend.label, systemImage: trend.symbol)
                    .font(Theme.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(8, geo.size.width * barLevel))
                }
            }
            .frame(height: 10)

            HStack {
                Text(signalClass.label)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let rssi = smoothedRssi, signalClass != .lost {
                    Text("\(Int(rssi.rounded())) dBm")
                        .font(Theme.caption.monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct FineSearchPanel: View {
    @ObservedObject var engine: BLESearchEngine

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Text("Feinsuche")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)

            Text(engine.signalClass.label)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(12, geo.size.width * engine.signalClass.barLevel))
                }
            }
            .frame(height: 18)

            Label(engine.trend.warmColdLabel, systemImage: engine.trend.symbol)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.accent)

            if let rssi = engine.smoothedRssi, engine.signalClass != .lost {
                Text("\(Int(rssi.rounded())) dBm")
                    .font(Theme.caption.monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
            }

            Text("Heatmap im Hintergrund — fokus auf Annäherung über Signalstärke.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Kompakte Heatmap-Miniatur
            SignalHeatmapView(snapshot: engine.heatmap)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .opacity(0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
    }
}
