@testable import TandemKit
import XCTest

final class SetModesRequestTests: XCTestCase {
    func testSetModesRequest_exerciseModeOffToOn() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesRequest(cargo: Data([0x03]))

        let parsed: SetModesRequest = MessageTester.test(
            "0179cc7919034d978b1e32c70c65d5b530fdf45a",
            121,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0079b59d63358bab1b849bb1a4e4"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3, parsed.bitmap)
        XCTAssertEqual(.exerciseModeOn, parsed.command)
    }

    func testSetModesRequest_exerciseModeOnToOff() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesRequest(cargo: Data([0x04]))

        let parsed: SetModesRequest = MessageTester.test(
            "0181cc81190461978b1eff1bb7778cd232419aa1",
            -127,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0081d97936364e86562320d973e2"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(4, parsed.bitmap)
        XCTAssertEqual(.exerciseModeOff, parsed.command)
    }

    func testSetModesRequest_sleepModeOffToOn() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesRequest(cargo: Data([0x01]))

        let parsed: SetModesRequest = MessageTester.test(
            "018acc8a19017d978b1ef95a55180db9a2f1c821",
            -118,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            "008ace22b462fab923c16c2cc428"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.bitmap)
        XCTAssertEqual(.sleepModeOn, parsed.command)
    }

    func testSetModesRequest_sleepModeOnToOff() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 1_905_716)
        let expected = SetModesRequest(cargo: Data([0x02]))

        let parsed: SetModesRequest = MessageTester.test(
            "0191cc9119029a978b1e7ce08a7a68802cca71dc",
            -111,
            2,
            .CONTROL_CHARACTERISTICS,
            expected,
            "009134fd2877d2a8bd3247ef819d"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(2, parsed.bitmap)
        XCTAssertEqual(.sleepModeOff, parsed.command)
    }
}
