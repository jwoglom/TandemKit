import XCTest
@testable import TandemCore

final class AlertStatusResponseTests: XCTestCase {
    func testAlertStatusEmpty() {
        let expected = AlertStatusResponse(intMap: 0)

        let parsed: AlertStatusResponse = MessageTester.test(
            "000545050800000000000000005bf2",
            5,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(0, parsed.intMap)
        XCTAssertTrue(parsed.alerts.isEmpty)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlertStatusWithDevicePaired() {
        let bitmask = bitmask(for: [.DEVICE_PAIRED])
        let expected = AlertStatusResponse(intMap: bitmask)

        let parsed: AlertStatusResponse = MessageTester.test(
            "00034503080000000000004000288c",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(bitmask, parsed.intMap)
        XCTAssertEqual(expected.alerts, parsed.alerts)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlertStatusWithIncompleteCartridgeChange() {
        let bitmask = bitmask(for: [.INCOMPLETE_CARTRIDGE_CHANGE_ALERT])
        let expected = AlertStatusResponse(intMap: bitmask)

        let parsed: AlertStatusResponse = MessageTester.test(
            "00064506080020000000000000622d",
            6,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(bitmask, parsed.intMap)
        XCTAssertEqual(expected.alerts, parsed.alerts)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testAlertStatusWithCgmGraphRemoved() {
        let parsed = AlertStatusResponse(cargo: Data([0, 0, 0, 2, 0, 0, 0, 0]))

        XCTAssertEqual(Set([AlertStatusResponse.AlertResponseType.CGM_GRAPH_REMOVED]), parsed.alerts)
    }

    func testAlertStatusWithInvalidG7TxId() {
        let bitmask = bitmask(for: [.INVALID_TRANSMITTER_ID])
        let expected = AlertStatusResponse(intMap: bitmask)

        let parsed: AlertStatusResponse = MessageTester.test(
            "000c450c080000002000000000e1df",
            12,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(bitmask, parsed.intMap)
        XCTAssertEqual(expected.alerts, parsed.alerts)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    private func bitmask(for types: [AlertStatusResponse.AlertResponseType]) -> UInt64 {
        return types.reduce(0) { partialResult, type in
            partialResult | (UInt64(1) << UInt64(type.rawValue))
        }
    }
}
