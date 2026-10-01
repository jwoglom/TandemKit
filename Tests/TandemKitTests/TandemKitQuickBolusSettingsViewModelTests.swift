import Foundation
@testable import TandemKit
import XCTest

/// The quick bolus screen saves in units mode only (#428), so a pump left in carbs mode has to be
/// savable without an edit, and a save the pump does not apply has to leave the edit on screen.
@available(macOS 13.0, iOS 14.0, *) final class TandemKitQuickBolusSettingsViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitQuickBolusSettingsViewModel

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

    private func seedQuickBolus(enabled: Bool, mode: QuickBolusMode = .units, incrementUnits: Int) {
        manager.state.quickBolusEnabled = enabled
        manager.state.quickBolusEntryType = mode.rawValue
        manager.state.quickBolusIncrementUnits = incrementUnits
    }

    private func makeViewModel() -> ViewModel {
        let viewModel = ViewModel(pumpManager: manager)
        drainMainQueue()
        return viewModel
    }

    private func row(_ milliunits: Int) -> Int {
        ViewModel.unitIncrements.firstIndex { $0.milliunits == milliunits } ?? -1
    }

    /// Runs the main queue long enough for the view model's nested main-queue hops to land: a status
    /// update reaches it on the main queue, then schedules the reload and the dirty check behind it.
    private func drainMainQueue(iterations: Int = 20) {
        for _ in 0 ..< iterations {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    // MARK: - Seeded state

    func testTheScreenOpensOnThePumpsSettingsWithNothingToSave() {
        seedQuickBolus(enabled: true, incrementUnits: 2000)

        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.enabled)
        XCTAssertEqual(ViewModel.unitIncrements[viewModel.unitsIncrementIndex].label, "2.0 U")
        XCTAssertFalse(viewModel.pumpIsInCarbsMode)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertFalse(viewModel.canSave)
    }

    func testEveryIncrementThePumpAcceptsOpensOnItsOwnRow() {
        for milliunits in SetQuickBolusSettingsRequest.supportedIncrementUnits {
            seedQuickBolus(enabled: true, incrementUnits: milliunits)

            let viewModel = ViewModel(pumpManager: manager)

            XCTAssertEqual(ViewModel.unitIncrements[viewModel.unitsIncrementIndex].milliunits, milliunits)
        }
    }

    func testAPumpInCarbsModeCanBeSavedWithoutAnEdit() {
        seedQuickBolus(enabled: true, mode: .carbs, incrementUnits: 500)

        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.pumpIsInCarbsMode)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertTrue(viewModel.canSave)
    }

    func testCarbsModeIsNotFlaggedWhileQuickBolusIsOff() {
        seedQuickBolus(enabled: false, mode: .carbs, incrementUnits: 500)

        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.pumpIsInCarbsMode)
        XCTAssertFalse(viewModel.canSave)
    }

    // MARK: - Unsaved changes

    func testEditingEnablesSaveAndUndoingTheEditDisablesIt() {
        seedQuickBolus(enabled: true, incrementUnits: 500)
        let viewModel = makeViewModel()

        viewModel.unitsIncrementIndex = row(5000)
        drainMainQueue()
        XCTAssertTrue(viewModel.isDirty)
        XCTAssertTrue(viewModel.canSave)

        viewModel.unitsIncrementIndex = row(500)
        drainMainQueue()
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertFalse(viewModel.canSave)
    }

    func testAStatusUpdateLeavesAnUnsavedEditAlone() {
        seedQuickBolus(enabled: true, incrementUnits: 500)
        let viewModel = makeViewModel()
        viewModel.enabled = false
        drainMainQueue()

        manager.state.quickBolusIncrementUnits = 2000
        manager.notifyDelegateStateUpdated()
        drainMainQueue()

        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.unitsIncrementIndex, row(500))
        XCTAssertTrue(viewModel.isDirty)
    }

    func testAStatusUpdateRefreshesAnUneditedScreen() {
        seedQuickBolus(enabled: true, incrementUnits: 500)
        let viewModel = makeViewModel()

        manager.state.quickBolusIncrementUnits = 2000
        manager.notifyDelegateStateUpdated()
        drainMainQueue()

        XCTAssertEqual(viewModel.unitsIncrementIndex, row(2000))
        XCTAssertFalse(viewModel.isDirty)
    }

    // MARK: - Saving to the pump

    func testASavedChangeIsSentAndTheScreenEndsOnThePumpsSettings() throws {
        seedQuickBolus(enabled: false, incrementUnits: 500)
        bluetooth.enqueue(
            PumpGlobalsRequest.self,
            responses: [
                PumpGlobalsResponse.quickBolus(enabled: false, incrementUnits: 500),
                PumpGlobalsResponse.quickBolus(enabled: true, incrementUnits: 1000)
            ]
        )
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 0))
        let viewModel = makeViewModel()
        viewModel.enabled = true
        viewModel.unitsIncrementIndex = row(1000)
        drainMainQueue()

        viewModel.submit()
        drainMainQueue()

        let request = try XCTUnwrap(bluetooth.sent(SetQuickBolusSettingsRequest.self).first)
        XCTAssertTrue(request.enabled)
        XCTAssertEqual(request.mode, .units)
        XCTAssertEqual(request.incrementUnits, 1000)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.saveError)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertFalse(viewModel.canSave)
        XCTAssertTrue(viewModel.enabled)
        XCTAssertEqual(viewModel.unitsIncrementIndex, row(1000))
    }

    func testARefusedSaveKeepsTheEditAndSaysSo() {
        seedQuickBolus(enabled: false, incrementUnits: 500)
        bluetooth.stub(PumpGlobalsRequest.self, with: PumpGlobalsResponse.quickBolus(enabled: false, incrementUnits: 500))
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 1))
        let viewModel = makeViewModel()
        viewModel.enabled = true
        drainMainQueue()

        viewModel.submit()
        drainMainQueue()

        XCTAssertTrue(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
        XCTAssertNotNil(viewModel.saveError)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.enabled)
        XCTAssertTrue(viewModel.isDirty)
        XCTAssertTrue(viewModel.canSave)
    }
}
