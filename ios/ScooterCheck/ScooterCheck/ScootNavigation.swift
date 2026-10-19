import SwiftUI
import UIKit

// Motion tokens (`page`, `rootCrossfade`, `reduced`) leben in Theme.Motion.

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
