@testable import TandemKit
import XCTest

final class ControlResponseHistoryLogTests: XCTestCase {
    func testStopTempRateResponse() {
        let expected = ControlResponseHistoryLog(
            pumpTimeSec: 591098918,
            sequenceNum: 723590,
            responseOpCode: 167,
            status: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "2c1126743b23860a0b00a7000000000000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.responseOpCode, 167)
        XCTAssertEqual(parsed.status, 0)
        XCTAssertEqual(parsed.unknown11, 0)
        MessageTester.assertHexEquals(parsed.unknownTail, Data(count: 13))
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testFailedResumePumpingResponse() {
        let expected = ControlResponseHistoryLog(
            pumpTimeSec: 590519594,
            sequenceNum: 692817,
            responseOpCode: 155,
            status: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "2c112a9d322351920a009b000100000000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.responseOpCode, 155)
        XCTAssertEqual(parsed.status, 1)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testFailedSuspendPumpingResponse() {
        let expected = ControlResponseHistoryLog(
            pumpTimeSec: 590614626,
            sequenceNum: 697678,
            responseOpCode: 157,
            status: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "2c11621034234ea50a009d000100000000000000000000000000",
            expected
        )
        XCTAssertEqual(parsed.responseOpCode, 157)
        XCTAssertEqual(parsed.status, 1)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testTslimX2UserInteractionResponseKeepsTailBytes() {
        let tail = Data(hexadecimalString: "0000fafbd60000000000000000")!
        let expected = ControlResponseHistoryLog(
            pumpTimeSec: 534182906,
            sequenceNum: 1049380,
            responseOpCode: 133,
            status: 0,
            unknownTail: tail
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "2c01fafbd61f240310008500000000fafbd60000000000000000",
            expected
        )
        XCTAssertEqual(parsed.responseOpCode, 133)
        MessageTester.assertHexEquals(parsed.unknownTail, tail)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
