@testable import TandemKit
import XCTest

/// Ported from pumpX2's `DailyStatusHistoryLogTest`.
final class DailyStatusHistoryLogTests: XCTestCase {
    func testDailyStatusHistoryLogParse() {
        let expected = DailyStatusHistoryLog(
            pumpTimeSec: 566516808,
            sequenceNum: 506706,
            sensorType: 2,
            userMode: 1,
            pumpControlState: 3
        )

        let parsed = HistoryLogParser.parse(expected.cargo)
        XCTAssertTrue(parsed is DailyStatusHistoryLog)

        guard let parsedRes = parsed as? DailyStatusHistoryLog else { return }
        XCTAssertEqual(expected.pumpTimeSec, parsedRes.pumpTimeSec)
        XCTAssertEqual(expected.sequenceNum, parsedRes.sequenceNum)
        XCTAssertEqual(expected.sensorType, parsedRes.sensorType)
        XCTAssertEqual(expected.userMode, parsedRes.userMode)
        XCTAssertEqual(expected.pumpControlState, parsedRes.pumpControlState)
        XCTAssertEqual(expected.sensorTypeEnum, parsedRes.sensorTypeEnum)
        XCTAssertEqual(expected.userModeEnum, parsedRes.userModeEnum)
        XCTAssertEqual(expected.pumpControlStateEnum, parsedRes.pumpControlStateEnum)
        XCTAssertEqual(DailyStatusHistoryLog.SensorType.cgmTypeLibre2, parsedRes.sensorTypeEnum)
        XCTAssertEqual(DailyStatusHistoryLog.UserMode.sleeping, parsedRes.userModeEnum)
        XCTAssertEqual(DailyStatusHistoryLog.PumpControlState.pcmClosedLoop, parsedRes.pumpControlStateEnum)
    }
}
