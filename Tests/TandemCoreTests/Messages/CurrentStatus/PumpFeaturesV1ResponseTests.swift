@testable import TandemKit
import XCTest

final class PumpFeaturesV1ResponseTests: XCTestCase {
    func testPumpFeaturesResponse() {
        let expected = PumpFeaturesV1Response(intMap: 35_708_314)

        let parsed: PumpFeaturesV1Response = MessageTester.test(
            "00034f03089add2002000000007f08",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(parsed.primaryFeatures, [.DEXCOM_G6_SUPPORTED, .CONTROL_IQ_SUPPORTED, .AUTO_POP_SUPPORTED])
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
