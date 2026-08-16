@testable import TandemKit
import XCTest

final class ReminderActivatedHistoryLogTests: XCTestCase {
    func testReminderActivatedHistoryLog1() {
        let expected = ReminderActivatedHistoryLog(
            // pumpTimeSec, sequenceNum, reminderId
            pumpTimeSec: 580_777_206, sequenceNum: 491_057, reminderId: 2
        )

        // Bytes 14-25 of this capture are a nonzero, unparsed tail (b0200000000000000080ac44)
        // that is identical across all captured type-25 records; parse() does not read it.
        HistoryLogMessageTester.testSingle(
            "1910f6f49d22317e070002000000b0200000000000000080ac44",
            expected
        )
        // no cargo round-trip: bytes 14-15 (0x20b0) and 23-25 (0x44ac80) carry unparsed data that buildCargo zero-fills
    }

    func testReminderActivatedHistoryLog2() {
        let expected = ReminderActivatedHistoryLog(
            // pumpTimeSec, sequenceNum, reminderId
            pumpTimeSec: 579_740_400, sequenceNum: 447_851, reminderId: 2
        )

        // Bytes 14-25 of this capture are a nonzero, unparsed tail (b0200000000000000080ac44)
        // that is identical across all captured type-25 records; parse() does not read it.
        HistoryLogMessageTester.testSingle(
            "1910f0228e226bd5060002000000b0200000000000000080ac44",
            expected
        )
        // no cargo round-trip: bytes 14-15 (0x20b0) and 23-25 (0x44ac80) carry unparsed data that buildCargo zero-fills
    }
}
