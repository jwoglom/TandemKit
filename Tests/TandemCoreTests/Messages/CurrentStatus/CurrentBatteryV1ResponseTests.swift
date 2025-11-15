import XCTest
@testable import TandemCore

final class CurrentBatteryV1ResponseTests: XCTestCase {
    func testCurrentBatteryV1Response() {
        let expected = CurrentBatteryV1Response(
            currentBatteryAbc: 99,
            currentBatteryIbc: 100
        )

        let parsed: CurrentBatteryV1Response = MessageTester.test(
            "0003350302636452b9",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(99, parsed.currentBatteryAbc)
        XCTAssertEqual(100, parsed.currentBatteryIbc)
        XCTAssertEqual(100, parsed.getBatteryPercent())
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testCurrentBatteryV1ResponseFullCharge() {
        let expected = CurrentBatteryV1Response(
            currentBatteryAbc: 100,
            currentBatteryIbc: 100
        )

        let parsed: CurrentBatteryV1Response = MessageTester.test(
            "00043504026464e871",
            4,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(100, parsed.currentBatteryAbc)
        XCTAssertEqual(100, parsed.currentBatteryIbc)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
