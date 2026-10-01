import Foundation
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitG7SetupViewModelTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var viewModel: TandemKitG7SetupViewModel!
    private var setupCompletions = 0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        setupCompletions = 0
        viewModel = TandemKitG7SetupViewModel(pumpManager: manager) { [weak self] in
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

    func testAPairingCodeIsDigitsOnly() {
        viewModel.pairingCode = "4321"
        XCTAssertTrue(viewModel.isPairingCodeValid)

        for invalid in ["", "43a1", "43 1", "-432"] {
            viewModel.pairingCode = invalid
            XCTAssertFalse(viewModel.isPairingCodeValid, "\"\(invalid)\" was accepted")
        }
    }

    // MARK: - Starting a sensor

    func testStartingASensorSetsTheTypeThenSendsThePairingCode() {
        stubSensorType(status: 0)
        stubPairingCode(status: 0)
        viewModel.pairingCode = "4321"

        viewModel.startG7Sensor()
        XCTAssertTrue(viewModel.isLoading)
        drainMainQueue()

        XCTAssertEqual(sentRequestNames, ["SetSensorTypeRequest", "SetDexcomG7PairingCodeRequest"])
        XCTAssertEqual(
            bluetooth.sent(SetSensorTypeRequest.self).first?.sensorTypeId,
            CGMStatusV2Response.CGMSensorType.dexcomG7.rawValue
        )
        XCTAssertEqual(bluetooth.sent(SetDexcomG7PairingCodeRequest.self).first?.pairingCode, 4321)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.didComplete)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(setupCompletions, 1)
    }

    func testARefusedSensorTypeStopsBeforeThePairingCodeIsSent() {
        stubSensorType(status: 1)
        stubPairingCode(status: 0)
        viewModel.pairingCode = "4321"

        viewModel.startG7Sensor()
        drainMainQueue()

        XCTAssertEqual(sentRequestNames, ["SetSensorTypeRequest"])
        assertFailed()
    }

    func testARefusedPairingCodeIsReportedAsAFailure() {
        stubSensorType(status: 0)
        stubPairingCode(status: 1)
        viewModel.pairingCode = "4321"

        viewModel.startG7Sensor()
        drainMainQueue()

        XCTAssertTrue(bluetooth.didSend(SetDexcomG7PairingCodeRequest.self))
        assertFailed()
    }

    func testAnUnansweredPairingCodeIsReportedAsAFailure() {
        stubSensorType(status: 0)
        bluetooth.stub(SetDexcomG7PairingCodeRequest.self) { _ in nil }
        viewModel.pairingCode = "4321"

        viewModel.startG7Sensor()
        drainMainQueue()

        assertFailed()
    }

    func testAPumpThatCannotBeReachedIsReportedWithoutSendingAnything() {
        bluetooth.connectError = PumpCommError.pumpNotConnected
        viewModel.pairingCode = "4321"

        viewModel.startG7Sensor()
        drainMainQueue()

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        assertFailed()
    }

    func testAnInvalidPairingCodeSendsNothing() {
        viewModel.pairingCode = "43a1"

        viewModel.startG7Sensor()
        drainMainQueue()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Helpers

    private func stubSensorType(status: Int) {
        bluetooth.stub(SetSensorTypeRequest.self, with: SetSensorTypeResponse(status: status, statusAcknowledgement: 0))
    }

    private func stubPairingCode(status: Int) {
        bluetooth.stub(SetDexcomG7PairingCodeRequest.self, with: SetDexcomG7PairingCodeResponse(status: status))
    }

    private var sentRequestNames: [String] {
        bluetooth.sentMessages.map { String(describing: type(of: $0)) }
    }

    private func assertFailed(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(viewModel.isLoading, file: file, line: line)
        XCTAssertFalse(viewModel.didComplete, file: file, line: line)
        XCTAssertEqual(viewModel.error, "Failed to set G7 pairing code", file: file, line: line)
        XCTAssertEqual(setupCompletions, 0, file: file, line: line)
    }

    /// The stub answers inline, so only the view model's hop to main is left to run.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5.0)
    }
}
