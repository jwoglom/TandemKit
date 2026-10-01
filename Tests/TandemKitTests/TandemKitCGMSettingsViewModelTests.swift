import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitCGMSettingsViewModelTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var viewModel: TandemKitCGMSettingsViewModel!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        viewModel = TandemKitCGMSettingsViewModel(pumpManager: manager)
    }

    override func tearDown() {
        viewModel = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Status display

    func testARunningG6SessionIsShownInFull() {
        stubStatus(makeStatus(
            sessionState: .active,
            sensorStartedTimestamp: pumpTimestamp(secondsAgo: 2 * 3600 + 30),
            battery: .okay,
            sessionDurationSeconds: 10 * 86400,
            sessionTimeRemainingSeconds: 9 * 86400 + 22 * 3600,
            sensorType: .dexcomG6
        ))

        viewModel.fetchCGMStatus()
        drainMainQueue()

        XCTAssertFalse(viewModel.isFetching)
        XCTAssertEqual(viewModel.cgmSessionState, .active)
        XCTAssertEqual(viewModel.sensorTypeText, "Dexcom G6")
        XCTAssertEqual(viewModel.sensorStartedText, "2h ago")
        XCTAssertEqual(viewModel.sessionDuration, "10d")
        XCTAssertEqual(viewModel.sessionTimeRemaining, "9d 22h")
        XCTAssertEqual(viewModel.transmitterBattery, "OK")
        XCTAssertFalse(viewModel.gracePeriod)
    }

    func testAG7SessionShowsNoTransmitterBattery() {
        stubStatus(makeStatus(battery: .okay, sensorType: .dexcomG7))

        viewModel.fetchCGMStatus()
        drainMainQueue()

        XCTAssertEqual(viewModel.sensorTypeText, "Dexcom G7")
        XCTAssertNil(viewModel.transmitterBattery)
    }

    func testEachG6TransmitterBatteryStatusIsNamed() {
        let expected: [(CGMStatusV2Response.TransmitterBatteryStatus, String?)] = [
            (.okay, "OK"),
            (.error, "Error"),
            (.expired, "Expired"),
            (.outOfRange, "Out of Range"),
            (.unavailable, "Unavailable"),
            (.unknown, nil)
        ]

        for (battery, text) in expected {
            stubStatus(makeStatus(battery: battery, sensorType: .dexcomG6))

            viewModel.fetchCGMStatus(force: true)
            drainMainQueue()

            XCTAssertEqual(viewModel.transmitterBattery, text, "\(battery)")
        }
    }

    func testASessionWithNoTimingLeavesThoseRowsEmpty() {
        stubStatus(makeStatus(
            sessionState: .stopped,
            sensorStartedTimestamp: 0,
            sessionDurationSeconds: 0,
            sessionTimeRemainingSeconds: 0,
            sensorType: .notApplicable
        ))

        viewModel.fetchCGMStatus()
        drainMainQueue()

        XCTAssertEqual(viewModel.cgmSessionState, .stopped)
        XCTAssertNil(viewModel.sensorTypeText)
        XCTAssertNil(viewModel.sensorStartedText)
        XCTAssertNil(viewModel.sessionDuration)
        XCTAssertNil(viewModel.sessionTimeRemaining)
    }

    func testAGracePeriodIsShown() {
        stubStatus(makeStatus(gracePeriod: true))

        viewModel.fetchCGMStatus()
        drainMainQueue()

        XCTAssertTrue(viewModel.gracePeriod)
    }

    func testEverySessionStateThePumpReportsIsRecognised() {
        XCTAssertEqual(CGMSessionState(from: 0), .stopped)
        XCTAssertEqual(CGMSessionState(from: 1), .startPending)
        XCTAssertEqual(CGMSessionState(from: 2), .active)
        XCTAssertEqual(CGMSessionState(from: 3), .stopPending)
        XCTAssertEqual(CGMSessionState(from: 4), .unknown)
        XCTAssertEqual(CGMSessionState(from: 99), .unknown)
    }

    func testOnlyStartingAndStoppingArePending() {
        XCTAssertTrue(CGMSessionState.startPending.isPending)
        XCTAssertTrue(CGMSessionState.stopPending.isPending)
        XCTAssertFalse(CGMSessionState.stopped.isPending)
        XCTAssertFalse(CGMSessionState.active.isPending)
        XCTAssertFalse(CGMSessionState.unknown.isPending)
    }

    func testAnUnansweredReadStopsTheSpinnerAndKeepsWhatIsShown() {
        stubStatus(makeStatus(sessionState: .active, sensorType: .dexcomG6))
        viewModel.fetchCGMStatus()
        drainMainQueue()

        bluetooth.stub(CGMStatusV2Request.self) { _ in nil }
        viewModel.fetchCGMStatus(force: true)
        drainMainQueue()

        XCTAssertFalse(viewModel.isFetching)
        XCTAssertEqual(viewModel.cgmSessionState, .active)
        XCTAssertEqual(viewModel.sensorTypeText, "Dexcom G6")
    }

    func testTheStatusIsReadOnceUnlessARefreshIsForced() {
        stubStatus(makeStatus())

        viewModel.fetchCGMStatus()
        drainMainQueue()
        viewModel.fetchCGMStatus()
        drainMainQueue()
        XCTAssertEqual(bluetooth.sent(CGMStatusV2Request.self).count, 1)

        viewModel.fetchCGMStatus(force: true)
        drainMainQueue()
        XCTAssertEqual(bluetooth.sent(CGMStatusV2Request.self).count, 2)
    }

    func testARefreshInPlaceDoesNotShowTheSpinner() {
        stubStatus(makeStatus())
        viewModel.fetchCGMStatus()
        drainMainQueue()

        viewModel.fetchCGMStatus(force: true, showsSpinner: false)
        XCTAssertFalse(viewModel.isFetching)
        drainMainQueue()

        viewModel.fetchCGMStatus(force: true)
        XCTAssertTrue(viewModel.isFetching)
        drainMainQueue()
    }

    // MARK: - Stopping the sensor

    func testStoppingTheSensorReloadsTheStatusFromThePump() {
        stubStatus(makeStatus(sessionState: .active))
        viewModel.fetchCGMStatus()
        drainMainQueue()
        bluetooth.stub(StopDexcomCGMSensorSessionRequest.self, with: StopDexcomCGMSensorSessionResponse(status: 0))
        stubStatus(makeStatus(sessionState: .stopped))
        bluetooth.resetRecordedTraffic()

        viewModel.stopCGMSensor()
        XCTAssertTrue(viewModel.isLoading)
        drainMainQueue(hops: 2)

        XCTAssertEqual(sentRequestNames, ["StopDexcomCGMSensorSessionRequest", "CGMStatusV2Request"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.commandError)
        XCTAssertEqual(viewModel.cgmSessionState, .stopped)
    }

    func testAStoppedSensorReadsAsStoppingUntilThePumpSaysOtherwise() {
        stubStatus(makeStatus(sessionState: .active))
        viewModel.fetchCGMStatus()
        drainMainQueue()
        bluetooth.stub(StopDexcomCGMSensorSessionRequest.self, with: StopDexcomCGMSensorSessionResponse(status: 0))
        bluetooth.stub(CGMStatusV2Request.self) { _ in nil }

        viewModel.stopCGMSensor()
        drainMainQueue(hops: 2)

        XCTAssertEqual(viewModel.cgmSessionState, .stopPending)
    }

    func testARefusedStopSaysSoAndLeavesTheSessionAsItWas() {
        stubStatus(makeStatus(sessionState: .active))
        viewModel.fetchCGMStatus()
        drainMainQueue()
        bluetooth.stub(StopDexcomCGMSensorSessionRequest.self, with: StopDexcomCGMSensorSessionResponse(status: 1))
        bluetooth.resetRecordedTraffic()

        viewModel.stopCGMSensor()
        drainMainQueue(hops: 2)

        XCTAssertEqual(viewModel.commandError, "Failed to stop CGM sensor. Check pump connection.")
        XCTAssertEqual(viewModel.cgmSessionState, .active)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(bluetooth.didSend(CGMStatusV2Request.self))
    }

    func testAnUnansweredStopIsReportedAsAFailure() {
        bluetooth.stub(StopDexcomCGMSensorSessionRequest.self) { _ in nil }

        viewModel.stopCGMSensor()
        drainMainQueue(hops: 2)

        XCTAssertEqual(viewModel.commandError, "Failed to stop CGM sensor. Check pump connection.")
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - After a setup wizard

    func testAFinishedG6SetupShowsTheSensorStartingAndReloadsTheStatus() {
        bluetooth.stub(SetSensorTypeRequest.self, with: SetSensorTypeResponse(status: 0, statusAcknowledgement: 0))
        bluetooth.stub(SetG6TransmitterIdRequest.self, with: SetG6TransmitterIdResponse(status: 0))
        bluetooth.stub(StartDexcomG6SensorSessionRequest.self, with: StartDexcomG6SensorSessionResponse(status: 0))
        // Unanswered, so what remains is the state shown before the reload.
        bluetooth.stub(CGMStatusV2Request.self) { _ in nil }
        let setup = viewModel.createG6SetupViewModel()
        setup.transmitterId = "8G12AB"
        setup.sensorCode = "5678"

        setup.startNewSensor()
        drainMainQueue(hops: 2)

        XCTAssertEqual(viewModel.cgmSessionState, .startPending)
        XCTAssertTrue(bluetooth.didSend(CGMStatusV2Request.self))
    }

    func testAFinishedG7SetupShowsTheSensorStartingAndReloadsTheStatus() {
        bluetooth.stub(SetSensorTypeRequest.self, with: SetSensorTypeResponse(status: 0, statusAcknowledgement: 0))
        bluetooth.stub(SetDexcomG7PairingCodeRequest.self, with: SetDexcomG7PairingCodeResponse(status: 0))
        // Unanswered, so what remains is the state shown before the reload.
        bluetooth.stub(CGMStatusV2Request.self) { _ in nil }
        let setup = viewModel.createG7SetupViewModel()
        setup.pairingCode = "4321"

        setup.startG7Sensor()
        drainMainQueue(hops: 2)

        XCTAssertEqual(viewModel.cgmSessionState, .startPending)
        XCTAssertTrue(bluetooth.didSend(CGMStatusV2Request.self))
    }

    func testAFailedSetupLeavesTheStatusAlone() {
        bluetooth.stub(SetSensorTypeRequest.self, with: SetSensorTypeResponse(status: 1, statusAcknowledgement: 0))
        let setup = viewModel.createG7SetupViewModel()
        setup.pairingCode = "4321"

        setup.startG7Sensor()
        drainMainQueue(hops: 2)

        XCTAssertEqual(viewModel.cgmSessionState, .unknown)
        XCTAssertFalse(bluetooth.didSend(CGMStatusV2Request.self))
    }

    // MARK: - Helpers

    private func makeStatus(
        sessionState: CGMStatusV2Response.SessionState = .active,
        sensorStartedTimestamp: UInt32 = 0,
        battery: CGMStatusV2Response.TransmitterBatteryStatus = .okay,
        sessionDurationSeconds: UInt32 = 0,
        sessionTimeRemainingSeconds: UInt32 = 0,
        sensorType: CGMStatusV2Response.CGMSensorType = .dexcomG6,
        gracePeriod: Bool = false
    ) -> CGMStatusV2Response {
        CGMStatusV2Response(
            sessionStateId: sessionState.rawValue,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: sensorStartedTimestamp,
            transmitterBatteryStatusId: battery.rawValue,
            sessionDurationSeconds: sessionDurationSeconds,
            sessionTimeRemainingSeconds: sessionTimeRemainingSeconds,
            cgmSensorTypeId: sensorType.rawValue,
            gracePeriod: gracePeriod
        )
    }

    private func stubStatus(_ response: CGMStatusV2Response) {
        bluetooth.stub(CGMStatusV2Request.self, with: response)
    }

    /// Pump-epoch seconds on the pump's local clock, the form `sensorStartedTimestamp` comes in.
    private func pumpTimestamp(secondsAgo: TimeInterval) -> UInt32 {
        UInt32(Dates.fromInstantToJan12008EpochSeconds(Date().addingTimeInterval(-secondsAgo)))
    }

    private var sentRequestNames: [String] {
        bluetooth.sentMessages.map { String(describing: type(of: $0)) }
    }

    /// One hop publishes a read; a stop or a finished setup takes a second for the reload it starts.
    private func drainMainQueue(hops: Int = 1) {
        for _ in 0 ..< hops {
            let drained = expectation(description: "main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 5.0)
        }
    }
}
