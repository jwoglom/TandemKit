@testable import TandemKit
import XCTest

final class CGMStatusV2ResponseTests: XCTestCase {
    private func makeResponse(sessionStateId: Int) -> CGMStatusV2Response {
        CGMStatusV2Response(
            sessionStateId: sessionStateId,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: 0,
            transmitterBatteryStatusId: 0,
            sessionDurationSeconds: 0,
            sessionTimeRemainingSeconds: 0,
            cgmSensorTypeId: 0,
            gracePeriod: false
        )
    }

    // A running sensor session means a CGM is connected -> Control-IQ can close the loop.
    func testSensorSessionConfiguredWhenActive() {
        let response = makeResponse(sessionStateId: CGMStatusV2Response.SessionState.active.rawValue)
        XCTAssertEqual(.active, response.sessionState)
        XCTAssertTrue(response.isSensorSessionConfigured)
    }

    // A warming-up sensor still counts as a configured CGM.
    func testSensorSessionConfiguredWhenStartPending() {
        let response = makeResponse(sessionStateId: CGMStatusV2Response.SessionState.startPending.rawValue)
        XCTAssertEqual(.startPending, response.sessionState)
        XCTAssertTrue(response.isSensorSessionConfigured)
    }

    // No active session -> no CGM feeding the pump -> Control-IQ would run open-loop.
    func testSensorSessionNotConfiguredWhenStopped() {
        let response = makeResponse(sessionStateId: CGMStatusV2Response.SessionState.stopped.rawValue)
        XCTAssertEqual(.stopped, response.sessionState)
        XCTAssertFalse(response.isSensorSessionConfigured)
    }

    // A session being torn down is treated as not configured going forward.
    func testSensorSessionNotConfiguredWhenStopPending() {
        let response = makeResponse(sessionStateId: CGMStatusV2Response.SessionState.stopPending.rawValue)
        XCTAssertEqual(.stopPending, response.sessionState)
        XCTAssertFalse(response.isSensorSessionConfigured)
    }

    func testSensorSessionNotConfiguredWhenUnknown() {
        let response = makeResponse(sessionStateId: CGMStatusV2Response.SessionState.unknown.rawValue)
        XCTAssertEqual(.unknown, response.sessionState)
        XCTAssertFalse(response.isSensorSessionConfigured)
    }

    // Any unrecognized session id decodes to `.unknown` and is not treated as configured.
    func testSensorSessionNotConfiguredForUnrecognizedSessionId() {
        let response = makeResponse(sessionStateId: 99)
        XCTAssertEqual(.unknown, response.sessionState)
        XCTAssertFalse(response.isSensorSessionConfigured)
    }
}
