import Combine
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

    // MARK: - The pump's pause

    func testThePausePromptsOnceTheReleaseReadSeesIt() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)
        viewModel.currentStep = .filling

        viewModel.handleButtonState(buttonDown: true)
        viewModel.handleButtonState(buttonDown: false)
        drainMainQueue()

        XCTAssertTrue(viewModel.isShowingFillPausedPrompt)
        XCTAssertFalse(viewModel.hasActiveNotifications, "The prompt answers for the pause; it is not also a card")
        XCTAssertFalse(viewModel.canCompleteFill, "The pump still waits to be acknowledged")
    }

    func testOtherNotificationsStayOnScreenAlongsideThePause() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS, .LOW_INSULIN_ALERT)
        viewModel.currentStep = .filling

        refreshNotifications()

        XCTAssertTrue(viewModel.isShowingFillPausedPrompt)
        XCTAssertEqual(viewModel.notificationsViewModel.notifications.map(\.name), ["LOW_INSULIN_ALERT"])
    }

    func testThePauseDoesNotPromptBeforeTheFillStarts() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)
        viewModel.currentStep = .disconnect

        refreshNotifications()

        XCTAssertFalse(viewModel.isShowingFillPausedPrompt, "Before the fill it is an ordinary notification to clear")
        XCTAssertTrue(viewModel.hasActiveNotifications)
    }

    func testThePromptGoesWhenThePumpNoLongerHasThePause() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)
        viewModel.currentStep = .filling
        refreshNotifications()

        stubAlerts()
        refreshNotifications()

        XCTAssertFalse(viewModel.isShowingFillPausedPrompt, "Acknowledged on the pump itself")
    }

    func testOKDismissesThePauseAndLetsTheFillComplete() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)
        bluetooth.stub(DismissNotificationRequest.self, with: DismissNotificationResponse(status: 0))
        viewModel.currentStep = .filling
        refreshNotifications()

        stubAlerts()
        viewModel.isShowingFillPausedPrompt = false
        viewModel.acknowledgeFillPause()
        drainAcknowledgement()

        let dismissals = bluetooth.sent(DismissNotificationRequest.self)
        XCTAssertEqual(dismissals.count, 1)
        XCTAssertEqual(dismissals.first?.notificationId, UInt32(AlertStatusResponse.AlertResponseType.FILL_TUBING_STILL_IN_PROGRESS.rawValue))
        XCTAssertEqual(dismissals.first?.notificationType, .alert)
        XCTAssertFalse(viewModel.isShowingFillPausedPrompt)
        XCTAssertTrue(viewModel.canCompleteFill)
    }

    func testARefusedDismissalBringsThePromptBack() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)
        bluetooth.stub(DismissNotificationRequest.self, with: DismissNotificationResponse(status: 1))
        viewModel.currentStep = .filling
        refreshNotifications()

        viewModel.isShowingFillPausedPrompt = false
        viewModel.acknowledgeFillPause()
        drainAcknowledgement()

        XCTAssertTrue(viewModel.isShowingFillPausedPrompt)
        XCTAssertFalse(viewModel.canCompleteFill)
    }

    func testAPollLandingMidDismissalDoesNotBringThePromptBack() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)
        bluetooth.stub(DismissNotificationRequest.self, with: DismissNotificationResponse(status: 0))
        viewModel.currentStep = .filling
        refreshNotifications()

        viewModel.isShowingFillPausedPrompt = false
        var shownSinceOK = false
        let observation = viewModel.$isShowingFillPausedPrompt.dropFirst().sink { shownSinceOK = shownSinceOK || $0 }
        defer { observation.cancel() }

        // The poll lands before the dismissal's answer, while the pump still reports the alert.
        viewModel.notificationsViewModel.refreshNotifications()
        viewModel.acknowledgeFillPause()
        stubAlerts()
        drainAcknowledgement()

        XCTAssertFalse(shownSinceOK)
    }

    func testLeavingTheFillingStepTakesThePromptDown() {
        stubAlerts(.FILL_TUBING_STILL_IN_PROGRESS)
        viewModel.currentStep = .filling
        refreshNotifications()

        viewModel.currentStep = .exiting

        XCTAssertFalse(viewModel.isShowingFillPausedPrompt)
    }

    // MARK: - Reporting the prime

    func testLeavingFillTubingModeAfterInsulinFlowedReportsAPrime() {
        let delegate = attachDelegate()
        stubAlerts()
        bluetooth.stub(ExitFillTubingModeRequest.self, with: ExitFillTubingModeResponse(status: 0))
        viewModel.handleButtonState(buttonDown: true)
        viewModel.handleButtonState(buttonDown: false)
        drainMainQueue()

        viewModel.exitFillTubingMode()
        drainMainQueue()
        manager.waitForDelegateCalls()

        XCTAssertEqual(delegate.pumpEventBatches.flatMap(\.events).map(\.type), [.prime])
        XCTAssertEqual(delegate.pumpEventBatches.last?.replacePendingEvents, false)
    }

    func testLeavingFillTubingModeBeforeAnyInsulinFlowedReportsNoPrime() {
        let delegate = attachDelegate()
        bluetooth.stub(ExitFillTubingModeRequest.self, with: ExitFillTubingModeResponse(status: 0))

        viewModel.exitFillTubingMode()
        drainMainQueue()
        manager.waitForDelegateCalls()

        XCTAssertEqual(delegate.pumpEventBatches.flatMap(\.events), [])
    }

    func testARefusedExitFromFillTubingModeReportsNoPrime() {
        let delegate = attachDelegate()
        stubAlerts()
        bluetooth.stub(ExitFillTubingModeRequest.self, with: ExitFillTubingModeResponse(status: 1))
        viewModel.handleButtonState(buttonDown: true)
        viewModel.handleButtonState(buttonDown: false)
        drainMainQueue()

        viewModel.exitFillTubingMode()
        drainMainQueue()
        manager.waitForDelegateCalls()

        XCTAssertEqual(delegate.pumpEventBatches.flatMap(\.events), [])
        XCTAssertTrue(viewModel.failedExitMode)
    }

    // MARK: - Starting the fill

    func testTheFillCannotStartBeforeTheNotificationReadLands() {
        stubAlerts()
        viewModel.isSuspended = true
        viewModel.currentStep = .disconnect

        viewModel.checkNotificationsBeforeFill()
        XCTAssertFalse(viewModel.canStartFill)

        drainMainQueue()
        XCTAssertTrue(viewModel.canStartFill)
    }

    func testTheFillCannotStartWhileARefreshIsInFlight() {
        stubAlerts()
        viewModel.isSuspended = true
        viewModel.currentStep = .disconnect
        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()

        viewModel.notificationsViewModel.refreshNotifications()
        XCTAssertFalse(viewModel.canStartFill)

        drainMainQueue()
        XCTAssertTrue(viewModel.canStartFill)
    }

    func testTheDisconnectStepWaitsForTheUserToStartTheFill() {
        startAtTheDisconnectStep()
        stubAlerts()
        bluetooth.stub(EnterFillTubingModeRequest.self, with: EnterFillTubingModeResponse(status: 0))

        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()
        drainMainQueue()

        XCTAssertEqual(bluetooth.sent(EnterFillTubingModeRequest.self).count, 0)
        XCTAssertEqual(viewModel.currentStep, .disconnect)
    }

    func testTheTubingIsConnectedBetweenDisconnectingAndFilling() {
        XCTAssertEqual(TubingFillStep.disconnect.nextStep(), .connectTubing)
        XCTAssertEqual(TubingFillStep.connectTubing.nextStep(), .filling)
    }

    func testStartingTheFillEntersFillMode() {
        startAtTheConnectTubingStep()
        stubAlerts()
        bluetooth.stub(EnterFillTubingModeRequest.self, with: EnterFillTubingModeResponse(status: 0))
        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()

        viewModel.enterFillTubingMode()
        drainMainQueue()

        XCTAssertEqual(bluetooth.sent(EnterFillTubingModeRequest.self).count, 1)
        XCTAssertEqual(viewModel.currentStep, .filling)
        XCTAssertFalse(viewModel.failedEnterMode)
    }

    func testARefusedEnterKeepsTheConnectTubingStep() {
        startAtTheConnectTubingStep()
        stubAlerts()
        bluetooth.stub(EnterFillTubingModeRequest.self, with: EnterFillTubingModeResponse(status: 1))
        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()

        viewModel.enterFillTubingMode()
        drainMainQueue()

        XCTAssertEqual(viewModel.currentStep, .connectTubing)
        XCTAssertTrue(viewModel.failedEnterMode)
        XCTAssertFalse(viewModel.isProcessing)
    }

    /// The step shows no notification list while it is empty, so nothing on screen re-reads it.
    func testARefusedEnterReadsTheNotificationsAgain() {
        startAtTheConnectTubingStep()
        stubAlerts()
        bluetooth.stub(EnterFillTubingModeRequest.self, with: EnterFillTubingModeResponse(status: 1))
        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()

        stubAlerts(.LOW_INSULIN_ALERT)
        viewModel.enterFillTubingMode()
        drainMainQueue()
        drainMainQueue()

        XCTAssertTrue(viewModel.hasActiveNotifications)
        XCTAssertFalse(viewModel.canStartFill)
    }

    func testANotificationToClearBlocksTheFill() {
        startAtTheDisconnectStep()
        stubAlerts(.LOW_INSULIN_ALERT)

        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()

        XCTAssertTrue(viewModel.hasActiveNotifications)
        XCTAssertFalse(viewModel.canStartFill)
    }

    func testClearingTheNotificationsLetsTheFillStart() {
        startAtTheDisconnectStep()
        stubAlerts(.LOW_INSULIN_ALERT)
        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()

        stubAlerts()
        refreshNotifications()

        XCTAssertFalse(viewModel.hasActiveNotifications)
        XCTAssertTrue(viewModel.canStartFill)
    }

    func testANotificationRaisedAfterTheReadBlocksTheFill() {
        startAtTheDisconnectStep()
        stubAlerts()
        viewModel.checkNotificationsBeforeFill()
        drainMainQueue()

        stubAlerts(.LOW_INSULIN_ALERT)
        refreshNotifications()

        XCTAssertTrue(viewModel.hasActiveNotifications)
        XCTAssertFalse(viewModel.canStartFill)
    }

    // MARK: - Graphics

    func testTheFillGraphicShowsThePressUntilTheButtonComesUpThenTheDrop() {
        stubAlerts()
        XCTAssertEqual(viewModel.fillingGraphic, .fillTubing)

        viewModel.handleButtonState(buttonDown: true)
        XCTAssertEqual(viewModel.fillingGraphic, .fillTubing)

        viewModel.handleButtonState(buttonDown: false)
        XCTAssertEqual(viewModel.fillingGraphic, .fillingStopped)

        viewModel.handleButtonState(buttonDown: true)
        XCTAssertEqual(viewModel.fillingGraphic, .fillTubing)
        drainMainQueue()
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

    private func startAtTheDisconnectStep() {
        viewModel.isSuspended = true
        viewModel.currentStep = .disconnect
    }

    private func startAtTheConnectTubingStep() {
        viewModel.isSuspended = true
        viewModel.currentStep = .connectTubing
    }

    private func attachDelegate() -> MockPumpManagerDelegate {
        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
        return delegate
    }

    /// Answers the pump's alert read with exactly `alerts` active.
    private func stubAlerts(_ alerts: AlertStatusResponse.AlertResponseType...) {
        let bitmask = alerts.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1.rawValue)) }
        bluetooth.stub(AlertStatusRequest.self, with: AlertStatusResponse(intMap: bitmask))
    }

    private func refreshNotifications() {
        viewModel.notificationsViewModel.refreshNotifications()
        drainMainQueue()
    }

    /// The dismissal's answer hops to the main queue to start the confirming read, which hops again to publish.
    private func drainAcknowledgement() {
        drainMainQueue()
        drainMainQueue()
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
