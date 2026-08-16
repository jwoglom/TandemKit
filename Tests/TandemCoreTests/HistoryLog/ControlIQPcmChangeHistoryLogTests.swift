@testable import TandemKit
import XCTest

/// Ported from pumpX2's `ControlIQPcmChangeHistoryLogTest`.
final class ControlIQPcmChangeHistoryLogTests: XCTestCase {
    func testControlIQPcmChangeHistoryLog1() {
        let expected = ControlIQPcmChangeHistoryLog(
            pumpTimeSec: 580773244,
            sequenceNum: 490889,
            currentPcm: 0,
            previousPcm: 3,
            pumpSuspended: 1,
            calculationAvailable: 1,
            cgmAvailable: 1,
            closedLoopPreferred: 1,
            sufficientClosedLoopParams: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e6107ce59d22897d070000030101010101000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testControlIQPcmChangeHistoryLog2() {
        let expected = ControlIQPcmChangeHistoryLog(
            pumpTimeSec: 580720759,
            sequenceNum: 488634,
            currentPcm: 3,
            previousPcm: 2,
            pumpSuspended: 0,
            calculationAvailable: 1,
            cgmAvailable: 1,
            closedLoopPreferred: 1,
            sufficientClosedLoopParams: 1
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e61077189d22ba74070003020001010101000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
