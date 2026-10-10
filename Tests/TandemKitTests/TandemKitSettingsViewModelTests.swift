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
