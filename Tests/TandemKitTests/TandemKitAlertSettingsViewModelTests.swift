import Foundation
@testable import TandemKit
import XCTest

/// The snooze controls write to the pump as soon as they change, and the pump can refuse the write:
/// the screen must then show the setting the pump last accepted and say that the change failed.
@available(macOS 13.0, iOS 14.0, *) final class TandemKitAlertSettingsViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitAlertSettingsViewModel

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func seedAlertSnooze(enabled: Bool, durationMins: Int) {
        manager.state.alertSnoozeEnabled = enabled
        manager.state.alertSnoozeDuration = .minutes(durationMins)
    }

    private func stubAlertSnoozeStatus(_ status: Int) {
        bluetooth.stub(SetPumpAlertSnoozeRequest.self, with: SetPumpAlertSnoozeResponse(status: status))
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5.0)
    }

    // MARK: - Seeded state

    func testTheScreenOpensOnTheSettingsThePumpLastAccepted() {
        seedAlertSnooze(enabled: true, durationMins: 20)
        manager.state.forwardCGMAlerts = true

        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertTrue(viewModel.alertSnoozeEnabled)
        XCTAssertEqual(viewModel.alertSnoozeDurationMins, 20)
        XCTAssertTrue(viewModel.forwardCGMAlerts)
        XCTAssertNil(viewModel.saveError)
    }

    // MARK: - Alert snooze

    func testAnAcceptedChangeIsSentAndShown() throws {
        seedAlertSnooze(enabled: false, durationMins: 10)
        stubAlertSnoozeStatus(0)
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.setAlertSnooze(enabled: true, durationMins: 30)
        drainMainQueue()

        let request = try XCTUnwrap(bluetooth.sent(SetPumpAlertSnoozeRequest.self).first)
        XCTAssertTrue(request.snoozeEnabled)
        XCTAssertEqual(request.snoozeDurationMins, 30)
        XCTAssertTrue(viewModel.alertSnoozeEnabled)
        XCTAssertEqual(viewModel.alertSnoozeDurationMins, 30)
        XCTAssertNil(viewModel.saveError)
    }

    func testARefusedDurationChangeKeepsThePumpsDurationAndSaysSo() {
        seedAlertSnooze(enabled: true, durationMins: 10)
        stubAlertSnoozeStatus(1)
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.setAlertSnooze(enabled: true, durationMins: 30)
        drainMainQueue()

        XCTAssertTrue(bluetooth.didSend(SetPumpAlertSnoozeRequest.self))
        XCTAssertTrue(viewModel.alertSnoozeEnabled)
        XCTAssertEqual(viewModel.alertSnoozeDurationMins, 10)
        XCTAssertNotNil(viewModel.saveError)
        XCTAssertEqual(manager.state.alertSnoozeDuration, .minutes(10))
    }

    func testARefusedToggleSwitchesBack() {
        seedAlertSnooze(enabled: false, durationMins: 10)
        stubAlertSnoozeStatus(1)
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.setAlertSnooze(enabled: true, durationMins: 10)
        drainMainQueue()

        XCTAssertFalse(viewModel.alertSnoozeEnabled)
        XCTAssertNotNil(viewModel.saveError)
        XCTAssertFalse(manager.state.alertSnoozeEnabled)
    }

    func testAnUnansweredChangeIsReportedAsAFailure() {
        seedAlertSnooze(enabled: false, durationMins: 10)
        bluetooth.stub(SetPumpAlertSnoozeRequest.self) { _ in nil }
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.setAlertSnooze(enabled: true, durationMins: 20)
        drainMainQueue()

        XCTAssertFalse(viewModel.alertSnoozeEnabled)
        XCTAssertEqual(viewModel.alertSnoozeDurationMins, 10)
        XCTAssertNotNil(viewModel.saveError)
    }

    func testAChangeWithNoConnectionSendsNothingAndSaysSo() {
        seedAlertSnooze(enabled: false, durationMins: 10)
        bluetooth.connectError = PumpCommError.pumpNotConnected
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.setAlertSnooze(enabled: true, durationMins: 10)
        drainMainQueue()

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        XCTAssertFalse(viewModel.alertSnoozeEnabled)
        XCTAssertNotNil(viewModel.saveError)
    }

    func testAnAcceptedChangeClearsTheLastFailure() {
        seedAlertSnooze(enabled: false, durationMins: 10)
        bluetooth.enqueue(
            SetPumpAlertSnoozeRequest.self,
            responses: [SetPumpAlertSnoozeResponse(status: 1), SetPumpAlertSnoozeResponse(status: 0)]
        )
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.setAlertSnooze(enabled: true, durationMins: 10)
        drainMainQueue()
        XCTAssertNotNil(viewModel.saveError)

        viewModel.setAlertSnooze(enabled: true, durationMins: 10)
        drainMainQueue()

        XCTAssertNil(viewModel.saveError)
        XCTAssertTrue(viewModel.alertSnoozeEnabled)
    }

    // MARK: - CGM alert forwarding

    func testTurningOffCGMAlertForwardingIsStoredWithoutTalkingToThePump() {
        manager.state.forwardCGMAlerts = true
        let viewModel = ViewModel(pumpManager: manager)

        viewModel.setForwardCGMAlerts(false)

        XCTAssertFalse(viewModel.forwardCGMAlerts)
        XCTAssertFalse(manager.state.forwardCGMAlerts)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }
}
