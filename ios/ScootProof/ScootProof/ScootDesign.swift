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

/// Vektor-Radar: feine Ringe, weicher Einzel-Sweep, Blip-Nachglühen,
/// elegante weiße Scooter-Line-Art — kein Bitmap-Look.
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
    /// Nach dem Überstreichen: so viele Grad braucht der Fade bis zur Ruhehelligkeit.
    private let blipFadeDegrees: Double = 110

    private var blips: [SonarBlip] {
        let fallback = (style == .hero) ? 4 : (isScanning ? 5 : 4)
        return SonarBlip.seeded(count: max(blipCount, fallback), style: style)
    }

    var body: some View {
        ZStack {
            radarCanvas
            if style != .compact {
                scooterOverlay
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(discoveryFlash ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.4), value: discoveryFlash)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var radarCanvas: some View {
        if isScanning && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                canvas(angle: sweepAngle(at: timeline.date))
            }
        } else {
            canvas(angle: idleAngle)
        }
    }

    private var idleAngle: Double {
        if isScanning && reduceMotion { return 48 }
        if style == .hero { return 36 }
        return 18
    }

    private func sweepAngle(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: revolutionSeconds) / revolutionSeconds) * 360.0
    }

    private var scooterOverlay: some View {
        let scooterW = size * 0.48
        let scooterH = size * 0.36
        return ZStack {
            // Soft under-glow (wie Icon-Referenz, aber weiß)
            ScooterLineArt()
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: max(5, size * 0.038), lineCap: .round, lineJoin: .round))
                .blur(radius: size * 0.018)
                .frame(width: scooterW, height: scooterH)
                .offset(y: size * 0.012)

            ScooterLineArt()
                .stroke(Color.white.opacity(0.96), style: StrokeStyle(lineWidth: max(2.4, size * 0.018), lineCap: .round, lineJoin: .round))
                .frame(width: scooterW, height: scooterH)
                .offset(y: size * 0.012)

            // Check badge — mittig hinter der Deck-/Rahmenzone
            ZStack {
                Circle()
                    .fill(Theme.bg.opacity(0.88))
                Circle()
                    .stroke(Theme.accent.opacity(0.95), lineWidth: max(1.2, size * 0.008))
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.058, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: size * 0.135, height: size * 0.135)
            .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.02)
            .offset(y: size * 0.018)
        }
        .allowsHitTesting(false)
    }

    private func canvas(angle: Double) -> some View {
        let drawSweep = isScanning || style == .hero
        let rings = style == .compact ? 2 : 5
        let strokeW: CGFloat = style == .compact ? 0.65 : 0.85
        let span: Double = style == .compact ? 46 : 58
        let flashBoost = discoveryFlash ? 1.25 : 1.0
        let animateBlips = drawSweep && isScanning && !reduceMotion

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
                        Theme.accent.opacity(0.06 * flashBoost),
                        Theme.accent.opacity(0.015),
                        .clear
                    ]),
                    center: mid,
                    startRadius: 2,
                    endRadius: radius
                )
            )

            // Concentric rings
            for i in 1...rings {
                let frac = CGFloat(i) / CGFloat(rings)
                let r = radius * (0.24 + frac * 0.72)
                var ring = Path()
                ring.addEllipse(in: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2))
                context.stroke(
                    ring,
                    with: .color(Theme.accent.opacity(0.11 + Double(i) * 0.028)),
                    lineWidth: strokeW
                )
            }

            // Crosshair
            if style != .compact {
                var h = Path(); h.move(to: CGPoint(x: mid.x - radius * 0.9, y: mid.y)); h.addLine(to: CGPoint(x: mid.x + radius * 0.9, y: mid.y))
                var v = Path(); v.move(to: CGPoint(x: mid.x, y: mid.y - radius * 0.9)); v.addLine(to: CGPoint(x: mid.x, y: mid.y + radius * 0.9))
                context.stroke(h, with: .color(Theme.accent.opacity(0.09)), lineWidth: 0.55)
                context.stroke(v, with: .color(Theme.accent.opacity(0.09)), lineWidth: 0.55)
            }

            // Single soft light-cone — kein separater Lead-Stroke (der wirkte wie zweiter Strich).
            if drawSweep {
                let steps = style == .compact ? 36 : 64
                for i in 0..<steps {
                    let t = Double(i) / Double(max(steps - 1, 1))
                    let a0 = angle - span * t
                    let a1 = angle - span * min(1, t + 1.0 / Double(steps))
                    // Smoothstep-ähnlicher Falloff: hell an der Vorderkante, unsichtbar am Schweifende
                    let fall = (1.0 - t)
                    let alpha = fall * fall * fall * (style == .compact ? 0.42 : 0.36) * flashBoost
                    guard alpha > 0.003 else { continue }
                    var wedge = Path()
                    wedge.move(to: mid)
                    wedge.addArc(
                        center: mid,
                        radius: radius * 0.985,
                        startAngle: .degrees(a1 - 90),
                        endAngle: .degrees(a0 - 90),
                        clockwise: false
                    )
                    wedge.closeSubpath()
                    context.fill(wedge, with: .color(Theme.accent.opacity(alpha)))
                }
            }

            // Blips: nach Sweep-Überfahrt aufleuchten, dann weich ausfaden
            for (index, blip) in blips.enumerated() {
                let pulse = animateBlips ? blipPulse(blipAngle: blip.angle, sweep: angle) : 0.15
                let highlighted = highlightIndex == index
                let intensity = highlighted ? max(pulse, 0.85) : pulse
                let br = radius * blip.radius
                let bx = mid.x + br * CGFloat(cos((blip.angle - 90) * .pi / 180))
                let by = mid.y + br * CGFloat(sin((blip.angle - 90) * .pi / 180))
                let baseDot: CGFloat = style == .compact
                    ? max(1.5, size * 0.05)
                    : max(2.2, size * blip.dot)
                let d = baseDot * (0.9 + 0.45 * intensity)
                // Soft glow first (under)
                if intensity > 0.08 {
                    let glow = d * (1.8 + intensity * 1.4)
                    let glowRect = CGRect(x: bx - glow / 2, y: by - glow / 2, width: glow, height: glow)
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(Theme.accent.opacity(0.12 + 0.28 * intensity))
                    )
                }
                let opacity = 0.28 + 0.67 * intensity
                let dotRect = CGRect(x: bx - d / 2, y: by - d / 2, width: d, height: d)
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(Color.white.opacity(opacity))
                )
            }

            // Compact hub
            if style == .compact {
                let hub = max(2.2, size * 0.12)
                context.fill(
                    Path(ellipseIn: CGRect(x: mid.x - hub / 2, y: mid.y - hub / 2, width: hub, height: hub)),
                    with: .color(Theme.accent.opacity(0.9))
                )
            }
        }
    }

    /// 0…1: Peak direkt nach dem Überstreichen, danach weicher Abfall.
    private func blipPulse(blipAngle: Double, sweep: Double) -> Double {
        // Positive Werte = Sweep ist bereits über den Punkt hinaus (im Uhrzeigersinn).
        let behind = normalizedDelta(sweep - blipAngle)
        if behind < 0 {
            // Noch nicht erreicht — Ruhehelligkeit
            return 0.18
        }
        if behind > blipFadeDegrees {
            return 0.18
        }
        let t = behind / blipFadeDegrees
        // Ease-out: sofort hell, dann weich abfallend
        let fade = (1.0 - t)
        return 0.18 + 0.82 * (fade * fade)
    }

    private func normalizedDelta(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

/// Elegante E-Scooter-Seitenansicht — dicke Line-Art wie App-Icon-Referenz.
struct ScooterLineArt: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x0 = rect.minX
        let y0 = rect.minY

        func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: x0 + nx * w, y: y0 + ny * h)
        }

        var p = Path()

        // Proportionen angelehnt an das Mint-Radar-Icon (Seitenansicht links→rechts).
        let wheelR: CGFloat = 0.115
        let rearCX: CGFloat = 0.20
        let frontCX: CGFloat = 0.80
        let wheelCY: CGFloat = 0.74
        let deckY: CGFloat = 0.60

        // Räder
        p.addEllipse(in: CGRect(
            x: x0 + (rearCX - wheelR) * w, y: y0 + (wheelCY - wheelR) * h,
            width: wheelR * 2 * w, height: wheelR * 2 * h
        ))
        p.addEllipse(in: CGRect(
            x: x0 + (frontCX - wheelR) * w, y: y0 + (wheelCY - wheelR) * h,
            width: wheelR * 2 * w, height: wheelR * 2 * h
        ))

        // Deck
        p.move(to: pt(rearCX + wheelR * 0.7, deckY))
        p.addLine(to: pt(frontCX - wheelR * 0.35, deckY))

        // Heck-Kotflügel
        p.move(to: pt(rearCX - wheelR * 0.35, deckY + 0.01))
        p.addQuadCurve(to: pt(rearCX + wheelR * 0.55, deckY - 0.02), control: pt(rearCX, deckY - 0.13))

        // Lenksäule: Deck → oben
        p.move(to: pt(frontCX - wheelR * 0.25, deckY))
        p.addLine(to: pt(0.74, 0.18))

        // Lenker
        p.move(to: pt(0.60, 0.16))
        p.addLine(to: pt(0.88, 0.16))

        // Front-Kotflügel
        p.move(to: pt(frontCX - wheelR * 0.55, deckY + 0.02))
        p.addQuadCurve(to: pt(frontCX + wheelR * 0.55, wheelCY - 0.04), control: pt(frontCX + 0.04, deckY - 0.14))

        return p
    }
}

/// Alias für bestehende Aufrufe / Preview.
typealias ScooterSilhouette = ScooterLineArt

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
