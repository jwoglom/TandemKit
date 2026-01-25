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
