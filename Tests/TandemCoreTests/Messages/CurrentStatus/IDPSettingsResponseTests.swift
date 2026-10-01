@testable import TandemKit
import XCTest

final class IDPSettingsResponseTests: XCTestCase {
    func testIDPSettingsResponse() {
        let expected = IDPSettingsResponse(
            idpId: 0,
            name: "A",
            numberOfProfileSegments: 4,
            insulinDuration: 300,
            maxBolus: 25000,
            carbEntry: true
        )

        let parsed: IDPSettingsResponse = MessageTester.test(
            "00044104170041000000000000000000000000000000042c01a86101c2a5",
            4,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.idpId)
        XCTAssertEqual("A", parsed.name)
        XCTAssertEqual(4, parsed.numberOfProfileSegments)
        XCTAssertEqual(300, parsed.insulinDuration)
        XCTAssertEqual(25000, parsed.maxBolus)
        XCTAssertTrue(parsed.carbEntry)
    }

    func testIDPSettingsResponse2() {
        let expected = IDPSettingsResponse(
            idpId: 1,
            name: "Na",
            numberOfProfileSegments: 1,
            insulinDuration: 480,
            maxBolus: 25000,
            carbEntry: true
        )

        let parsed: IDPSettingsResponse = MessageTester.test(
            "0005410517014e61000000000000000000000000000001e001a861015ef2",
            5,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.idpId)
        XCTAssertEqual("Na", parsed.name)
        XCTAssertEqual(1, parsed.numberOfProfileSegments)
        XCTAssertEqual(480, parsed.insulinDuration)
        XCTAssertEqual(25000, parsed.maxBolus)
        XCTAssertTrue(parsed.carbEntry)
    }
}
