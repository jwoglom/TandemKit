@testable import TandemKit
import XCTest

final class ReminderStatusResponseTests: XCTestCase {
    func testReminderStatusResponseEmpty() {
        let expected = ReminderStatusResponse(intMap: 0)

        let parsed: ReminderStatusResponse = MessageTester.test(
            "000349030800000000000000002d72",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.intMap)
        XCTAssertTrue(parsed.reminders.isEmpty)
    }

    func testReminderStatusResponse_SiteChangeReminder() {
        let siteChangeBit = UInt64(1) << UInt64(ReminderStatusResponse.ReminderType.SITE_CHANGE_REMINDER.rawValue)
        let expected = ReminderStatusResponse(intMap: siteChangeBit)

        let parsed: ReminderStatusResponse = MessageTester.test(
            "00194919080400000000000000177d",
            25,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(siteChangeBit, parsed.intMap)
        XCTAssertEqual([.SITE_CHANGE_REMINDER], parsed.reminders)
    }
}
