import Foundation
@testable import TandemKit
import XCTest

/// The sound screen edits a copy of the pump's annunciation settings and, once paired, sends only the
/// ones changed. During onboarding there is no pump to write to, so it stores them instead.
@available(macOS 13.0, iOS 14.0, *) final class TandemKitSoundSettingsViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitSoundSettingsViewModel

    private let beep = PumpGlobalsResponse.AnnunciationEnum.audioHigh.rawValue
    private let vibrate = PumpGlobalsResponse.AnnunciationEnum.vibrate.rawValue

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        manager.state.quickBolusAnnun = .audioHigh
        manager.state.generalAnnun = .vibrate
        manager.state.reminderAnnun = .vibrate
        manager.state.alertAnnun = .audioHigh
        manager.state.alarmAnnun = .vibrate
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeViewModel(onSubmit: (() -> Void)? = nil) -> ViewModel {
        let viewModel = ViewModel(pumpManager: manager, onSubmit: onSubmit)
        drainMainQueue()
        return viewModel
    }

    private func pumpGlobals(quickBolus: Int, general: Int, reminder: Int, alert: Int, alarm: Int) -> PumpGlobalsResponse {
        PumpGlobalsResponse(
            quickBolusEnabledRaw: 0,
            quickBolusIncrementUnits: 500,
            quickBolusIncrementCarbs: 2000,
            quickBolusEntryType: QuickBolusMode.units.rawValue,
            quickBolusStatus: 0,
            buttonAnnun: 0,
            quickBolusAnnun: quickBolus,
            generalAnnun: general,
            reminderAnnun: reminder,
            alertAnnun: alert,
            alarmAnnun: alarm,
            fillTubingAnnun: 0
        )
    }

    /// Runs the main queue long enough for the view model's nested main-queue hops to land: a status
    /// update reaches it on the main queue, then schedules the reload and the dirty check behind it.
    private func drainMainQueue(iterations: Int = 20) {
        for _ in 0 ..< iterations {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    // MARK: - Seeded state

    func testTheScreenOpensOnThePumpsSoundsWithNothingToSave() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.quickBolusAnnun, beep)
        XCTAssertEqual(viewModel.generalAnnun, vibrate)
        XCTAssertEqual(viewModel.reminderAnnun, vibrate)
        XCTAssertEqual(viewModel.alertAnnun, beep)
        XCTAssertEqual(viewModel.alarmAnnun, vibrate)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertTrue(viewModel.isDisabled)
    }

    // MARK: - Unsaved changes

    func testChangingASoundEnablesSaveAndChangingItBackDisablesIt() {
        let viewModel = makeViewModel()

        viewModel.generalAnnun = beep
        drainMainQueue()
        XCTAssertTrue(viewModel.isDirty)
        XCTAssertFalse(viewModel.isDisabled)

        viewModel.generalAnnun = vibrate
        drainMainQueue()
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertTrue(viewModel.isDisabled)
    }

    func testAStatusUpdateLeavesAnUnsavedChangeAlone() {
        let viewModel = makeViewModel()
        viewModel.generalAnnun = beep
        drainMainQueue()

        manager.state.alarmAnnun = .audioHigh
        manager.notifyDelegateStateUpdated()
        drainMainQueue()

        XCTAssertEqual(viewModel.generalAnnun, beep)
        XCTAssertEqual(viewModel.alarmAnnun, vibrate)
        XCTAssertTrue(viewModel.isDirty)
    }

    func testAStatusUpdateRefreshesAnUneditedScreen() {
        let viewModel = makeViewModel()

        manager.state.alarmAnnun = .audioHigh
        manager.notifyDelegateStateUpdated()
        drainMainQueue()

        XCTAssertEqual(viewModel.alarmAnnun, beep)
        XCTAssertFalse(viewModel.isDirty)
    }

    // MARK: - Saving to the pump

    func testSavingWithNothingChangedSendsNothing() {
        let viewModel = makeViewModel()

        viewModel.submit()
        drainMainQueue()

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testSavingSendsOnlyTheChangedSounds() throws {
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 0))
        bluetooth.stub(
            PumpGlobalsRequest.self,
            with: pumpGlobals(quickBolus: beep, general: beep, reminder: vibrate, alert: vibrate, alarm: vibrate)
        )
        let viewModel = makeViewModel()
        viewModel.generalAnnun = beep
        viewModel.alertAnnun = vibrate
        drainMainQueue()

        viewModel.submit()
        drainMainQueue()

        let request = try XCTUnwrap(bluetooth.sent(SetPumpSoundsRequest.self).first)
        XCTAssertEqual(request.changeBitmask, [.generalAnnun, .alertAnnun])
        XCTAssertEqual(request.generalAnnunRaw, beep)
        XCTAssertEqual(request.alertAnnunRaw, vibrate)
        XCTAssertEqual(request.quickBolusAnnunRaw, beep)
        XCTAssertEqual(request.reminderAnnunRaw, vibrate)
        XCTAssertEqual(request.alarmAnnunRaw, vibrate)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertEqual(viewModel.generalAnnun, beep)
        XCTAssertEqual(viewModel.alertAnnun, vibrate)
    }

    func testAChangeThePumpRefusedIsReplacedByWhatItReportsBack() {
        bluetooth.stub(SetPumpSoundsRequest.self, with: SetPumpSoundsResponse(status: 1))
        bluetooth.stub(
            PumpGlobalsRequest.self,
            with: pumpGlobals(quickBolus: beep, general: vibrate, reminder: vibrate, alert: beep, alarm: vibrate)
        )
        let viewModel = makeViewModel()
        viewModel.generalAnnun = beep
        drainMainQueue()

        viewModel.submit()
        drainMainQueue()

        XCTAssertTrue(bluetooth.didSend(SetPumpSoundsRequest.self))
        XCTAssertEqual(viewModel.generalAnnun, vibrate)
        XCTAssertFalse(viewModel.isDirty)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Onboarding

    func testDuringOnboardingContinueIsAvailableWithoutAChange() {
        let viewModel = makeViewModel(onSubmit: {})

        XCTAssertFalse(viewModel.isDirty)
        XCTAssertFalse(viewModel.isDisabled)
    }

    func testDuringOnboardingSubmitStoresTheSoundsWithoutTalkingToThePump() {
        var submitted = false
        let viewModel = makeViewModel(onSubmit: { submitted = true })
        viewModel.generalAnnun = beep
        viewModel.alarmAnnun = beep

        viewModel.submit()

        XCTAssertTrue(submitted)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        XCTAssertEqual(manager.state.generalAnnun, .audioHigh)
        XCTAssertEqual(manager.state.alarmAnnun, .audioHigh)
        XCTAssertEqual(manager.state.reminderAnnun, .vibrate)
    }
}
