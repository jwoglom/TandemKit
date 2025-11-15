import XCTest
@testable import TandemCore

final class CurrentBatteryV1RequestTests: XCTestCase {
    func testCurrentBatteryV1Request() {
        let expected = CurrentBatteryV1Request()

        let parsed: CurrentBatteryV1Request = MessageTester.test(
            "0003340300aa80",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
