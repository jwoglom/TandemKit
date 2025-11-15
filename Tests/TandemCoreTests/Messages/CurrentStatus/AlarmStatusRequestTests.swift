import XCTest
@testable import TandemCore

final class AlarmStatusRequestTests: XCTestCase {
    func testAlarmStatusRequest() {
        let expected = AlarmStatusRequest()

        let parsed: AlarmStatusRequest = MessageTester.test(
            "0003460300c236",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
