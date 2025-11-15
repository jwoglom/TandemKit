@testable import TandemCore
import XCTest

final class CGMAlertStatusResponseTests: XCTestCase {
    func testCGMAlertStatusResponseEmpty() {
        let expected = CGMAlertStatusResponse(intMap: 0)

        let parsed: CGMAlertStatusResponse = MessageTester.test(
            "00034b030800000000000000009ed2",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(0, parsed.intMap)
        XCTAssertTrue(parsed.alerts.isEmpty)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testCGMAlertStatusResponseDecodesMultipleAlerts() {
        let alerts: [CGMAlertStatusResponse.CGMAlert] = [
            .HIGH_CGM_ALERT,
            .LOW_CGM_ALERT,
            .RAPID_RISE_CGM_ALERT
        ]
        let mask = bitmask(for: alerts)

        let response = CGMAlertStatusResponse(cargo: Bytes.toUint64(mask))

        XCTAssertEqual(mask, response.intMap)
        XCTAssertEqual(Set(alerts), response.alerts)
    }

    private func bitmask(for alerts: [CGMAlertStatusResponse.CGMAlert]) -> UInt64 {
        alerts.reduce(0) { partialResult, alert in
            partialResult | (UInt64(1) << UInt64(alert.rawValue))
        }
    }
}
