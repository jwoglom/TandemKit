import XCTest
@testable import TandemCore

final class CGMStatusResponseTests: XCTestCase {
    func testCGMStatusResponseAllZeros() {
        let expected = CGMStatusResponse(
            sessionStateId: 0,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: 0,
            transmitterBatteryStatusId: 0
        )

        let parsed: CGMStatusResponse = MessageTester.test(
            "000351030a00000000000000000000a926",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        XCTAssertEqual(expected.sessionStateId, parsed.sessionStateId)
        XCTAssertEqual(.sessionStopped, parsed.sessionState)
        XCTAssertEqual(expected.lastCalibrationTimestamp, parsed.lastCalibrationTimestamp)
        XCTAssertEqual(Dates.fromJan12008EpochSecondsToDate(0), parsed.lastCalibrationDate)
        XCTAssertEqual(expected.sensorStartedTimestamp, parsed.sensorStartedTimestamp)
        XCTAssertEqual(Dates.fromJan12008EpochSecondsToDate(0), parsed.sensorStartedDate)
        XCTAssertEqual(expected.transmitterBatteryStatusId, parsed.transmitterBatteryStatusId)
        XCTAssertEqual(.unavailable, parsed.transmitterBatteryStatus)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
