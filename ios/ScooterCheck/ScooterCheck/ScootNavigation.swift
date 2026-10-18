import SwiftUI
import UIKit

// MARK: - Motion tokens

extension Theme.Motion {
    /// Native-ähnlicher Seitenpush (~300 ms).
    static let page = Animation.easeInOut(duration: 0.30)
    /// Sanfter Wurzel-/Tab-Wechsel.
    static let rootCrossfade = Animation.easeInOut(duration: 0.22)
    /// Sehr kurz bei „Bewegung reduzieren“.
    static let reduced = Animation.easeInOut(duration: 0.12)
}

// MARK: - Interactive pop (Custom-Back + hidden NavigationBar)

/// Reaktiviert die iOS-Edge-Swipe-Zurückgeste, wenn die System-Back-Button-Leiste versteckt ist.
struct NavigationInteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.refresh()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            refresh()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            refresh()
        }

        func refresh() {
            guard let nav = navigationController else { return }
            guard let pop = nav.interactivePopGestureRecognizer else { return }
            pop.isEnabled = nav.viewControllers.count > 1
            pop.delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Pop-Geste hat Vorrang vor konkurrierenden Pans am linken Rand.
            gestureRecognizer === navigationController?.interactivePopGestureRecognizer
        }
    }
}

extension View {
    /// Edge-Swipe-Zurück trotz versteckter NavigationBar / Custom-Chevron.
    func scootInteractivePopGesture() -> some View {
        background(NavigationInteractivePopEnabler().frame(width: 0, height: 0))
    }

    /// Einheitliche Seitenanimation unter Berücksichtigung von „Bewegung reduzieren“.
    func scootPageAnimation<V: Equatable>(
        reduceMotion: Bool,
        value: V
    ) -> some View {
        animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.page, value: value)
    }
}

// MARK: - Find routes (Hashable für NavigationPath)

enum ScooterFindRoute: String, Hashable, CaseIterable {
    case radar
    case watch
    case signalFinder

    init?(destination: ScooterFindDestination) {
        switch destination {
        case .hub: return nil
        case .radar: self = .radar
        case .watch: self = .watch
        case .signalFinder: self = .signalFinder
        }
    }

    var destination: ScooterFindDestination {
        switch self {
        case .radar: return .radar
        case .watch: return .watch
        case .signalFinder: return .signalFinder
        }
    }
}
