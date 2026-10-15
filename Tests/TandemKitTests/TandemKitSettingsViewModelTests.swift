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
