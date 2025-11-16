import SwiftUI

extension Image {
    init(imageName: String) {
        self.init(uiImage: UIImage(named: imageName, in: Bundle(for: TandemUICoordinator.self), compatibleWith: nil)!)
    }
}
