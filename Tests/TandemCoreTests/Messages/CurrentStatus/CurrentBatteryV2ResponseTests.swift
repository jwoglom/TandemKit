@testable import TandemKit
import XCTest

/// Packet captures taken from pumpX2's CurrentBatteryV2ResponseTest, which records real
/// pump connections on the V2.5 API.
final class CurrentBatteryV2ResponseTests: XCTestCase {
    /// V2.5 API: fully charged
    func testCurrentBatteryV2ResponseFull() {
        let expected = CurrentBatteryV2Response(
            currentBatteryAbc: 100,
            currentBatteryIbc: 100,
            chargingStatus: 0,
            unknown1: 0,
            unknown2: 0,
            unknown3: 0,
            unknown4: 0
        )

        let parsed: CurrentBatteryV2Response = MessageTester.test(
            "000d910d0b6464000000000000000000eb4f",
            13,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(100, parsed.currentBatteryAbc)
        XCTAssertEqual(100, parsed.currentBatteryIbc)
        XCTAssertEqual(100, parsed.getBatteryPercent())
        XCTAssertEqual(0, parsed.chargingStatus)
        XCTAssertFalse(parsed.isCharging)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    /// V2.5 API: pump displays battery at 10%
    func testCurrentBatteryV2Response() {
        let expected = CurrentBatteryV2Response(
            currentBatteryAbc: 27,
            currentBatteryIbc: 10,
            chargingStatus: 0,
            unknown1: 0,
            unknown2: 0,
            unknown3: 0,
            unknown4: 0
        )

        let parsed: CurrentBatteryV2Response = MessageTester.test(
            "000691060b1b0a00000000000000000056c9",
            6,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(27, parsed.currentBatteryAbc)
        XCTAssertEqual(10, parsed.currentBatteryIbc)
        XCTAssertEqual(10, parsed.getBatteryPercent())
        XCTAssertEqual(0, parsed.chargingStatus)
        XCTAssertFalse(parsed.isCharging)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    /// V2.5 API: pump displays battery at 10%, charging
    func testCurrentBatteryV2ResponseCharging() {
        let expected = CurrentBatteryV2Response(
            currentBatteryAbc: 27,
            currentBatteryIbc: 10,
            chargingStatus: 1,
            unknown1: 0,
            unknown2: 0,
            unknown3: 0,
            unknown4: 0
        )

        let parsed: CurrentBatteryV2Response = MessageTester.test(
            "000791070b1b0a0100000000000000001667",
            7,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(27, parsed.currentBatteryAbc)
        XCTAssertEqual(10, parsed.currentBatteryIbc)
        XCTAssertEqual(10, parsed.getBatteryPercent())
        XCTAssertEqual(1, parsed.chargingStatus)
        XCTAssertTrue(parsed.isCharging)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    /// V1 carries no charging field, so the shared protocol reports not charging for it.
    func testCurrentBatteryV1ResponseIsNeverCharging() {
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

        let response: CurrentBatteryAbstractResponse = parsed
        XCTAssertEqual(100, response.batteryPercent)
        XCTAssertFalse(response.isCharging)
    }
}
