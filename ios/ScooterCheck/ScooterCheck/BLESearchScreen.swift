import SwiftUI
import MapKit
import UIKit
import CoreLocation

/// Aktive BLE-Suche: Heatmap + Analyse-Zusatzbereiche (kein BLE-Kompass).
struct BLESearchScreen: View {
    @ObservedObject var engine: BLESearchEngine
    @ObservedObject private var radar = BLERadarService.shared
    var onClose: () -> Void

    @State private var showEndDialog = false
    @State private var expandSignalHistory = false
    @State private var expandTimeline = false
    @State private var expandAnalyse = true
    @State private var expandWhyFingerprint = false
    @State private var showRawRssi = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if let banner = engine.refoundBanner {
                    refoundBannerView(banner)
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.top, Theme.Space.sm)
                }
                if let radarBanner = radar.banner {
                    BLERadarBannerView(text: radarBanner)
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.top, Theme.Space.sm)
                }
                if engine.searchMode == .fine {
                    FineSearchPanel(engine: engine)
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.top, Theme.Space.md)
                } else {
                    heatmapCard
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.top, Theme.Space.sm)
                }
                bottomPanel
                    .padding(.top, Theme.Space.md)
            }
        }
        .onAppear {
            radar.startSession(enableRadar: radar.isEnabled)
            BLESearchLiveActivityController.shared.start(deviceName: engine.deviceName)
        }
        .onChange(of: engine.signalStatus) { status in
            let lastSeen: String = {
                if status.contains("verloren") { return "Signal verloren" }
                return "vor Kurzem"
            }()
            BLESearchLiveActivityController.shared.update(
                status: status,
                signal: engine.signalClass.label,
                lastSeen: lastSeen,
                deviceName: engine.deviceName
            )
        }
        .onDisappear {
            BLESearchLiveActivityController.shared.end()
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

    private func refoundBannerView(_ text: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: text.contains("Möglicherweise") ? "questionmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(Theme.secondary.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let rssi = engine.smoothedRssi {
                Text("\(Int(rssi.rounded())) dBm")
                    .font(Theme.caption.monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
        )
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            surfaceModePicker

            ZStack(alignment: .topTrailing) {
                Group {
                    if engine.surfaceMode == .map {
                        BLESearchMapCanvas(
                            overlay: engine.mapOverlay,
                            heatmap: engine.heatmap
                        )
                    } else {
                        ZStack {
                            SignalHeatmapView(
                                snapshot: engine.heatmap,
                                pathSnapshot: engine.pathSnapshot,
                                showMeasurementDots: true
                            )
                            if engine.searchGrid.area?.isMeaningful == true {
                                SearchGridOverlay(grid: engine.searchGrid)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )

                Button {
                    engine.recenterViewport()
                } label: {
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.card.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }
                .accessibilityLabel("Zentrieren")
                .padding(10)
            }

            HStack(spacing: Theme.Space.md) {
                metricChip(title: "Messungen", value: "\(engine.measurementCount)")
                metricChip(title: "Strecke", value: engine.pathLengthText)
                metricChip(title: "Dauer", value: engine.durationText)
            }

            Text(engine.surfaceHint)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let coverage = engine.searchGrid.coveragePercentText {
                Text(coverage)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

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

    private var surfaceModePicker: some View {
        Picker("Ansicht", selection: Binding(
            get: { engine.surfaceMode },
            set: { engine.setSurfaceMode($0) }
        )) {
            ForEach(BLESearchSurfaceMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .font(Theme.segment)
        .accessibilityLabel("Relativ oder Karte")
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(Theme.secondary.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
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

            BLERadarControlsCard(radar: radar)

            collapsibleSection(
                title: "Signalverlauf",
                expanded: $expandSignalHistory
            ) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    BLELiveRssiGraph(
                        history: engine.signalHistory,
                        showRaw: showRawRssi
                    )
                    .frame(height: 110)
                    Toggle("Raw-RSSI anzeigen", isOn: $showRawRssi)
                        .font(Theme.caption)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            collapsibleSection(
                title: "Suchverlauf",
                expanded: $expandTimeline
            ) {
                BLESearchTimelineView(events: engine.timeline.chronological)
            }

            collapsibleSection(
                title: "Analyse",
                expanded: $expandAnalyse
            ) {
                analyseContent
            }

            Text("Messungen: \(engine.measurementCount) · Strecke: \(engine.pathLengthText) · keine exakte Ortung")
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

    private var analyseContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            // Fingerprint
            if let match = engine.fingerprintMatch {
                VStack(alignment: .leading, spacing: 6) {
                    Text(match.summary)
                        .font(Theme.secondary.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        expandWhyFingerprint.toggle()
                    } label: {
                        Text(expandWhyFingerprint ? "Warum? ausblenden" : "Warum?")
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    if expandWhyFingerprint {
                        ForEach(match.factors) { factor in
                            HStack(alignment: .top, spacing: 8) {
                                Text(factor.matched ? "✓" : "!")
                                    .font(Theme.caption.weight(.bold))
                                    .foregroundStyle(factor.matched ? Theme.accent : Theme.hintOrange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(factor.title)
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textPrimary)
                                    if let note = factor.note {
                                        Text(note)
                                            .font(Theme.caption)
                                            .foregroundStyle(Theme.textMuted)
                                    }
                                }
                            }
                        }
                        Text("Hohe Übereinstimmung bedeutet nicht sicher dasselbe Gerät.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                            .padding(.top, 4)
                    }
                }
            } else {
                Text("Fingerprint wird aus Advertising-Merkmalen aufgebaut…")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Divider().overlay(Theme.border)

            // Bewegung
            if engine.movementHint.active {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mögliche Bewegung erkannt")
                        .font(Theme.secondary.weight(.medium))
                        .foregroundStyle(Theme.hintOrange)
                    Text(engine.movementHint.explanation)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(engine.movementHint.confidence.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            } else {
                Text("Keine Bewegungsanzeige — Handy und Signal wirken konsistent.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Divider().overlay(Theme.border)

            // Beste Bewegungsrichtung
            VStack(alignment: .leading, spacing: 8) {
                Text(engine.directionTrend.label)
                    .font(Theme.secondary.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if engine.directionTrend.reliable, let deg = engine.directionTrend.headingDegrees {
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .rotationEffect(.degrees(deg))
                        Text(engine.directionTrend.detail)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Kein BLE-Kompass — nur die Richtung, in der sich das Signal zuletzt verbessert hat.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                } else {
                    Text(engine.directionTrend.detail)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func collapsibleSection<Content: View>(
        title: String,
        expanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(Theme.secondary.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue {
                content()
                    .padding(.top, 2)
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - RSSI Graph

struct BLELiveRssiGraph: View {
    let history: BLESignalHistory
    var showRaw: Bool = false

    private let yMax: Double = -40
    private let yMin: Double = -100

    var body: some View {
        Canvas { context, size in
            let bg = Path(CGRect(origin: .zero, size: size))
            context.fill(bg, with: .color(Color.white.opacity(0.04)))

            // Grid lines
            for dbm in stride(from: -40, through: -100, by: -20) {
                let y = yPos(Double(dbm), height: size.height)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
            }

            let points = history.points
            guard let first = points.first, let last = points.last, points.count >= 2 else {
                return
            }
            let t0 = first.timestamp
            let span = max(last.timestamp.timeIntervalSince(t0), 1)

            if showRaw {
                var rawPath = Path()
                var started = false
                for p in points {
                    guard let raw = p.raw else { continue }
                    let x = CGFloat(p.timestamp.timeIntervalSince(t0) / span) * size.width
                    let y = yPos(Double(raw), height: size.height)
                    if !started {
                        rawPath.move(to: CGPoint(x: x, y: y))
                        started = true
                    } else {
                        rawPath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(rawPath, with: .color(Theme.textMuted.opacity(0.45)), lineWidth: 1)
            }

            var path = Path()
            for (i, p) in points.enumerated() {
                let x = CGFloat(p.timestamp.timeIntervalSince(t0) / span) * size.width
                let y = yPos(p.smoothed, height: size.height)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(
                path,
                with: .color(Theme.accent),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            for marker in history.markers {
                let x = CGFloat(marker.timestamp.timeIntervalSince(t0) / span) * size.width
                guard x >= 0, x <= size.width else { continue }
                let color: Color = {
                    switch marker.kind {
                    case .signalLost: return Theme.hintOrange
                    case .signalRefound: return Theme.accent
                    case .strongest: return Color.white.opacity(0.7)
                    }
                }()
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tick, with: .color(color.opacity(0.55)), lineWidth: 1)
            }
        }
        .accessibilityLabel("Live-RSSI-Verlauf")
        .overlay(alignment: .topLeading) {
            Text("−40")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .padding(4)
        }
        .overlay(alignment: .bottomLeading) {
            Text("−100")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    private func yPos(_ rssi: Double, height: CGFloat) -> CGFloat {
        let clamped = min(yMax, max(yMin, rssi))
        let t = (clamped - yMin) / (yMax - yMin)
        return height - CGFloat(t) * height
    }
}

// MARK: - Timeline list

struct BLESearchTimelineView: View {
    let events: [BLESearchEvent]

    var body: some View {
        if events.isEmpty {
            Text("Noch keine Ereignisse")
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(events.reversed()) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Text(timeLabel(event.timestamp))
                            .font(Theme.caption.monospacedDigit())
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(Theme.caption.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            if let d = event.description {
                                Text(d)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Search grid overlay

struct SearchGridOverlay: View {
    let grid: BLESearchGrid

    var body: some View {
        Canvas { context, size in
            guard grid.cols > 0, grid.rows > 0, let area = grid.area else { return }
            let cw = size.width / CGFloat(grid.cols)
            let rh = size.height / CGFloat(grid.rows)
            for r in 0..<grid.rows {
                for c in 0..<grid.cols {
                    let idx = r * grid.cols + c
                    guard idx < grid.cells.count else { continue }
                    let status = grid.cells[idx].status
                    let color: Color = {
                        switch status {
                        case .unscanned: return Color.black.opacity(0.28)
                        case .partial: return Color.white.opacity(0.06)
                        case .scanned: return Color.clear
                        }
                    }()
                    let rect = CGRect(
                        x: CGFloat(c) * cw,
                        y: size.height - CGFloat(r + 1) * rh,
                        width: cw + 0.4,
                        height: rh + 0.4
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
            _ = area
        }
    }
}

// MARK: - Heatmap canvas

struct SignalHeatmapView: View {
    let snapshot: BLEHeatmapSnapshot
    var pathSnapshot: BLESearchPathSnapshot = .empty
    var showMeasurementDots: Bool = false

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
                    let conf = cell.samples > 0 ? cell.confidence : max(0.12, cell.confidence * 0.55)
                    guard let color = BLEHeatmapProcessor.color(forRssi: cell.rssi, confidence: conf) else { continue }
                    let rect = CGRect(
                        x: CGFloat(c) * cw,
                        y: size.height - CGFloat(r + 1) * rh,
                        width: cw + 0.6,
                        height: rh + 0.6
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(color.opacity(0.88)))
                }
            }

            let poly: [(x: Double, y: Double)] = {
                if pathSnapshot.smoothedPolyline.count >= 2 {
                    return pathSnapshot.smoothedPolyline
                }
                return snapshot.trail
            }()

            if showMeasurementDots {
                let step = max(1, poly.count / 48)
                for (i, p) in poly.enumerated() where i % step == 0 {
                    let pt = project(x: p.x, y: p.y, in: size, snapshot: snapshot)
                    let r: CGFloat = 4.5
                    let oval = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                    context.fill(oval, with: .color(Theme.accent.opacity(0.28)))
                }
            }

            if poly.count >= 2 {
                var path = Path()
                for (i, p) in poly.enumerated() {
                    let pt = project(x: p.x, y: p.y, in: size, snapshot: snapshot)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    path,
                    with: .color(Theme.accent.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
            }

            if let last = pathSnapshot.current ?? poly.last.map({ BLEPathPoint(x: $0.x, y: $0.y) }) {
                let pt = project(x: last.x, y: last.y, in: size, snapshot: snapshot)
                var ring = Path()
                ring.addEllipse(in: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22))
                context.stroke(ring, with: .color(Theme.accent.opacity(0.45)), lineWidth: 1.5)
                let dot = Path(ellipseIn: CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9))
                context.fill(dot, with: .color(Theme.accent))
            }

            if let s = snapshot.strongestCell {
                let cx = (CGFloat(s.col) + 0.5) * cw
                let cy = size.height - (CGFloat(s.row) + 0.5) * rh
                var ring = Path()
                ring.addEllipse(in: CGRect(x: cx - 11, y: cy - 11, width: 22, height: 22))
                context.stroke(ring, with: .color(Color.white.opacity(0.75)), lineWidth: 1.5)
                var cross = Path()
                cross.move(to: CGPoint(x: cx - 7, y: cy))
                cross.addLine(to: CGPoint(x: cx + 7, y: cy))
                cross.move(to: CGPoint(x: cx, y: cy - 7))
                cross.addLine(to: CGPoint(x: cx, y: cy + 7))
                context.stroke(cross, with: .color(Color.white.opacity(0.65)), lineWidth: 1)
            }
        }
        .accessibilityLabel("Signal-Heatmap")
        .accessibilityHint("Pfad zeigt relative Bewegung. Mint bedeutet stärkeres Signal. Keine exakte Ortung.")
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

// MARK: - Outdoor MapKit canvas (dezente Karte + Overlay)

struct BLESearchMapCanvas: UIViewRepresentable {
    let overlay: BLEMapOverlayModel
    let heatmap: BLEHeatmapSnapshot

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsTraffic = false
        map.overrideUserInterfaceStyle = .dark
        // Karte bewusst zurückgenommen: dunkles UI + reduzierte POIs; Heatmap/Pfad bleiben dominant.
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.heatmap = heatmap
        map.setRegion(overlay.region, animated: false)

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        if overlay.coordinates.count >= 2 {
            let poly = MKPolyline(coordinates: overlay.coordinates, count: overlay.coordinates.count)
            map.addOverlay(poly, level: .aboveRoads)
        }

        for sample in overlay.heatSamples.suffix(120) {
            let a = BLEMapHeatAnnotation(coordinate: sample.coord, rssi: sample.rssi)
            map.addAnnotation(a)
        }

        if let current = overlay.current {
            let pin = BLEMapCurrentAnnotation(coordinate: current)
            map.addAnnotation(pin)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(heatmap: heatmap)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var heatmap: BLEHeatmapSnapshot

        init(heatmap: BLEHeatmapSnapshot) {
            self.heatmap = heatmap
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = UIColor(Theme.accent).withAlphaComponent(0.85)
                r.lineWidth = 3
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is BLEMapCurrentAnnotation {
                let id = "current"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                view.image = Self.dotImage(color: UIColor(Theme.accent), size: 14, ring: true)
                return view
            }
            if let heat = annotation as? BLEMapHeatAnnotation {
                let id = "heat"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                let color = Self.color(forRssi: heat.rssi)
                view.image = Self.dotImage(color: color, size: 10, ring: false)
                view.alpha = 0.7
                return view
            }
            return nil
        }

        private static func color(forRssi rssi: Double) -> UIColor {
            if let c = BLEHeatmapProcessor.color(forRssi: rssi, confidence: 0.8) {
                return UIColor(c)
            }
            return UIColor(Theme.accent).withAlphaComponent(0.5)
        }

        private static func dotImage(color: UIColor, size: CGFloat, ring: Bool) -> UIImage {
            let s = size + (ring ? 8 : 0)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
            return renderer.image { ctx in
                let rect = CGRect(x: (s - size) / 2, y: (s - size) / 2, width: size, height: size)
                if ring {
                    color.withAlphaComponent(0.35).setStroke()
                    ctx.cgContext.setLineWidth(1.5)
                    ctx.cgContext.strokeEllipse(in: CGRect(x: 1, y: 1, width: s - 2, height: s - 2))
                }
                color.setFill()
                ctx.cgContext.fillEllipse(in: rect)
            }
        }
    }
}

final class BLEMapHeatAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let rssi: Double
    init(coordinate: CLLocationCoordinate2D, rssi: Double) {
        self.coordinate = coordinate
        self.rssi = rssi
    }
}

final class BLEMapCurrentAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
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

            BLELiveRssiGraph(history: engine.signalHistory, showRaw: false)
                .frame(height: 88)

            Text("Heatmap im Hintergrund — Fokus auf Annäherung über Signalstärke.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SignalHeatmapView(
                snapshot: engine.heatmap,
                pathSnapshot: engine.pathSnapshot,
                showMeasurementDots: false
            )
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .opacity(0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
    }
}
