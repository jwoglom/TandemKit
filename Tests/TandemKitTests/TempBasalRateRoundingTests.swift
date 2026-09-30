import LoopKit
@testable import TandemKit
import XCTest

/// The rate the driver enacts and reports never exceeds the rate that was requested — a host that
/// filters on it (Trio drops temp basals above its `maxBasal`) would otherwise discard the record.
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

    /// Stubs the pump traffic `enactTempBasal` needs: no temp rate currently running, and a pump
    /// that accepts whatever percent it is given.
    private func stubHappyPump() {
        bluetooth.stub(CurrentBasalStatusRequest.self, with: CurrentBasalStatusResponse(
            profileBasalRate: 0,
            currentBasalRate: 0,
            basalModifiedBitmask: 0
        ))
        bluetooth.stub(SetTempRateRequest.self, with: SetTempRateResponse(status: 0, tempRateId: 42))
        bluetooth.stub(StopTempRateRequest.self, with: StopTempRateResponse(status: 0, tempRateId: 42))
    }

    private func enact(
        _ manager: TandemPumpManager,
        unitsPerHour: Double,
        duration: TimeInterval = .minutes(30)
    ) -> PumpManagerError? {
        var result: PumpManagerError?
        let completed = expectation(description: "enactTempBasal")
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) {
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

    /// The rate a given percent actually delivers, computed the way the driver does.
    private func rate(percent: Int, baseline: Double) -> Double {
        supportedRates.last(where: { $0 <= baseline * Double(percent) / 100.0 }) ?? 0
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
    /// bounds that keep the fix from being "just always deliver less".
    func testSweepNeverOvershootsAndStaysCloseToTheRequest() {
        let baselines: [Double] = [0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.5, 7.5, 10.0, 15.0]

        for baseline in baselines {
            let manager = makeManager(baseline: baseline)
            let ceiling = min(15.0, baseline * Double(TandemPumpManager.maximumTempBasalPercent) / 100.0)

            for requested in supportedRates where requested > 0 && requested <= ceiling {
                let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: requested, baseline: baseline)

                XCTAssertGreaterThanOrEqual(percent, 0, "baseline \(baseline), requested \(requested)")
                XCTAssertLessThanOrEqual(
                    percent,
                    TandemPumpManager.maximumTempBasalPercent,
                    "baseline \(baseline), requested \(requested)"
                )

                // The invariant this issue is about.
                XCTAssertLessThanOrEqual(
                    rate,
                    requested + 1e-9,
                    "overshoot: baseline \(baseline), requested \(requested) -> \(percent)% = \(rate)"
                )

                // The percent and the reported rate must describe the same delivery.
                XCTAssertEqual(
                    rate,
                    self.rate(percent: percent, baseline: baseline),
                    accuracy: 1e-9,
                    "percent/rate disagree: baseline \(baseline), requested \(requested)"
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

    /// Baselines below 1 U/h quantise finer than the 0.01 U/h grid, so several percents share a
    /// rate. The resolved rate must still never exceed the request.
    func testSubUnitBaselineStillRespectsTheRequest() {
        let manager = makeManager(baseline: 0.15)

        for requested in [0.11, 0.14, 0.15, 0.16, 0.29, 0.37] {
            let (percent, rate) = manager.tempBasalPercentAndRate(requestedRate: requested, baseline: 0.15)
            XCTAssertLessThanOrEqual(rate, requested + 1e-9, "requested \(requested) -> \(percent)% = \(rate)")
        }
    }

    // MARK: - End to end through enactTempBasal

    /// The whole point of the fix: the dose handed to the host carries a rate the host's own
    /// `maxBasal` filter will accept.
    func testEnactReportsARateAtOrBelowTheRequest() throws {
        let manager = makeManager(baseline: 4.0)
        let (delegate, queue) = attach(manager)
        stubHappyPump()

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
        stubHappyPump()

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
        stubHappyPump()

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
                stubHappyPump()

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
