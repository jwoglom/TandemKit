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

    func testHistoryBackfillAndDoseReportingAreOnUntilSomeoneTurnsThemOff() {
        let flags = TandemFeatureFlags.default

        XCTAssertTrue(flags.historyBackfill)
        XCTAssertFalse(flags.isOverridden(.historyBackfill))
        XCTAssertTrue(flags.historyDoseReporting)
        XCTAssertFalse(flags.isOverridden(.historyDoseReporting))
        XCTAssertFalse(flags.basalHistoryReporting)
    }

    func testHistoryBasalReportingNeedsTheBackfill() {
        var flags = TandemFeatureFlags.default
        flags[.basalHistoryReporting] = true
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
}
