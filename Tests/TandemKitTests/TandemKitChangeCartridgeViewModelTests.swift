import Combine
import Foundation
@testable import TandemKit
import XCTest

/// Covers the cartridge change wizard's handling of the enter-change-mode request.
///
/// The pump does not answer `EnterChangeCartridgeMode` until the cartridge is mechanically safe to
/// remove, which takes 5-15 seconds. So a missing answer does not mean the pump refused, and the
/// wizard must not re-offer a blind retry of a signed insulin-affecting request on the strength of
/// one. The moment the cartridge can be removed is estimated from the cartridge volume for as long
/// as the pump's change-cartridge stream stays dark.
@available(macOS 13.0, iOS 14.0, *) final class TandemKitChangeCartridgeViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitChangeCartridgeViewModel

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

    private func makeViewModel() -> ViewModel {
        let viewModel = ViewModel(pumpManager: manager, done: {}, toFillTubing: {})
        viewModel.isSuspended = true
        viewModel.currentStep = .enterMode
        return viewModel
    }

    /// Stubs the cartridge volume read that precedes every enter request.
    private func stubReservoir(units: Int) {
        bluetooth.stub(
            InsulinStatusRequest.self,
            with: InsulinStatusResponse(currentInsulinAmount: units, isEstimate: 0, insulinLowAmount: 20)
        )
    }

    private func stubSuspended(_ suspended: Bool) {
        bluetooth.stub(
            CurrentBasalStatusRequest.self,
            with: CurrentBasalStatusResponse(
                profileBasalRate: 800,
                currentBasalRate: suspended ? 0 : 800,
                basalModifiedBitmask: suspended ? 0x01 : 0x00
            )
        )
    }

    private func loadStatus(active: Bool, _ state: LoadStatusResponse.LoadState) -> LoadStatusResponse {
        LoadStatusResponse(isLoadingActive: active, loadStateId: state.rawValue, primeStatusId: 0)
    }

    private func stubActiveAlert(_ alert: AlertStatusResponse.AlertResponseType) {
        bluetooth.stub(AlertStatusRequest.self, with: AlertStatusResponse(intMap: UInt64(1) << UInt64(alert.rawValue)))
    }

    private var sentCartridgeProcedureRequests: [String] {
        bluetooth.sentMessages.map { String(describing: type(of: $0)) }.filter {
            ["EnterChangeCartridgeModeRequest", "ExitChangeCartridgeModeRequest", "ExitFillTubingModeRequest"].contains($0)
        }
    }

    /// Lets the view model's `DispatchQueue.main.async` hops run. The stub answers writes inline, so
    /// the only thing outstanding is the main-queue scheduling.
    private func drainMainQueue(iterations: Int = 20) {
        for _ in 0 ..< iterations {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    // MARK: - Ready-to-change estimate

    func testAFullCartridgeWaitsOnlyTheFixedOverhead() {
        XCTAssertEqual(makeViewModel().readyToChangeDelay(unitsRemaining: 200, capacity: 200), 5)
    }

    func testAnEmptyCartridgeWaitsTheOverheadPlusTheFullTraversal() {
        XCTAssertEqual(makeViewModel().readyToChangeDelay(unitsRemaining: 0, capacity: 200), 15)
    }

    func testTheWaitScalesWithInsulinAlreadyDelivered() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.readyToChangeDelay(unitsRemaining: 150, capacity: 200), 7.5)
        XCTAssertEqual(viewModel.readyToChangeDelay(unitsRemaining: 100, capacity: 200), 10)
        XCTAssertEqual(viewModel.readyToChangeDelay(unitsRemaining: 50, capacity: 200), 12.5)
    }

    func testAnUnknownVolumeAssumesTheWorstCase() {
        let viewModel = makeViewModel()

        XCTAssertEqual(
            viewModel.readyToChangeDelay(unitsRemaining: nil, capacity: 200),
            viewModel.readyToChangeDelay(unitsRemaining: 0, capacity: 200)
        )
    }

    func testOutOfRangeVolumesAreClamped() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.readyToChangeDelay(unitsRemaining: 500, capacity: 200), 5)
        XCTAssertEqual(viewModel.readyToChangeDelay(unitsRemaining: -20, capacity: 200), 15)
    }

    // MARK: - Enter change cartridge mode

    func testASuccessfulEnterWaitsForThePumpBeforeOfferingToRemoveTheCartridge() {
        stubReservoir(units: 120)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 0))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        // 120 U of 200 leaves a 9s estimate, so the wizard is still holding when the queue drains.
        XCTAssertEqual(viewModel.currentStep, .waitingForReady)
        XCTAssertNil(viewModel.changeCartridgeState)
        XCTAssertTrue(viewModel.isProcessing)
    }

    func testAPumpRejectionIsReportedAsAPlainFailure() {
        stubReservoir(units: 120)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.failedEnterMode)
        XCTAssertFalse(viewModel.indeterminateEnterMode)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertFalse(
            bluetooth.didSend(ExitChangeCartridgeModeRequest.self),
            "the pump answered, so its state is known and needs no recovery"
        )
    }

    func testAnUnansweredEnterIsRecoveredWithAnExitRatherThanARetry() {
        stubReservoir(units: 120)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self) { _ in nil }
        bluetooth.stub(ExitChangeCartridgeModeRequest.self, with: ExitChangeCartridgeModeResponse(status: 0))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertEqual(
            bluetooth.sent(EnterChangeCartridgeModeRequest.self).count,
            1,
            "a signed insulin-affecting request must not be re-sent while the pump state is unknown"
        )
        XCTAssertTrue(bluetooth.didSend(ExitChangeCartridgeModeRequest.self))
        XCTAssertEqual(viewModel.currentStep, .enterMode)
        XCTAssertFalse(viewModel.isProcessing)
        // The exit was acknowledged, so the pump is known to be out of change mode and a retry is safe.
        XCTAssertTrue(viewModel.failedEnterMode)
        XCTAssertFalse(viewModel.indeterminateEnterMode)
    }

    func testAnUnansweredExitLeavesTheModeIndeterminate() {
        stubReservoir(units: 120)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self) { _ in nil }
        bluetooth.stub(ExitChangeCartridgeModeRequest.self) { _ in nil }

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.indeterminateEnterMode)
        XCTAssertFalse(viewModel.failedEnterMode, "an unknown pump state must not read as a clean failure")
        XCTAssertEqual(viewModel.currentStep, .enterMode)
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testEnteringIsRefusedWhileDeliveryIsStillRunning() {
        let viewModel = makeViewModel()
        viewModel.isSuspended = false

        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.failedEnterMode)
        XCTAssertFalse(bluetooth.didSend(EnterChangeCartridgeModeRequest.self))
    }

    // MARK: - Stuck cartridge procedure

    /// A refusal with delivery suspended and nothing on the pump's notification list is what a
    /// cartridge procedure left open looks like: the pump gives no other reason.
    func testARefusalWithDeliverySuspendedAndNoNotificationsOffersRecovery() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.stuckModeRecoveryOffered)
        XCTAssertTrue(viewModel.failedEnterMode, "the plain failure stays on screen behind the prompt")
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testOfferingRecoveryDoesNothingToThePumpUntilItIsAccepted() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()
        drainMainQueue()

        XCTAssertEqual(sentCartridgeProcedureRequests, ["EnterChangeCartridgeModeRequest"])
        XCTAssertEqual(viewModel.currentStep, .enterMode)
    }

    func testARefusalWithAnActiveNotificationDoesNotOfferRecovery() {
        stubReservoir(units: 0)
        stubSuspended(true)
        stubActiveAlert(.INCOMPLETE_FILL_TUBING_ALERT)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.hasActiveNotifications, "the test needs the pump's alert to have been read")
        XCTAssertFalse(viewModel.stuckModeRecoveryOffered)
        XCTAssertTrue(viewModel.failedEnterMode)
    }

    func testARefusalAfterDeliveryHasResumedDoesNotOfferRecovery() {
        stubReservoir(units: 0)
        stubSuspended(false)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertFalse(viewModel.stuckModeRecoveryOffered)
        XCTAssertTrue(viewModel.failedEnterMode)
    }

    func testAnUnansweredEnterDoesNotOfferRecovery() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self) { _ in nil }
        bluetooth.stub(ExitChangeCartridgeModeRequest.self, with: ExitChangeCartridgeModeResponse(status: 0))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertFalse(viewModel.stuckModeRecoveryOffered)
    }

    func testASuccessfulEnterDoesNotOfferRecovery() {
        stubReservoir(units: 120)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 0))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertFalse(viewModel.stuckModeRecoveryOffered)
    }

    func testAcceptingRecoveryUnwindsThePumpThenResumesTheWizard() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.enqueue(
            EnterChangeCartridgeModeRequest.self,
            responses: [EnterChangeCartridgeModeResponse(status: 1), EnterChangeCartridgeModeResponse(status: 0)]
        )
        bluetooth.stub(ExitFillTubingModeRequest.self, with: ExitFillTubingModeResponse(status: 0))
        bluetooth.stub(ExitChangeCartridgeModeRequest.self, with: ExitChangeCartridgeModeResponse(status: 1))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()
        XCTAssertTrue(viewModel.stuckModeRecoveryOffered)

        viewModel.recoverFromStuckMode()
        drainMainQueue()

        XCTAssertEqual(
            sentCartridgeProcedureRequests,
            [
                "EnterChangeCartridgeModeRequest",
                "ExitFillTubingModeRequest",
                "ExitChangeCartridgeModeRequest",
                "EnterChangeCartridgeModeRequest"
            ]
        )
        XCTAssertFalse(viewModel.failedEnterMode)
        XCTAssertEqual(viewModel.currentStep, .waitingForReady, "the wizard carries on as after a first-time enter")
        XCTAssertTrue(viewModel.isProcessing)
    }

    func testAcceptingRecoveryWaitsOutTheRetractionBeforeOfferingToRemoveTheCartridge() {
        stubReservoir(units: 0) // Worst case: a 15s estimate the test must not wait out.
        stubSuspended(true)
        bluetooth.enqueue(
            EnterChangeCartridgeModeRequest.self,
            responses: [EnterChangeCartridgeModeResponse(status: 1), EnterChangeCartridgeModeResponse(status: 0)]
        )

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()
        viewModel.recoverFromStuckMode()
        drainMainQueue()

        XCTAssertEqual(viewModel.currentStep, .waitingForReady)
        XCTAssertNil(viewModel.changeCartridgeState)
    }

    func testARefusalAfterRecoveryIsReportedWithoutOfferingItAgain() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()
        viewModel.stuckModeRecoveryOffered = false // The view consumes the offer when it shows the prompt.

        viewModel.recoverFromStuckMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.failedEnterMode)
        XCTAssertFalse(viewModel.stuckModeRecoveryOffered, "a prompt after every recovery would loop")
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.currentStep, .enterMode)
    }

    func testAnUnansweredEnterAfterRecoveryLeavesTheModeIndeterminate() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.enqueue(
            EnterChangeCartridgeModeRequest.self,
            responses: [EnterChangeCartridgeModeResponse(status: 1), nil]
        )

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()
        viewModel.recoverFromStuckMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.indeterminateEnterMode)
        XCTAssertFalse(viewModel.failedEnterMode)
        XCTAssertFalse(viewModel.isProcessing)
    }

    // MARK: - Unfinished procedure

    func testARefusalWhileThePumpIsStillInChangeModeResumesAtTheCartridgeSwap() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))
        bluetooth.stub(LoadStatusRequest.self, with: loadStatus(active: true, .changeCartridge))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertEqual(sentCartridgeProcedureRequests, ["EnterChangeCartridgeModeRequest"])
        XCTAssertEqual(viewModel.currentStep, .physicalChange)
        XCTAssertEqual(viewModel.changeCartridgeState, .readyToChange)
        XCTAssertFalse(viewModel.failedEnterMode)
        XCTAssertFalse(viewModel.stuckModeRecoveryOffered)
        XCTAssertTrue(viewModel.isProcessing, "the pump is in change mode, so the wizard can't be left without exiting it")
    }

    func testARefusalWithACartridgeAlreadyLoadedFinishesAtTheTubingFill() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))
        bluetooth.stub(LoadStatusRequest.self, with: loadStatus(active: true, .loadCartridge))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertEqual(sentCartridgeProcedureRequests, ["EnterChangeCartridgeModeRequest"])
        XCTAssertEqual(viewModel.currentStep, .done)
        XCTAssertTrue(viewModel.foundCartridgeAlreadyLoaded)
        XCTAssertFalse(viewModel.failedEnterMode)
        XCTAssertFalse(viewModel.stuckModeRecoveryOffered)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(
            manager.state.lastCartridgeChangeDate,
            "a cancelled change also exits change mode, so the cartridge detected may be the old one"
        )
    }

    func testARefusalOutsideALoadingProcedureStillOffersRecovery() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))
        bluetooth.stub(LoadStatusRequest.self, with: loadStatus(active: false, .changeCartridge))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        XCTAssertTrue(viewModel.stuckModeRecoveryOffered)
        XCTAssertTrue(viewModel.failedEnterMode)
        XCTAssertEqual(viewModel.currentStep, .enterMode)
    }

    func testARecoveryThatLeavesACartridgeDetectedFinishesAtTheTubingFill() {
        stubReservoir(units: 0)
        stubSuspended(true)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 1))
        bluetooth.stub(ExitFillTubingModeRequest.self, with: ExitFillTubingModeResponse(status: 1))
        bluetooth.stub(ExitChangeCartridgeModeRequest.self, with: ExitChangeCartridgeModeResponse(status: 0))
        // Unanswered before the recovery; after it, the exit has had the pump detect a cartridge.
        bluetooth.enqueue(LoadStatusRequest.self, responses: [nil, loadStatus(active: true, .loadCartridge)])

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()
        viewModel.stuckModeRecoveryOffered = false // The view consumes the offer when it shows the prompt.

        viewModel.recoverFromStuckMode()
        drainMainQueue()

        XCTAssertEqual(viewModel.currentStep, .done)
        XCTAssertTrue(viewModel.foundCartridgeAlreadyLoaded)
        XCTAssertFalse(viewModel.failedEnterMode)
    }

    // MARK: - Ready-to-change stream

    func testThePumpsReadySignalAdvancesTheWizardWithoutWaitingOutTheEstimate() {
        stubReservoir(units: 0) // Worst case: a 15s estimate the test must not wait out.
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 0))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()
        XCTAssertEqual(viewModel.currentStep, .waitingForReady)

        manager.changeCartridgeStateStream.send(EnterChangeCartridgeModeStateStreamResponse(
            stateId: EnterChangeCartridgeModeStateStreamResponse.ChangeCartridgeState.readyToChange.rawValue
        ))
        drainMainQueue()

        XCTAssertEqual(viewModel.changeCartridgeState, .readyToChange)
        XCTAssertEqual(viewModel.currentStep, .physicalChange)
    }

    // MARK: - Detection stream

    func testDetectionProgressFollowsThePumpWhenItReportsAny() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .physicalChange
        viewModel.cartridgeInserted()

        manager.detectingCartridgeStateStream.send(DetectingCartridgeStateStreamResponse(percentComplete: 40))
        drainMainQueue()

        XCTAssertEqual(viewModel.detectingProgress, 40)
        XCTAssertTrue(viewModel.isDetecting)
    }

    func testDetectionCompletesOnceAndRecordsTheCartridgeChange() {
        bluetooth.stub(ExitChangeCartridgeModeRequest.self, with: ExitChangeCartridgeModeResponse(status: 0))

        let viewModel = makeViewModel()
        viewModel.currentStep = .physicalChange
        viewModel.cartridgeInserted()

        manager.detectingCartridgeStateStream.send(DetectingCartridgeStateStreamResponse(percentComplete: 100))
        // A duplicate completion must not drive a second exit request.
        manager.detectingCartridgeStateStream.send(DetectingCartridgeStateStreamResponse(percentComplete: 100))
        drainMainQueue()

        XCTAssertFalse(viewModel.isDetecting)
        XCTAssertNotNil(manager.state.lastCartridgeChangeDate)
        XCTAssertEqual(bluetooth.sent(ExitChangeCartridgeModeRequest.self).count, 1)
        XCTAssertEqual(viewModel.currentStep, .done)
    }
}
