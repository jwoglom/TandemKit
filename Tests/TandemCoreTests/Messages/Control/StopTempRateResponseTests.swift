@testable import TandemKit
import XCTest

final class StopTempRateResponseTests: XCTestCase {
    func testStopTempRateResponse() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_906_112)
        let expected = StopTempRateResponse(cargo: Data([0x00, 0x09, 0x00]))

        let parsed: StopTempRateResponse = MessageTester.test(
            "002ca72c1b000900d9448b1ea1dcb10f6cd0a00465d9091bad121938e17e51d4c3c9",
            44,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testStopTempRateResponse_2() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_906_112)
        let expected = StopTempRateResponse(cargo: Data([0x00, 0x0F, 0x00]))

        let parsed: StopTempRateResponse = MessageTester.test(
            "0051a7511b000f00caa3ee1f206002d65b54e77f42869917c881cae3dde6ad621928",
            81,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testStopTempRateResponse_3() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = StopTempRateResponse(status: 0, tempRateId: 97)

        let parsed: StopTempRateResponse = MessageTester.test(
            "007ca77c1b00610028034f20de866872a5759f0a90733baae767381b6184106f17ed",
            124,
            1,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(97, parsed.tempRateId)
    }
}
