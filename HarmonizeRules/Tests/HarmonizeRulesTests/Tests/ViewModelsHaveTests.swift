import Harmonize
import XCTest

final class ViewModelsHaveTests: XCTestCase {
    func testEveryViewModelHasAMatchingTestCase() {
        let testClassNames = TandemHarmonize.testClassNames

        TandemHarmonize.viewModels.assertTrue(rule: Self.rule, strict: true, baseline: Self.baseline) {
            testClassNames.contains($0.name + "Tests")
        }
    }

    private static let baseline: [String] = [
        "TandemKitCGMSettingsViewModel",
        "TandemKitDebugViewModel",
        "TandemKitG6SetupViewModel",
        "TandemKitG7SetupViewModel",
        "TandemKitHistoryLogViewerViewModel",
        "TandemKitTroubleshootConnectionViewModel"
    ]

    private static let rule = Rule(
        description: "Every TandemKitUI view model has a <Name>Tests test case.",
        rationale: """
            View models decide what the user may send to the pump: they gate Save buttons, hold unsaved therapy settings
            and turn driver errors into what the screen says. The view on top is not unit-tested, so the view model's
            test is the only place that behaviour is pinned down.
            """,
        fixHint: "Add Tests/TandemKitTests/<Name>Tests.swift (an XCTestCase), driving the view model against a TandemPumpManager built on StubPumpBluetooth.",
        badExample: "final class TandemKitSoundSettingsViewModel: ObservableObject  // no TandemKitSoundSettingsViewModelTests",
        goodExample: "final class TandemKitSoundSettingsViewModelTests: XCTestCase"
    )
}
