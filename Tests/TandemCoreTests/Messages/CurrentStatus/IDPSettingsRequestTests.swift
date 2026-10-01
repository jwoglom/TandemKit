@testable import TandemKit
import XCTest

final class IDPSettingsRequestTests: XCTestCase {
    func testIDPSettingsRequest() {
        let expected = IDPSettingsRequest(idpId: 0)

        let parsed: IDPSettingsRequest = MessageTester.test(
            "000440040100ad05",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.idpId)
    }
}
