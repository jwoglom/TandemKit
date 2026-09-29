@testable import TandemKit
import XCTest

final class CgmStateChangeGxHistoryLogTests: XCTestCase {
    func testCgmStateChangeIdleTickWithoutSession() {
        // Maintainer's Tandem Mobi (7.9.0.2), no CGM session.
        let expected = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 590112364,
            sequenceNum: 670898,
            previousStateId: 0,
            stateId: 0,
            eventId: 6
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "db106c662c23b23c0a0000000000000000000000000006000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(.stopped, parsed.previousState)
        XCTAssertEqual(.stopped, parsed.state)
        XCTAssertEqual(.idleTick, parsed.event)
        XCTAssertFalse(parsed.isStateChange)
        XCTAssertEqual(0, parsed.unknown11)
        XCTAssertEqual(0, parsed.unknown15)
        XCTAssertEqual(0, parsed.unknown18)
        XCTAssertEqual(0, parsed.unknown23)
    }

    func testCgmStateChangeCycleStartThenDataReceived() {
        // Maintainer's t:slim X2 (2024), Dexcom G7 session.
        let expectedStart = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 534413222,
            sequenceNum: 1061528,
            previousStateId: 2,
            stateId: 2,
            eventId: 1
        )
        let parsedStart = HistoryLogMessageTester.testSingle(
            "db00a67fda1f9832100002000000020000000000000001000000",
            expectedStart
        )
        MessageTester.assertHexEquals(expectedStart.cargo, parsedStart.cargo)
        XCTAssertEqual(.active, parsedStart.state)
        XCTAssertEqual(.cycleStart, parsedStart.event)

        let expectedData = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 534413223,
            sequenceNum: 1061529,
            previousStateId: 2,
            stateId: 2,
            eventId: 2
        )
        let parsedData = HistoryLogMessageTester.testSingle(
            "db00a77fda1f9932100002000000020000000000000002000000",
            expectedData
        )
        MessageTester.assertHexEquals(expectedData.cargo, parsedData.cargo)
        XCTAssertEqual(.active, parsedData.state)
        XCTAssertEqual(.dataReceived, parsedData.event)
        XCTAssertEqual(1, parsedData.pumpTimeSec - parsedStart.pumpTimeSec)

        // Maintainer's Tandem Mobi (2025), Dexcom G7 session.
        let expectedMobi = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 539479615,
            sequenceNum: 106080,
            previousStateId: 2,
            stateId: 2,
            eventId: 2
        ).withHeaderHighNibble(1)
        let parsedMobi = HistoryLogMessageTester.testSingle(
            "db103fce2720609e010002000000020000000000000002000000",
            expectedMobi
        )
        MessageTester.assertHexEquals(expectedMobi.cargo, parsedMobi.cargo)
        XCTAssertEqual(.dataReceived, parsedMobi.event)
    }

    func testCgmStateChangeCycleStartThenNoData() {
        // Maintainer's t:slim X2 (2024), Dexcom G7 session.
        let expectedStart = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 534170224,
            sequenceNum: 1048758,
            previousStateId: 2,
            stateId: 2,
            eventId: 1
        )
        let parsedStart = HistoryLogMessageTester.testSingle(
            "db0070cad61fb600100002000000020000000000000001000000",
            expectedStart
        )
        MessageTester.assertHexEquals(expectedStart.cargo, parsedStart.cargo)

        let expectedNoData = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 534170251,
            sequenceNum: 1048761,
            previousStateId: 2,
            stateId: 2,
            eventId: 3
        )
        let parsedNoData = HistoryLogMessageTester.testSingle(
            "db008bcad61fb900100002000000020000000000000003000000",
            expectedNoData
        )
        MessageTester.assertHexEquals(expectedNoData.cargo, parsedNoData.cargo)
        XCTAssertEqual(.noData, parsedNoData.event)
        XCTAssertEqual(.active, parsedNoData.state)
        XCTAssertFalse(parsedNoData.isStateChange)
        XCTAssertEqual(27, parsedNoData.pumpTimeSec - parsedStart.pumpTimeSec)
    }

    func testCgmStateChangeSessionStopAndRestart() {
        // Maintainer's t:slim X2 (2024), Dexcom G7 sensor change.
        let expectedStop = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 534413823,
            sequenceNum: 1061550,
            previousStateId: 2,
            stateId: 0,
            eventId: 4
        )
        let parsedStop = HistoryLogMessageTester.testSingle(
            "db00ff81da1fae32100002000000000000000000000004000000",
            expectedStop
        )
        MessageTester.assertHexEquals(expectedStop.cargo, parsedStop.cargo)
        XCTAssertEqual(.active, parsedStop.previousState)
        XCTAssertEqual(.stopped, parsedStop.state)
        XCTAssertEqual(.sessionCommand, parsedStop.event)
        XCTAssertTrue(parsedStop.isStateChange)

        let expectedStart = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 534413964,
            sequenceNum: 1061577,
            previousStateId: 0,
            stateId: 1,
            eventId: 1
        )
        let parsedStart = HistoryLogMessageTester.testSingle(
            "db008c82da1fc932100000000000010000000000000001000000",
            expectedStart
        )
        MessageTester.assertHexEquals(expectedStart.cargo, parsedStart.cargo)
        XCTAssertEqual(.stopped, parsedStart.previousState)
        XCTAssertEqual(.startPending, parsedStart.state)
        XCTAssertEqual(.cycleStart, parsedStart.event)

        let expectedActive = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 534414060,
            sequenceNum: 1061589,
            previousStateId: 1,
            stateId: 2,
            eventId: 2
        )
        let parsedActive = HistoryLogMessageTester.testSingle(
            "db00ec82da1fd532100001000000020000000000000002000000",
            expectedActive
        )
        MessageTester.assertHexEquals(expectedActive.cargo, parsedActive.cargo)
        XCTAssertEqual(.startPending, parsedActive.previousState)
        XCTAssertEqual(.active, parsedActive.state)
        XCTAssertEqual(.dataReceived, parsedActive.event)
    }

    func testCgmStateChangeUserActivity() {
        // Maintainer's t:slim X2 (2024), right after a PumpButton release.
        let expected = CgmStateChangeGxHistoryLog(
            pumpTimeSec: 532612484,
            sequenceNum: 976447,
            previousStateId: 2,
            stateId: 2,
            eventId: 5
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "db008405bf1f3fe60e0002000000020000000000000005000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(.active, parsed.state)
        XCTAssertEqual(.userActivity, parsed.event)
    }

    func testCgmStateChangeUnidentifiedIdsMapToUnknown() {
        let log = CgmStateChangeGxHistoryLog(pumpTimeSec: 0, sequenceNum: 0, previousStateId: 1, stateId: 3, eventId: 9)
        XCTAssertEqual(.startPending, log.previousState)
        XCTAssertEqual(3, log.stateId)
        XCTAssertEqual(.unknown, log.state)
        XCTAssertEqual(9, log.eventId)
        XCTAssertEqual(.unknown, log.event)
    }
}
