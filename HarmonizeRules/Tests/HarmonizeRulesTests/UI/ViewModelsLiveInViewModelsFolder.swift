import Harmonize
import XCTest

final class ViewModelsLiveInViewModelsFolder: XCTestCase {
    func testViewModelsAreDeclaredUnderViewModels() {
        let viewModels = TandemHarmonize.uiPackage.classes().withSuffix("ViewModel").filter {
            !$0.modifiers.contains(.private) && !$0.modifiers.contains(.fileprivate)
        }

        viewModels.assertTrue(rule: Self.rule, strict: true) {
            $0.sourceCodeLocation.sourceFilePath?.path.contains("/Sources/TandemKitUI/ViewModels/") == true
        }
    }

    private static let rule = Rule(
        description: "View models live in Sources/TandemKitUI/ViewModels/<Area>/, mirroring Views/<Area>/.",
        rationale: "Every screen has the same two halves in the same two places, so the logic behind a view can be found by convention.",
        fixHint: "Move the class to the ViewModels folder for its area, next to where its view sits under Views.",
        badExample: "// Sources/TandemKitUI/Views/Settings/TandemKitSoundSettingsViewModel.swift",
        goodExample: "// Sources/TandemKitUI/ViewModels/Settings/TandemKitSoundSettingsViewModel.swift"
    )
}
