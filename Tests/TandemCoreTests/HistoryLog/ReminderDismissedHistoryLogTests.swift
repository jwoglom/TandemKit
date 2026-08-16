@testable import TandemKit
import XCTest

final class ReminderDismissedHistoryLogTests: XCTestCase {
    func testReminderDismissedHistoryLog1() {
        let expected = ReminderDismissedHistoryLog(
            // pumpTimeSec, sequenceNum, reminderId
            pumpTimeSec: 580_095_338, sequenceNum: 462_904, reminderId: 2
        )

        // Bytes 14-25 of this capture are a nonzero, unparsed tail (91d19d175f00000064050000)
        // that parse() does not read; it differs from the other captured type-29 record below
        // except for a constant trailing 64050000.
        HistoryLogMessageTester.testSingle(
            "1d106a8d9322381007000200000091d19d175f00000064050000",
            expected
        )
        // no cargo round-trip: bytes 14-18 and 22-23 (0x0564) carry unparsed data that buildCargo zero-fills
    }

    func testReminderDismissedHistoryLog2() {
        let expected = ReminderDismissedHistoryLog(
            // pumpTimeSec, sequenceNum, reminderId
            pumpTimeSec: 579_744_845, sequenceNum: 448_171, reminderId: 2
        )

        // Bytes 14-25 of this capture are a nonzero, unparsed tail (56b8b9020e00000064050000)
        // that parse() does not read; it differs from the other captured type-29 record above
        // except for a constant trailing 64050000.
        HistoryLogMessageTester.testSingle(
            "1d104d348e22abd606000200000056b8b9020e00000064050000",
            expected
        )
        // no cargo round-trip: bytes 14-18 and 22-23 (0x0564) carry unparsed data that buildCargo zero-fills
    }
}
