import XCTest
@testable import TandemCore

final class CreateIDPRequestTests: XCTestCase {
    func testCreateIDPRequest_new1() {
        MessageTester.initPumpState("", 1)
        let expected = CreateIDPRequest(
            profileName: "testprofile",
            firstSegmentProfileCarbRatio: 3000,
            firstSegmentProfileBasalRate: 1000,
            firstSegmentProfileTargetBG: 100,
            firstSegmentProfileISF: 2,
            profileInsulinDuration: 300,
            profileCarbEntry: 1
        )

        let parsed: CreateIDPRequest = MessageTester.test(
            "03c9e6c93b7465737470726f66696c6500000000",
            -55,
            4,
            .CONTROL_CHARACTERISTICS,
            expected,
            "02c90000b80b00000000e803640002002c011f05",
            "01c9ff01b5483e20f4256e953cbe7320b25c5de0",
            "00c9f9e8fc891764dd51b865"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testCreateIDPRequest_duplicate1() {
        MessageTester.initPumpState("", 0)
        let expected = CreateIDPRequest(profileName: "dup", sourceIdpId: 1)

        let parsed: CreateIDPRequest = MessageTester.test(
            "0337e6373b647570000000000000000000000000",
            55,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0237000000000000000000000000000000000000",
            "01370100b0493e20b795d5f162b92bbd30cd8823",
            "00372bc754ba29764a5b4765"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testScenario42_ProfC_Duplicate() {
        MessageTester.initPumpState("", 1)
        let expected = CreateIDPRequest(profileName: "ProfCDup", sourceIdpId: 2)

        let parsed: CreateIDPRequest = MessageTester.test(
            "0368e6683b50726f664344757000000000000000",
            104,
            1,
            .CONTROL_CHARACTERISTICS,
            expected,
            "0268000000000000000000000000000000000000",
            "01680200d648472076197caf3096ac0d1c300758",
            "00684ef8851d5c1d36b8bd09"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
