import Foundation
import Harmonize
import XCTest

final class MessagesAreRegistered: XCTestCase {
    func testEveryMessageIsListedInMessageRegistry() {
        let registry = TandemHarmonize.messagesPackage.sources()
            .first { $0.fileName == "MessageRegistry.swift" }?
            .source ?? ""
        let messages = TandemHarmonize.messagesPackage.classes()
            .withNameEndingWith("Request", "Response")
            .filter { !$0.name.contains("Abstract") }

        messages.assertTrue(rule: Self.rule, strict: true, baseline: Self.baseline) {
            registry.contains("\($0.name).self,") || registry.contains("\($0.name).self\n")
        }
    }

    private static let baseline: [String] = []

    private static let rule = Rule(
        description: "Every request and response class is listed in MessageRegistry.allTypes.",
        rationale: """
            BTResponseParser finds the class for an incoming opcode through the registry. An unlisted response compiles
            and passes its own serialization test, then arrives from the pump as an unknown message the driver drops.
            """,
        fixHint: "Add <Name>.self to MessageRegistry.allTypes next to its request or response.",
        badExample: "public class SetTempRateResponse: Message, StatusMessage { ... }\n// …and no SetTempRateResponse.self in MessageRegistry",
        goodExample: "private static let allTypes: [Message.Type] = [\n    SetTempRateRequest.self,\n    SetTempRateResponse.self,\n]"
    )
}
