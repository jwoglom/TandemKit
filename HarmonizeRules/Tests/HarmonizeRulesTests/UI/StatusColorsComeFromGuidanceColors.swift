import Harmonize
import SwiftSyntax
import XCTest

final class StatusColorsComeFromGuidanceColors: XCTestCase {
    func testViewsDoNotHardcodeStatusColors() {
        let colors = TandemHarmonize.uiPackage.sources().flatMap { file in
            file.occurrences(of: MemberAccessExprSyntax.self).filter { access in
                guard Self.statusColors.contains(access.node.declName.baseName.text) else { return false }
                guard let base = access.node.base else { return true }
                return ["Color", "UIColor"].contains(base.trimmedDescription)
            }
        }

        colors.assertEmpty(rule: Self.rule, baseline: Self.baseline)
    }

    private static let statusColors: Set<String> = [
        "red", "orange", "yellow", "green", "systemRed", "systemOrange", "systemYellow", "systemGreen"
    ]

    // By file: a colour has no name to tell one occurrence from another.
    private static let baseline: [String] = [
        "BatteryIndicatorView.swift",
        "TandemKitCGMSettingsView.swift",
        "TandemKitChangeCartridgeView.swift",
        "TandemKitControlIQSettingsView.swift",
        "TandemKitDebugView.swift",
        "TandemKitFillCannulaView.swift",
        "TandemKitFillTubingView.swift",
        "TandemKitHistoryLogViewerView.swift",
        "TandemKitNotificationsView.swift",
        "TandemKitQuickBolusSettingsView.swift",
        "TandemKitSettingsView.swift",
        "TandemKitTroubleshootConnectionView.swift"
    ]

    private static let rule = Rule(
        description: "Status colours come from LoopKitUI's guidanceColors, not hardcoded red, orange, yellow or green.",
        rationale: """
            The host app sets \\.guidanceColors so every pump, CGM and app screen uses the same red for critical and
            the same orange for warning. TandemKitUI already reads it in most places; a hardcoded .red can differ
            from the host's shade and ignores what the host chose.
            """,
        fixHint: "Read @Environment(\\.guidanceColors) and use .critical, .warning or .acceptable. Use .secondary, .accentColor or .primary for non-status colours.",
        badExample: "Text(error).foregroundColor(.red)",
        goodExample: "@Environment(\\.guidanceColors) private var guidanceColors\n...\nText(error).foregroundColor(guidanceColors.critical)"
    )
}
