@testable import TandemKit
import XCTest

final class AlarmActivatedHistoryLogTests: XCTestCase {
    func testAlarmActivatedHistoryLog1() {
        // long alarmId, long faultLocatorData, long param1, float param2
        let expected = AlarmActivatedHistoryLog(
            alarmId: 18,
            faultLocatorData: 8311,
            param1: 6544514,
            param2: 0.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "0500b3e8951a86c90200120000007720000082dc630000000000",
            expected
        )
        XCTAssertEqual(AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM, parsedRes.alarmResponseType)
    }

    func testAlarmActivatedHistoryLog2() {
        // long alarmId, long faultLocatorData, long param1, float param2
        let expected = AlarmActivatedHistoryLog(
            alarmId: 23,
            faultLocatorData: 8311,
            param1: 18,
            param2: 0.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "05004044971af9d2020017000000772000001200000000000000",
            expected
        )
        XCTAssertEqual(AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM2, parsedRes.alarmResponseType)
    }

    func testAlarmActivatedHistoryLog3() {
        // long alarmId, long faultLocatorData, long param1, float param2
        let expected = AlarmActivatedHistoryLog(
            alarmId: 23,
            faultLocatorData: 8311,
            param1: 18,
            param2: 0.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "0500b3e8951a87c9020017000000772000001200000000000000",
            expected
        )
        XCTAssertEqual(AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM2, parsedRes.alarmResponseType)
    }

    func testAlarmActivatedHistoryLog4() {
        // long alarmId, long faultLocatorData, long param1, float param2
        let expected = AlarmActivatedHistoryLog(
            alarmId: 18,
            faultLocatorData: 8311,
            param1: 6633487,
            param2: 0.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "05004044971af8d2020012000000772000000f38650000000000",
            expected
        )
        XCTAssertEqual(AlarmStatusResponse.AlarmResponseType.RESUME_PUMP_ALARM, parsedRes.alarmResponseType)
    }
}
