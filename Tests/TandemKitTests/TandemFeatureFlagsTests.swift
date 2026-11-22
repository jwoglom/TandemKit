@testable import TandemKit
import XCTest

/// Two things have to hold: an untouched install follows the declared default, and an explicit
/// choice survives the trip through `rawState` and back.
@available(macOS 13.0, iOS 14.0, *) final class TandemFeatureFlagsTests: XCTestCase {
    // MARK: - Defaults

    func testEveryFlagIsOnUntilSomeoneTurnsItOff() {
        let flags = TandemFeatureFlags.default

        XCTAssertTrue(flags.controlIQSupport)
        XCTAssertTrue(flags.manualTempBasalSupport)
        XCTAssertTrue(flags.quickBolusButtonSupport)
        XCTAssertTrue(flags.historyBackfill)
        XCTAssertTrue(flags.historyDoseReporting)
        XCTAssertTrue(flags.basalHistoryReporting)
        for flag in TandemFeatureFlags.Flag.allCases {
            XCTAssertFalse(flags.isOverridden(flag), "\(flag.rawValue) was overridden")
        }
    }

    func testHistoryBasalReportingNeedsTheBackfill() {
        var flags = TandemFeatureFlags.default
        flags[.historyBackfill] = false
        XCTAssertFalse(flags.basalHistoryReporting)

        flags[.historyBackfill] = true
        XCTAssertTrue(flags.basalHistoryReporting)
    }

    func testTurningHistoryBackfillOffSurvivesTheRawStateRoundTrip() throws {
        var flags = TandemFeatureFlags.default
        flags[.historyBackfill] = false

        let restored = try XCTUnwrap(TandemFeatureFlags(rawValue: flags.rawValue))

        XCTAssertFalse(restored.historyBackfill)
    }

    func testEveryFlagAnswersWithItsDeclaredDefault() {
        let flags = TandemFeatureFlags.default

        for flag in TandemFeatureFlags.Flag.allCases {
            XCTAssertEqual(flags[flag], flag.defaultValue, "\(flag.rawValue) did not follow its default")
        }
    }

    func testClearingAnOverrideReturnsTheFlagToItsDefault() {
        var flags = TandemFeatureFlags.default
        flags[.controlIQSupport] = false
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
        flags[.controlIQSupport] = false

        let restored = try XCTUnwrap(TandemFeatureFlags(rawValue: flags.rawValue))

        XCTAssertFalse(restored.controlIQSupport)
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
        XCTAssertTrue(restored.controlIQSupport)
    }

    // MARK: - Manager state persistence

    func testFlagsSurviveAManagerStateRoundTrip() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.controlIQSupport] = false

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertFalse(restored.featureFlags.controlIQSupport)
    }

    func testStateFromABuildWithoutFeatureFlagsDecodesToDefaults() {
        let state = TandemPumpManagerState(rawValue: [:])

        XCTAssertTrue(state.featureFlags.controlIQSupport)
        XCTAssertTrue(state.featureFlags.manualTempBasalSupport)
        XCTAssertNil(state.rawValue["featureFlags"])
    }

    // MARK: - Pump manager

    func testSettingAFlagOnTheManagerPersistsAndReadsBack() {
        let manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth()
        )

        XCTAssertTrue(manager.isFeatureEnabled(.controlIQSupport))

        manager.setFeatureFlag(.controlIQSupport, enabled: false)

        XCTAssertFalse(manager.isFeatureEnabled(.controlIQSupport))
        XCTAssertFalse(manager.state.featureFlags.controlIQSupport)

        let restored = TandemPumpManagerState(rawValue: manager.state.rawValue)
        XCTAssertFalse(restored.featureFlags.controlIQSupport)
    }
}
