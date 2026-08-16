@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmStopSessionG7HistoryLogTest`.
final class CgmStopSessionG7HistoryLogTests: XCTestCase {
    func testCgmStopSessionG7HistoryLogParse() {
        // pumpTimeSec, sequenceNum, currentTransmitterTime, sessionStartTime, sessionStopTime, stopSessionCode, sessionStopReason, sessionDuration
        let expected = CgmStopSessionG7HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            currentTransmitterTime: 566_516_805,
            sessionStartTime: 566_430_000,
            sessionStopTime: 566_516_800,
            stopSessionCode: 1,
            sessionStopReason: 2,
            sessionDuration: 10
        )

        let rawHex = "bf01485cc42152bb0700455cc4213009c321405cc4210001020a"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)

        let parsed = HistoryLogMessageTester.testSingle(rawHex, expected)

        XCTAssertEqual(expected.pumpTimeSec, parsed.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsed.sequenceNum)
        XCTAssertEqual(expected.currentTransmitterTime, parsed.currentTransmitterTime)
        XCTAssertEqual(expected.sessionStartTime, parsed.sessionStartTime)
        XCTAssertEqual(expected.sessionStopTime, parsed.sessionStopTime)
        XCTAssertEqual(expected.stopSessionCode, parsed.stopSessionCode)
        XCTAssertEqual(expected.sessionStopReason, parsed.sessionStopReason)
        XCTAssertEqual(expected.sessionDuration, parsed.sessionDuration)
    }
}
