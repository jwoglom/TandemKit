@testable import TandemKit
import XCTest

/// Ported from pumpX2's `BasalDeliveryHistoryLogTest`.
final class BasalDeliveryHistoryLogTests: XCTestCase {
    // Bytes 12-13 carry an as-yet-unidentified field in ~58% of captured LID_BASAL_DELIVERY
    // records (no reference source defines them); these fixtures use captures where those bytes
    // are zero so the round-trip below is honest.
    func testBasalDeliveryHistoryLog1() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 580771325,
            sequenceNum: 490788,
            commandedRateSource: 3,
            commandedRate: 1000,
            profileBasalRate: 1000,
            algorithmRate: 1000,
            tempRate: 65535
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1711fddd9d22247d070003000000e803e803e803ffff00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBasalDeliveryHistoryLog2() {
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 580640885,
            sequenceNum: 485442,
            commandedRateSource: 1,
            commandedRate: 1200,
            profileBasalRate: 1200,
            algorithmRate: 65535,
            tempRate: 65535
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "171175e09b224268070001000000b004b004ffffffff00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBasalDeliveryHistoryLog3() {
        // suspend record: no commanded rate, algorithm/temp rate both "n/a" (0xffff)
        let expected = BasalDeliveryHistoryLog(
            pumpTimeSec: 580601530,
            sequenceNum: 483924,
            commandedRateSource: 0,
            commandedRate: 0,
            profileBasalRate: 1000,
            algorithmRate: 65535,
            tempRate: 65535
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "1711ba469b2254620700000000000000e803ffffffff00000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
