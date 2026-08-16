@testable import TandemKit
import XCTest

/// Ported from pumpX2's `ControlIQUserModeChangeHistoryLogTest`.
final class ControlIQUserModeChangeHistoryLogTests: XCTestCase {
    func testControlIQUserModeChangeHistoryLog1() {
        let expected = ControlIQUserModeChangeHistoryLog(
            pumpTimeSec: 579954015,
            sequenceNum: 456965,
            currentUserMode: 1,
            previousUserMode: 2,
            requestedAction: 4,
            sleepStartedByGui: 0,
            activeSleepSchedule: 1,
            exerciseStoppedByTimer: 0,
            exerciseChoice: 0,
            exerciseTime: 0,
            eatingSoonStoppedByTimer: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e5105f65912205f9060001020400000100000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testControlIQUserModeChangeHistoryLog2() {
        let expected = ControlIQUserModeChangeHistoryLog(
            pumpTimeSec: 579953995,
            sequenceNum: 456952,
            currentUserMode: 0,
            previousUserMode: 1,
            requestedAction: 2,
            sleepStartedByGui: 1,
            activeSleepSchedule: 1,
            exerciseStoppedByTimer: 0,
            exerciseChoice: 0,
            exerciseTime: 0,
            eatingSoonStoppedByTimer: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "e5104b659122f8f8060000010200010100000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
