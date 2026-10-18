import SwiftUI
import UIKit

/// Interaktive Zurück-Wischgeste vom linken Rand (iOS-ähnlich), für Views ohne NavigationPath-Pop.
struct ScootEdgeBackGesture: ViewModifier {
    var isEnabled: Bool
    var onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let edgeWidth: CGFloat = 28
    private let dismissThreshold: CGFloat = 110

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: max(0, dragOffset))
                    .disabled(isDragging)

                if dragOffset > 0 {
                    Color.black.opacity(Double(min(0.28, dragOffset / width * 0.4)))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .leading) {
                if isEnabled {
                    Color.clear
                        .frame(width: edgeWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(edgePan(width: width))
                }
            }
        }
    }

    private func edgePan(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard isEnabled else { return }
                // Nur von links nach rechts
                guard value.startLocation.x <= edgeWidth else { return }
                isDragging = true
                dragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                guard isEnabled else {
                    resetDrag(animated: true)
                    return
                }
                let predicted = value.predictedEndTranslation.width
                let shouldDismiss = dragOffset > dismissThreshold || predicted > dismissThreshold * 1.35
                if shouldDismiss {
                    let anim = reduceMotion ? Theme.Motion.reduced : Theme.Motion.page
                    withAnimation(anim) {
                        dragOffset = width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.12 : 0.28)) {
                        onBack()
                        dragOffset = 0
                        isDragging = false
                    }
                } else {
                    resetDrag(animated: true)
                }
            }
    }

    private func resetDrag(animated: Bool) {
        let anim = animated
            ? (reduceMotion ? Theme.Motion.reduced : Theme.Motion.page)
            : nil
        if let anim {
            withAnimation(anim) {
                dragOffset = 0
                isDragging = false
            }
        } else {
            dragOffset = 0
            isDragging = false
        }
    }
}

extension View {
    func scootEdgeBackGesture(isEnabled: Bool = true, onBack: @escaping () -> Void) -> some View {
        modifier(ScootEdgeBackGesture(isEnabled: isEnabled, onBack: onBack))
    }

    /// Horizontale Push-/Pop-Übergänge für Zustandswechsel (ohne NavigationPath).
    func scootPushTransition(reduceMotion: Bool) -> some View {
        transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                )
        )
    }
}
