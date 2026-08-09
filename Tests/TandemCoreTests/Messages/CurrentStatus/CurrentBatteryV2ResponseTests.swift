@testable import TandemCore
import XCTest

final class CurrentBatteryV2ResponseTests: XCTestCase {
    private func roundTrip(chargingStatus: Int) -> CurrentBatteryV2Response {
        let expected = CurrentBatteryV2Response(
            currentBatteryAbc: 10,
            currentBatteryIbc: 60,
            chargingStatus: chargingStatus,
            unknown1: 1,
            unknown2: 2,
            unknown3: 3,
            unknown4: 4
        )

        let parsed = CurrentBatteryV2Response(cargo: expected.cargo)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        return parsed
    }

    func testCurrentBatteryV2ResponseNotCharging() {
        let parsed = roundTrip(chargingStatus: 0)

        XCTAssertEqual(10, parsed.currentBatteryAbc)
        XCTAssertEqual(60, parsed.currentBatteryIbc)
        XCTAssertEqual(60, parsed.getBatteryPercent())
        XCTAssertEqual(60, parsed.batteryPercent)
        XCTAssertEqual(0, parsed.chargingStatus)
        XCTAssertFalse(parsed.isCharging)
    }

    func testCurrentBatteryV2ResponseCharging() {
        let parsed = roundTrip(chargingStatus: 1)

        XCTAssertEqual(1, parsed.chargingStatus)
        XCTAssertTrue(parsed.isCharging)
    }

    func testCurrentBatteryV2ResponseUnknownChargingStatusIsNotCharging() {
        XCTAssertFalse(roundTrip(chargingStatus: 2).isCharging)
    }

    /// V1 has no charging field, so the shared protocol reports not charging for it.
    func testCurrentBatteryV1ResponseIsNeverCharging() {
        let response: CurrentBatteryAbstractResponse = CurrentBatteryV1Response(
            currentBatteryAbc: 99,
            currentBatteryIbc: 100
        )

        XCTAssertFalse(response.isCharging)
        XCTAssertEqual(100, response.batteryPercent)
    }
}
