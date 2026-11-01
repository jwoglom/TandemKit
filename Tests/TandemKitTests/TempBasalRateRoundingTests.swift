import LoopKit
@testable import TandemKit
import XCTest

/// The rate the driver enacts and reports never exceeds the rate that was requested — a host that
/// filters on it (Trio drops temp basals above its `maxBasal`) would otherwise discard the record.
/// The one exception is a percent the pump refuses as under its lowest rate, where the lowest
/// percent it accepts goes out instead.
@available(macOS 13.0, iOS 14.0, *) final class TempBasalRateRoundingTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A manager whose profile basal is a single all-day segment at `baseline`, which is what
    /// `getScheduledBasalRate()` reads.
    private func makeManager(baseline: Double) -> TandemPumpManager {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: baseline)])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func stubHappyPump(baseline: Double) {
        bluetooth.stubBasalPump(profileMilliunits: UInt32((baseline * 1000).rounded()))
    }

    private func enact(
        _ manager: TandemPumpManager,
        unitsPerHour: Double,
        duration: TimeInterval = .minutes(30)
    ) -> PumpManagerError? {
        var result: PumpManagerError?
        let completed = expectation(description: "enactTempBasal")
        manager.enactTempBasal(decisionId: nil, unitsPerHour: unitsPerHour, for: duration) {
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5.0)
        return result
    }

    /// The rate the driver reported to the host for the temp basal it just enacted.
    private func reportedTempBasalRate(_ delegate: MockPumpManagerDelegate) -> Double? {
        delegate.pumpEvents.compactMap(\.dose).last(where: { $0.type == .tempBasal })?.unitsPerHour
    }

    private func attach(_ manager: TandemPumpManager) -> (MockPumpManagerDelegate, DispatchQueue) {
        let delegate = MockPumpManagerDelegate()
        let queue = DispatchQueue(label: "temp-basal-rounding-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = queue
        queue.sync {}
        return (delegate, queue)
    }

    private var supportedRates: [Double] { TandemPumpCapabilities.supportedBasalRates }

    /// The grid rate a given percent delivers, by integer arithmetic on the pump's milliunits.
    private func rate(percent: Int, baseline: Double) -> Double {
        let gridMilliunits = TandemPumpCapabilities.milliunits(baseline) * percent / 1000 * 10
        return gridMilliunits < 100 ? 0 : Double(min(gridMilliunits, 15000)) / 1000
    }

    /// The highest rate any whole percent can deliver without exceeding `limit`. The rate is
    /// monotonic in the percent, so walking up from `start` finds it.
    private func bestAchievableRate(atOrBelow limit: Double, baseline: Double, from start: Int) -> Double {
        var percent = start
        while percent < TandemPumpManager.maximumTempBasalPercent,
              rate(percent: percent + 1, baseline: baseline) <= limit + 1e-9
        {
            percent += 1
        }
        return rate(percent: percent, baseline: baseline)
    }

    // MARK: - The reported rate never exceeds the request

    /// The case from the report: baseline 4.0 U/h with oref asking for exactly its 3.02 U/h
    /// maxBasal. Rounding to nearest gives 76% → 3.04, which Trio discards.
    func testIssueScenarioDoesNotOvershootTheRequest() {
        let manager = makeManager(baseline: 4.0)

        let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: 3.02, baseline: 4.0)

        XCTAssertEqual(percent, 75)
        XCTAssertEqual(rate, 3.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(rate, 3.02)
    }

    /// Sweeps every baseline/request pair the pump can express and asserts the invariant plus the
    /// bounds that keep the fix from being "just always deliver less". Where the pump would refuse
    /// the percent as under its lowest rate, the invariant gives way to the lowest percent it accepts.
    func testSweepNeverOvershootsAndStaysCloseToTheRequest() {
        let baselines: [Double] = [0.1, 0.25, 0.42, 0.48, 0.5, 0.58, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.5, 7.5, 9.9, 10.0, 15.0]

        for baseline in baselines {
            let manager = makeManager(baseline: baseline)
            let ceiling = min(15.0, baseline * Double(TandemPumpManager.maximumTempBasalPercent) / 100.0)
            let lowestAccepted = TandemPumpManager.minimumTempBasalPercent(baseline: baseline)

            for requested in supportedRates where requested > 0 && requested <= ceiling {
                let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: requested, baseline: baseline)

                XCTAssertGreaterThanOrEqual(percent, 0, "baseline \(baseline), requested \(requested)")
                XCTAssertLessThanOrEqual(
                    percent,
                    TandemPumpManager.maximumTempBasalPercent,
                    "baseline \(baseline), requested \(requested)"
                )
                XCTAssertTrue(
                    percent == 0 || percent >= lowestAccepted,
                    "the pump refuses this: baseline \(baseline), requested \(requested) -> \(percent)%"
                )

                // The percent and the reported rate must describe the same delivery.
                XCTAssertEqual(
                    rate,
                    self.rate(percent: percent, baseline: baseline),
                    accuracy: 1e-9,
                    "percent/rate disagree: baseline \(baseline), requested \(requested)"
                )

                let exact = baseline * Double(percent) / 100.0
                if percent == lowestAccepted, rate > requested + 1e-9 {
                    // Raised over a refused percent: by under a percent of the baseline, and nearer
                    // the request than 0% would have been.
                    XCTAssertLessThan(
                        exact - requested,
                        baseline / 100.0 + 1e-9,
                        "raised too far: baseline \(baseline), requested \(requested) -> \(percent)% = \(exact)"
                    )
                    XCTAssertLessThanOrEqual(
                        exact - requested,
                        requested,
                        "0% was nearer: baseline \(baseline), requested \(requested) -> \(percent)% = \(exact)"
                    )
                    continue
                }

                // The invariant this issue is about.
                XCTAssertLessThanOrEqual(
                    rate,
                    requested + 1e-9,
                    "overshoot: baseline \(baseline), requested \(requested) -> \(percent)% = \(rate)"
                )

                // Never below the best the pump could have done, by more than the half percent
                // the step-down gives back plus one grid step — so the fix cannot degenerate into
                // "always deliver less". Above a 2 U/h baseline this pins the exact optimum.
                let best = bestAchievableRate(atOrBelow: requested, baseline: baseline, from: percent)
                XCTAssertLessThanOrEqual(
                    rate,
                    best + 1e-9,
                    "beat the optimum?: baseline \(baseline), requested \(requested) -> \(percent)% = \(rate)"
                )
                XCTAssertLessThanOrEqual(
                    best - rate,
                    0.01 + baseline / 200.0 + 1e-9,
                    "undershoot vs optimum \(best): baseline \(baseline), requested \(requested) -> \(percent)% = \(rate)"
                )
            }
        }
    }

    /// A request the pump can hit exactly must not be stepped down "just in case".
    func testExactlyRepresentableRequestsKeepTheirPercent() {
        for baseline in [1.0, 2.0, 4.0, 10.0] {
            let manager = makeManager(baseline: baseline)

            for percent in stride(from: 0, through: 250, by: 5) {
                let exact = rate(percent: percent, baseline: baseline)
                guard exact > 0 else { continue }

                let (resolved, resolvedRate) = manager.tempBasalPercentAndRate(
                    requestedRate: exact,
                    baseline: baseline
                )

                XCTAssertEqual(resolvedRate, exact, accuracy: 1e-9, "baseline \(baseline), \(percent)%")
                // A lower percent may land on the same grid rate for small baselines; what matters
                // is that we never pay a grid step for a request the pump can hit.
                XCTAssertLessThanOrEqual(resolved, percent, "baseline \(baseline), \(percent)%")
            }
        }
    }

    func testRequestEqualToBaselineResolvesToOneHundredPercent() {
        let manager = makeManager(baseline: 1.35)

        let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: 1.35, baseline: 1.35)

        XCTAssertEqual(percent, 100)
        XCTAssertEqual(rate, 1.35, accuracy: 1e-9)
    }

    // MARK: - Under the pump's lowest rate

    /// The case from the field (Trio, a Mobi): oref asking a 0.58 U/hr profile for the 0.1 U/hr it
    /// was short of. 17% is nearest but works out to 0.0986 U/hr, which the pump refused with
    /// status 1 after the running temp had been stopped; 18% runs 0.1044 U/hr.
    func testTheLowestRateUnderAPointFiveEightProfileGoesOutAsEighteenPercent() {
        let manager = makeManager(baseline: 0.58)

        let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: 0.1, baseline: 0.58)

        XCTAssertEqual(percent, 18)
        XCTAssertEqual(rate, 0.1, accuracy: 1e-9)
    }

    /// 21% of 0.48 U/hr is 0.1008 U/hr, which the same pump ran: a nearest percent it accepts is kept.
    func testTheLowestRateUnderAPointFourEightProfileKeepsItsNearestPercent() {
        let manager = makeManager(baseline: 0.48)

        let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: 0.1, baseline: 0.48)

        XCTAssertEqual(percent, 21)
        XCTAssertEqual(rate, 0.1, accuracy: 1e-9)
    }

    /// 0.11 U/hr of 3 U/hr is nearest 4%, which overshoots to 0.12; the step down lands on 3%,
    /// 0.09 U/hr, which the pump refuses; so 4% it is.
    func testAStepDownOntoARefusedPercentComesBackUp() {
        let manager = makeManager(baseline: 3.0)

        let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: 0.11, baseline: 3.0)

        XCTAssertEqual(percent, 4)
        XCTAssertEqual(rate, 0.12, accuracy: 1e-9)
    }

    /// A request under the lowest rate itself is nearer 0% than any percent the pump accepts, and
    /// `enactTempBasal` floors it there before asking.
    func testARequestUnderTheLowestRateResolvesToZero() {
        let manager = makeManager(baseline: 0.58)

        for requested in [0.05, 0.06, 0.099] {
            let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: requested, baseline: 0.58)
            XCTAssertEqual(percent, 0, "requested \(requested)")
            XCTAssertEqual(rate, 0, "requested \(requested)")
        }
    }

    /// 20% of 0.499 U/hr is 99.8 mU/hr: under the minimum whether the pump truncates or not.
    func testTheLowestPercentFollowsThePumpsMilliunitArithmetic() {
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 0.58), 18)
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 0.48), 21)
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 0.5), 20)
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 0.499), 21)
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 0.1), 100)
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 9.9), 2)
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 10.0), 1)
        XCTAssertEqual(TandemPumpManager.minimumTempBasalPercent(baseline: 15.0), 1)
    }

    /// The field failure end to end: the stub pump refuses 17% of 0.58 U/hr as the Mobi did, so the
    /// enact only succeeds by sending 18%, and the host is told the 0.1 U/hr grid rate below it.
    func testEnactUnderAPointFiveEightProfileSendsEighteenPercentAndReportsTheLowestRate() throws {
        let manager = makeManager(baseline: 0.58)
        let (delegate, queue) = attach(manager)
        stubHappyPump(baseline: 0.58)

        XCTAssertNil(enact(manager, unitsPerHour: 0.1))
        queue.sync {}

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [18])
        XCTAssertEqual(try XCTUnwrap(reportedTempBasalRate(delegate)), 0.1, accuracy: 1e-9)
    }

    // MARK: - Float noise

    /// Hosts compute their rates: 0.57 + 0.01 is 0.5800000000000001 and 1.1 * 0.4 is
    /// 0.44000000000000006. Flooring onto the grid by raw comparison would drop each a step.
    func testARequestCarryingFloatNoiseResolvesToTheRateItMeans() {
        let manager = makeManager(baseline: 1.0)

        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: 0.57 + 0.01), 0.58)
        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: 1.1 * 0.4), 0.44)
        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: 0.58 * 50 / 100), 0.29)
        XCTAssertEqual(manager.roundToSupportedBasalRate(unitsPerHour: Double(Float(0.9))), 0.9)
        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: 0.1 + 0.2), 0.3)
        XCTAssertEqual(manager.roundToSupportedBolusVolume(units: Double(Float(1.15))), 1.15)
    }

    /// A request a hair over the scheduled rate is the scheduled rate: no 99% temp goes out for it.
    func testARequestANoiseAboveTheScheduledRateChangesNothing() throws {
        let manager = makeManager(baseline: 0.58)
        let (delegate, queue) = attach(manager)
        stubHappyPump(baseline: 0.58)

        XCTAssertNil(enact(manager, unitsPerHour: 0.57 + 0.01))
        queue.sync {}

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        let reported = try XCTUnwrap(delegate.pumpEvents.compactMap(\.dose).last(where: { $0.type == .basal })?.unitsPerHour)
        XCTAssertEqual(reported, 0.58)
    }

    // MARK: - Degenerate inputs

    func testNoBaselineResolvesToZero() {
        let manager = makeManager(baseline: 1.0)

        let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: 2.0, baseline: 0)

        XCTAssertEqual(percent, 0)
        XCTAssertEqual(rate, 0)
    }

    func testZeroAndNegativeRequestsResolveToZero() {
        let manager = makeManager(baseline: 2.0)

        for requested in [0.0, -0.5, -100.0] {
            let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: requested, baseline: 2.0)
            XCTAssertEqual(percent, 0, "requested \(requested)")
            XCTAssertEqual(rate, 0, "requested \(requested)")
        }
    }

    /// A request the pump cannot reach is capped, not stepped down: 250% is already below it.
    func testRequestAboveTheCeilingIsCappedAtMaximumPercent() {
        let manager = makeManager(baseline: 2.0)

        let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: 12.0, baseline: 2.0)

        XCTAssertEqual(percent, TandemPumpManager.maximumTempBasalPercent)
        XCTAssertEqual(rate, 5.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(rate, 12.0)
    }

    func testCeilingDetectionFollowsTheRoundedPercent() {
        XCTAssertTrue(TandemPumpManager.tempBasalExceedsCeiling(requestedRate: 3.0, baseline: 1.0))
        XCTAssertTrue(TandemPumpManager.tempBasalExceedsCeiling(requestedRate: 2.51, baseline: 1.0))
        XCTAssertFalse(TandemPumpManager.tempBasalExceedsCeiling(requestedRate: 2.5, baseline: 1.0))
        XCTAssertFalse(TandemPumpManager.tempBasalExceedsCeiling(requestedRate: 2.504, baseline: 1.0))
        XCTAssertFalse(TandemPumpManager.tempBasalExceedsCeiling(requestedRate: 3.0, baseline: 0))
        XCTAssertFalse(TandemPumpManager.tempBasalExceedsCeiling(requestedRate: 0, baseline: 1.0))
    }

    /// The pump refuses a percent above 250, so the request is cut, and the host is told what runs.
    func testEnactAboveTheCeilingSendsTheMaximumPercentAndReportsWhatItDelivers() throws {
        let manager = makeManager(baseline: 1.0)
        let (delegate, queue) = attach(manager)
        stubHappyPump(baseline: 1.0)

        XCTAssertNil(enact(manager, unitsPerHour: 3.0))
        queue.sync {}

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [TandemPumpManager.maximumTempBasalPercent])
        XCTAssertEqual(try XCTUnwrap(reportedTempBasalRate(delegate)), 2.5, accuracy: 1e-9)
    }

    /// Baselines below 1 U/h quantise finer than the 0.01 U/h grid, so several percents share a
    /// rate. The resolved rate must still never exceed the request.
    func testSubUnitBaselineStillRespectsTheRequest() {
        let manager = makeManager(baseline: 0.15)

        for requested in [0.11, 0.14, 0.15, 0.16, 0.29, 0.37] {
            let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: requested, baseline: 0.15)
            XCTAssertLessThanOrEqual(rate, requested + 1e-9, "requested \(requested) -> \(percent)% = \(rate)")
        }
    }

    // MARK: - Delivered units

    /// 1.13 U/hr for 20 minutes is 0.37666… U.
    func testAFinalizedTempBasalsDeliveredUnitsIsOnThePumpsMilliunitIncrement() throws {
        let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let dose = UnfinalizedDose(tempRate: 1.13, duration: .minutes(30), automatic: true, insulinType: nil, startDate: start)

        let entry = dose.toDoseEntry(isMutable: false, endDate: start.addingTimeInterval(.minutes(20)))

        XCTAssertEqual(try XCTUnwrap(entry.deliveredUnits), 0.377, accuracy: 1e-12)
    }

    // MARK: - End to end through enactTempBasal

    /// The whole point of the fix: the dose handed to the host carries a rate the host's own
    /// `maxBasal` filter will accept.
    func testEnactReportsARateAtOrBelowTheRequest() throws {
        let manager = makeManager(baseline: 4.0)
        let (delegate, queue) = attach(manager)
        stubHappyPump(baseline: 4.0)

        XCTAssertNil(enact(manager, unitsPerHour: 3.02))
        queue.sync {}

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [75])
        let reported = try XCTUnwrap(reportedTempBasalRate(delegate))
        XCTAssertEqual(reported, 3.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(reported, 3.02)
    }

    /// Just under the baseline, nearest-percent rounding used to land on 100% — which takes the
    /// "nothing to change" path and reports the *scheduled* rate, above what was asked for. The
    /// step-down has to apply there too, so a real temp rate goes out.
    func testJustBelowBaselineEnactsATempRateInsteadOfReportingTheScheduledRate() throws {
        let manager = makeManager(baseline: 2.0)
        let (delegate, queue) = attach(manager)
        stubHappyPump(baseline: 2.0)

        XCTAssertNil(enact(manager, unitsPerHour: 1.99))
        queue.sync {}

        XCTAssertEqual(bluetooth.sent(SetTempRateRequest.self).map(\.percent), [99])
        let reported = try XCTUnwrap(reportedTempBasalRate(delegate))
        XCTAssertEqual(reported, 1.98, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(reported, 1.99)
    }

    /// A request that really is the scheduled rate still short-circuits — the step-down must not
    /// turn a no-op into pump traffic.
    func testRequestEqualToScheduledRateStillSkipsTheTempRate() throws {
        let manager = makeManager(baseline: 2.0)
        let (delegate, queue) = attach(manager)
        stubHappyPump(baseline: 2.0)

        XCTAssertNil(enact(manager, unitsPerHour: 2.0))
        queue.sync {}

        XCTAssertFalse(bluetooth.didSend(SetTempRateRequest.self))
        let reported = try XCTUnwrap(
            delegate.pumpEvents.compactMap(\.dose).last(where: { $0.type == .basal })?.unitsPerHour
        )
        XCTAssertEqual(reported, 2.0, accuracy: 1e-9)
    }

    /// Models Trio's filter directly: every enacted temp basal must survive `unitsPerHour <=
    /// maxBasal` when oref asks for exactly `maxBasal`.
    func testEnactedRateSurvivesAHostMaxBasalFilter() {
        // Baselines at or above 2 U/h are where the old overshoot cleared the 0.01 U/h grid.
        for baseline in [2.0, 2.5, 3.0, 4.0, 6.0, 10.0] {
            for maxBasal in [baseline * 0.755, baseline * 0.995, baseline, baseline * 1.505] {
                let requested = supportedRates.last(where: { $0 <= maxBasal }) ?? 0
                guard requested > 0 else { continue }

                bluetooth = StubPumpBluetooth()
                let manager = makeManager(baseline: baseline)
                let (delegate, queue) = attach(manager)
                stubHappyPump(baseline: baseline)

                XCTAssertNil(enact(manager, unitsPerHour: requested), "baseline \(baseline), max \(requested)")
                queue.sync {}

                // Either a temp rate went out, or the request matched the scheduled rate and the
                // driver reported that instead. Both are rates the host will filter.
                let reported = delegate.pumpEvents.compactMap(\.dose)
                    .last(where: { $0.type == .tempBasal || $0.type == .basal })?
                    .unitsPerHour
                XCTAssertNotNil(reported, "baseline \(baseline), max \(requested)")
                XCTAssertLessThanOrEqual(
                    reported ?? .infinity,
                    requested + 1e-9,
                    "Trio would drop this record: baseline \(baseline), max \(requested), reported \(reported ?? -1)"
                )
            }
        }
    }
}
