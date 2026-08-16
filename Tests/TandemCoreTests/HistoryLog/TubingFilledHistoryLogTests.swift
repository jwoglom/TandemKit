@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `TubingFilledHistoryLogTest`.
final class TubingFilledHistoryLogTests: XCTestCase {
    // All ten captured samples for this record type carry primeSize == -1.0F (bytes 000080bf)
    // alongside completionStatus == COMPLETED (3); this looks like a firmware sentinel rather
    // than a decode error, since the IEEE-754 bit pattern is exact and consistent across every
    // sample. Left in verbatim per the capture rather than assumed a bug.
    func testTubingFilledHistoryLog1() {
        let expected = TubingFilledHistoryLog(
            // pumpTimeSec, sequenceNum, primeSize, completionStatus, position
            pumpTimeSec: 580_734_269, sequenceNum: 489_155, primeSize: -1.0, completionStatus: 3, position: 662_652
        ).withHeaderHighNibble(1)

        let parsedRes: TubingFilledHistoryLog = HistoryLogMessageTester.testSingle(
            "3f103d4d9d22c3760700000080bf030000007c1c0a0000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    func testTubingFilledHistoryLog2() {
        let expected = TubingFilledHistoryLog(
            // pumpTimeSec, sequenceNum, primeSize, completionStatus, position
            pumpTimeSec: 579_743_459, sequenceNum: 448_074, primeSize: -1.0, completionStatus: 3, position: 547_509
        ).withHeaderHighNibble(1)

        let parsedRes: TubingFilledHistoryLog = HistoryLogMessageTester.testSingle(
            "3f10e32e8e224ad60600000080bf03000000b55a080000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }
}
