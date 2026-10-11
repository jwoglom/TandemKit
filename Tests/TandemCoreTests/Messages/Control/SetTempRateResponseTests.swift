@testable import TandemKit
import XCTest

final class SetTempRateResponseTests: XCTestCase {
    func testSetTempRateResponse_101pct_15min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateResponse(cargo: Data([0x00, 0x0F, 0x00, 0x00]))

        let parsed: SetTempRateResponse = MessageTester.test(
            "0048a5481c000f0000c3a3ee1fae161cb447c0235205f7a59796d2457a779c39c91b1a",
            72,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testSetTempRateResponse_2() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateResponse(cargo: Data([0x00, 0x0F, 0x00, 0x00]))

        let parsed: SetTempRateResponse = MessageTester.test(
            "0048a5481c000f0000c3a3ee1fae161cb447c0235205f7a59796d2457a779c39c91b1a",
            72,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testSetTempRateResponse_builder() {
        let expected = SetTempRateResponse(status: 0, tempRateId: 15)

        let parsed: SetTempRateResponse = MessageTester.test(
            "0048a5481c000f0000c3a3ee1fae161cb447c0235205f7a59796d2457a779c39c91b1a",
            72,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(15, parsed.tempRateId)
    }

    func testSetTempRateResponse_failed() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetTempRateResponse(cargo: Data([0x01, 0x00, 0x00, 0x01]))

        XCTAssertEqual(1, expected.status)
    }
}
