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

    func testSettingsViewModelReportsTheFlagsWhenTheyAreOn() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        manager.setFeatureFlag(.controlIQSupport, enabled: true)

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertTrue(viewModel.controlIQSupportEnabled)
        XCTAssertTrue(viewModel.quickBolusButtonSupportEnabled)
    }

    func testSettingsViewModelHidesTheControlIQRowByDefaultAndShowsTheQuickBolusRow() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertFalse(viewModel.controlIQSupportEnabled)
        XCTAssertTrue(viewModel.quickBolusButtonSupportEnabled)
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
