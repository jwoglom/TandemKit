import XCTest
@testable import TandemCore

final class CancelBolusRequestTests: XCTestCase {
    func testCancelBolusRequest_ID10677() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461710145)
        let expected = CancelBolusRequest(bolusId: 10677)

        let parsed: CancelBolusRequest = MessageTester.test(
            "01bca0bc1cb52900004123851bde7e214f942297",
            -68,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00bcea477474bb87dbb3293c92642f43e8"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testCancelBolusRequest_ID10678() {
        MessageTester.initPumpState("6VeDeRAL5DCigGw2", 461710145)
        let expected = CancelBolusRequest(bolusId: 10678)

        let parsed: CancelBolusRequest = MessageTester.test(
            "01e8a0e81cb62900007a23851b1b100405c517c0",
            -24,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "00e887856f69ef78c79bf186fa39a0c5d1"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
