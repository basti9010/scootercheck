import UIKit

/// Presents `UIActivityViewController` from the topmost view controller so the
/// share sheet appears immediately even inside a nested `fullScreenCover`.
enum FirmwareExportSharePresenter {
    @MainActor
    static func present(items: [Any], completion: ((Bool) -> Void)? = nil) {
        guard !items.isEmpty else {
            completion?(false)
            return
        }
        guard let host = topViewController() else {
            completion?(false)
            return
        }
        // Avoid stacking another activity controller.
        if host.presentedViewController is UIActivityViewController {
            completion?(true)
            return
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = [.addToReadingList, .assignToContact]
        if let pop = controller.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(
                x: host.view.bounds.midX,
                y: host.view.bounds.midY,
                width: 1,
                height: 1
            )
            pop.permittedArrowDirections = []
        }
        host.present(controller, animated: true)
        completion?(true)
    }

    @MainActor
    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let resolvedBase: UIViewController? = {
            if let base { return base }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                if let key = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    return key
                }
            }
            return scenes.flatMap(\.windows).first { $0.isHidden == false }?.rootViewController
        }()
        if let nav = resolvedBase as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = resolvedBase as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = resolvedBase?.presentedViewController {
            return topViewController(base: presented)
        }
        return resolvedBase
    }
}
