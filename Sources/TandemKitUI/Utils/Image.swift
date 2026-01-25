import SwiftUI

extension Image {
    init(imageName: String) {
        if let image = UIImage(
            named: imageName,
            in: Bundle(for: TandemUICoordinator.self),
            compatibleWith: nil
        ) {
            self.init(uiImage: image)
        } else {
            assertionFailure("Missing asset \(imageName) in TandemKitUI bundle")
            self = Image(systemName: "questionmark.square.dashed")
        }
    }
}
