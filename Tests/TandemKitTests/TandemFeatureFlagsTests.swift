@testable import TandemKit
import XCTest

/// Two things have to hold: an untouched install follows the declared default, and an explicit
/// choice survives the trip through `rawState` and back.
@available(macOS 13.0, iOS 14.0, *) final class TandemFeatureFlagsTests: XCTestCase {
    // MARK: - Defaults

    func testControlIQSupportIsOffUntilSomeoneTurnsItOn() {
        let flags = TandemFeatureFlags.default

        XCTAssertFalse(flags.controlIQSupport)
        XCTAssertFalse(flags[.controlIQSupport])
        XCTAssertFalse(flags.isOverridden(.controlIQSupport))
    }

    func testEveryFlagAnswersWithItsDeclaredDefault() {
        let flags = TandemFeatureFlags.default

        for flag in TandemFeatureFlags.Flag.allCases {
            XCTAssertEqual(flags[flag], flag.defaultValue, "\(flag.rawValue) did not follow its default")
        }
    }

    func testClearingAnOverrideReturnsTheFlagToItsDefault() {
        var flags = TandemFeatureFlags.default
        flags[.controlIQSupport] = true
        XCTAssertTrue(flags.isOverridden(.controlIQSupport))

        flags.clear(.controlIQSupport)

        XCTAssertFalse(flags.isOverridden(.controlIQSupport))
        XCTAssertEqual(flags[.controlIQSupport], TandemFeatureFlags.Flag.controlIQSupport.defaultValue)
    }

    // MARK: - Raw value

    func testAnUntouchedFlagIsNotWrittenOut() {
        XCTAssertTrue(TandemFeatureFlags.default.rawValue.isEmpty)
    }

    func testExplicitChoiceRoundTrips() throws {
        var flags = TandemFeatureFlags.default
        flags[.controlIQSupport] = true

        let restored = try XCTUnwrap(TandemFeatureFlags(rawValue: flags.rawValue))

        XCTAssertTrue(restored.controlIQSupport)
        XCTAssertTrue(restored.isOverridden(.controlIQSupport))
    }

    func testTurningAFlagBackOffIsItselfPersisted() throws {
        // Explicitly off must stay distinguishable from never-set, or a flag that later defaults
        // to on would switch back on for someone who turned it off.
        var flags = TandemFeatureFlags.default
        flags[.controlIQSupport] = false

        let raw = flags.rawValue
        XCTAssertEqual(raw["controlIQSupport"] as? Bool, false)

        let restored = try XCTUnwrap(TandemFeatureFlags(rawValue: raw))
        XCTAssertTrue(restored.isOverridden(.controlIQSupport))
    }

    func testFlagsFromANewerBuildArePreserved() throws {
        let restored = try XCTUnwrap(TandemFeatureFlags(rawValue: [
            "controlIQSupport": true,
            "someFutureFlag": true
        ]))

        XCTAssertEqual(restored.rawValue["someFutureFlag"] as? Bool, true)
        XCTAssertTrue(restored.controlIQSupport)
    }

    func testNonBooleanValuesAreIgnoredRatherThanTrapping() throws {
        let restored = try XCTUnwrap(TandemFeatureFlags(rawValue: ["controlIQSupport": "yes please"]))

        XCTAssertFalse(restored.isOverridden(.controlIQSupport))
        XCTAssertFalse(restored.controlIQSupport)
    }

    // MARK: - Manager state persistence

    func testFlagsSurviveAManagerStateRoundTrip() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.controlIQSupport] = true

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertTrue(restored.featureFlags.controlIQSupport)
    }

    func testStateFromABuildWithoutFeatureFlagsDecodesToDefaults() {
        let state = TandemPumpManagerState(rawValue: [:])

        XCTAssertFalse(state.featureFlags.controlIQSupport)
        XCTAssertNil(state.rawValue["featureFlags"])
    }

    // MARK: - Pump manager

    func testSettingAFlagOnTheManagerPersistsAndReadsBack() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        XCTAssertFalse(manager.isFeatureEnabled(.controlIQSupport))

        manager.setFeatureFlag(.controlIQSupport, enabled: true)

        XCTAssertTrue(manager.isFeatureEnabled(.controlIQSupport))
        XCTAssertTrue(manager.state.featureFlags.controlIQSupport)

        let restored = TandemPumpManagerState(rawValue: manager.state.rawValue)
        XCTAssertTrue(restored.featureFlags.controlIQSupport)
    }

    // MARK: - Feature flags screen

    /// The screen hides the flag list behind a triple tap unless something is already on, so a flag
    /// that is enabled can never be left unreachable.
    func testTheFlagListIsShownWithoutTheTripleTapOnceAFlagIsOn() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        XCTAssertFalse(TandemKitFeatureFlagsViewModel(pumpManager: manager).hasEnabledFlag)

        manager.setFeatureFlag(.controlIQSupport, enabled: true)

        XCTAssertTrue(TandemKitFeatureFlagsViewModel(pumpManager: manager).hasEnabledFlag)
    }

    func testTheFlagsScreenWritesThroughToTheManager() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        let viewModel = TandemKitFeatureFlagsViewModel(pumpManager: manager)

        viewModel.setFlag(.quickBolusButtonSupport, enabled: true)

        XCTAssertTrue(viewModel.isEnabled(.quickBolusButtonSupport))
        XCTAssertTrue(manager.state.featureFlags.quickBolusButtonSupport)
    }

    // MARK: - Settings screen gating

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
