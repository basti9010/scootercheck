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
    @State private var expandAnalyse = false
    @State private var expandWhyFingerprint = false
    @State private var showRawRssi = false
    @State private var showOptions = false

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
                heatmapCard
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.sm)
                liveStatusCard
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.md)
                compactStatsRow
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.sm)
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
        .sheet(isPresented: $showOptions) {
            searchOptionsSheet
        }
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
            Button {
                showOptions = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Optionen")
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
            HStack(spacing: Theme.Space.sm) {
                surfaceModePicker
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("Stark")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.accent)
                    heatmapLegendBar
                        .frame(width: 72)
                    Text("Schwach")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.hintOrange)
                }
            }

            ZStack(alignment: .topTrailing) {
                Group {
                    if engine.surfaceMode == .map {
                        BLESearchMapCanvas(
                            overlay: engine.mapOverlay,
                            heatmap: engine.heatmap
                        )
                    } else {
                        SignalHeatmapView(
                            snapshot: engine.heatmap,
                            pathSnapshot: engine.pathSnapshot,
                            breadcrumbs: engine.breadcrumbs,
                            showMeasurementDots: false
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 380)
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

            if let hint = engine.positionHint {
                Text(hint)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Signal")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Text("\(engine.signalClass.label) · \(rssiText)")
                    .font(Theme.secondary.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Trend")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Label(engine.trend.label, systemImage: engine.trend.symbol)
                    .font(Theme.secondary.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Bester Bereich")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Text(bestAreaText)
                    .font(Theme.secondary.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
            }

            if let guide = relativeDirectionGuide {
                HStack(alignment: .firstTextBaseline) {
                    Text("Richtung")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text(guide)
                        .font(Theme.secondary.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(8, geo.size.width * engine.signalClass.barLevel))
                }
            }
            .frame(height: 8)
        }
        .padding(Theme.Space.lg)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var compactStatsRow: some View {
        HStack(spacing: 0) {
            compactStat("Messungen", "\(engine.measurementCount)")
            compactStatDivider
            compactStat("Strecke", engine.pathLengthText)
            compactStatDivider
            compactStat("Dauer", engine.durationText)
            if let ratio = engine.searchGrid.coverageRatio, engine.searchGrid.area?.isMeaningful == true {
                compactStatDivider
                compactStat("Fläche", String(format: "%.0f %%", ratio * 100))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Theme.card.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var compactStatDivider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 4)
    }

    private func compactStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
            Text(value)
                .font(Theme.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var rssiText: String {
        if let rssi = engine.smoothedRssi, engine.signalClass != .lost {
            return "\(Int(rssi.rounded())) dBm"
        }
        return "—"
    }

    private var bestAreaText: String {
        if let rssi = engine.strongestRssi {
            return "\(engine.strongestLabel) · \(Int(rssi.rounded())) dBm"
        }
        return engine.strongestLabel
    }

    /// Grobe relative Richtung zum bisher stärksten Bereich (keine GPS-Ortung).
    private var relativeDirectionGuide: String? {
        guard let current = engine.pathSnapshot.current,
              let heading = current.headingDegrees,
              let cell = engine.heatmap.strongestCell else { return nil }
        let snap = engine.heatmap
        let tx = snap.originEast + (Double(cell.col) + 0.5) * snap.cellSize
        let ty = snap.originNorth + (Double(cell.row) + 0.5) * snap.cellSize
        let dx = tx - current.x
        let dy = ty - current.y
        guard hypot(dx, dy) >= 1.2 else { return "in der Nähe" }
        var bearing = atan2(dx, dy) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        var rel = bearing - heading
        while rel < -180 { rel += 360 }
        while rel > 180 { rel -= 360 }
        switch rel {
        case -22..<22: return "geradeaus"
        case 22..<67: return "rechts vorne"
        case 67..<112: return "rechts"
        case 112..<157: return "rechts hinten"
        case -67 ..< -22: return "links vorne"
        case -112 ..< -67: return "links"
        case -157 ..< -112: return "links hinten"
        default: return "hinten"
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
            Button {
                showOptions = true
            } label: {
                HStack {
                    Label("Optionen", systemImage: "slider.horizontal.3")
                        .font(Theme.secondary.weight(.medium))
                    Spacer()
                    if engine.cameraTrackingEnabled {
                        Image(systemName: "camera.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                engine.cameraTrackingHealthy
                                    ? Color(red: 0.32, green: 0.82, blue: 0.45)
                                    : Theme.danger
                            )
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            collapsibleSection(
                title: "Signalverlauf",
                expanded: $expandSignalHistory
            ) {
                BLELiveRssiGraph(
                    history: engine.signalHistory,
                    showRaw: showRawRssi
                )
                .frame(height: 110)
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

            Text("Relative Signalfläche · keine exakte Ortung")
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

    private var searchOptionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Toggle(isOn: $engine.hapticsEnabled) {
                        Text("Haptik").font(Theme.secondary)
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $engine.audioEnabled) {
                        Text("Ton").font(Theme.secondary)
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: Binding(
                        get: { engine.cameraTrackingEnabled },
                        set: { engine.setCameraTrackingEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Space.sm) {
                                Text("Kamera-Tracking").font(Theme.secondary)
                                if engine.cameraTrackingEnabled {
                                    Image(systemName: "camera.fill")
                                        .foregroundStyle(
                                            engine.cameraTrackingHealthy
                                                ? Color(red: 0.32, green: 0.82, blue: 0.45)
                                                : Theme.danger
                                        )
                                }
                            }
                            Text(engine.cameraTrackingStatus)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .tint(Theme.accent)

                    Toggle("Raw-RSSI im Signalverlauf", isOn: $showRawRssi)
                        .font(Theme.secondary)
                        .tint(Theme.accent)

                    BLERadarControlsCard(radar: radar)

                    Text(engine.surfaceHint)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(Theme.Space.xl)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Optionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { showOptions = false }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium, .large])
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

// MARK: - Heatmap canvas (weiche Signalfläche, kein Kachelraster)

struct SignalHeatmapView: View {
    let snapshot: BLEHeatmapSnapshot
    var pathSnapshot: BLESearchPathSnapshot = .empty
    /// Eingefrorene Messpunkte (RSSI zum Aufnahmezeitpunkt).
    var breadcrumbs: [BLEBreadcrumb] = []
    var showMeasurementDots: Bool = false

    var body: some View {
        Canvas { context, size in
            let bg = Path(CGRect(origin: .zero, size: size))
            context.fill(bg, with: .color(Theme.bg))

            let paintPoints = Self.softPaintPoints(
                breadcrumbs: breadcrumbs,
                snapshot: snapshot
            )
            // Schwache Flächen zuerst, starke zuletzt → Hotspots bleiben lesbar
            let ordered = paintPoints.sorted { $0.rssi < $1.rssi }
            for point in ordered {
                Self.drawSoftBlob(
                    at: project(x: point.x, y: point.y, in: size, snapshot: snapshot),
                    rssi: point.rssi,
                    meters: snapshot.boundsMeters,
                    size: size,
                    context: &context
                )
            }

            let poly: [(x: Double, y: Double)] = {
                if pathSnapshot.smoothedPolyline.count >= 2 {
                    return pathSnapshot.smoothedPolyline
                }
                return snapshot.trail
            }()

            if poly.count >= 2 {
                var path = Path()
                for (i, p) in poly.enumerated() {
                    let pt = project(x: p.x, y: p.y, in: size, snapshot: snapshot)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.14)),
                    style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    path,
                    with: .color(Theme.accent.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
            }

            if showMeasurementDots {
                for b in Self.decimateBreadcrumbs(breadcrumbs, maxCount: 40) {
                    let pt = project(x: b.x, y: b.y, in: size, snapshot: snapshot)
                    let fill = Self.softColor(forRssi: b.rssi)
                    let oval = Path(ellipseIn: CGRect(x: pt.x - 2.2, y: pt.y - 2.2, width: 4.4, height: 4.4))
                    context.fill(oval, with: .color(fill.opacity(0.85)))
                }
            }

            // Stärkster Bereich — Fadenkreuz / Zielring
            if let s = snapshot.strongestCell {
                let wx = snapshot.originEast + (Double(s.col) + 0.5) * snapshot.cellSize
                let wy = snapshot.originNorth + (Double(s.row) + 0.5) * snapshot.cellSize
                let hot = project(x: wx, y: wy, in: size, snapshot: snapshot)
                var outer = Path()
                outer.addEllipse(in: CGRect(x: hot.x - 16, y: hot.y - 16, width: 32, height: 32))
                context.stroke(outer, with: .color(Color.white.opacity(0.55)), lineWidth: 1.5)
                var inner = Path()
                inner.addEllipse(in: CGRect(x: hot.x - 7, y: hot.y - 7, width: 14, height: 14))
                context.stroke(inner, with: .color(Theme.accent.opacity(0.95)), lineWidth: 1.6)
                var cross = Path()
                cross.move(to: CGPoint(x: hot.x - 11, y: hot.y))
                cross.addLine(to: CGPoint(x: hot.x + 11, y: hot.y))
                cross.move(to: CGPoint(x: hot.x, y: hot.y - 11))
                cross.addLine(to: CGPoint(x: hot.x, y: hot.y + 11))
                context.stroke(cross, with: .color(Color.white.opacity(0.7)), lineWidth: 1.1)
            }

            // Standort + Blickrichtung
            if let last = pathSnapshot.current ?? poly.last.map({ BLEPathPoint(x: $0.x, y: $0.y) }) {
                let pt = project(x: last.x, y: last.y, in: size, snapshot: snapshot)
                if let heading = last.headingDegrees ?? pathSnapshot.current?.headingDegrees {
                    Self.drawHeadingCone(at: pt, headingDegrees: heading, context: &context)
                }
                var ring = Path()
                ring.addEllipse(in: CGRect(x: pt.x - 12, y: pt.y - 12, width: 24, height: 24))
                context.stroke(ring, with: .color(Theme.accent.opacity(0.4)), lineWidth: 1.5)
                let dot = Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
                context.fill(dot, with: .color(Theme.accent))
                let core = Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
                context.fill(core, with: .color(Color.white.opacity(0.9)))
            }
        }
        .accessibilityLabel("Signal-Finder Heatmap")
        .accessibilityHint("Weiche Signalfläche. Farben bleiben am Ort, bis dort neu gemessen wird. Keine exakte Ortung.")
    }

    private struct SoftPaintPoint {
        var x: Double
        var y: Double
        var rssi: Double
    }

    /// Frozen Breadcrumbs zuerst; sonst nur gemessene Zellen (kein Soft-Fill-Flackern).
    private static func softPaintPoints(
        breadcrumbs: [BLEBreadcrumb],
        snapshot: BLEHeatmapSnapshot
    ) -> [SoftPaintPoint] {
        if !breadcrumbs.isEmpty {
            return decimateBreadcrumbs(breadcrumbs, maxCount: 70).map {
                SoftPaintPoint(x: $0.x, y: $0.y, rssi: $0.rssi)
            }
        }
        var points: [SoftPaintPoint] = []
        for r in 0..<snapshot.rows {
            for c in 0..<snapshot.cols {
                let idx = r * snapshot.cols + c
                guard idx < snapshot.cells.count, let cell = snapshot.cells[idx], cell.samples > 0 else { continue }
                let x = snapshot.originEast + (Double(c) + 0.5) * snapshot.cellSize
                let y = snapshot.originNorth + (Double(r) + 0.5) * snapshot.cellSize
                points.append(SoftPaintPoint(x: x, y: y, rssi: cell.rssi))
            }
        }
        return points
    }

    private static func drawSoftBlob(
        at center: CGPoint,
        rssi: Double,
        meters: Double,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        let color = softColor(forRssi: rssi)
        // Radius skaliert mit Zoom (~2,5–4 m weiche Ausstrahlung)
        let metersPerPoint = max(meters, 1) / max(Double(size.width), 1)
        let baseRadius = CGFloat(3.2 / metersPerPoint)
        let rings: [(scale: CGFloat, alpha: Double)] = [
            (1.00, 0.05),
            (0.78, 0.08),
            (0.58, 0.12),
            (0.40, 0.18),
            (0.24, 0.28),
            (0.12, 0.42)
        ]
        for ring in rings {
            let r = max(4, baseRadius * ring.scale)
            let oval = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.fill(oval, with: .color(color.opacity(ring.alpha)))
        }
    }

    private static func drawHeadingCone(
        at center: CGPoint,
        headingDegrees: Double,
        context: inout GraphicsContext
    ) {
        // Canvas Y zeigt nach unten; Heading 0 = Nord = negativ Y auf dem Canvas
        let rad = (headingDegrees - 90) * .pi / 180
        let length: CGFloat = 34
        let tip = CGPoint(
            x: center.x + CGFloat(cos(rad)) * length,
            y: center.y + CGFloat(sin(rad)) * length
        )
        let leftRad = rad - 0.38
        let rightRad = rad + 0.38
        let left = CGPoint(
            x: center.x + CGFloat(cos(leftRad)) * length * 0.72,
            y: center.y + CGFloat(sin(leftRad)) * length * 0.72
        )
        let right = CGPoint(
            x: center.x + CGFloat(cos(rightRad)) * length * 0.72,
            y: center.y + CGFloat(sin(rightRad)) * length * 0.72
        )
        var cone = Path()
        cone.move(to: center)
        cone.addLine(to: left)
        cone.addLine(to: tip)
        cone.addLine(to: right)
        cone.closeSubpath()
        context.fill(cone, with: .color(Theme.accent.opacity(0.22)))
        context.stroke(cone, with: .color(Theme.accent.opacity(0.55)), lineWidth: 1)
    }

    /// Mint → Gelb → Orange → Rot (stark → schwach).
    private static func softColor(forRssi rssi: Double) -> Color {
        let t = BLEHeatmapProcessor.normalizedStrength(rssi)
        switch t {
        case 0.72...1.0:
            return Theme.accent
        case 0.52..<0.72:
            return Color(red: 0.48, green: 0.88, blue: 0.52)
        case 0.36..<0.52:
            return Color(red: 0.92, green: 0.82, blue: 0.28)
        case 0.20..<0.36:
            return Theme.hintOrange
        default:
            return Color(red: 0.78, green: 0.32, blue: 0.30)
        }
    }

    private static func decimateBreadcrumbs(_ samples: [BLEBreadcrumb], maxCount: Int) -> [BLEBreadcrumb] {
        guard samples.count > maxCount, maxCount > 1 else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        var out: [BLEBreadcrumb] = []
        for i in 0..<maxCount {
            let idx = min(samples.count - 1, Int((Double(i) * step).rounded()))
            out.append(samples[idx])
        }
        return out
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
        map.setRegion(overlay.region, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.heatmap = heatmap
        context.coordinator.applyRegionIfNeeded(overlay.region, on: map)

        let signature = "\(overlay.coordinates.count)|\(overlay.heatSamples.count)|\(overlay.current?.latitude ?? 0)"
        guard signature != context.coordinator.lastOverlaySignature else { return }
        context.coordinator.lastOverlaySignature = signature

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        if overlay.coordinates.count >= 2 {
            let poly = MKPolyline(coordinates: overlay.coordinates, count: overlay.coordinates.count)
            map.addOverlay(poly, level: .aboveRoads)
        }

        // Breadcrumbs entlang des Laufwegs (ausgedünnt, lesbar wie WLAN-Analyzer)
        let samples = Self.decimate(overlay.heatSamples, maxCount: 80)
        for sample in samples {
            map.addAnnotation(BLEMapHeatAnnotation(coordinate: sample.coord, rssi: sample.rssi))
        }

        if let current = overlay.current {
            map.addAnnotation(BLEMapCurrentAnnotation(coordinate: current))
        }
    }

    private static func decimate(
        _ samples: [(coord: CLLocationCoordinate2D, rssi: Double)],
        maxCount: Int
    ) -> [(coord: CLLocationCoordinate2D, rssi: Double)] {
        guard samples.count > maxCount, maxCount > 1 else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        var out: [(coord: CLLocationCoordinate2D, rssi: Double)] = []
        for i in 0..<maxCount {
            let idx = min(samples.count - 1, Int((Double(i) * step).rounded()))
            out.append(samples[idx])
        }
        return out
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(heatmap: heatmap)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var heatmap: BLEHeatmapSnapshot
        var lastOverlaySignature = ""
        private var lastAppliedRegion: MKCoordinateRegion?

        init(heatmap: BLEHeatmapSnapshot) {
            self.heatmap = heatmap
        }

        func applyRegionIfNeeded(_ region: MKCoordinateRegion, on map: MKMapView) {
            if let prev = lastAppliedRegion {
                let dLat = abs(prev.center.latitude - region.center.latitude)
                let dLon = abs(prev.center.longitude - region.center.longitude)
                let dSpan = abs(prev.span.latitudeDelta - region.span.latitudeDelta)
                // Nur bei spürbarer Änderung zoomen — kein ständiges Zucken
                if dLat < 0.00002, dLon < 0.00002, dSpan < 0.00003 { return }
            }
            lastAppliedRegion = region
            map.setRegion(region, animated: true)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = UIColor(Theme.accent).withAlphaComponent(0.9)
                r.lineWidth = 3.5
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
                view.image = Self.dotImage(color: UIColor(Theme.accent), size: 16, ring: true)
                return view
            }
            if let heat = annotation as? BLEMapHeatAnnotation {
                let id = "heat"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                let color = Self.color(forRssi: heat.rssi)
                // Größere, halbtransparente Kreise entlang der Route
                view.image = Self.dotImage(color: color.withAlphaComponent(0.55), size: 14, ring: false)
                view.alpha = 0.85
                return view
            }
            return nil
        }

        private static func color(forRssi rssi: Double) -> UIColor {
            if let c = BLEHeatmapProcessor.color(forRssi: rssi, confidence: 0.85) {
                return UIColor(c)
            }
            return UIColor(Theme.accent).withAlphaComponent(0.55)
        }

        private static func dotImage(color: UIColor, size: CGFloat, ring: Bool) -> UIImage {
            let s = size + (ring ? 10 : 0)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
            return renderer.image { ctx in
                let rect = CGRect(x: (s - size) / 2, y: (s - size) / 2, width: size, height: size)
                if ring {
                    color.withAlphaComponent(0.4).setStroke()
                    ctx.cgContext.setLineWidth(2)
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

