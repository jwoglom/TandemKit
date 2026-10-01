import Harmonize
import SwiftSyntax
import XCTest

final class StatusColorsComeFromGuidanceColors: XCTestCase {
    func testViewsDoNotHardcodeStatusColors() {
        let colors = TandemHarmonize.uiPackage.sources().flatMap { file in
            file.occurrences(of: MemberAccessExprSyntax.self, name: Self.occurrenceName).filter { access in
                guard Self.statusColors.contains(access.node.declName.baseName.text) else { return false }
                guard let base = access.node.base else { return true }
                return ["Color", "UIColor"].contains(base.trimmedDescription)
            }
        }

        colors.assertEmpty(rule: Self.rule, baseline: Self.baseline)
    }

    private static func occurrenceName(_ access: MemberAccessExprSyntax) -> String {
        "\(access.enclosingTypeName ?? "?"): \(access.trimmedDescription)"
    }

    // No green: guidanceColors.acceptable is .primary in LoopKitUI and in Trio, so it has no success colour to replace one.
    private static let statusColors: Set<String> = ["red", "orange", "yellow", "systemRed", "systemOrange", "systemYellow"]

    // Debug screens, and the swipe-to-dismiss background, which stays system red like LoopKitUI's own delete affordances.
    private static let baseline: [String] = [
        "TandemKitDebugView.swift",
        "TandemKitHistoryLogViewerView.swift",
        "NotificationRow: Color.red"
    ]

    private static let rule = Rule(
        description: "Warning and critical colours come from LoopKitUI's guidanceColors, not hardcoded red, orange or yellow.",
        rationale: """
            The host app sets \\.guidanceColors so every pump, CGM and app screen uses the same red for critical and
            the same orange for warning. TandemKitUI already reads it in most places; a hardcoded .red can differ
            from the host's shade and ignores what the host chose.
            """,
        fixHint: "Read @Environment(\\.guidanceColors) and use .critical for red and .warning for orange or yellow.",
        badExample: "Text(error).foregroundColor(.red)",
        goodExample: "@Environment(\\.guidanceColors) private var guidanceColors\n...\nText(error).foregroundColor(guidanceColors.critical)"
    )
}
