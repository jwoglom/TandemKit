@testable import TandemKit
import XCTest

final class SetMaxBasalLimitRequestTests: XCTestCase {
    func testSetMaxBasalLimitRequest_5u() throws {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 5000)

        let parsed: SetMaxBasalLimitRequest = MessageTester.test(
            "017588751c881300003ee34920d580d42e829ec9",
            117,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00754d9fdc7a1f65f92b9b1f7c227bbb56"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(5000, parsed.maxHourlyBasalMilliunits)
    }

    func testBoundsAreAccepted() throws {
        XCTAssertEqual(1000, try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 1000).maxHourlyBasalMilliunits)
        XCTAssertEqual(15000, try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 15000).maxHourlyBasalMilliunits)
    }

    func testBuildsLittleEndianCargo() throws {
        let request = try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 4200)

        XCTAssertEqual("68100000", request.cargo.hexadecimalString)
        XCTAssertEqual(4200, SetMaxBasalLimitRequest(cargo: request.cargo).maxHourlyBasalMilliunits)
    }

    func testOutOfRangeLimitsAreRejected() {
        XCTAssertThrowsError(try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 999))
        XCTAssertThrowsError(try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 15001))
        XCTAssertThrowsError(try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: -1))
    }
}
