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
            Circle()
                .fill(Theme.accent.opacity(0.07))
                .frame(width: 200, height: 200)
                .blur(radius: 28)
            // Vektor-Radar als Hero — kein skaliertes Bitmap im Zentrum.
            SonarRadarView(
                isScanning: false,
                blipCount: 4,
                size: 196,
                style: .hero
            )
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
            let layers: [(amp: CGFloat, speed: CGFloat, drift: CGFloat, y: CGFloat, alpha: Double, spacing: CGFloat, dot: CGFloat)] = [
                (7, 0.36, 4.5, size.height * 0.30, 0.42, 9.0, 1.4),
                (10, 0.24, 3.2, size.height * 0.50, 0.28, 10.0, 1.3),
                (6, 0.48, 5.5, size.height * 0.70, 0.20, 8.0, 1.2),
                (4, 0.30, 2.4, size.height * 0.86, 0.14, 11.0, 1.1)
            ]
            for layer in layers {
                let offsetX = CGFloat(t * layer.drift).truncatingRemainder(dividingBy: layer.spacing * 4)
                var x: CGFloat = -24 - offsetX
                while x < size.width + 24 {
                    let wobble = sin((x / 32) + t * layer.speed) * layer.amp
                    let y = layer.y + wobble
                    let d = layer.dot
                    let rect = CGRect(x: x, y: y, width: d, height: d)
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(layer.alpha)))
                    x += layer.spacing
                }
            }
        }
    }
}

// MARK: - Sonar / search atmosphere

/// Kompaktes Status-Sonar (Header „Suche aktiv“) — rein vektorbasiert.
struct RotatingSonarIcon: View {
    var size: CGFloat = 22
    var isScanning: Bool = true

    var body: some View {
        SonarRadarView(
            isScanning: isScanning,
            blipCount: 2,
            size: size,
            style: .compact
        )
        .accessibilityHidden(true)
    }
}

