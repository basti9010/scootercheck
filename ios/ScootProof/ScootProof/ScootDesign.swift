import SwiftUI

// MARK: - Branding

struct Wordmark: View {
    var size: Font = .title
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Theme.accent)
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
                .stroke(Theme.accent.opacity(0.18), lineWidth: 2)
                .frame(width: 168, height: 168)
            Circle()
                .fill(Theme.accent.opacity(0.06))
                .frame(width: 148, height: 148)
            Image("ScooterGeneric")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 76)
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .offset(x: 46, y: 42)
                .shadow(color: Theme.accent.opacity(0.45), radius: 8)
        }
        .frame(height: 180)
        .accessibilityHidden(true)
    }
}

/// Langsame mintfarbene Punkt-/Signalwellen am unteren Startscreen.
struct AnimatedSignalWaves: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let layers: [(amp: CGFloat, speed: CGFloat, y: CGFloat, alpha: Double, spacing: CGFloat)] = [
                    (10, 0.55, size.height * 0.32, 0.55, 7),
                    (14, 0.38, size.height * 0.52, 0.38, 8),
                    (8, 0.72, size.height * 0.72, 0.28, 6)
                ]
                for layer in layers {
                    var x: CGFloat = -20
                    while x < size.width + 20 {
                        let wobble = sin((x / 28) + t * layer.speed) * layer.amp
                        let y = layer.y + wobble
                        let rect = CGRect(x: x, y: y, width: 2.2, height: 2.2)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Theme.accent.opacity(layer.alpha))
                        )
                        x += layer.spacing
                    }
                }
            }
            .blur(radius: 0.4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Sonar / search atmosphere

struct RotatingSonarIcon: View {
    var size: CGFloat = 22
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(
                    AngularGradient(
                        colors: [Theme.accent.opacity(0.05), Theme.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(spinning ? 360 : 0))
            Circle()
                .fill(Theme.accent)
                .frame(width: 4, height: 4)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.35), radius: 4)
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct PulsingSearchGraphic: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Theme.accent.opacity(0.22 - Double(i) * 0.05), lineWidth: 1.5)
                    .frame(width: 90 + CGFloat(i) * 36, height: 90 + CGFloat(i) * 36)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 0.35 : 0.85)
                    .animation(
                        .easeInOut(duration: 1.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.22),
                        value: pulse
                    )
            }
            Image("ScooterGeneric")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 52)
                .shadow(color: Theme.accent.opacity(0.35), radius: 10)
        }
        .frame(height: 160)
        .onAppear { pulse = true }
        .accessibilityHidden(true)
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
