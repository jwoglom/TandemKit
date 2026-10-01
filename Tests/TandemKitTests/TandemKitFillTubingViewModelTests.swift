import Foundation
@testable import TandemKit
import XCTest

/// The pump stops a tubing fill on its own once it has delivered as much as it will for one press,
/// and raises an alert asking the user to confirm before it delivers any more. That happens exactly
/// when the fill button comes back up, so the screen re-reads the pump's notification state right
/// then instead of waiting out its next poll — otherwise it offers to complete a fill the pump has
/// actually paused (#248).
@available(macOS 13.0, iOS 14.0, *) final class TandemKitFillTubingViewModelTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var viewModel: TandemKitFillTubingViewModel!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        viewModel = TandemKitFillTubingViewModel(pumpManager: manager, done: {}, toFillingCannula: {})
    }

    override func tearDown() {
        viewModel = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Reacting to the button

    func testReleasingTheButtonReadsNotificationsImmediately() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)

        viewModel.handleButtonState(buttonDown: true)
        XCTAssertEqual(notificationReads, 0, "Holding the button down tells us nothing new to read")

        viewModel.handleButtonState(buttonDown: false)
        XCTAssertEqual(notificationReads, 1, "The release must read the pump, not wait for the next poll")
        XCTAssertTrue(viewModel.isCheckingNotifications)
        XCTAssertFalse(viewModel.canCompleteFill, "The read that decides this has not come back yet")

        drainMainQueue()

        XCTAssertFalse(viewModel.isCheckingNotifications)
        XCTAssertTrue(viewModel.hasActiveNotifications)
        XCTAssertFalse(viewModel.canCompleteFill, "The pump is waiting to be confirmed")
        XCTAssertEqual(
            viewModel.notificationsViewModel.notifications.map(\.name),
            ["FILL_TUBING_STILL_IN_PROGRESS"]
        )
    }

    func testAReleaseWithNothingOutstandingLeavesTheFillCompletable() {
        stubAlerts()

        viewModel.handleButtonState(buttonDown: true)
        viewModel.handleButtonState(buttonDown: false)
        drainMainQueue()

        XCTAssertEqual(notificationReads, 1)
        XCTAssertFalse(viewModel.hasActiveNotifications)
        XCTAssertTrue(viewModel.canCompleteFill)
    }

    /// The pump repeats its button state on the control stream; only the change matters, otherwise
    /// a chatty stream turns into a stream of pump reads.
    func testRepeatsOfAKnownButtonStateAreNotRead() {
        stubAlerts()

        viewModel.handleButtonState(buttonDown: true)
        viewModel.handleButtonState(buttonDown: true)
        viewModel.handleButtonState(buttonDown: false)
        drainMainQueue()
        viewModel.handleButtonState(buttonDown: false)
        drainMainQueue()

        XCTAssertEqual(notificationReads, 1)
    }

    /// A fill usually takes several presses, and the pump can stop after any of them.
    func testEveryReleaseGetsItsOwnRead() {
        stubAlerts()

        for _ in 0 ..< 3 {
            viewModel.handleButtonState(buttonDown: true)
            viewModel.handleButtonState(buttonDown: false)
            drainMainQueue()
        }

        XCTAssertEqual(notificationReads, 3)
    }

    // MARK: - Which reports warrant a read

    func testAReleaseIsRead() {
        XCTAssertTrue(TandemKitFillTubingViewModel.shouldCheckNotifications(previouslyDown: true, nowDown: false))
    }

    /// A press we never saw reported can still have stopped the fill, so the pump's first report is
    /// read whenever it already has the button up.
    func testAFirstReportWithTheButtonUpIsRead() {
        XCTAssertTrue(TandemKitFillTubingViewModel.shouldCheckNotifications(previouslyDown: nil, nowDown: false))
    }

    func testTheButtonGoingDownIsNotRead() {
        XCTAssertFalse(TandemKitFillTubingViewModel.shouldCheckNotifications(previouslyDown: false, nowDown: true))
        XCTAssertFalse(TandemKitFillTubingViewModel.shouldCheckNotifications(previouslyDown: true, nowDown: true))
        XCTAssertFalse(TandemKitFillTubingViewModel.shouldCheckNotifications(previouslyDown: nil, nowDown: true))
    }

    func testStayingUpIsNotReadAgain() {
        XCTAssertFalse(TandemKitFillTubingViewModel.shouldCheckNotifications(previouslyDown: false, nowDown: false))
    }

    // MARK: - Helpers

    /// Answers the pump's alert read with exactly `alerts` active.
    private func stubAlerts(_ alerts: AlertStatusResponse.AlertResponseType...) {
        let bitmask = alerts.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1.rawValue)) }
        bluetooth.stub(AlertStatusRequest.self, with: AlertStatusResponse(intMap: bitmask))
    }

    /// How many notification reads the driver has performed. Every read sends exactly one
    /// `AlertStatusRequest`, so counting them counts the reads.
    private var notificationReads: Int {
        bluetooth.sent(AlertStatusRequest.self).count
    }

    /// Runs the main queue until everything queued so far has run. The stub answers writes inline,
    /// so a read's pump traffic is already done by the time a call returns; what is left on the
    /// queue is the view model publishing the result.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5.0)
    }
}
