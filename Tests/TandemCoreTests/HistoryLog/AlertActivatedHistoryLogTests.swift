@testable import TandemKit
import XCTest

final class AlertActivatedHistoryLogTests: XCTestCase {
    func testAlertActivatedHistoryLog1() {
        // long alertId, long faultLocatorData, long param1, float param2
        let expected = AlertActivatedHistoryLog(
            alertId: 51,
            faultLocatorData: 0,
            param1: 0,
            param2: 514.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "040024c0981aadde020033000000000000000000000000800044",
            expected
        )
        // pumpX2's Java test asserts CONTROL_IQ_LOW here; the Swift AlertResponseType enum
        // (Sources/TandemCore/Messages/CurrentStatus/AlertStatus.swift) currently names alert id
        // 51 `DEFAULT_ALERT_51` rather than `CONTROL_IQ_LOW` -- a pre-existing naming gap in
        // AlertStatus.swift, out of scope for this history-log parity pass. The rawValue (51)
        // still matches, so this assertion is behaviorally equivalent to the Java test.
        XCTAssertEqual(AlertStatusResponse.AlertResponseType.DEFAULT_ALERT_51, parsedRes.alertResponseType)
    }

    func testAlertActivatedHistoryLog2() {
        // long alertId, long faultLocatorData, long param1, float param2
        let expected = AlertActivatedHistoryLog(
            alertId: 48,
            faultLocatorData: 8623,
            param1: 0,
            param2: 0.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "040022df971aced8020030000000af2100000000000000000000",
            expected
        )
        XCTAssertEqual(AlertStatusResponse.AlertResponseType.CGM_UNAVAILABLE, parsedRes.alertResponseType)
    }

    func testAlertActivatedHistoryLog3() {
        // long alertId, long faultLocatorData, long param1, float param2
        let expected = AlertActivatedHistoryLog(
            alertId: 11,
            faultLocatorData: 8378,
            param1: 0,
            param2: 0.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "0400b5f4981a66e002000b000000ba2000000000000000000000",
            expected
        )
        XCTAssertEqual(AlertStatusResponse.AlertResponseType.INCOMPLETE_BOLUS_ALERT, parsedRes.alertResponseType)
    }

    func testAlertActivatedHistoryLog4() {
        // long alertId, long faultLocatorData, long param1, float param2
        let expected = AlertActivatedHistoryLog(
            alertId: 0,
            faultLocatorData: 8242,
            param1: 102,
            param2: 347.551513671875
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "0400304e951a90c5020000000000322000006600000098c6ad43",
            expected
        )
        XCTAssertEqual(AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT, parsedRes.alertResponseType)
    }
}
