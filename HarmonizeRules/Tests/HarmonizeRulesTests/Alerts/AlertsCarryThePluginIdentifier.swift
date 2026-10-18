import Harmonize
import SwiftSyntax
import XCTest

final class AlertsCarryThePluginIdentifier: XCTestCase {
    func testEveryAlertIdentifierCarriesThePluginIdentifier() {
        let identifiers = TandemHarmonize.productionCode.sources().flatMap { file in
            file.occurrences(of: FunctionCallExprSyntax.self).filter { call in
                Self.identifierInitializers.contains(call.node.calledExpression.trimmedDescription) && !Self.isRoutable(call.node)
            }
        }

        identifiers.assertEmpty(rule: Self.rule)
    }

    private static let identifierInitializers: Set<String> = ["Alert.Identifier", "LoopKit.Alert.Identifier"]

    private static let pluginIdentifier: Set<String> = [
        "pluginIdentifier", "self.pluginIdentifier", "Self.pluginIdentifier", "TandemPumpManager.pluginIdentifier"
    ]

    private static func isRoutable(_ call: FunctionCallExprSyntax) -> Bool {
        guard let manager = call.arguments.first(where: { $0.label?.text == "managerIdentifier" })?.expression.trimmedDescription else {
            return false
        }
        return pluginIdentifier.contains(manager)
    }

    private static let rule = Rule(
        description: "Every LoopKit alert identifier carries TandemPumpManager.pluginIdentifier.",
        rationale: """
            Loop and Trio register the pump manager as alert responder and sound vendor under its pluginIdentifier, and
            look either up by an alert's managerIdentifier. An alert under any other string is acknowledged on the phone
            alone: the pump keeps its notification, and a sound the driver ships is never found.
            """,
        fixHint: "Build the identifier with TandemPumpManager.alertIdentifier(_:).",
        badExample: "LoopKit.Alert.Identifier(managerIdentifier: TandemPumpManager.managerIdentifier, alertIdentifier: id)",
        goodExample: "TandemPumpManager.alertIdentifier(id)"
    )
}
