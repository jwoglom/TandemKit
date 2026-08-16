@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `CgmJoinSessionG7HistoryLogTest`.
final class CgmJoinSessionG7HistoryLogTests: XCTestCase {
    func testCgmJoinSessionG7HistoryLogParse() {
        // pumpTimeSec, sequenceNum, cgmTimestamp, sessionSignature
        let expected = CgmJoinSessionG7HistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            cgmTimestamp: 566_516_805,
            sessionSignature: 123_456_789
        )

        let rawHex = "8a01485cc42152bb0700455cc42115cd5b070000000000000000"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)

        let parsed = HistoryLogMessageTester.testSingle(rawHex, expected)

        XCTAssertEqual(expected.pumpTimeSec, parsed.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsed.sequenceNum)
        XCTAssertEqual(expected.cgmTimestamp, parsed.cgmTimestamp)
        XCTAssertEqual(expected.sessionSignature, parsed.sessionSignature)
    }
}
