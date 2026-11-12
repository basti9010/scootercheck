import ObjectiveC
import UniformTypeIdentifiers
import UIKit

enum FirmwareDocumentTypes {
    /// Breite Typen, damit ZIP/BIN/ENC (auch mit Sonderzeichen im Namen) sichtbar sind.
    static var subject: [UTType] {
        var types: [UTType] = [.item, .data, .content, .archive, .zip, .json, .plainText, .text]
        if let bin = UTType(filenameExtension: "bin") { types.append(bin) }
        if let enc = UTType(filenameExtension: "enc") { types.append(enc) }
        if let firm = UTType(filenameExtension: "firm") { types.append(firm) }
        return types
    }

    static var reference: [UTType] { subject }
}

/// Präsentiert `UIDocumentPickerViewController` über UIKit (funktioniert in Sheets/FullScreenCovers).
enum FirmwareDocumentPickerPresenter {
    @MainActor
    static func present(
        contentTypes: [UTType],
        onPick: @escaping (URL) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        guard let host = topViewController() else {
            onCancel?()
            return
        }
        let types = contentTypes.isEmpty ? [UTType.item] : contentTypes
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        let delegate = Delegate(onPick: onPick, onCancel: onCancel)
        // Retain delegate for the lifetime of the picker.
        objc_setAssociatedObject(picker, &AssociateKeys.delegate, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        picker.delegate = delegate
        host.present(picker, animated: true)
    }

    @MainActor
    private static func topViewController(
        base: UIViewController? = {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }()
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    private enum AssociateKeys {
        static var delegate: UInt8 = 0
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: (() -> Void)?

        init(onPick: @escaping (URL) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            defer { controller.dismiss(animated: true) }
            guard let url = urls.first else {
                onCancel?()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
