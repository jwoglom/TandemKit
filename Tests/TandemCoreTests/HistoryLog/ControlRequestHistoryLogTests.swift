@testable import TandemKit
import XCTest

final class ControlRequestHistoryLogTests: XCTestCase {
    func testStopTempRateRequest() {
        let expected = ControlRequestHistoryLog(
            pumpTimeSec: 591098918,
            sequenceNum: 723589,
            requestTimestamp: 1764775,
            requestOpCode: 166
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "221126743b23850a0b00a7ed1a00a60000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.requestTimestamp, 1764775)
        XCTAssertEqual(parsed.requestOpCode, 166)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testSetTempRateRequest() {
        let expected = ControlRequestHistoryLog(
            pumpTimeSec: 591098918,
            sequenceNum: 723592,
            requestTimestamp: 1764775,
            requestOpCode: 164
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "221126743b23880a0b00a7ed1a00a40000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.requestOpCode, 164)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testEnterFillTubingModeRequest() {
        let expected = ControlRequestHistoryLog(
            pumpTimeSec: 590440422,
            sequenceNum: 689018,
            requestTimestamp: 1105602,
            requestOpCode: 148
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "2211e66731237a830a00c2de1000940000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.requestOpCode, 148)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testOfficialAppStampIsUtcNotPumpLocal() {
        let expected = ControlRequestHistoryLog(
            pumpTimeSec: 536692298,
            sequenceNum: 236,
            requestTimestamp: 536710300,
            requestOpCode: 132
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "22114a46fd1fec0000009c8cfd1f840000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.requestTimestamp - parsed.pumpTimeSec, 18002)
        XCTAssertEqual(parsed.requestOpCode, 132)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testTslimX2UserInteractionRequest() {
        let expected = ControlRequestHistoryLog(
            pumpTimeSec: 534182906,
            sequenceNum: 1049379,
            requestTimestamp: 534200996,
            requestOpCode: 132
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "2201fafbd61f23031000a442d71f840000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testIssueExampleStampIsOneUint32() {
        let expected = ControlRequestHistoryLog(
            pumpTimeSec: 589527121,
            sequenceNum: 640770,
            requestTimestamp: 192683,
            requestOpCode: 166
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "22115178232302c70900abf00200a60000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.requestTimestamp, 192683)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
