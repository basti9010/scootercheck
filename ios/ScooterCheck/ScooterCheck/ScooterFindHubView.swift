import SwiftUI

/// Unterziele innerhalb von „E-Scooter finden“.
enum ScooterFindDestination: Equatable {
    case hub
    case radar
    case watch
    case signalFinder
}

/// Zentrale Übersicht: E-Scooter-Radar, Geräte-Wächter, Signal-Finder.
struct ScooterFindHubView: View {
    @ObservedObject var ble: BleClient
    @Binding var destination: ScooterFindDestination

    var body: some View {
        Group {
            switch destination {
            case .hub:
                hubContent
            case .radar:
                ScooterFinderView(
                    ble: ble,
                    mode: .radar,
                    onBackToHub: { destination = .hub }
                )
            case .watch:
                BLEWatchListScreen(
                    onSelect: nil,
                    onClose: { destination = .hub }
                )
            case .signalFinder:
                ScooterFinderView(
                    ble: ble,
                    mode: .signalPicker,
                    onBackToHub: { destination = .hub }
                )
            }
        }
    }

    private var hubContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 6) {
                    PageTitle(text: "E-Scooter finden")
                    Text("Wähle eine Such- oder Analysefunktion")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Space.sm) {
                    findFunctionCard(
                        title: "E-Scooter-Radar",
                        subtitle: "Erkennt automatisch E-Scooter in deiner Nähe.",
                        systemImage: "dot.radiowaves.left.and.right"
                    ) {
                        destination = .radar
                    }
                    findFunctionCard(
                        title: "Geräte-Wächter",
                        subtitle: "Benachrichtigt dich, wenn gespeicherte Geräte wieder erkannt werden.",
                        systemImage: "bell.badge"
                    ) {
                        destination = .watch
                    }
                    findFunctionCard(
                        title: "Signal-Finder",
                        subtitle: "Untersuche Signalstärken, um dich einem Gerät anzunähern.",
                        systemImage: "viewfinder"
                    ) {
                        destination = .signalFinder
                    }
                }

                AppCopyrightFooter()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Space.sm)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.sm)
        }
    }

    private func findFunctionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Theme.Space.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
