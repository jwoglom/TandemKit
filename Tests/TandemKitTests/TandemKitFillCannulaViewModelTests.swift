import Combine
import Foundation
@testable import TandemKit
import XCTest

/// Covers the fill cannula wizard's memory of the prime amount.
///
/// Most users prime the same amount at every site change, so the wizard pre-fills the amount used
/// for the last *successful* fill, persisted in `TandemPumpManagerState.lastCannulaFillAmount`.
@available(macOS 13.0, iOS 14.0, *) final class TandemKitFillCannulaViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitFillCannulaViewModel

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
        let viewModel = ViewModel(pumpManager: manager, done: {})
        viewModel.isSuspended = true
        viewModel.currentStep = .enterAmount
        return viewModel
    }

    /// Lets the view model's `DispatchQueue.main.async` hops run. The stub answers writes inline, so
    /// the only thing outstanding is the main-queue scheduling.
    private func drainMainQueue(iterations: Int = 20) {
        for _ in 0 ..< iterations {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    /// Runs a fill through to the pump's completion message.
    private func completeFill(_ viewModel: ViewModel) {
        bluetooth.stub(FillCannulaRequest.self, with: FillCannulaResponse(status: 0))
        viewModel.fillCannula()
        drainMainQueue()
        manager.fillCannulaStateStream.send(
            FillCannulaStateStreamResponse(stateId: FillCannulaStateStreamResponse.FillCannulaState.cannulaFilled.rawValue)
        )
        drainMainQueue()
    }

    // MARK: - Prefill

    func testTheFirstFillOffersTheDefaultAmount() {
        XCTAssertNil(manager.state.lastCannulaFillAmount)
        XCTAssertEqual(makeViewModel().primeAmount, ViewModel.defaultPrimeAmount, accuracy: 0.0001)
    }

    func testThePrefilledAmountAlwaysMatchesAnOfferedAmount() {
        // The picker tags its rows with `primeAmountOptions`, and shows no selection for a value
        // that is merely close to one, so both the default and a remembered amount have to snap.
        XCTAssertTrue(ViewModel.primeAmountOptions.contains(makeViewModel().primeAmount))

        manager.state.lastCannulaFillAmount = 0.7
        XCTAssertTrue(ViewModel.primeAmountOptions.contains(makeViewModel().primeAmount))
    }

    func testARememberedAmountIsPrefilled() {
        manager.state.lastCannulaFillAmount = 1.1

        XCTAssertEqual(makeViewModel().primeAmount, 1.1, accuracy: 0.0001)
    }

    // MARK: - Recording

    func testACompletedFillRemembersItsAmount() {
        let viewModel = makeViewModel()
        viewModel.primeAmount = ViewModel.nearestPrimeAmount(to: 0.5)

        completeFill(viewModel)

        XCTAssertEqual(viewModel.currentStep, .done)
        XCTAssertEqual(manager.state.lastCannulaFillAmount ?? 0, 0.5, accuracy: 0.0001)
        // And the next run of the wizard opens on it.
        XCTAssertEqual(makeViewModel().primeAmount, 0.5, accuracy: 0.0001)
    }

    func testAFailedFillLeavesTheRememberedAmountAlone() {
        manager.state.lastCannulaFillAmount = 0.4

        let viewModel = makeViewModel()
        viewModel.primeAmount = ViewModel.nearestPrimeAmount(to: 1.5)
        // The pump refuses to start priming.
        bluetooth.stub(FillCannulaRequest.self, with: FillCannulaResponse(status: 1))
        viewModel.fillCannula()
        drainMainQueue()

        XCTAssertTrue(viewModel.failedFill)
        XCTAssertEqual(manager.state.lastCannulaFillAmount ?? 0, 0.4, accuracy: 0.0001)
    }
}
