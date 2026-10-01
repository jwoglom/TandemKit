@testable import TandemKit
import XCTest

final class SetModesResponseTests: XCTestCase {
    func testSetModesResponse_exerciseModeOffToOn() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesResponse(cargo: Data([0x00]))

        let parsed: SetModesResponse = MessageTester.test(
            "0079cd791900e8428b1ec8fa29dc63d8f79a1c678b339ba801061a620659e904",
            121,
            2,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }

    func testSetModesResponse_exerciseModeOnToOff() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesResponse(cargo: Data([0x00]))

        let parsed: SetModesResponse = MessageTester.test(
            "0081cd811900fb428b1ec6956c4b467290f8ba7ee8df78dd2ca119dbef422894",
            -127,
            2,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }

    func testSetModesResponse_sleepModeOffToOn() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesResponse(cargo: Data([0x00]))

        let parsed: SetModesResponse = MessageTester.test(
            "008acd8a190017438b1e16af1181440210dc1feed9fc36a3882124bc7bd2678e",
            -118,
            2,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }

    func testSetModesResponse_sleepModeOnToOff() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesResponse(cargo: Data([0x00]))

        let parsed: SetModesResponse = MessageTester.test(
            "0091cd91190034438b1e5858889224eafe67bf93fc50bb2575a514602ff34e62",
            -111,
            2,
            .CONTROL_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.status)
    }
}
