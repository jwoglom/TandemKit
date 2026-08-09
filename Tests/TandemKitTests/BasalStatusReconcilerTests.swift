import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Covers how basal delivery is tracked and reported to LoopKit between temp basals.
///
/// The regression these guard against (issue #211): after Loop switches to open loop it cancels
/// the temp basal and stops enacting new ones, and nothing was reported to LoopKit afterwards --
/// scheduled basal doses were zero-duration (LoopKit discards those), and a basal status read only
/// did anything when the *type* changed, so a move into the next segment of the pump's profile was
/// invisible. Loop's insulin graph and the rate on the pump screen both stayed on the last temp
/// basal.
final class BasalStatusReconcilerTests: XCTestCase {
    // MARK: - Transition rules

    func testRateChangeWithinScheduledBasalStartsANewDose() {
        let action = BasalStatusReconciler.action(
            pumpBasalType: .basal,
            pumpProfileBasalRate: 1.25,
            trackedType: .basal,
            trackedRate: 0.85
        )

        XCTAssertEqual(action, .startBasal(rate: 1.25))
    }

    func testUnchangedScheduledBasalOnlyRefreshes() {
        let action = BasalStatusReconciler.action(
            pumpBasalType: .basal,
            pumpProfileBasalRate: 0.85,
            trackedType: .basal,
            trackedRate: 0.85
        )

        XCTAssertEqual(action, .refresh)
    }

    /// Rates cross the wire in milliunits, so sub-milliunit differences are the same rate and must
    /// not churn out a new dose on every sync.
    func testSubMilliunitRateDifferenceIsNotARateChange() {
        let action = BasalStatusReconciler.action(
            pumpBasalType: .basal,
            pumpProfileBasalRate: 0.8501,
            trackedType: .basal,
            trackedRate: 0.85
        )

        XCTAssertEqual(action, .refresh)
    }

    func testTempBasalEndingStartsScheduledBasalAtThePumpsRate() {
        let action = BasalStatusReconciler.action(
            pumpBasalType: .basal,
            pumpProfileBasalRate: 1.1,
            trackedType: .tempBasal,
            trackedRate: 0
        )

        XCTAssertEqual(action, .startBasal(rate: 1.1))
    }

    /// A resume dose carries no rate, so the pump's profile rate has to replace it -- otherwise the
    /// pump screen reads "Profile Basal 0.00 U/hr" until the next segment boundary.
    func testResumeAdoptsThePumpsProfileRate() {
        let action = BasalStatusReconciler.action(
            pumpBasalType: .basal,
            pumpProfileBasalRate: 0.9,
            trackedType: .resume,
            trackedRate: 0
        )

        XCTAssertEqual(action, .startBasal(rate: 0.9))
    }

    func testSuspendIsPickedUpOnceAndThenRefreshed() {
        XCTAssertEqual(
            BasalStatusReconciler.action(
                pumpBasalType: .suspend,
                pumpProfileBasalRate: 0.85,
                trackedType: .basal,
                trackedRate: 0.85
            ),
            .startSuspend
        )

        XCTAssertEqual(
            BasalStatusReconciler.action(
                pumpBasalType: .suspend,
                pumpProfileBasalRate: 0.85,
                trackedType: .suspend,
                trackedRate: 0
            ),
            .refresh
        )
    }

    /// A basal status response has no duration in it, so a temp rate started on the pump cannot be
    /// turned into a dose here; the tracked dose is left alone rather than guessed at.
    func testTempRateWeDidNotProgramIsLeftAlone() {
        let action = BasalStatusReconciler.action(
            pumpBasalType: .tempBasal,
            pumpProfileBasalRate: 0.85,
            trackedType: .basal,
            trackedRate: 0.85
        )

        XCTAssertEqual(action, .untrackedTempBasal)
    }

    func testRunningTempBasalRefreshes() {
        let action = BasalStatusReconciler.action(
            pumpBasalType: .tempBasal,
            pumpProfileBasalRate: 0.85,
            trackedType: .tempBasal,
            trackedRate: 0.4
        )

        XCTAssertEqual(action, .refresh)
    }

    // MARK: - Scheduled basal doses

    /// LoopKit's `reconciled()` keeps a trailing basal dose only when it has run for some time, so
    /// a scheduled basal dose has to report an interval rather than an instant.
    func testScheduledBasalDoseReportsAnInterval() {
        let start = Date().addingTimeInterval(-TimeInterval.minutes(20))
        let dose = UnfinalizedDose(basalRate: 0.85, insulinType: nil, startDate: start)

        let ongoing = dose.toDoseEntry(isMutable: true)
        XCTAssertEqual(ongoing.type, .basal)
        XCTAssertTrue(ongoing.isMutable)
        XCTAssertGreaterThan(ongoing.endDate, ongoing.startDate)
        XCTAssertEqual(ongoing.unitsPerHour, 0.85, accuracy: 0.0001)

        let finalized = dose.toDoseEntry(isMutable: false, endDate: start.addingTimeInterval(TimeInterval.minutes(10)))
        XCTAssertFalse(finalized.isMutable)
        XCTAssertEqual(
            finalized.endDate.timeIntervalSince(finalized.startDate),
            TimeInterval.minutes(10),
            accuracy: 0.001
        )
    }

    /// An end date before the start (a clock adjustment, say) must not produce a negative interval.
    func testScheduledBasalDoseNeverEndsBeforeItStarts() {
        let start = Date()
        let dose = UnfinalizedDose(basalRate: 0.85, insulinType: nil, startDate: start)

        let entry = dose.toDoseEntry(isMutable: false, endDate: start.addingTimeInterval(-TimeInterval.minutes(5)))

        XCTAssertEqual(entry.endDate, entry.startDate)
    }

    // MARK: - Reported basal delivery state

    func testRunningTempBasalIsReportedAsTempBasal() {
        var state = makeState()
        state.basalDose = makeTempBasalDose()

        guard case .tempBasal = state.basalDeliveryState else {
            return XCTFail("Expected a running temp basal to be reported as .tempBasal")
        }
    }

    /// Once a temp rate runs past its programmed end the pump is back on its profile, whether or not
    /// basal status has been re-read. Reporting it as still running makes Loop show a temp basal
    /// that has finished, and makes it skip cancelling on the way to open loop.
    func testExpiredTempBasalIsReportedAsActiveBasal() {
        var state = makeState()
        let dose = makeTempBasalDose()
        dose.estimatedEndDate = Date().addingTimeInterval(-TimeInterval.minutes(1))
        state.basalDose = dose

        guard case let .active(date) = state.basalDeliveryState else {
            return XCTFail("Expected an expired temp basal to be reported as .active")
        }
        XCTAssertEqual(date, dose.estimatedEndDate)
    }

    private func makeTempBasalDose() -> UnfinalizedDose {
        UnfinalizedDose(
            tempRate: 0.4,
            duration: TimeInterval.minutes(30),
            automatic: true,
            insulinType: nil
        )
    }

    private func makeState() -> TandemPumpManagerState {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.85)])!
        return TandemPumpManagerState(basalRateSchedule: schedule)
    }
}
