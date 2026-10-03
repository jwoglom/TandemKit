@testable import TandemKit
import XCTest

final class SetMaxBolusLimitRequestTests: XCTestCase {
    func testSetMaxBolusLimitRequest_20u() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1)
        let expected = try SetMaxBolusLimitRequest(maxBolusMilliunits: 20000)

        let parsed: SetMaxBolusLimitRequest = MessageTester.test(
            "016186611a204e92e14920c2f4aee8ca1b7d1960",
            97,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "006175ffd49542eeb8c009ed2022f2"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(20000, parsed.maxBolusMilliunits)
    }

    func testBoundsAreAccepted() throws {
        XCTAssertEqual(1000, try SetMaxBolusLimitRequest(maxBolusMilliunits: 1000).maxBolusMilliunits)
        XCTAssertEqual(25000, try SetMaxBolusLimitRequest(maxBolusMilliunits: 25000).maxBolusMilliunits)
    }

    func testBuildsLittleEndianCargo() throws {
        let request = try SetMaxBolusLimitRequest(maxBolusMilliunits: 9500)

        XCTAssertEqual("1c25", request.cargo.hexadecimalString)
        XCTAssertEqual(9500, SetMaxBolusLimitRequest(cargo: request.cargo).maxBolusMilliunits)
    }

    func testOutOfRangeLimitsAreRejected() {
        XCTAssertThrowsError(try SetMaxBolusLimitRequest(maxBolusMilliunits: 999))
        XCTAssertThrowsError(try SetMaxBolusLimitRequest(maxBolusMilliunits: 25001))
        XCTAssertThrowsError(try SetMaxBolusLimitRequest(maxBolusMilliunits: -1))
    }
}
