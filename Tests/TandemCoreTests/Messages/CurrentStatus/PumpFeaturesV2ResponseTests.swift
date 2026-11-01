@testable import TandemKit
import XCTest

final class PumpFeaturesV2ResponseTests: XCTestCase {
    func testMainFeaturesResponse() {
        let parsed = PumpFeaturesV2Response(cargo: Data(hexadecimalString: "000012956576")!)

        XCTAssertEqual(parsed.status, 0)
        XCTAssertEqual(parsed.supportedFeatureIndex, .mainFeatures)
        XCTAssertEqual(parsed.pumpFeaturesBitmask, 1_986_368_786)
        XCTAssertEqual(parsed.primaryFeatures, [
            .DEXCOM_G6_SUPPORTED, .CONTROL_IQ_SUPPORTED, .WOMBAT_SUPPORTED, .BASAL_LIMIT_SUPPORTED,
            .AUTO_POP_SUPPORTED, .BLE_PUMP_CONTROL_SUPPORTED, .PUMP_SETTINGS_IN_IDP_GUI_SUPPORTED,
        ])
        MessageTester.assertHexEquals(PumpFeaturesV2Response(status: 0, supportedFeatureIndex: 0, pumpFeaturesBitmask: 1_986_368_786).cargo, parsed.cargo)
    }
}
