@testable import TandemKit
import XCTest

final class CgmStopSessionHistoryLogTests: XCTestCase {
    // Tandem Mobi + Dexcom G6, official app BLE capture, 34m59s after the CgmStartSession record seq 52248.
    func testCgmStopSessionHistoryLogTransmitterNotInSession() {
        let expected = CgmStopSessionHistoryLog(
            pumpTimeSec: 540_616_480,
            sequenceNum: 52337,
            currentTransmitterTime: 2_120_781,
            sessionStartTime: 4_294_967_295,
            sessionStopTime: 0,
            sessionStopReasonRaw: 6,
            sessionDuration: 10
        ).withHeaderHighNibble(1)

        let parsed: CgmStopSessionHistoryLog = HistoryLogMessageTester.testSingle(
            "d6102027392071cc00004d5c2000ffffffff000000000a060000",
            expected
        )
        XCTAssertEqual(2_120_781, parsed.currentTransmitterTime)
        XCTAssertEqual(CgmStopSessionHistoryLog.SessionStopReason.DEXBLES_REASON_TRANSMITTER_NOT_IN_SESSION, parsed.sessionStopReason)
        XCTAssertEqual(10, parsed.sessionDuration)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    // Same pump, captured alongside the app's StopDexcomCGMSensorSessionRequest.
    func testCgmStopSessionHistoryLogUserStop() {
        let expected = CgmStopSessionHistoryLog(
            pumpTimeSec: 536_004_396,
            sequenceNum: 48530,
            currentTransmitterTime: 0,
            sessionStartTime: 4_294_967_295,
            sessionStopTime: 0,
            sessionStopReasonRaw: 0,
            sessionDuration: 10
        ).withHeaderHighNibble(1)

        let parsed: CgmStopSessionHistoryLog = HistoryLogMessageTester.testSingle(
            "d6102cc7f21f92bd000000000000ffffffff000000000a000000",
            expected
        )
        XCTAssertEqual(CgmStopSessionHistoryLog.SessionStopReason.DEXBLES_REASON_USER, parsed.sessionStopReason)
        XCTAssertEqual(10, parsed.sessionDuration)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
