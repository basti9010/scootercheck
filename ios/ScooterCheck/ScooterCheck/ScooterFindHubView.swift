import SwiftUI

/// Unterziele innerhalb von „E-Scooter finden“.
enum ScooterFindDestination: Equatable {
    case hub
    case radar
    case watch
    case signalFinder
}

/// Zentrale Übersicht: E-Scooter-Radar, Geräte-Wächter, Signal-Finder.
/// Unterseiten per nativem `NavigationStack` (Slide + Edge-Swipe-Zurück).
struct ScooterFindHubView: View {
    @ObservedObject var ble: BleClient
    @Binding var destination: ScooterFindDestination
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var path = NavigationPath()
    /// Verhindert Ping-Pong zwischen Path und Destination.
    @State private var isApplyingDestination = false
    @State private var presentedRoute: ScooterFindRoute?

    var body: some View {
        NavigationStack(path: $path) {
            hubContent
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ScooterFindRoute.self) { route in
                    findRouteView(route)
                        .toolbar(.hidden, for: .navigationBar)
                        .scootInteractivePopGesture()
                }
        }
        .onAppear { syncPath(from: destination, animated: false) }
        .onChange(of: destination) { newValue in
            syncPath(from: newValue, animated: true)
        }
        .onChange(of: path.count) { count in
            guard !isApplyingDestination else { return }
            if count == 0 {
                presentedRoute = nil
                if destination != .hub {
                    destination = .hub
                }
            }
        }
    }

    @ViewBuilder
    private func findRouteView(_ route: ScooterFindRoute) -> some View {
        switch route {
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

    private func syncPath(from destination: ScooterFindDestination, animated: Bool) {
        let target = ScooterFindRoute(destination: destination)
        if target == presentedRoute {
            // Bereits sichtbar — kein erneuter Push (verhindert Doppelanimation).
            if target == nil, !path.isEmpty {
                // Inkonsistenz bereinigen
            } else {
                return
            }
        }

        isApplyingDestination = true
        let anim: Animation? = animated
            ? (reduceMotion ? Theme.Motion.reduced : Theme.Motion.page)
            : nil

        if let target {
            var next = NavigationPath()
            next.append(target)
            if let anim {
                withAnimation(anim) { path = next }
            } else {
                path = next
            }
            presentedRoute = target
        } else {
            if let anim {
                withAnimation(anim) { path = NavigationPath() }
            } else {
                path = NavigationPath()
            }
            presentedRoute = nil
        }

        // Nach Path-Update wieder freigeben (nächster RunLoop).
        DispatchQueue.main.async {
            isApplyingDestination = false
        }
    }
}
