@testable import TandemKit
import XCTest

final class PumpFeaturesV2RequestTests: XCTestCase {
    func testMainFeaturesRequest() {
        let expected = PumpFeaturesV2Request(supportedFeature: .mainFeatures)

        let parsed: PumpFeaturesV2Request = MessageTester.test(
            "0006a006010027ef",
            6,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
