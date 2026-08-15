@testable import TandemKit
import XCTest

/// Feature flags decide which surfaces the app offers, and they are stored in `rawState`, so two
/// things have to hold: an untouched install follows the declared default, and an explicit choice
/// survives the trip through `[String: Any]` and back.
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
        // Nothing is persisted until the user makes a choice, so a later change to a default moves
        // everyone who never touched the switch.
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
        // Explicitly off has to be distinguishable from never-set, otherwise a flag that later
        // defaults to on would silently switch back on for someone who turned it off.
        var flags = TandemFeatureFlags.default
        flags[.controlIQSupport] = false

        let raw = flags.rawValue
        XCTAssertEqual(raw["controlIQSupport"] as? Bool, false)

        let restored = try XCTUnwrap(TandemFeatureFlags(rawValue: raw))
        XCTAssertTrue(restored.isOverridden(.controlIQSupport))
    }

    func testFlagsFromANewerBuildArePreserved() throws {
        // Downgrading and upgrading again must not discard a choice this build cannot interpret.
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

    // MARK: - Settings screen gating

    /// The pump settings screen hides the gesture that switches the algorithm to Control-IQ while
    /// the flag is off; this pins the view model's backstop so no other caller can start the switch.
    func testSwitchToControlIQIsRefusedWhileTheFlagIsOff() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        // Both values present, so the only thing standing in the way is the flag.
        manager.state.controlIQWeightLbs = 154
        manager.state.controlIQTotalDailyInsulin = 42

        let viewModel = makeSettingsViewModel(manager)
        viewModel.attemptSwitchToControlIQ()

        XCTAssertFalse(viewModel.isCheckingCGMForCIQ)
        XCTAssertFalse(viewModel.showSwitchToCIQConfirm)
        XCTAssertFalse(viewModel.showControlIQValuesRequired)
        XCTAssertFalse(viewModel.controlIQSupportEnabled)
    }

    func testSettingsViewModelReportsTheFlagWhenItIsOn() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )
        manager.setFeatureFlag(.controlIQSupport, enabled: true)

        XCTAssertTrue(makeSettingsViewModel(manager).controlIQSupportEnabled)
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
