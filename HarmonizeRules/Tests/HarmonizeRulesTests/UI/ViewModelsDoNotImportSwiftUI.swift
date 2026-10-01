import Harmonize
import XCTest

final class ViewModelsDoNotImportSwiftUI: XCTestCase {
    func testViewModelFilesDoNotImportUIFrameworks() {
        TandemHarmonize.viewModelsFolder.sources().assertFalse(rule: Self.rule, baseline: Self.baseline) { file in
            file.imports().contains { Self.uiFrameworks.contains($0.name) }
        }
    }

    private static let uiFrameworks = ["SwiftUI", "UIKit", "LoopKitUI"]

    private static let baseline: [String] = [
        "TandemKitAlertSettingsViewModel.swift",
        "TandemKitCGMSettingsViewModel.swift",
        "TandemKitChangeCartridgeViewModel.swift",
        "TandemKitControlIQSettingsViewModel.swift",
        "TandemKitDebugViewModel.swift",
        "TandemKitFeatureFlagsViewModel.swift",
        "TandemKitFillCannulaViewModel.swift",
        "TandemKitFillTubingViewModel.swift",
        "TandemKitG6SetupViewModel.swift",
        "TandemKitG7SetupViewModel.swift",
        "TandemKitHistoryLogViewerViewModel.swift",
        "TandemKitNotificationsViewModel.swift",
        "TandemKitPumpInformationViewModel.swift",
        "TandemKitQuickBolusSettingsViewModel.swift",
        "TandemKitScanViewModel.swift",
        "TandemKitSettingsViewModel.swift",
        "TandemKitSoundSettingsViewModel.swift",
        "TandemKitTroubleshootConnectionViewModel.swift"
    ]

    private static let rule = Rule(
        description: "View models do not import SwiftUI, UIKit or LoopKitUI.",
        rationale: """
            ObservableObject and @Published come from Combine. A view model that imports SwiftUI starts making view
            decisions such as animation and colour, which its tests cannot see, and cannot be compiled where SwiftUI
            is unavailable.
            """,
        fixHint: "Import Combine (and Foundation/LoopKit as needed) instead. Leave withAnimation, colours and images to the view.",
        badExample: "import SwiftUI\n\nclass TandemKitG6SetupViewModel: ObservableObject {\n    func next() { withAnimation { step += 1 } }\n}",
        goodExample: "import Combine\n\nclass TandemKitG6SetupViewModel: ObservableObject {\n    func next() { step += 1 }\n}\n// view: .animation(.default, value: viewModel.step)"
    )
}
