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

    /// Byte layout per the Tandem Source event schema for LID_AA_DAILY_STATUS:
    /// pumpControlState u8 @0, userMode u8 @1, sensorType u8 @2, weightUnit u8 @3, weight u16 @4, currentTdiPop u8 @6.
    func testDailyStatusHistoryLogLayout() {
        let expected = DailyStatusHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            sensorType: 3,
            userMode: 1,
            pumpControlState: 2,
            weightUnit: 1,
            weight: 180,
            currentTdiPop: 45
        )
        let rawHex = "3901485cc42152bb070002010301b4002d000000000000000000"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)
        let parsedRes = HistoryLogMessageTester.testSingle(rawHex, expected)
        XCTAssertEqual(.pcmPining, parsedRes.pumpControlStateEnum)
        XCTAssertEqual(.sleeping, parsedRes.userModeEnum)
        XCTAssertEqual(.cgmTypeDexcomG7, parsedRes.sensorTypeEnum)
        XCTAssertEqual(.pounds, parsedRes.weightUnitEnum)
        XCTAssertEqual(180, parsedRes.weight)
        XCTAssertEqual(45, parsedRes.currentTdiPop)
    }
}
