@testable import TandemKit
import XCTest

final class SetPumpAlertSnoozeRequestTests: XCTestCase {
    func testSetPumpAlertSnoozeRequest_enable_10min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetPumpAlertSnoozeRequest(snoozeEnabled: true, snoozeDurationMins: 10)

        let parsed: SetPumpAlertSnoozeRequest = MessageTester.test(
            "0116d4161a010a0db76820eabe11bbaf518d5a06",
            22,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0016ef31958dafac47f38327cad7f7"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(true, parsed.snoozeEnabled)
        XCTAssertEqual(10, parsed.snoozeDurationMins)
    }

    func testSetPumpAlertSnoozeRequest_enable_20min() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetPumpAlertSnoozeRequest(snoozeEnabled: true, snoozeDurationMins: 20)

        let parsed: SetPumpAlertSnoozeRequest = MessageTester.test(
            "0118d4181a01142fb768207351c4815476eb350a",
            24,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00184b210fb8263ff36ec4e138732f"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(true, parsed.snoozeEnabled)
        XCTAssertEqual(20, parsed.snoozeDurationMins)
    }

    func testSetPumpAlertSnoozeRequest_off() {
        MessageTester.initPumpState("IGNORE_HMAC_SIGNATURE_EXCEPTION", 0)
        let expected = SetPumpAlertSnoozeRequest(snoozeEnabled: false, snoozeDurationMins: 0)

        let parsed: SetPumpAlertSnoozeRequest = MessageTester.test(
            "0131d4311a0000fbb8682038d7a22100f7646faa",
            49,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00316f9d827605f665814a30dbe72b"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(false, parsed.snoozeEnabled)
        XCTAssertEqual(0, parsed.snoozeDurationMins)
    }
}
