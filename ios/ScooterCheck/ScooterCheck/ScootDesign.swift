import SwiftUI
import UIKit

// MARK: - Branding

struct Wordmark: View {
    /// Optional override; default = App-Header Semibold ~23 pt.
    var size: Font = Theme.brandWordmark
    var body: some View {
        HStack(spacing: 0) {
            Text("Scooter").foregroundStyle(Theme.accent)
            Text("Check").foregroundStyle(Theme.textPrimary)
        }
        .font(size)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ScooterCheck")
    }
}

/// Einzige animierte App-Wordmark-Instanz: Display-Mitte ↔ Drawer-Mitte.
/// Full-Screen-Overlay über dem Drawer; Y = SafeArea + Header-Mitte (nie Statusleiste).
struct FloatingAppBrandWordmark: View {
    /// 0 = horizontal mittig im App-Header, 1 = mittig in der Drawer-Breite.
    var menuProgress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let panelWidth = Theme.Chrome.drawerPanelWidth(screenWidth: geo.size.width)
            let closedX = geo.size.width * 0.5
            let openX = panelWidth * 0.5
            let x = closedX + (openX - closedX) * menuProgress
            // GeometryReader-Overlays liefern oft safeAreaInsets.top == 0 → UIKit-Fallback.
            let y = Theme.Chrome.brandCenterY(safeAreaTop: geo.safeAreaInsets.top)
            Wordmark()
                .position(x: x, y: y)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Fester App-Header unter der Safe Area (68 pt). Wordmark kommt als Overlay darüber.
struct AppChromeHeaderBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing = { Color.clear.frame(width: 44, height: 44) }
    ) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 0) {
            leading()
                .frame(width: 44, height: 44)
            Spacer(minLength: 0)
            // Platz für die schwebende Wordmark — keine zweite Instanz hier.
            Color.clear.frame(width: 1, height: 1)
            Spacer(minLength: 0)
            trailing()
                .frame(width: 44, height: 44)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Chrome.headerHeight)
        .padding(.horizontal, Theme.Space.lg)
        .background(Theme.bg)
    }
}

/// Sheet-Header mit derselben Headerhöhe und zentrierter Wordmark.
struct AppChromeSheetHeader: View {
    var closeTitle: String = "Schließen"
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Wordmark()
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(closeTitle, action: onClose)
                    .font(Theme.buttonSecondary)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, Theme.Space.lg)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Chrome.headerHeight)
        .background(Theme.bg)
    }
}

/// Runder ☰-Button wie im Mockup — eine Fläche, keine äußere Kontur.
struct MenuGlyphButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.surfaceSecondary)
                .clipShape(Circle())
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
            HStack(spacing: Theme.Space.md) {
                if busy {
                    ProgressView().tint(Theme.ink)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Theme.Icon.standard, weight: .semibold))
                }
                Text(title)
                    .font(Theme.button)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Control.buttonMinHeight)
            .foregroundStyle(Theme.ink)
            .background(Theme.accent.opacity(enabled ? 1 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
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
            HStack(spacing: Theme.Space.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Theme.Icon.standard, weight: .medium))
                }
                Text(title)
                    .font(Theme.buttonSecondary)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.cardPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Control.secondaryMinHeight)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
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
            HStack(spacing: Theme.Space.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Theme.Icon.standard, weight: .medium))
                }
                Text(title)
                    .font(Theme.buttonSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Control.secondaryMinHeight)
            .foregroundStyle(Theme.accent)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .stroke(Theme.accent.opacity(0.7), lineWidth: Theme.Control.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prüfbericht Action Panel

/// Primärer Mint-Button für die Ergebnis-Bottom-Bar (Bericht speichern).
struct ScootActionPrimaryButton: View {
    let title: String
    var systemImage: String = "square.and.arrow.down"
    var enabled: Bool = true
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(Theme.ink)
                } else {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.system(size: 16.5, weight: .medium))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.accent.opacity(enabled && !busy ? 1 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .accessibilityLabel(title)
    }
}

/// Ruhiger Sekundärbutton mit Mint-Outline (Vergleichstest).
struct ScootActionFeatureCard: View {
    let title: String
    let subtitle: String
    var systemImage: String = "testtube.2"
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 48)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.accent.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

/// Kompakte Tertiär-Aktion für die zweispaltige Fußzeile.
struct ScootActionChipButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.medium))
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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

/// Sonar hinter dem bereitgestellten `radar_scooter`-Asset.
/// Ebenen: Disk → Achsen → Ringe → Sweep → Blips → Image("radar_scooter").
struct SonarRadarView: View {
    enum Style {
        case compact
        case hero
        case search
    }

    var isScanning: Bool
    var blipCount: Int = 0
    var size: CGFloat = 220
    var style: Style = .search
    var discoveryFlash: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let revolutionSeconds: Double = 2.0
    /// ~0.9 s Nachleuchten bei 2 s/Umdrehung → ~162°, danach opacity = 0.
    private let blipFadeDegrees: Double = 162

