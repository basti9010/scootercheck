import SwiftUI

struct FactRow: View {
    let fact: MeasuredFact
    @State private var showTechnical = false

    private var showsExplanation: Bool {
        let e = fact.erlaeuterung.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return false }
        if e == fact.bewertung || e == fact.auslesewert || e == fact.title { return false }
        // Lange Analyse-Texte nur aufklappen, Messzeilen kurz halten.
        if fact.group == .speed || fact.group == .serial || fact.group == .odometer {
            return false
        }
        return e.count < 160
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.fact(fact.status))
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(fact.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if showsExplanation {
                    Text(fact.erlaeuterung)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if fact.status != .regelkonform && fact.status != .nichtFeststellbar {
                    Text(statusPhrase)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.fact(fact.status))
                } else if let evidenceClass = fact.evidenceClass, evidenceClass != .info {
                    Text(evidenceClass.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text("Gefunden: \(fact.auslesewert)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Ab Werk erwartet: \(fact.sollwert)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                if fact.raw != nil || fact.sourceBoard != nil || fact.volatility != nil {
                    Button {
                        showTechnical.toggle()
                    } label: {
                        Text(showTechnical ? "Technische Details ausblenden" : "Technische Details")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if showTechnical {
                    VStack(alignment: .leading, spacing: 3) {
                        if let board = fact.sourceBoard {
                            Text("Quelle: \(board)" + (fact.sourceRegister.map { " / \($0)" } ?? ""))
                        }
                        if let hex = fact.rawHex {
                            Text("Rohwert: \(hex)")
                        }
                        if !fact.erlaeuterung.isEmpty, !showsExplanation {
                            Text(fact.erlaeuterung)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let volatility = fact.volatility {
                            Text("Persistenz: \(volatility.label) · \(volatility.resetsOnPowerOffHint)")
                        }
                        if let evidenceClass = fact.evidenceClass {
                            Text("Technische Klasse: \(evidenceClass.label)")
                        }
                        Text("Status: \(fact.status.rawValue)")
                        if let raw = fact.raw, !raw.isEmpty {
                            Text(raw)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var statusPhrase: String {
        switch fact.status {
        case .abweichend: return "Auffällig"
        case .erheblichAbweichend: return "Deutlich abweichend"
        case .regelkonform: return "Unauffällig"
        case .nichtFeststellbar: return "Nicht feststellbar"
        }
    }

    private var icon: String {
        switch fact.status {
        case .regelkonform: return "checkmark.circle.fill"
        case .abweichend: return "exclamationmark.circle.fill"
        case .erheblichAbweichend: return "xmark.circle.fill"
        case .nichtFeststellbar: return "questionmark.circle"
        }
    }
}

struct ScoreRing: View {
    let score: Int
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("Seriennähe")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityLabel("Seriennähe \(score) von 100")
    }
}
