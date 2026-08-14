import Combine
import Foundation
@testable import TandemKit
import XCTest

/// Covers the cartridge change wizard's handling of the enter-change-mode request.
///
/// The pump does not answer `EnterChangeCartridgeMode` until the cartridge is mechanically safe to
/// remove, which takes 5-20 seconds. So a missing answer does not mean the pump refused, and the
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

    /// Lets the view model's `DispatchQueue.main.async` hops run. The stub answers writes inline, so
    /// the only thing outstanding is the main-queue scheduling.
    private func drainMainQueue(iterations: Int = 20) {
        for _ in 0 ..< iterations {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    // MARK: - Ready-to-change estimate

    func testAFullCartridgeNeedsNoWait() {
        XCTAssertEqual(makeViewModel().readyToChangeDelay(unitsRemaining: 200, capacity: 200), 0)
    }

    func testAnEmptyCartridgeWaitsTheFullTraversal() {
        XCTAssertEqual(makeViewModel().readyToChangeDelay(unitsRemaining: 0, capacity: 200), 10)
    }

    func testTheWaitScalesWithInsulinAlreadyDelivered() {
        XCTAssertEqual(makeViewModel().readyToChangeDelay(unitsRemaining: 100, capacity: 200), 5)
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

        XCTAssertEqual(viewModel.readyToChangeDelay(unitsRemaining: 500, capacity: 200), 0)
        XCTAssertEqual(viewModel.readyToChangeDelay(unitsRemaining: -20, capacity: 200), 10)
    }

    // MARK: - Enter change cartridge mode

    func testASuccessfulEnterWaitsForThePumpBeforeOfferingToRemoveTheCartridge() {
        stubReservoir(units: 120)
        bluetooth.stub(EnterChangeCartridgeModeRequest.self, with: EnterChangeCartridgeModeResponse(status: 0))

        let viewModel = makeViewModel()
        viewModel.enterChangeCartridgeMode()
        drainMainQueue()

        // 120 U of 200 leaves a 4s estimate, so the wizard is still holding when the queue drains.
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

    // MARK: - Ready-to-change stream

    func testThePumpsReadySignalAdvancesTheWizardWithoutWaitingOutTheEstimate() {
        stubReservoir(units: 0) // Worst case: a 10s estimate the test must not wait out.
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
