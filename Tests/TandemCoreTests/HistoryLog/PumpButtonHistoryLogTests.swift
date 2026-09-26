@testable import TandemKit
import XCTest

final class PumpButtonHistoryLogTests: XCTestCase {
    @discardableResult
    private func check(
        _ hex: String,
        nibble: Int,
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        timeOfDayMs: UInt32,
        state: Int
    ) -> PumpButtonHistoryLog {
        let expected = PumpButtonHistoryLog(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            timeOfDayMs: timeOfDayMs,
            state: state
        ).withHeaderHighNibble(nibble)

        let parsed = HistoryLogMessageTester.testSingle(hex, expected)
        XCTAssertEqual(pumpTimeSec, parsed.pumpTimeSec)
        XCTAssertEqual(sequenceNum, parsed.sequenceNum)
        XCTAssertEqual(timeOfDayMs, parsed.timeOfDayMs)
        XCTAssertEqual(state, parsed.state)
        XCTAssertEqual(pumpTimeSec % 86400, parsed.timeOfDayMs / 1000)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        return parsed
    }

    func testMobiPressThenRelease() {
        let press = check("11102c713823d0e20a002a50b600010000000000000000000000", nibble: 1, pumpTimeSec: 590901548, sequenceNum: 713424, timeOfDayMs: 11948074, state: 1)
        let release = check("11102c713823d1e20a00b750b600000000000000000000000000", nibble: 1, pumpTimeSec: 590901548, sequenceNum: 713425, timeOfDayMs: 11948215, state: 0)
        XCTAssertTrue(press.isPressed)
        XCTAssertFalse(release.isPressed)
        XCTAssertEqual(141, release.timeOfDayMs - press.timeOfDayMs)
    }

    func testMobiPressStartingTubingPrime() {
        let press = check("1110ec6731237c830a00f2562004010000000000000000000000", nibble: 1, pumpTimeSec: 590440428, sequenceNum: 689020, timeOfDayMs: 69228274, state: 1)
        XCTAssertTrue(press.isPressed)
    }

    func testX2PressAndRelease() {
        let press = check("11009d4a831b15640000c2ae6702010000000000000000000000", nibble: 0, pumpTimeSec: 461589149, sequenceNum: 25621, timeOfDayMs: 40349378, state: 1)
        let release = check("11009d4a831b1664000044af6702000000000000000000000000", nibble: 0, pumpTimeSec: 461589149, sequenceNum: 25622, timeOfDayMs: 40349508, state: 0)
        XCTAssertTrue(press.isPressed)
        XCTAssertFalse(release.isPressed)
        XCTAssertEqual(130, release.timeOfDayMs - press.timeOfDayMs)
    }
}
