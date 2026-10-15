import Foundation
import Harmonize
import HarmonizeSemantics
import SwiftSyntax
import XCTest

final class DriverMessagesHaveSerializationTests: XCTestCase {
    func testEveryMessageTheDriverUsesHasASerializationTest() {
        let catalog = TandemHarmonize.messagesPackage.classes()
            .withNameEndingWith("Request", "Response", "HistoryLog")
            .filter { !$0.name.contains("Abstract") && $0.name != "HistoryLog" }
        let referenced = Set(Self.driverCode.flatMap(\.identifiers))
        // A reply reaches the driver as `Request.Response`, so it is used without being named.
        let replies = catalog.filter { referenced.contains($0.name) }.compactMap(Self.responseType)
        let used = referenced.union(replies)
        let testClassNames = TandemHarmonize.testClassNames

        catalog.filter { used.contains($0.name) }
            .assertTrue(rule: Self.rule, strict: true, baseline: Self.baseline) { testClassNames.contains($0.name + "Tests") }
    }

    /// The driver, and the TandemCore builders and helpers it names; not the message catalog, which names every
    /// message, nor the UI's debug sender.
    private static var driverCode: [SwiftSourceCode] {
        let driver = TandemHarmonize.driverPackage.sources()
        let referenced = Set(driver.flatMap(\.identifiers))
        let helpers = TandemHarmonize.corePackage.sources().filter { file in
            guard file.filePath?.path.contains("/Sources/TandemCore/Messages/") == false else { return false }
            let declared = file.classes().map(\.name) + file.structs().map(\.name) + file.enums().map(\.name)
                + file.protocols().map(\.name)
            return declared.contains(where: referenced.contains)
        }
        return driver + helpers
    }

    private static func responseType(of request: Class) -> String? {
        request.node.memberBlock.members.lazy
            .compactMap { $0.decl.as(TypeAliasDeclSyntax.self) }
            .first { $0.name.text == "Response" }?
            .initializer.value.trimmedDescription
    }

    private static let baseline: [String] = [
        "ActiveAamBitsRequest",
        "ActiveAamBitsResponse",
        "CGMStatusV2Request",
        "ControlIQInfoV2Request",
        "LastBolusStatusV3Request",
        "MalfunctionStatusRequest",
        "OtherNotification2StatusResponse",
        "OtherNotificationStatusResponse",
        "PumpVersionBRequest",
        "PumpingStateStreamResponse",
        "TimeChangedHistoryLog"
    ]

    private static let rule = Rule(
        description: "Every request, response and history record the driver uses has a <Type>Tests serialization test.",
        rationale: """
            Manager tests go through StubPumpBluetooth, which hands back constructed objects and never touches cargo,
            so a wrong offset or byte order in a message the driver relies on passes every manager test and misreads
            the pump in use.
            """,
        fixHint: """
            Add Tests/TandemCoreTests/Messages/<Category>/<Type>Tests.swift (history records:
            Tests/TandemCoreTests/HistoryLog/<Type>Tests.swift) using MessageTester or HistoryLogMessageTester, with hex
            from pumpX2's tests or a pump capture. Then delete the type from this rule's baseline.
            """,
        badExample: "// TandemPumpManager sends SetTempRateRequest, and there is no SetTempRateRequestTests",
        goodExample: "final class SetTempRateRequestTests: XCTestCase {\n    func testSetTempRateRequest() throws { try MessageTester.test(\"...\", ...) }\n}"
    )
}
