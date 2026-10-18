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
                    onBack: { destination = .hub }
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
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    PageTitle(text: "E-Scooter finden")
                    Text("Wähle eine Such- oder Analysefunktion")
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Space.listGap) {
                    ScootFunctionCard(
                        title: "E-Scooter-Radar",
                        subtitle: "Erkennt automatisch E-Scooter in deiner Nähe.",
                        systemImage: "dot.radiowaves.left.and.right"
                    ) {
                        destination = .radar
                    }
                    ScootFunctionCard(
                        title: "Geräte-Wächter",
                        subtitle: "Benachrichtigt dich, wenn gespeicherte Geräte wieder erkannt werden.",
                        systemImage: "bell.badge"
                    ) {
                        destination = .watch
                    }
                    ScootFunctionCard(
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
                    .padding(.bottom, Theme.Space.xxl)
            }
            .scootPagePadding()
            .padding(.top, Theme.Space.sm)
        }
    }
}