    /// Lenkerstange sitzt im Asset bei ~34 % der Bildbreite → nach rechts versetzen,
    /// damit das Sonarzentrum hinter dem Rohr liegt.
    private let stemAlignOffsetXFactor: CGFloat = 0.16

    private var blips: [SonarBlip] {
        let fallback = isScanning ? 5 : (style == .hero ? 4 : 0)
        return SonarBlip.seeded(count: max(blipCount, fallback), style: style)
    }

    var body: some View {
        ZStack {
            radarCanvas
            if style != .compact {
                scooterForeground
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

    /// Nur das bereitgestellte Asset — visuell an der Lenkerstange zentriert.
    /// Kein Shadow/Glow; RenderingMode original, damit die defringte Alpha-Kante sauber bleibt.
    private var scooterForeground: some View {
        let displayW = size * 0.78
        return Image("radar_scooter")
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: displayW)
            .offset(
                x: displayW * stemAlignOffsetXFactor,
                y: size * 0.02
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func canvas(angle: Double) -> some View {
        let drawSweep = isScanning || style == .hero
        let rings = style == .compact ? 2 : 5
        let strokeW: CGFloat = style == .compact ? 0.65 : 0.85
        let span: Double = style == .compact ? 46 : 58
        let flashBoost = discoveryFlash ? 1.25 : 1.0
        let animateBlips = isScanning && !reduceMotion

        return Canvas { context, canvasSize in
            let mid = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2

            // 1. Dunkler Radarbereich
            let disk = Path(ellipseIn: CGRect(
                x: mid.x - radius, y: mid.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.fill(
                disk,
                with: .radialGradient(
                    Gradient(colors: [
                        Theme.accent.opacity(0.05 * flashBoost),
                        Theme.accent.opacity(0.012),
                        .clear
                    ]),
                    center: mid,
                    startRadius: 2,
                    endRadius: radius
                )
            )

            // 2. Achsen
            if style != .compact {
                var h = Path(); h.move(to: CGPoint(x: mid.x - radius * 0.9, y: mid.y)); h.addLine(to: CGPoint(x: mid.x + radius * 0.9, y: mid.y))
                var v = Path(); v.move(to: CGPoint(x: mid.x, y: mid.y - radius * 0.9)); v.addLine(to: CGPoint(x: mid.x, y: mid.y + radius * 0.9))
                context.stroke(h, with: .color(Theme.accent.opacity(0.09)), lineWidth: 0.55)
                context.stroke(v, with: .color(Theme.accent.opacity(0.09)), lineWidth: 0.55)
            }

            // 3. Konzentrische Ringe
            for i in 1...rings {
                let frac = CGFloat(i) / CGFloat(rings)
                let r = radius * (0.24 + frac * 0.72)
                var ring = Path()
                ring.addEllipse(in: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2))
                context.stroke(
                    ring,
                    with: .color(Theme.accent.opacity(0.10 + Double(i) * 0.028)),
                    lineWidth: strokeW
                )
            }

            // 4. Einzelner weicher Sweep
            if drawSweep {
                let steps = style == .compact ? 40 : 72
                for i in 0..<steps {
                    let t = Double(i) / Double(max(steps - 1, 1))
                    let a0 = angle - span * t
                    let a1 = angle - span * min(1, t + 1.0 / Double(steps))
                    let fall = 1.0 - t
                    let peak: Double = style == .compact ? 0.48 : 0.40
                    let alpha = fall * fall * fall * peak * flashBoost
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
                // Weiche Vorderkante (kein zweiter Schweif-Strich)
                var lead = Path()
                let leadLen = radius * 0.985
                let lx = mid.x + leadLen * CGFloat(cos((angle - 90) * .pi / 180))
                let ly = mid.y + leadLen * CGFloat(sin((angle - 90) * .pi / 180))
                lead.move(to: mid)
                lead.addLine(to: CGPoint(x: lx, y: ly))
                context.stroke(
                    lead,
                    with: .color(Theme.accent.opacity(0.55 * flashBoost)),
                    style: StrokeStyle(lineWidth: style == .compact ? 1.0 : 1.25, lineCap: .round)
                )
            }

            // 5. Punkte nur beim Sweep — länger nachleuchten, dann opacity 0
            if animateBlips {
                for blip in blips {
                    let intensity = blipPulse(blipAngle: blip.angle, sweep: angle)
                    guard intensity > 0.012 else { continue }

                    let br = radius * blip.radius
                    let bx = mid.x + br * CGFloat(cos((blip.angle - 90) * .pi / 180))
                    let by = mid.y + br * CGFloat(sin((blip.angle - 90) * .pi / 180))
                    let baseDot: CGFloat = style == .compact
                        ? max(1.5, size * 0.05)
                        : max(2.2, size * blip.dot)
                    let d = baseDot * (0.85 + 0.55 * intensity)

                    let glow = d * (1.6 + intensity * 1.8)
                    let glowRect = CGRect(x: bx - glow / 2, y: by - glow / 2, width: glow, height: glow)
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(Theme.accent.opacity(0.20 * intensity))
                    )
                    let dotRect = CGRect(x: bx - d / 2, y: by - d / 2, width: d, height: d)
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(Color.white.opacity(intensity))
                    )
                }
            }

            if style == .compact {
                let hub = max(2.2, size * 0.12)
                context.fill(
                    Path(ellipseIn: CGRect(x: mid.x - hub / 2, y: mid.y - hub / 2, width: hub, height: hub)),
                    with: .color(Theme.accent.opacity(0.9))
                )
            }
        }
    }

    /// Peak beim Treffer, dann längeres Nachleuchten, danach exakt 0.
    private func blipPulse(blipAngle: Double, sweep: Double) -> Double {
        let behind = normalizedDelta(sweep - blipAngle)
        if behind < 0 || behind > blipFadeDegrees {
            return 0
        }
        let t = behind / blipFadeDegrees
        // Erste ~20 % hell halten (Nachleuchten), danach weich aus
        if t < 0.22 {
            return 1.0 - t * 0.15
        }
        let u = (t - 0.22) / 0.78
        let fade = 1.0 - u
        return fade * fade * fade
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
        // Radien bewusst über Innen-/Mittel-/Außenbereich (Ringe ~0.24…0.96),
        // Winkel unregelmäßig — nicht alle nah am Zentrum.
        let catalog: [SonarBlip] = [
            .init(angle: 22, radius: 0.34, dot: 0.017),
            .init(angle: 78, radius: 0.78, dot: 0.015),
            .init(angle: 138, radius: 0.52, dot: 0.016),
            .init(angle: 198, radius: 0.88, dot: 0.014),
            .init(angle: 256, radius: 0.41, dot: 0.016),
            .init(angle: 318, radius: 0.66, dot: 0.013)
        ]
        let n = min(count, catalog.count)
        if style == .compact {
            return Array(catalog.prefix(min(n, 2))).map {
                SonarBlip(angle: $0.angle, radius: min($0.radius, 0.55), dot: 0.08)
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
            blipCount: max(min(deviceCount, 5), isScanning ? 5 : 0),
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
            .font(Theme.caption)
            .foregroundStyle(Theme.textMuted)
            .accessibilityLabel(line)
    }
}

// MARK: - Side menu left-edge open (UIKit — zuverlässiger als SwiftUI-Clear-Strip)

/// Schmaler linker Rand unterhalb des App-Headers: Touches außerhalb + Header gehen durch.
struct MenuLeftEdgeOpenBridge: UIViewRepresentable {
    var isEnabled: Bool
    var edgeWidth: CGFloat = 52
    /// Safe Area + Header — Hamburger-Button darf nicht vom Edge-Pan blockiert werden.
    var excludedTop: CGFloat = 0
    var onBegan: () -> Void
    var onChanged: (_ translationX: CGFloat) -> Void
    var onEnded: (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> MenuLeftEdgeHitView {
        let view = MenuLeftEdgeHitView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.edgeWidth = edgeWidth
        view.excludedTop = excludedTop
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        return view
    }

    func updateUIView(_ uiView: MenuLeftEdgeHitView, context: Context) {
        uiView.edgeWidth = edgeWidth
        uiView.excludedTop = excludedTop
        uiView.isUserInteractionEnabled = isEnabled
        context.coordinator.pan?.isEnabled = isEnabled
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject {
        var onBegan: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void
        var pan: UIPanGestureRecognizer?
        private var didBegin = false

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat, CGFloat) -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let t = gesture.translation(in: view)
            let v = gesture.velocity(in: view)

            switch gesture.state {
            case .began:
                didBegin = false
                // Nur nach rechts vom linken Rand starten.
                guard t.x >= 0 || abs(v.x) > abs(v.y) else { return }
            case .changed:
                guard t.x > 0 || didBegin else { return }
                if !didBegin {
                    // Vertikal-Scroll nicht stehlen.
                    guard abs(t.x) >= abs(t.y) * 0.55, t.x > 4 else { return }
                    didBegin = true
                    onBegan()
                }
                onChanged(t.x)
            case .ended, .cancelled, .failed:
                if didBegin {
                    onEnded(t.x, v.x)
                }
                didBegin = false
            default:
                break
            }
        }
    }
}

final class MenuLeftEdgeHitView: UIView {
    var edgeWidth: CGFloat = 52
    var excludedTop: CGFloat = 0

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        guard point.x >= 0, point.x <= edgeWidth else { return nil }
        guard point.y >= excludedTop, point.y <= bounds.height else { return nil }
        return self
    }
}
