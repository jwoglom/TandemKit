@testable import TandemKit
import XCTest

final class LastBolusRequestBuilderTests: XCTestCase {
    func testSelectsV3ForMobi() {
        let request = LastBolusRequestBuilder.create(
            apiVersion: KnownApiVersion.mobiApiV3_5.value,
            pumpModel: .MOBI
        )
        XCTAssertTrue(request is LastBolusStatusV3Request)
    }

    /// V3 is Mobi-only from API 3.5, so anything else keeps the version-based selection.
    func testSelectsV2BelowMobiApi() {
        XCTAssertTrue(LastBolusRequestBuilder.create(
            apiVersion: KnownApiVersion.apiV3_4.value,
            pumpModel: .MOBI
        ) is LastBolusStatusV2Request)

        XCTAssertTrue(LastBolusRequestBuilder.create(
            apiVersion: KnownApiVersion.mobiApiV3_5.value,
            pumpModel: .TSLIM_X2
        ) is LastBolusStatusV2Request)

        XCTAssertTrue(LastBolusRequestBuilder.create(
            apiVersion: KnownApiVersion.apiV2_5.value
        ) is LastBolusStatusV2Request)
    }

    func testSelectsLegacyAtOrBelowApiV2_1() {
        XCTAssertTrue(LastBolusRequestBuilder.create(
            apiVersion: KnownApiVersion.apiV2_1.value
        ) is LastBolusStatusRequest)

        XCTAssertTrue(LastBolusRequestBuilder.create(apiVersion: nil) is LastBolusStatusRequest)
    }
}
