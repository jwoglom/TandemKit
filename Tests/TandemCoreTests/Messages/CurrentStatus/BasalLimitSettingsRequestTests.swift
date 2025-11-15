import XCTest
@testable import TandemCore

final class BasalLimitSettingsRequestTests: XCTestCase {
    func testBasalLimitSettingsRequest() {
        let expected = BasalLimitSettingsRequest()

        let parsed: BasalLimitSettingsRequest = MessageTester.test(
            "00048a0400c3fc",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
