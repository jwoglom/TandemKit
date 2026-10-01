@testable import TandemKit
import XCTest

final class CurrentBatteryV2RequestTests: XCTestCase {
    func testCurrentBatteryV2Request() {
        let expected = CurrentBatteryV2Request()

        let parsed: CurrentBatteryV2Request = MessageTester.test(
            "0005900500504b",
            5,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
