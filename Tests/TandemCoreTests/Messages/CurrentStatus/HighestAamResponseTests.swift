@testable import TandemKit
import XCTest

final class HighestAamResponseTests: XCTestCase {
    private func alarmStatus(_ alarm: AlarmStatusResponse.AlarmResponseType) -> AlarmStatusResponse {
        AlarmStatusResponse(intMap: UInt64(1) << UInt64(alarm.rawValue))
    }

    func testHighestAamResponse_12_0x2071_stuckVibratorMotor() {
        let expected = HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF, 0xFF]))

        let parsed: HighestAamResponse = MessageTester.test(
            "000779070b0c0000007120000004ffffd6a6",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(12, parsed.aamId)
        XCTAssertEqual(0x2071, parsed.faultId)
        XCTAssertEqual("12-0x2071", parsed.errorString)
        XCTAssertTrue(parsed.hasMalfunction())
    }

    func testHighestAamResponse_3_0x2026_pumpResetAlarmIgnored() {
        let expected = HighestAamResponse(aamId: 3, faultId: 8230, remaining: Data([2, 0xFF, 0xFF]))

        let parsed: HighestAamResponse = MessageTester.test(
            "001079100b030000002620000002ffff2ab0",
            16,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3, parsed.aamId)
        XCTAssertEqual(0x2026, parsed.faultId)
        XCTAssertFalse(parsed.hasMalfunction([alarmStatus(.PUMP_RESET_ALARM)]))
    }

    func testHighestAamResponse_18_0x2077_resumePumpAlarmIgnored() {
        let expected = HighestAamResponse(aamId: 18, faultId: 8311, remaining: Data([2, 3, 10]))

        let parsed: HighestAamResponse = MessageTester.test(
            "005979590b120000007720000002030a5792",
            89,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(18, parsed.aamId)
        XCTAssertEqual(0x2077, parsed.faultId)
        XCTAssertFalse(parsed.hasMalfunction([alarmStatus(.RESUME_PUMP_ALARM)]))
    }

    func testHighestAamResponse_parse10BytePayload() {
        let raw10 = HighestAamResponse(aamId: 12, faultId: 0x2071, remaining: Data([4, 0xFF])).cargo
        let parsed = HighestAamResponse(cargo: raw10)

        XCTAssertEqual(12, parsed.aamId)
        XCTAssertEqual(0x2071, parsed.faultId)
        XCTAssertEqual(Data([4, 0xFF]), parsed.remaining)
        XCTAssertEqual("12-0x2071", parsed.errorString)
    }
}
