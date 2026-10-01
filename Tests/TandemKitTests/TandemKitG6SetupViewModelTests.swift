import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitG6SetupViewModelTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var viewModel: TandemKitG6SetupViewModel!
    private var setupCompletions = 0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        setupCompletions = 0
        viewModel = TandemKitG6SetupViewModel(pumpManager: manager) { [weak self] in
            self?.setupCompletions += 1
        }
    }

    override func tearDown() {
        viewModel = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Validation

    func testATransmitterIdIsSixLettersOrDigits() {
        viewModel.transmitterId = "8G12AB"
        XCTAssertTrue(viewModel.isTransmitterIdValid)

        for invalid in ["", "8G12A", "8G12ABC", "8G-12A", "8G 12A", "8É12AB", "8G12A١"] {
            viewModel.transmitterId = invalid
            XCTAssertFalse(viewModel.isTransmitterIdValid, "\"\(invalid)\" was accepted")
        }
    }

    func testASensorCodeIsFourDigits() {
        viewModel.sensorCode = "5678"
        XCTAssertTrue(viewModel.isSensorCodeValid)

        for invalid in ["", "567", "56789", "56a8", "56 8", "١٢٣٤", "１２３４", "12½4"] {
            viewModel.sensorCode = invalid
            XCTAssertFalse(viewModel.isSensorCodeValid, "\"\(invalid)\" was accepted")
        }
    }

    func testStartingASensorNeedsBothTheTransmitterIdAndTheSensorCode() {
        viewModel.transmitterId = "8G12AB"
        XCTAssertFalse(viewModel.canStartSensor)

        viewModel.sensorCode = "5678"
        XCTAssertTrue(viewModel.canStartSensor)
    }

    func testJoiningARunningSessionNeedsOnlyTheTransmitterId() {
        viewModel.transmitterId = "8G12AB"

        XCTAssertTrue(viewModel.canConnectExisting)
    }

    // MARK: - Starting a new sensor

    func testStartingASensorSetsTheTypeAndTransmitterThenStartsTheSessionWithTheCode() {
        stubSensorType(status: 0)
        stubTransmitterId(status: 0)
        stubStartSession(status: 0)
        enterSensorDetails()

        viewModel.startNewSensor()
        XCTAssertTrue(viewModel.isLoading)
        drainMainQueue()

        XCTAssertEqual(
            sentRequestNames,
            ["SetSensorTypeRequest", "SetG6TransmitterIdRequest", "StartDexcomG6SensorSessionRequest"]
        )
        XCTAssertEqual(
            bluetooth.sent(SetSensorTypeRequest.self).first?.sensorTypeId,
            CGMStatusV2Response.CGMSensorType.dexcomG6.rawValue
        )
        XCTAssertEqual(bluetooth.sent(SetG6TransmitterIdRequest.self).first?.txId, "8G12AB")
        XCTAssertEqual(bluetooth.sent(StartDexcomG6SensorSessionRequest.self).first?.sensorCode, 5678)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.didComplete)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(setupCompletions, 1)
    }

    func testTheTransmitterIdIsSentInCapitals() {
        stubSensorType(status: 0)
        stubTransmitterId(status: 0)
        stubStartSession(status: 0)
        viewModel.transmitterId = "8g12ab"
        viewModel.sensorCode = "5678"

        viewModel.startNewSensor()
        drainMainQueue()

        XCTAssertEqual(bluetooth.sent(SetG6TransmitterIdRequest.self).first?.txId, "8G12AB")
    }

    func testARefusedSensorTypeStopsBeforeTheTransmitterIsSet() {
        stubSensorType(status: 1)
        stubTransmitterId(status: 0)
        stubStartSession(status: 0)
        enterSensorDetails()

        viewModel.startNewSensor()
        drainMainQueue()

        XCTAssertEqual(sentRequestNames, ["SetSensorTypeRequest"])
        assertFailed(with: "Failed to start CGM sensor")
    }

    func testARefusedTransmitterIdStopsBeforeTheSessionIsStarted() {
        stubSensorType(status: 0)
        stubTransmitterId(status: 1)
        stubStartSession(status: 0)
        enterSensorDetails()

        viewModel.startNewSensor()
        drainMainQueue()

        XCTAssertEqual(sentRequestNames, ["SetSensorTypeRequest", "SetG6TransmitterIdRequest"])
        assertFailed(with: "Failed to start CGM sensor")
    }

    func testARefusedSessionStartIsReportedAsAFailure() {
        stubSensorType(status: 0)
        stubTransmitterId(status: 0)
        stubStartSession(status: 1)
        enterSensorDetails()

        viewModel.startNewSensor()
        drainMainQueue()

        XCTAssertTrue(bluetooth.didSend(StartDexcomG6SensorSessionRequest.self))
        assertFailed(with: "Failed to start CGM sensor")
    }

    func testAnUnansweredSessionStartIsReportedAsAFailure() {
        stubSensorType(status: 0)
        stubTransmitterId(status: 0)
        bluetooth.stub(StartDexcomG6SensorSessionRequest.self) { _ in nil }
        enterSensorDetails()

        viewModel.startNewSensor()
        drainMainQueue()

        assertFailed(with: "Failed to start CGM sensor")
    }

    func testAPumpThatCannotBeReachedIsReportedWithoutSendingAnything() {
        bluetooth.connectError = PumpCommError.pumpNotConnected
        enterSensorDetails()

        viewModel.startNewSensor()
        drainMainQueue()

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        assertFailed(with: "Failed to start CGM sensor")
    }

    func testAnIncompleteSensorCodeSendsNothing() {
        viewModel.transmitterId = "8G12AB"
        viewModel.sensorCode = "567"

        viewModel.startNewSensor()
        drainMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    func testANonASCIISensorCodeSendsNothingRatherThanCodeZero() {
        viewModel.transmitterId = "8G12AB"
        viewModel.sensorCode = "１２３４"

        viewModel.startNewSensor()
        drainMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Joining a running session

    func testJoiningARunningSessionSetsTheTransmitterWithoutStartingANewSession() {
        stubSensorType(status: 0)
        stubTransmitterId(status: 0)
        stubStartSession(status: 0)
        viewModel.transmitterId = "8G12AB"

        viewModel.connectToExistingSession()
        drainMainQueue()

        XCTAssertEqual(sentRequestNames, ["SetSensorTypeRequest", "SetG6TransmitterIdRequest"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.didComplete)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(setupCompletions, 1)
    }

    func testARefusedTransmitterIdWhenJoiningSaysTheTransmitterWasNotSet() {
        stubSensorType(status: 0)
        stubTransmitterId(status: 1)
        viewModel.transmitterId = "8G12AB"

        viewModel.connectToExistingSession()
        drainMainQueue()

        assertFailed(with: "Failed to set transmitter.")
    }

    func testAnInvalidTransmitterIdSendsNothingWhenJoining() {
        viewModel.transmitterId = "8G12A"

        viewModel.connectToExistingSession()
        drainMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Helpers

    private func enterSensorDetails() {
        viewModel.transmitterId = "8G12AB"
        viewModel.sensorCode = "5678"
    }

    private func stubSensorType(status: Int) {
        bluetooth.stub(SetSensorTypeRequest.self, with: SetSensorTypeResponse(status: status, statusAcknowledgement: 0))
    }

    private func stubTransmitterId(status: Int) {
        bluetooth.stub(SetG6TransmitterIdRequest.self, with: SetG6TransmitterIdResponse(status: status))
    }

    private func stubStartSession(status: Int) {
        bluetooth.stub(StartDexcomG6SensorSessionRequest.self, with: StartDexcomG6SensorSessionResponse(status: status))
    }

    private var sentRequestNames: [String] {
        bluetooth.sentMessages.map { String(describing: type(of: $0)) }
    }

    private func assertFailed(with message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(viewModel.isLoading, file: file, line: line)
        XCTAssertFalse(viewModel.didComplete, file: file, line: line)
        XCTAssertEqual(viewModel.error, message, file: file, line: line)
        XCTAssertEqual(setupCompletions, 0, file: file, line: line)
    }

    /// The stub answers inline, so only the view model's hop to main is left to run.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5.0)
    }
}
