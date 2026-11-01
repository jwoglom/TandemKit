@testable import TandemKit
import XCTest

final class RemindersResponseTests: XCTestCase {
    private func reminder(_ frequency: UInt32, enabled: UInt8 = 0, validity: UInt8 = 0) -> RemindersResponse.Reminder {
        RemindersResponse.Reminder(frequency: frequency, startTime: 0, endTime: 0, activeDays: 0, enabled: enabled, validityStatus: validity)
    }

    func testRemindersResponseAllOff() {
        let expected = RemindersResponse(
            lowBGReminder: reminder(15),
            highBGReminder: reminder(120),
            siteChangeReminder: reminder(1260, validity: 3),
            missedBolusReminder0: reminder(0),
            missedBolusReminder1: reminder(0),
            missedBolusReminder2: reminder(0),
            missedBolusReminder3: reminder(0),
            afterBolusReminder: reminder(90),
            additionalBolusReminder: reminder(0, enabled: 1),
            lowBGThreshold: 70,
            highBGThreshold: 200,
            siteChangeDays: 3,
            status: 4
        )

        let parsed: RemindersResponse = MessageTester.test(
            "00035903690f000000000000000000007800000000000000000000ec0400000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000005a0000000000000000000000000000000000000001004600c8000304e7f9",
            3,
            7,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(parsed.siteChangeReminder.frequency, 1260)
        XCTAssertEqual(parsed.additionalBolusReminder.enabled, 1)
        XCTAssertEqual(parsed.lowBGThreshold, 70)
        XCTAssertEqual(parsed.highBGThreshold, 200)
        XCTAssertEqual(parsed.status, 4)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
