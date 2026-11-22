import Foundation
import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitSettingsViewModelTests: XCTestCase {
    func testSwitchToControlIQIsRefusedWhileTheFlagIsOff() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        manager.setFeatureFlag(.controlIQSupport, enabled: false)
        manager.state.controlIQWeightLbs = 154
        manager.state.controlIQTotalDailyInsulin = 42

        let viewModel = makeSettingsViewModel(manager)
        viewModel.attemptSwitchToControlIQ()

        XCTAssertFalse(viewModel.isCheckingCGMForCIQ)
        XCTAssertFalse(viewModel.showSwitchToCIQConfirm)
        XCTAssertFalse(viewModel.showControlIQValuesRequired)
        XCTAssertFalse(viewModel.controlIQSupportEnabled)
    }

    func testSwitchToControlIQAsksToConfirmOnceThePumpHasASensorSession() {
        let (viewModel, _) = makeControlIQSwitchViewModel(sessionState: .active)

        viewModel.attemptSwitchToControlIQ()
        drainMainQueue(until: { !viewModel.isCheckingCGMForCIQ && viewModel.showSwitchToCIQConfirm })

        XCTAssertTrue(viewModel.showSwitchToCIQConfirm)
        XCTAssertFalse(viewModel.showCGMRequiredForCIQ)
        XCTAssertFalse(viewModel.showControlIQValuesRequired)
    }

    func testSwitchToControlIQIsBlockedWithoutASensorSession() {
        let (viewModel, _) = makeControlIQSwitchViewModel(sessionState: .stopped)

        viewModel.attemptSwitchToControlIQ()
        drainMainQueue(until: { viewModel.showCGMRequiredForCIQ })

        XCTAssertTrue(viewModel.showCGMRequiredForCIQ)
        XCTAssertFalse(viewModel.showSwitchToCIQConfirm)
        XCTAssertFalse(viewModel.isCheckingCGMForCIQ)
    }

    func testSwitchToControlIQAsksForTheValuesTheDriverNeedsBeforeReadingThePump() {
        let (viewModel, bluetooth) = makeControlIQSwitchViewModel(sessionState: .active, hasValues: false)

        viewModel.attemptSwitchToControlIQ()
        drainMainQueue(until: { viewModel.showControlIQValuesRequired })

        XCTAssertTrue(viewModel.showControlIQValuesRequired)
        XCTAssertFalse(viewModel.showSwitchToCIQConfirm)
        XCTAssertFalse(bluetooth.didSend(CGMStatusV2Request.self))
    }

    func testASwitchToControlIQThePumpNeverAnswersFailsAsUnanswered() {
        let (viewModel, bluetooth) = makeControlIQSwitchViewModel(sessionState: .active)
        bluetooth.stub(ChangeControlIQSettingsRequest.self) { _ in nil }

        viewModel.switchAlgorithmToControlIQ()
        drainMainQueue(until: { viewModel.commandFailure != nil })

        XCTAssertEqual(viewModel.commandFailure, .enableControlIQUnanswered)
    }

    func testASwitchToControlIQThePumpRefusesFailsAsRejected() {
        let (viewModel, bluetooth) = makeControlIQSwitchViewModel(sessionState: .active)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))

        viewModel.switchAlgorithmToControlIQ()
        drainMainQueue(until: { viewModel.commandFailure != nil })

        XCTAssertEqual(viewModel.commandFailure, .enableControlIQ)
    }

    func testTurningControlIQOffThePumpNeverAnswersFailsAsUnanswered() {
        let (viewModel, bluetooth) = makeControlIQSwitchViewModel(sessionState: .active)
        bluetooth.stub(ChangeControlIQSettingsRequest.self) { _ in nil }

        viewModel.switchAlgorithmToDIY()
        drainMainQueue(until: { viewModel.commandFailure != nil })

        XCTAssertEqual(viewModel.commandFailure, .disableControlIQUnanswered)
    }

    func testTurningControlIQOffThePumpRefusesFailsAsRejected() {
        let (viewModel, bluetooth) = makeControlIQSwitchViewModel(sessionState: .active)
        bluetooth.stub(ChangeControlIQSettingsRequest.self, with: ChangeControlIQSettingsResponse(status: 1))

        viewModel.switchAlgorithmToDIY()
        drainMainQueue(until: { viewModel.commandFailure != nil })

        XCTAssertEqual(viewModel.commandFailure, .disableControlIQ)
    }

    func testOnlyAConnectionFailureOrNoAnswerCountsAsUnanswered() {
        typealias ViewModel = TandemKitSettingsViewModel

        XCTAssertTrue(ViewModel.isUnanswered(ControlIQConfigurationError.noResponse))
        XCTAssertTrue(ViewModel.isUnanswered(PumpCommError.noResponse))
        XCTAssertFalse(ViewModel.isUnanswered(ControlIQConfigurationError.pumpRejected(status: 1)))
        XCTAssertFalse(ViewModel.isUnanswered(ControlIQConfigurationError.weightNotSet))
    }

    func testSettingsViewModelReportsTheFlagsWhenTheyAreOn() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertTrue(viewModel.controlIQSupportEnabled)
        XCTAssertTrue(viewModel.quickBolusButtonSupportEnabled)
    }

    func testSettingsViewModelShowsTheControlIQAndQuickBolusRowsByDefault() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertTrue(viewModel.controlIQSupportEnabled)
        XCTAssertTrue(viewModel.quickBolusButtonSupportEnabled)
    }

    func testSettingsViewModelShowsTheAlgorithmStatusOnlyWithTheControlIQFlagOn() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        manager.setFeatureFlag(.controlIQSupport, enabled: false)
        XCTAssertFalse(makeSettingsViewModel(manager).showsAlgorithmStatus)

        manager.setFeatureFlag(.controlIQSupport, enabled: true)
        XCTAssertTrue(makeSettingsViewModel(manager).showsAlgorithmStatus)
    }

    func testSettingsViewModelHidesTheQuickBolusRowWhileTheFlagIsOff() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        manager.setFeatureFlag(.quickBolusButtonSupport, enabled: false)

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertFalse(viewModel.quickBolusButtonSupportEnabled)
    }

    func testADroppedLinkPublishesTheTempBasalThePumpWasLastSeenRunning() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        let lastContact = Date().addingTimeInterval(-.minutes(5))
        let end = lastContact.addingTimeInterval(.minutes(20))
        manager.state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.8)])!
        manager.state.hasSyncedBasalRateSchedule = true
        manager.state.lastReconciliation = lastContact
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 0.4,
            duration: end.timeIntervalSince(lastContact),
            automatic: true,
            insulinType: .novolog,
            startDate: lastContact
        )

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertEqual(viewModel.connectionIssue, .pumpUnreachable)
        XCTAssertEqual(
            viewModel.lastKnownBasalDelivery,
            LastKnownBasalDelivery(
                lastContact: lastContact,
                delivery: .tempBasal(unitsPerHour: 0.4, endDate: end, profileUnitsPerHourAfter: 0.8)
            )
        )
    }

    // MARK: - A manual temp basal

    private func managerHoldingATemp(automatic: Bool, rememberedAsManual: Bool, bluetooth: StubPumpBluetooth = StubPumpBluetooth()) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = 424_242
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        manager.state.basalDose = UnfinalizedDose(
            tempRate: 1.3,
            duration: .minutes(72),
            automatic: automatic,
            insulinType: .novolog,
            startDate: Date(),
            tempRateId: 42,
            tempPercent: 130
        )
        if rememberedAsManual {
            manager.rememberManualTempRate(tempRateId: 42)
        }
        return manager
    }

    func testATempSetFromSettingsOffersTheStopRow() {
        let viewModel = makeSettingsViewModel(managerHoldingATemp(automatic: false, rememberedAsManual: true))

        XCTAssertEqual(viewModel.manualTempBasal?.percent, 130)
        XCTAssertEqual(viewModel.manualTempBasal?.unitsPerHour, 1.3)
    }

    func testTheLoopsTempAndATempSetOnThePumpOfferNoStopRow() {
        XCTAssertNil(makeSettingsViewModel(managerHoldingATemp(automatic: true, rememberedAsManual: false)).manualTempBasal)
        XCTAssertNil(makeSettingsViewModel(managerHoldingATemp(automatic: false, rememberedAsManual: false)).manualTempBasal)
    }

    func testTheStopRowsSubtextGivesThePercentTheRateAndTheTimeLeft() {
        let now = Date()
        let temp = ManualTempBasalRow(percent: 130, unitsPerHour: 1.3, endDate: now.addingTimeInterval(.minutes(71) + 30))

        XCTAssertEqual(TandemKitSettingsViewModel.manualTempBasalSubtext(temp, now: now), "130% (1.30U/hr) with 1h 12m remaining")
    }

    func testTheStopRowStopsTheTempUnderControlIQToo() {
        let bluetooth = StubPumpBluetooth()
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 1000,
            currentBasalRate: 1300,
            basalModifiedBitmask: 0x02
        ))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 42))
        let manager = managerHoldingATemp(automatic: false, rememberedAsManual: true, bluetooth: bluetooth)
        manager.state.useControlIQ = true
        let viewModel = makeSettingsViewModel(manager)

        viewModel.stopManualTempBasal()
        drainMainQueue(until: { !viewModel.isUpdatingPumpState })

        XCTAssertEqual(bluetooth.sent(StopTempRateRequest.self).count, 1)
        XCTAssertNil(viewModel.commandFailure)
        XCTAssertEqual(manager.state.basalDose.type, .basal)
    }

    private func makeControlIQSwitchViewModel(
        sessionState: CGMStatusV2Response.SessionState,
        hasValues: Bool = true
    ) -> (viewModel: TandemKitSettingsViewModel, bluetooth: StubPumpBluetooth) {
        let bluetooth = StubPumpBluetooth()
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        manager.setFeatureFlag(.controlIQSupport, enabled: true)
        manager.state.controlIQWeightLbs = hasValues ? 154 : nil
        manager.state.controlIQTotalDailyInsulin = hasValues ? 42 : nil
        bluetooth.stub(CGMStatusV2Request.self, with: CGMStatusV2Response(
            sessionStateId: sessionState.rawValue,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: 100,
            transmitterBatteryStatusId: CGMStatusV2Response.TransmitterBatteryStatus.unavailable.rawValue,
            sessionDurationSeconds: 3600,
            sessionTimeRemainingSeconds: 3600,
            cgmSensorTypeId: CGMStatusV2Response.CGMSensorType.dexcomG7.rawValue,
            gracePeriod: false
        ))
        return (makeSettingsViewModel(manager), bluetooth)
    }

    private func drainMainQueue(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func makeSettingsViewModel(_ pumpManager: TandemPumpManager) -> TandemKitSettingsViewModel {
        TandemKitSettingsViewModel(
            pumpManager,
            nextStep: {},
            openPumpInformation: {},
            openNotifications: {},
            openInsulinType: {},
            openSoundSettings: {},
            openCartridgeChange: {},
            openFillTubing: {},
            openFillCannula: {},
            openCgmSettings: {},
            openControlIQSettings: {},
            openQuickBolus: {},
            openAlertSettings: {}
        )
    }
}
