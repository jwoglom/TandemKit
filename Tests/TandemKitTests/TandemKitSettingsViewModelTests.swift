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

    func testSettingsViewModelReportsTheFlagsWhenTheyAreOn() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        manager.setFeatureFlag(.controlIQSupport, enabled: true)
        manager.setFeatureFlag(.quickBolusButtonSupport, enabled: true)

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertTrue(viewModel.controlIQSupportEnabled)
        XCTAssertTrue(viewModel.quickBolusButtonSupportEnabled)
    }

    func testSettingsViewModelHidesTheGatedRowsByDefault() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        let viewModel = makeSettingsViewModel(manager)

        XCTAssertFalse(viewModel.controlIQSupportEnabled)
        XCTAssertFalse(viewModel.quickBolusButtonSupportEnabled)
    }

    func testTheTempBasalCeilingWarningListsTheCappedTimes() throws {
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: .hours(6), value: 1.5)
        ]))
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(basalRateSchedule: schedule, maxBasalRateUnitsPerHour: 3.0),
            bluetooth: StubPumpBluetooth()
        )

        let warning = try XCTUnwrap(makeSettingsViewModel(manager).tempBasalCeilingWarning)

        XCTAssertTrue(warning.contains("00:00–06:00: 2.00 U/hr"), warning)
        XCTAssertFalse(warning.contains("06:00–24:00"), warning)
    }

    func testNoTempBasalCeilingWarningWhenTheMaxBasalFits() throws {
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)]))
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(basalRateSchedule: schedule, maxBasalRateUnitsPerHour: 2.5),
            bluetooth: StubPumpBluetooth()
        )

        XCTAssertNil(makeSettingsViewModel(manager).tempBasalCeilingWarning)
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
