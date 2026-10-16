import SwiftUI

// MARK: - Branding

struct Wordmark: View {
    var size: Font = .title
    var showsMark: Bool = true
    var body: some View {
        HStack(spacing: 8) {
            if showsMark {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.accent.opacity(0.25), lineWidth: 0.5)
                    )
                    .accessibilityHidden(true)
            }
            HStack(spacing: 0) {
                Text("Scooter").foregroundStyle(Theme.accent)
                Text("Check").foregroundStyle(.white)
            }
        }
        .font(size.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Runder ☰-Button wie im Mockup.
struct MenuGlyphButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menü öffnen")
    }
}

// MARK: - Buttons

struct ScootPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(Theme.ink)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .foregroundStyle(Theme.ink)
            .background(Theme.accent.opacity(enabled ? 1 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

struct ScootSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var showsChevron: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.line.opacity(1.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ScootOutlineButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(Theme.accent)
            .background(Theme.bg.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.accent.opacity(0.85), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status badge

struct VerdictBadge: View {
    let verdict: VerdictLevel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(Theme.verdictBadgeTitle(verdict))
                .font(Theme.badgeFont)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.verdict(verdict))
        .clipShape(Capsule())
    }

    private var icon: String {
        switch verdict {
        case .stock: return "checkmark"
        case .auffaellig: return "exclamationmark"
        case .hinweise: return "exclamationmark.triangle.fill"
        case .eindeutig: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Start hero + waves

struct StartHeroGraphic: View {
    var body: some View {
        ZStack {
            // Soft mint bloom behind the icon (matches reference atmosphere).
            Circle()
                .fill(Theme.accent.opacity(0.10))
                .frame(width: 210, height: 210)
                .blur(radius: 24)
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 168, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(Theme.accent.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Theme.accent.opacity(0.28), radius: 18)
        }
        .frame(height: 210)
        .accessibilityHidden(true)
    }
}

/// Langsame mintfarbene Punkt-/Signalwellen am unteren Startscreen.
struct AnimatedSignalWaves: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                waveCanvas(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                    waveCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func waveCanvas(time t: TimeInterval) -> some View {
        Canvas { context, size in
            // Mehrere Ebenen: leicht unterschiedliche Horizontaldrift + Amplitude.
            let layers: [(amp: CGFloat, speed: CGFloat, drift: CGFloat, y: CGFloat, alpha: Double, spacing: CGFloat)] = [
                (9, 0.42, 6.0, size.height * 0.30, 0.52, 7.5),
                (13, 0.28, 4.2, size.height * 0.50, 0.36, 8.5),
                (7, 0.55, 7.5, size.height * 0.70, 0.26, 6.5),
                (5, 0.35, 3.0, size.height * 0.86, 0.18, 9.0)
            ]
            for layer in layers {
                let offsetX = CGFloat(t * layer.drift).truncatingRemainder(dividingBy: layer.spacing * 4)
                var x: CGFloat = -24 - offsetX
                while x < size.width + 24 {
                    let wobble = sin((x / 30) + t * layer.speed) * layer.amp
                    let y = layer.y + wobble
                    let rect = CGRect(x: x, y: y, width: 2.1, height: 2.1)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Theme.accent.opacity(layer.alpha))
                    )
                    x += layer.spacing
                }
            }
        }
        .blur(radius: 0.35)
    }
}

// MARK: - Sonar / search atmosphere

/// Kompaktes Status-Sonar (Header „Suche aktiv“).
struct RotatingSonarIcon: View {
    var size: CGFloat = 22
    var isScanning: Bool = true

    var body: some View {
        SonarRadarView(
            isScanning: isScanning,
            blipCount: 3,
            size: size,
            style: .compact
        )
        .accessibilityHidden(true)
    }
}

/// Großes Radar wie im App-Icon: Ringe, Strahl, Blips, Scooter + Check.
struct SonarRadarView: View {
    enum Style {
        case compact
        case hero
        case search
    }

    var isScanning: Bool
    var blipCount: Int = 0
    var highlightIndex: Int? = nil
    var size: CGFloat = 220
    var style: Style = .search
    /// Kurzer Glow-Boost wenn ein Gerät neu erkannt wurde.
    var discoveryFlash: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// ~2 s pro Umdrehung.
    private let revolutionSeconds: Double = 2.0

    private var ringCount: Int {
        switch style {
        case .compact: return 2
        case .hero, .search: return 4
        }
    }

    private var showsScooter: Bool { style != .compact }
    private var showsCrosshair: Bool { style != .compact }

    private var blips: [SonarBlip] {
        SonarBlip.seeded(count: max(blipCount, style == .hero ? 5 : 0), style: style)
    }

    var body: some View {
        Group {
            if isScanning && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    radarContent(angle: sweepAngle(at: timeline.date))
                }
            } else {
                radarContent(angle: isScanning && reduceMotion ? 42 : (style == .hero ? 38 : 0))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(discoveryFlash ? 1.04 : 1.0)
        .shadow(color: Theme.accent.opacity(discoveryFlash ? 0.55 : (isScanning ? 0.22 : 0.12)),
                radius: discoveryFlash ? 18 : (style == .compact ? 3 : 10))
        .animation(.easeOut(duration: 0.45), value: discoveryFlash)
        .accessibilityHidden(true)
    }

    private func sweepAngle(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: revolutionSeconds) / revolutionSeconds) * 360.0
    }

    @ViewBuilder
    private func radarContent(angle: Double) -> some View {
        ZStack {
            // Soft fill disk
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.accent.opacity(style == .compact ? 0.10 : 0.08),
                            Theme.accent.opacity(0.02),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.5
                    )
                )

            // Concentric rings (static)
            ForEach(1...ringCount, id: \.self) { i in
                let frac = CGFloat(i) / CGFloat(ringCount)
                Circle()
                    .stroke(Theme.accent.opacity(0.14 + Double(i) * 0.04), lineWidth: style == .compact ? 0.8 : 1.15)
                    .frame(width: size * (0.28 + frac * 0.68), height: size * (0.28 + frac * 0.68))
            }

            if showsCrosshair {
                Rectangle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: size * 0.92, height: 0.75)
                Rectangle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 0.75, height: size * 0.92)
            }

            // Sweep wedge (only while scanning, or static wedge on hero)
            if isScanning || style == .hero {
                SonarSweepWedge(spanDegrees: style == .compact ? 48 : 56)
                    .fill(
                        AngularGradient(
                            colors: [
                                Theme.accent.opacity(0.0),
                                Theme.accent.opacity(style == .compact ? 0.18 : 0.22),
                                Theme.accent.opacity(style == .compact ? 0.42 : 0.48)
                            ],
                            center: .center,
                            startAngle: .degrees(-56),
                            endAngle: .degrees(0)
                        )
                    )
                    .frame(width: size * 0.96, height: size * 0.96)
                    .rotationEffect(.degrees(angle))
                    .opacity(isScanning || style == .hero ? 1 : 0)
            }

            // Leading edge line of the beam
            if isScanning || style == .hero {
                Capsule()
                    .fill(Theme.accent.opacity(0.75))
                    .frame(width: 1.4, height: size * 0.46)
                    .offset(y: -size * 0.23)
                    .rotationEffect(.degrees(angle))
                    .shadow(color: Theme.accent.opacity(0.45), radius: 3)
            }

            // Device blips
            ForEach(Array(blips.enumerated()), id: \.offset) { index, blip in
                let lit = isScanning && !reduceMotion && isSwept(blipAngle: blip.angle, sweep: angle)
                let highlighted = highlightIndex == index
                Circle()
                    .fill(Color.white.opacity(highlighted || lit ? 0.95 : 0.75))
                    .frame(width: blipDiameter(blip, lit: lit || highlighted),
                           height: blipDiameter(blip, lit: lit || highlighted))
                    .shadow(color: Theme.accent.opacity(lit || highlighted ? 0.9 : 0.35),
                            radius: lit || highlighted ? 6 : 2)
                    .offset(
                        x: cos((blip.angle - 90) * .pi / 180) * size * blip.radius,
                        y: sin((blip.angle - 90) * .pi / 180) * size * blip.radius
                    )
            }

            if showsScooter {
                scooterCore
            } else {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: max(3, size * 0.14), height: max(3, size * 0.14))
            }
        }
    }

    private var scooterCore: some View {
        ZStack {
            Image("ScooterGeneric")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.42, height: size * 0.28)
                .shadow(color: Theme.accent.opacity(0.45), radius: 10)

            // Checkmark badge at center (icon language)
            ZStack {
                Circle()
                    .fill(Theme.bg.opacity(0.88))
                    .frame(width: size * 0.16, height: size * 0.16)
                Circle()
                    .stroke(Theme.accent.opacity(0.85), lineWidth: 1.4)
                    .frame(width: size * 0.16, height: size * 0.16)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.07, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .shadow(color: Theme.accent.opacity(0.4), radius: 6)
            .offset(y: size * 0.01)
        }
    }

    private func blipDiameter(_ blip: SonarBlip, lit: Bool) -> CGFloat {
        let base = style == .compact ? size * 0.10 : size * blip.dot
        return lit ? base * 1.45 : base
    }

    /// Blip leuchtet kurz auf, wenn der Strahl ihn überstreicht (±14°).
    private func isSwept(blipAngle: Double, sweep: Double) -> Bool {
        let delta = abs(normalizedDelta(blipAngle - sweep))
        return delta < 14
    }

    private func normalizedDelta(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

private struct SonarBlip {
    let angle: Double
    let radius: CGFloat
    let dot: CGFloat

    static func seeded(count: Int, style: SonarRadarView.Style) -> [SonarBlip] {
        guard count > 0 else { return [] }
        // Feste, ruhige Positionen (wie im Icon) — keine Zufalls-Jitter pro Frame.
        let catalog: [SonarBlip] = [
            .init(angle: 28, radius: 0.28, dot: 0.028),
            .init(angle: 78, radius: 0.36, dot: 0.022),
            .init(angle: 142, radius: 0.31, dot: 0.026),
            .init(angle: 198, radius: 0.38, dot: 0.020),
            .init(angle: 248, radius: 0.27, dot: 0.024),
            .init(angle: 302, radius: 0.34, dot: 0.022),
            .init(angle: 338, radius: 0.22, dot: 0.018),
            .init(angle: 55, radius: 0.42, dot: 0.020),
            .init(angle: 170, radius: 0.20, dot: 0.024),
            .init(angle: 265, radius: 0.40, dot: 0.018)
        ]
        let n = min(count, catalog.count)
        if style == .compact {
            return Array(catalog.prefix(min(n, 3))).map {
                SonarBlip(angle: $0.angle, radius: min($0.radius, 0.32), dot: 0.12)
            }
        }
        return Array(catalog.prefix(n))
    }
}

private struct SonarSweepWedge: Shape {
    var spanDegrees: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-spanDegrees),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Such-Grafik im Geräte-Screen (großes Sonar).
struct PulsingSearchGraphic: View {
    var isScanning: Bool = true
    var deviceCount: Int = 0
    var discoveryFlash: Bool = false
    var size: CGFloat = 210

    var body: some View {
        SonarRadarView(
            isScanning: isScanning,
            blipCount: max(deviceCount, isScanning ? 4 : 3),
            highlightIndex: deviceCount > 0 ? 0 : nil,
            size: size,
            style: .search,
            discoveryFlash: discoveryFlash
        )
        .frame(height: size)
    }
}

// MARK: - Copyright

struct AppCopyrightFooter: View {
    private var line: String {
        let year = Calendar.current.component(.year, from: Date())
        return "© \(year) Bastian Ellinghausen"
    }

    var body: some View {
        Text(verbatim: line)
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .accessibilityLabel(line)
    }
}
