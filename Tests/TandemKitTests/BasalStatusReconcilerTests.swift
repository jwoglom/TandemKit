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
@available(macOS 13.0, iOS 14.0, *) final class BasalStatusReconcilerTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

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

    // MARK: - What reaches LoopKit

    /// The temp basal has to be closed out at the moment it stopped, and scheduled basal has to be
    /// reported in its place -- LoopKit only fills in scheduled delivery *between* the doses it was
    /// given, so without the second dose the record just ends at the temp basal.
    func testTempBasalEndingReportsTheTruncatedTempAndScheduledBasal() {
        let startedAt = Date().addingTimeInterval(-TimeInterval.minutes(10))
        let tempBasal = makeTempBasalDose(
            startDate: startedAt,
            duration: TimeInterval.minutes(30),
            rate: 0
        )
        let manager = makeManager(basalDose: tempBasal)
        let delegate = attachDelegate(to: manager)
        stubBasalStatus(profileBasalRateMilliunits: 850, basalModifiedBitmask: 0)

        let reported = expectation(description: "pump events reported")
        delegate.didReceivePumpEventsExpectation = reported
        manager.fetchBasalStatus()
        wait(for: [reported], timeout: 2.0)

        let doses = delegate.pumpEvents.compactMap(\.dose)

        guard let temp = doses.first(where: { $0.type == .tempBasal }) else {
            return XCTFail("Expected the temp basal to be closed out, got \(doses)")
        }
        XCTAssertFalse(temp.isMutable, "A temp basal that has stopped is no longer pending")
        XCTAssertEqual(temp.endDate.timeIntervalSince(startedAt), TimeInterval.minutes(10), accuracy: 5)

        guard let basal = doses.first(where: { $0.type == .basal }) else {
            return XCTFail("Expected scheduled basal to be reported, got \(doses)")
        }
        XCTAssertEqual(basal.unitsPerHour, 0.85, accuracy: 0.0001)

        XCTAssertEqual(manager.state.basalDose.type, .basal)
        XCTAssertEqual(manager.state.basalDose.value, 0.85, accuracy: 0.0001)
    }

    /// The open-loop case: nothing about basal delivery changed, and the running dose still has to
    /// be re-reported so the record -- and Loop's insulin graph -- keeps up with the clock. This
    /// used to report nothing at all.
    func testUnchangedScheduledBasalIsStillReported() {
        let startedAt = Date().addingTimeInterval(-TimeInterval.minutes(10))
        let manager = makeManager(basalDose: makeScheduledBasalDose(startDate: startedAt, rate: 0.85))
        let delegate = attachDelegate(to: manager)
        stubBasalStatus(profileBasalRateMilliunits: 850, basalModifiedBitmask: 0)

        let reported = expectation(description: "pump events reported")
        delegate.didReceivePumpEventsExpectation = reported
        manager.fetchBasalStatus()
        wait(for: [reported], timeout: 2.0)

        let doses = delegate.pumpEvents.compactMap(\.dose)
        XCTAssertEqual(doses.count, 1, "got \(doses)")

        guard let basal = doses.first else {
            return XCTFail("Expected the running scheduled basal to be reported")
        }
        XCTAssertEqual(basal.type, .basal)
        XCTAssertTrue(basal.isMutable, "The dose is still running, so it is still pending")
        XCTAssertEqual(basal.startDate, startedAt)
        XCTAssertEqual(basal.endDate.timeIntervalSince(startedAt), TimeInterval.minutes(10), accuracy: 5)

        // The same dose keeps running; it is grown, not replaced.
        XCTAssertEqual(manager.state.basalDose.startDate, startedAt)
    }

    /// Crossing into the next segment of the pump's own profile is a rate change with no type
    /// change, which used to go unnoticed -- leaving the pump screen on the rate from whenever the
    /// dose happened to be created.
    func testProfileSegmentChangeReportsTheNewRate() {
        let startedAt = Date().addingTimeInterval(-TimeInterval.minutes(30))
        let manager = makeManager(basalDose: makeScheduledBasalDose(startDate: startedAt, rate: 0.85))
        let delegate = attachDelegate(to: manager)
        stubBasalStatus(profileBasalRateMilliunits: 1200, basalModifiedBitmask: 0)

        let reported = expectation(description: "pump events reported")
        delegate.didReceivePumpEventsExpectation = reported
        manager.fetchBasalStatus()
        wait(for: [reported], timeout: 2.0)

        let doses = delegate.pumpEvents.compactMap(\.dose)
        XCTAssertEqual(doses.count, 2, "got \(doses)")

        let finished = doses.first { !$0.isMutable }
        XCTAssertEqual(finished?.unitsPerHour ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(finished?.startDate, startedAt)

        let started = doses.first { $0.isMutable }
        XCTAssertEqual(started?.unitsPerHour ?? 0, 1.2, accuracy: 0.0001)

        XCTAssertEqual(manager.state.basalDose.value, 1.2, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func makeManager(basalDose: UnfinalizedDose) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0.85)])!
        state.basalDose = basalDose
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func attachDelegate(to manager: TandemPumpManager) -> MockPumpManagerDelegate {
        let delegate = MockPumpManagerDelegate()
        manager.delegateQueue = DispatchQueue(label: "basal-status-test")
        manager.pumpManagerDelegate = delegate
        return delegate
    }

    private func stubBasalStatus(profileBasalRateMilliunits: UInt32, basalModifiedBitmask: Int) {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: profileBasalRateMilliunits,
            currentBasalRate: profileBasalRateMilliunits,
            basalModifiedBitmask: basalModifiedBitmask
        ))
    }

    /// Built from a raw value because the convenience initializers always start the dose now, and
    /// these tests need one that has already been running.
    private func makeTempBasalDose(startDate: Date, duration: TimeInterval, rate: Double) -> UnfinalizedDose {
        makeDose(type: .tempBasal, startDate: startDate, endDate: startDate.addingTimeInterval(duration), rate: rate)
    }

    private func makeScheduledBasalDose(startDate: Date, rate: Double) -> UnfinalizedDose {
        makeDose(type: .basal, startDate: startDate, endDate: startDate, rate: rate)
    }

    private func makeDose(type: DoseType, startDate: Date, endDate: Date, rate: Double) -> UnfinalizedDose {
        UnfinalizedDose(rawValue: [
            "type": type.rawValue,
            "value": rate,
            "startDate": startDate,
            "estimatedEndDate": endDate,
            "deliveredUnits": 0.0,
            "automatic": true
        ])!
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
