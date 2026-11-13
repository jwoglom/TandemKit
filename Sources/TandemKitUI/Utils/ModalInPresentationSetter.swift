import SwiftUI
import UIKit

struct ModalInPresentationSetter: UIViewControllerRepresentable {
    let isModalInPresentation: Bool

    func makeUIViewController(context _: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context _: Context) {
        var controller: UIViewController? = uiViewController
        while let current = controller {
            if current.isModalInPresentation != isModalInPresentation {
                current.isModalInPresentation = isModalInPresentation
            }
            controller = current.parent
        }
    }
}

extension View {
    /// SwiftUI's modifier alone does not reach a sheet the host presents from UIKit, as Loop's and Trio's
    /// pump setup sheets are; `ModalInPresentationSetter` sets it on every controller above this view.
    func preventsSheetDismissal(_ isLocked: Bool = true) -> some View {
        interactiveDismissDisabled(isLocked)
            .background(ModalInPresentationSetter(isModalInPresentation: isLocked))
    }
}