/// Vektor-Radar: feine Ringe, Crosshair, weicher Sweep (eine Vorderkante),
/// Blips und weiße Scooter-Silhouette — kein Bitmap-Look.
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
    var discoveryFlash: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let revolutionSeconds: Double = 2.0

    private var blips: [SonarBlip] {
        let fallback = (style == .hero) ? 4 : (isScanning ? 4 : 3)
        return SonarBlip.seeded(count: max(blipCount, fallback), style: style)
    }

    var body: some View {
        Group {
            if isScanning && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 45)) { timeline in
                    canvas(angle: sweepAngle(at: timeline.date))
                }
            } else {
                canvas(angle: idleAngle)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(discoveryFlash ? 1.025 : 1.0)
        .animation(.easeOut(duration: 0.4), value: discoveryFlash)
        .accessibilityHidden(true)
    }

    private var idleAngle: Double {
        if isScanning && reduceMotion { return 48 }
        if style == .hero { return 36 }
        return 0
    }

    private func sweepAngle(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: revolutionSeconds) / revolutionSeconds) * 360.0
    }

    private func canvas(angle: Double) -> some View {
        let drawSweep = isScanning || style == .hero
        let showScooter = style != .compact
        let rings = style == .compact ? 2 : 5
        let strokeW: CGFloat = style == .compact ? 0.7 : 0.9
        let span: Double = style == .compact ? 42 : 52
        let flashBoost = discoveryFlash ? 1.35 : 1.0

        return Canvas { context, canvasSize in
            let mid = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2

            // Soft mint disk
            let disk = Path(ellipseIn: CGRect(
                x: mid.x - radius, y: mid.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.fill(
                disk,
                with: .radialGradient(
                    Gradient(colors: [
                        Theme.accent.opacity(0.07 * flashBoost),
                        Theme.accent.opacity(0.02),
                        .clear
                    ]),
                    center: mid,
                    startRadius: 2,
                    endRadius: radius
                )
            )

            // Concentric rings — hairline
            for i in 1...rings {
                let frac = CGFloat(i) / CGFloat(rings)
                let r = radius * (0.22 + frac * 0.74)
                var ring = Path()
                ring.addEllipse(in: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2))
                context.stroke(
                    ring,
                    with: .color(Theme.accent.opacity(0.12 + Double(i) * 0.03)),
                    lineWidth: strokeW
                )
            }

            // Crosshair
            if style != .compact {
                var h = Path(); h.move(to: CGPoint(x: mid.x - radius * 0.92, y: mid.y)); h.addLine(to: CGPoint(x: mid.x + radius * 0.92, y: mid.y))
                var v = Path(); v.move(to: CGPoint(x: mid.x, y: mid.y - radius * 0.92)); v.addLine(to: CGPoint(x: mid.x, y: mid.y + radius * 0.92))
                context.stroke(h, with: .color(Theme.accent.opacity(0.10)), lineWidth: 0.6)
                context.stroke(v, with: .color(Theme.accent.opacity(0.10)), lineWidth: 0.6)
            }

            // Soft sweep: many thin slices fading to zero — no trailing hard edge,
            // no separate capsule (that caused the double-line look).
            if drawSweep {
                let steps = style == .compact ? 28 : 48
                let leadingWidth: Double = style == .compact ? 1.1 : 1.35
                for i in 0..<steps {
                    let t = Double(i) / Double(steps - 1)
                    // t=0 at leading edge (bright), t=1 at trailing (invisible)
                    let a0 = angle - span * t
                    let a1 = angle - span * min(1, t + 1.0 / Double(steps))
                    // Quadratic fade → no hard trailing contour
                    let alpha = (1.0 - t) * (1.0 - t) * (style == .compact ? 0.38 : 0.32) * flashBoost
                    guard alpha > 0.004 else { continue }
                    var wedge = Path()
                    wedge.move(to: mid)
                    wedge.addArc(
                        center: mid,
                        radius: radius * 0.98,
                        startAngle: .degrees(a1 - 90),
                        endAngle: .degrees(a0 - 90),
                        clockwise: false
                    )
                    wedge.closeSubpath()
                    context.fill(wedge, with: .color(Theme.accent.opacity(alpha)))
                }
                // Single soft leading edge (not a second stroke behind the sweep)
                var lead = Path()
                let leadRad = radius * 0.98
                let lx = mid.x + leadRad * CGFloat(cos((angle - 90) * .pi / 180))
                let ly = mid.y + leadRad * CGFloat(sin((angle - 90) * .pi / 180))
                lead.move(to: mid)
                lead.addLine(to: CGPoint(x: lx, y: ly))
                context.stroke(
                    lead,
                    with: .color(Theme.accent.opacity(0.55 * flashBoost)),
                    style: StrokeStyle(lineWidth: leadingWidth, lineCap: .round)
                )
            }

            // Blips
            for (index, blip) in blips.enumerated() {
                let lit = drawSweep && isScanning && !reduceMotion && isSwept(blipAngle: blip.angle, sweep: angle)
                let highlighted = highlightIndex == index
                let bright = lit || highlighted
                let br = radius * blip.radius
                let bx = mid.x + br * CGFloat(cos((blip.angle - 90) * .pi / 180))
                let by = mid.y + br * CGFloat(sin((blip.angle - 90) * .pi / 180))
                let baseDot: CGFloat = style == .compact
                    ? max(1.6, size * 0.055)
                    : max(2.0, size * blip.dot)
                let d = bright ? baseDot * 1.35 : baseDot
                let dotRect = CGRect(x: bx - d / 2, y: by - d / 2, width: d, height: d)
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(Color.white.opacity(bright ? 0.95 : 0.55))
                )
                if bright {
                    let glow = d * 2.2
                    let glowRect = CGRect(x: bx - glow / 2, y: by - glow / 2, width: glow, height: glow)
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(Theme.accent.opacity(0.22))
                    )
                }
            }

            // Center: white vector scooter + check, or mint hub for compact
            if showScooter {
                drawScooterCore(context: &context, mid: mid, size: size)
            } else {
                let hub = max(2.2, size * 0.12)
                context.fill(
                    Path(ellipseIn: CGRect(x: mid.x - hub / 2, y: mid.y - hub / 2, width: hub, height: hub)),
                    with: .color(Theme.accent.opacity(0.9))
                )
            }
        }
    }

    private func drawScooterCore(context: inout GraphicsContext, mid: CGPoint, size: CGFloat) {
        let w = size * 0.46
        let h = size * 0.30
        let box = CGRect(x: mid.x - w / 2, y: mid.y - h / 2 + size * 0.008, width: w, height: h)
        let line = max(1.2, size * 0.011)
        let scooter = ScooterSilhouette().path(in: box)
        context.stroke(
            scooter,
            with: .color(Color.white.opacity(0.94)),
            style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        )

        // Check badge — sits in the open frame area, no bitmap tile
        let badge = size * 0.15
        let badgeRect = CGRect(x: mid.x - badge / 2, y: mid.y - badge / 2 + size * 0.01, width: badge, height: badge)
        context.fill(Path(ellipseIn: badgeRect), with: .color(Theme.bg.opacity(0.94)))
        context.stroke(
            Path(ellipseIn: badgeRect.insetBy(dx: 0.3, dy: 0.3)),
            with: .color(Theme.accent.opacity(0.92)),
            lineWidth: max(1.0, size * 0.007)
        )
        let ck = badgeRect.insetBy(dx: badge * 0.28, dy: badge * 0.28)
        var check = Path()
        check.move(to: CGPoint(x: ck.minX, y: ck.midY))
        check.addLine(to: CGPoint(x: ck.minX + ck.width * 0.32, y: ck.maxY - ck.height * 0.08))
        check.addLine(to: CGPoint(x: ck.maxX, y: ck.minY + ck.height * 0.12))
        context.stroke(
            check,
            with: .color(Theme.accent),
            style: StrokeStyle(lineWidth: max(1.5, size * 0.013), lineCap: .round, lineJoin: .round)
        )
    }

    private func isSwept(blipAngle: Double, sweep: Double) -> Bool {
        abs(normalizedDelta(blipAngle - sweep)) < 12
    }

    private func normalizedDelta(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

/// Seitenansicht E-Scooter — Stroke-Silhouette (vektor, keine Bitmap-Kachel).
struct ScooterSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY

        func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: x0 + nx * w, y: y0 + ny * h)
        }

        var p = Path()

        // Rear wheel
        p.addEllipse(in: CGRect(x: x0 + 0.08 * w, y: y0 + 0.58 * h, width: 0.22 * w, height: 0.34 * h))
        // Front wheel
        p.addEllipse(in: CGRect(x: x0 + 0.68 * w, y: y0 + 0.58 * h, width: 0.22 * w, height: 0.34 * h))

        // Deck (open stroke line)
        p.move(to: pt(0.20, 0.68))
        p.addLine(to: pt(0.72, 0.68))

        // Stem up to bar
        p.move(to: pt(0.78, 0.68))
        p.addLine(to: pt(0.76, 0.20))

        // Handlebar
        p.move(to: pt(0.62, 0.18))
        p.addLine(to: pt(0.90, 0.18))

        // Front fender arc
        p.move(to: pt(0.72, 0.58))
        p.addQuadCurve(to: pt(0.90, 0.58), control: pt(0.81, 0.48))

        // Kickstand hint
        p.move(to: pt(0.34, 0.70))
        p.addLine(to: pt(0.30, 0.88))

        return p
    }
}

private struct SonarBlip {
    let angle: Double
    let radius: CGFloat
    let dot: CGFloat

    static func seeded(count: Int, style: SonarRadarView.Style) -> [SonarBlip] {
        guard count > 0 else { return [] }
        let catalog: [SonarBlip] = [
            .init(angle: 28, radius: 0.30, dot: 0.018),
            .init(angle: 95, radius: 0.38, dot: 0.015),
            .init(angle: 155, radius: 0.26, dot: 0.017),
            .init(angle: 220, radius: 0.36, dot: 0.014),
            .init(angle: 290, radius: 0.32, dot: 0.016),
            .init(angle: 335, radius: 0.22, dot: 0.013)
        ]
        let n = min(count, catalog.count)
        if style == .compact {
            return Array(catalog.prefix(min(n, 2))).map {
                SonarBlip(angle: $0.angle, radius: min($0.radius, 0.34), dot: 0.08)
            }
        }
        return Array(catalog.prefix(n))
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
            blipCount: max(min(deviceCount, 5), isScanning ? 4 : 3),
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
