@testable import TandemKit
import XCTest

final class CgmJoinSessionHistoryLogTests: XCTestCase {
    // t:slim X2 newly paired to a Dexcom G6 already in session, official app BLE capture. CgmStatusV2 in the
    // same capture reported sessionDurationSeconds 864000 and a session age matching
    // currentTransmitterTime - sessionStartTime to within 1 s.
    func testCgmJoinSessionHistoryLogTransmitterInSession() {
        let expected = CgmJoinSessionHistoryLog(
            pumpTimeSec: 503_758_995,
            sequenceNum: 2_107_936,
            currentTransmitterTime: 3_125_188,
            sessionStartTime: 2_807_728,
            sessionJoinReasonRaw: 10,
            sessionDuration: 10
        )

        let parsed: CgmJoinSessionHistoryLog = HistoryLogMessageTester.testSingle(
            "d50093c0061e202a2000c4af2f00b0d72a00000000000a0a0000",
            expected
        )
        XCTAssertEqual(3_125_188, parsed.currentTransmitterTime)
        XCTAssertEqual(2_807_728, parsed.sessionStartTime)
        XCTAssertEqual(CgmJoinSessionHistoryLog.SessionJoinReason.DEXBLES_REASON_TRANSMITTER_IN_SESSION, parsed.sessionJoinReason)
        XCTAssertEqual(10, parsed.sessionDuration)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testCgmJoinSessionHistoryLogBuildCargoPutsDurationBeforeReason() {
        let cargo = CgmJoinSessionHistoryLog(
            pumpTimeSec: 1,
            sequenceNum: 2,
            currentTransmitterTime: 3,
            sessionStartTime: 4,
            sessionJoinReasonRaw: 6,
            sessionDuration: 10
        ).cargo
        XCTAssertEqual(Array(cargo[22 ..< 26]), [10, 6, 0, 0])
    }
}
