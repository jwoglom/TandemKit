@testable import TandemKit
import XCTest

final class CgmStartSessionHistoryLogTests: XCTestCase {
    // Tandem Mobi + Dexcom G6, official app BLE capture, just after StartDexcomG6SensorSessionRequest.
    func testCgmStartSessionHistoryLogG6Start() {
        let expected = CgmStartSessionHistoryLog(
            pumpTimeSec: 540_614_381,
            sequenceNum: 52248,
            currentTransmitterTime: 2_118_683,
            sessionStartTime: 2_118_683,
            sessionDuration: 10
        ).withHeaderHighNibble(1)

        let parsed: CgmStartSessionHistoryLog = HistoryLogMessageTester.testSingle(
            "d410ed1e392018cc00001b5420001b542000000000000a000000",
            expected
        )
        XCTAssertEqual(2_118_683, parsed.currentTransmitterTime)
        XCTAssertEqual(2_118_683, parsed.sessionStartTime)
        XCTAssertEqual(10, parsed.sessionDuration)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
