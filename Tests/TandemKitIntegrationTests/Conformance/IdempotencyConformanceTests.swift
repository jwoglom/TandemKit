import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Group C of `docs/conformance-test-plan.md`: idempotency and complete batches.
///
/// The guide rules under test are §3 (report-or-delete: a mutable dose omitted from a complete
/// batch is deleted), §5 (`replacePendingEvents` means "this is the whole pending set"), §6 (the
/// trust boundary advances on every sync with the pump and never past one the pump did not answer)
/// and §11's two testing recommendations — re-report an in-progress dose many times and confirm it
/// stays one dose with an identical `raw`, and confirm an empty sync still calls the delegate.
/// Audit points P04, P06, P17, P18, P01 and G04.
///
/// Every scenario asserts through both host oracles and the delegate journal, and ends by diffing
/// the oracle's ledger against the pump's own record. Assertions the driver is known to fail are
/// kept as the guide demands and wrapped in a strict `XCTExpectFailure` naming the issue, so the
/// fix turns them into unexpected passes.
final class IdempotencyConformanceTests: ConformanceTestCase {
    /// 0.02 U/s: a 5 U bolus takes 250 s of pump time, longer than any scenario here advances the
    /// clock, so the pump is still delivering at every sync.
    private static let slowBolusRate = 0.02
    private static let bolusUnits = 5.0
    /// The scheduled rate both sides agree on: the driver refuses a temp basal without one of its
    /// own, and the pump applies the commanded percentage to its profile rate.
    private static let scheduledBasalRate = 1.0
    private static let tempBasalRate = 2.0

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The base case stops at the first failure. These scenarios repeat a report many times and
        // keep asserting after a known non-conformance has been recorded as an expected failure, so
        // stopping there would silently cut the scenario short.
        continueAfterFailure = true
        let client = harness.client
        addTeardownBlock { [weak self] in
            // The driver goes first: putting delivery back raises qualifying events, and a driver
            // still attached would answer them — leaving the deactivation handshake queued behind a
            // fetch and the link still up when the base teardown checks it.
            try? self?.shutDownDriver()

            // `harness.reset()` puts the link, the auth and the clock back, but not delivery: a
            // bolus, temp rate or suspend this test left running would be the *next* test's first
            // observed transition, and would show up in its batches as a dose of its own.
            guard let snapshot = try? client.snapshot() else { return }
            if snapshot.bolus.active { _ = try? client.abortBolus() }
            if snapshot.basal.tempActive { _ = try? client.stopTempBasal() }
            if snapshot.basal.suspended { _ = try? client.resume() }
        }
    }

    // MARK: - C1 (§9 item 4, §11 idempotency; P04-1, P06-1, P17-1; #330)

    func testRunningBolusIsReportedInEveryBatchUnderOneIdentity() throws {
        let driver = try startPairedDriver()
        _ = try harness.client.setState(["bolus_rate_units_per_second": Self.slowBolusRate])

        let beforeEnact = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId, "the driver must track the bolus it started")
        let started = try XCTUnwrap(
            newBatches(since: beforeEnact).flatMap(\.events).first { $0.dose?.type == .bolus },
            "guide §10: the bolus must be registered before it can go missing"
        )
        XCTAssertEqual(started.dose?.isMutable, true, "a bolus that is still delivering is mutable")
        let raw = started.raw

        // A fixed instant to read IOB at: the dose never changes while it runs, so any movement is
        // a second copy of it or a vanished one, not pharmacology.
        let iobInstant = clock.now.addingTimeInterval(.minutes(30))
        var firstIOB: Double?

        for round in 1 ... 8 {
            // 8 × 15 s = 120 s, inside both the pump's 250 s delivery and the driver's own
            // 5 U / bolusSpeedUnder10U = 144 s estimate, so no sync reconciles it as stale.
            try clock.advanceBoth(seconds: 15, ticks: 3)
            let before = allPumpEventBatches.count
            _ = try sync()

            let snapshot = try harness.client.snapshot()
            XCTAssertTrue(snapshot.bolus.active, "round \(round): the pump must still be delivering")
            XCTAssertEqual(snapshot.bolus.bolusId, bolusId)

            let batches = newBatches(since: before)
            XCTAssertFalse(batches.isEmpty, "round \(round): a sync with the pump must report something")

            // §5: a batch that claims to be the complete pending set must carry the live bolus.
            for batch in batches where batch.replacePendingEvents {
                XCTAssertTrue(
                    batch.events.contains { $0.raw == raw },
                    "round \(round): a replacePendingEvents batch without the running bolus deletes it: "
                        + describe(batch)
                )
            }
            // §11 idempotency: every report of this bolus is byte-identical.
            for event in batches.flatMap(\.events) where event.dose?.type == .bolus {
                XCTAssertEqual(
                    event.raw, raw,
                    "round \(round): the bolus changed identity mid-delivery: \(LoopDoseStoreOracle.describe(event.raw))"
                )
            }

            XCTExpectFailure(
                "jwoglom/TandemKit#330: the running bolus is never re-reported — the driver reports it once at "
                    + "enact and then keeps the host's copy alive only by never sending a complete batch"
            ) {
                XCTAssertTrue(
                    batches.contains { batch in
                        batch.events.contains { $0.raw == raw && $0.dose?.isMutable == true }
                    },
                    "round \(round): guide §9 item 4 — an in-progress dose is re-reported on every sync until it "
                        + "finalizes; batches were \(batches.map(describe))"
                )
            }

            // Host side: one dose, still mutable, not deleted, in both hosts.
            let (loop, trio) = feedOracles()
            loop.assertNoDuplicates("round \(round)")
            let stored = try XCTUnwrap(loop.assertSingleDose(raw: raw, "round \(round)"))
            XCTAssertTrue(stored.isMutable, "round \(round): \(LoopDoseStoreOracle.describe(stored))")
            XCTAssertEqual(stored.value, Self.bolusUnits, accuracy: 0.0005, "round \(round): value is the programmed amount")
            XCTAssertNil(stored.dose.deliveredUnits, "round \(round): nothing is delivered until the pump says so")
            XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1, "round \(round): \(loop.doses.map(LoopDoseStoreOracle.describe))")
            XCTAssertEqual(trio.boluses.count, 1, "round \(round): Trio dedups by (date, type): \(trio.boluses)")

            let iob = loop.iob(at: iobInstant)
            if let firstIOB {
                XCTAssertEqual(iob, firstIOB, accuracy: 1e-9, "round \(round): IOB drifted from a duplicate or a lost dose")
            } else {
                XCTAssertGreaterThan(iob, 0, "the reported bolus must contribute IOB")
                firstIOB = iob
            }
        }

        let (loop, _) = feedOracles()
        let timeline = try timeline()
        let pumpBolus = try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId }, "timeline: \(timeline.boluses)")
        XCTAssertFalse(pumpBolus.isFinished, "the pump is still delivering")
        timeline.assertMatches(loop, tolerance: .exact, "after eight syncs inside one bolus")
    }

    // MARK: - C2 (§9 item 4, §11 idempotency; P04-3, P17-2)

    func testRunningTempBasalKeepsOneIdentityAndItsScheduledEnd() throws {
        let driver = try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)

        let beforeEnact = allPumpEventBatches.count
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: .minutes(60)))
        let started = try XCTUnwrap(
            newBatches(since: beforeEnact).flatMap(\.events).first { $0.dose?.type == .tempBasal },
            "the temp basal must be reported when it is enacted"
        )
        XCTAssertEqual(started.dose?.isMutable, true)
        let raw = started.raw
        let scheduledEnd = try XCTUnwrap(started.dose?.endDate)
        let tempStart = try XCTUnwrap(started.dose?.startDate)
        XCTAssertEqual(
            scheduledEnd.timeIntervalSince(tempStart),
            .minutes(60),
            accuracy: 1,
            "a mutable temp basal runs to its scheduled end"
        )
        XCTAssertEqual(driver.manager.state.basalDose.type, .tempBasal)

        for round in 1 ... 6 {
            try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
            let before = allPumpEventBatches.count
            _ = try sync()

            XCTAssertTrue(try harness.client.snapshot().basal.tempActive, "round \(round): the pump's temp rate must still run")
            let batches = newBatches(since: before)
            XCTAssertFalse(batches.isEmpty, "round \(round): a sync with the pump must report something")

            for event in batches.flatMap(\.events) where event.dose?.type == .tempBasal {
                XCTAssertEqual(
                    event.raw, raw,
                    "round \(round): the temp basal changed identity while it ran: \(LoopDoseStoreOracle.describe(event.raw))"
                )
            }
            for batch in batches where batch.replacePendingEvents {
                XCTAssertTrue(
                    batch.events.contains { $0.raw == raw },
                    "round \(round): a complete batch without the live temp basal deletes it: \(describe(batch))"
                )
            }

            XCTExpectFailure(
                "TandemKit audit P04-3 (no issue filed; the sibling of jwoglom/TandemKit#330 for the temp basal): "
                    + "a running temp basal is not re-reported on routine syncs — fetchBasalStatus emits only on a "
                    + "basal-type change"
            ) {
                XCTAssertTrue(
                    batches.contains { batch in
                        batch.events.contains { $0.raw == raw && $0.dose?.isMutable == true }
                    },
                    "round \(round): guide §9 item 4 — the live temp basal is re-reported on every sync"
                )
            }

            let (loop, trio) = feedOracles()
            loop.assertNoDuplicates("round \(round)")
            let stored = try XCTUnwrap(loop.assertSingleDose(raw: raw, "round \(round)"))
            XCTAssertTrue(stored.isMutable, "round \(round): \(LoopDoseStoreOracle.describe(stored))")
            XCTAssertEqual(stored.dose.endDate, scheduledEnd, "round \(round): a mutable temp basal keeps its scheduled end")
            XCTAssertEqual(stored.dose.unitsPerHour, Self.tempBasalRate, accuracy: 0.005, "round \(round)")
            XCTAssertEqual(
                loop.doses.filter { $0.dose.type == .tempBasal }.count, 1,
                "round \(round): \(loop.doses.map(LoopDoseStoreOracle.describe))"
            )
            XCTAssertEqual(trio.tempBasals.count, 1, "round \(round): Trio holds one temp basal row: \(trio.tempBasals)")
        }

        let (loop, _) = feedOracles()
        let timeline = try timeline()
        let temp = try XCTUnwrap(timeline.tempRates.first, "the pump must hold the temp rate: \(timeline.tempRates)")
        XCTAssertFalse(temp.isFinished, "30 minutes into a 60 minute temp rate it is still running")
        XCTAssertEqual(temp.rate ?? 0, Self.tempBasalRate, accuracy: 0.005, "the pump's own rate")
        timeline.assertMatches(loop, tolerance: .exact, "after six syncs inside one temp basal")
    }

    // MARK: - C3 (§3 report-or-delete, §5; P04-1, P04-4, P06-1, P13-7; #330, #344)

    func testCompleteBatchCarriesEveryLiveMutableDose() throws {
        let driver = try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        _ = try harness.client.setState(["bolus_rate_units_per_second": Self.slowBolusRate])

        // Temp basal first: the driver refuses to enact one while a bolus is running.
        let beforeTemp = allPumpEventBatches.count
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: .minutes(60)))
        let tempEvent = try XCTUnwrap(newBatches(since: beforeTemp).flatMap(\.events).first { $0.dose?.type == .tempBasal })
        let tempRaw = tempEvent.raw

        let beforeBolus = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let bolusEvent = try XCTUnwrap(newBatches(since: beforeBolus).flatMap(\.events).first { $0.dose?.type == .bolus })
        let bolusRaw = bolusEvent.raw

        // Both live at the host before anything stops.
        let live = feedOracles().loop
        XCTAssertEqual(live.mutableDoses.count, 2, "two mutable doses are outstanding: \(live.doses.map(LoopDoseStoreOracle.describe))")

        // Two minutes in: 2.4 U of the bolus and 0.067 U of the temp rate have gone in, and both are
        // still inside the driver's own estimate for the bolus (144 s + a 30 s grace), so the sync
        // below is a report of live delivery rather than a reconciliation of a stale one.
        try clock.advanceBoth(seconds: .minutes(2), ticks: 12)
        XCTAssertTrue(try harness.client.snapshot().bolus.active)

        // The pump stops delivery on its own. No clock movement between the stop and the sync, so
        // the driver's detection time is the pump's stop time and the timeline diff is about
        // contents, not dating (#333 is group D's scenario). The index is taken before the suspend
        // because the pump raises qualifying events for it: some of the reporting can happen before
        // the explicit sync runs.
        let beforeSuspendSync = allPumpEventBatches.count
        _ = try harness.client.suspend(reason: "user")
        _ = try sync()
        let suspendBatches = newBatches(since: beforeSuspendSync)

        let suspendEvent = try XCTUnwrap(
            suspendBatches.flatMap(\.events).first { $0.dose?.type == .suspend },
            "guide §10: a suspend is emitted whenever delivery actually stops; batches were \(suspendBatches.map(describe))"
        )
        XCTAssertEqual(suspendEvent.dose?.isMutable, false, "a suspend is a point event")

        let completeBatches = suspendBatches.filter(\.replacePendingEvents)
        XCTAssertFalse(
            completeBatches.isEmpty,
            "the suspend is appended with replacePendingEvents: true; batches were \(suspendBatches.map(describe))"
        )
        XCTAssertTrue(
            completeBatches.contains { batch in batch.events.contains { $0.dose?.type == .tempBasal } },
            "a complete batch must account for the temp basal the suspend ended: \(completeBatches.map(describe))"
        )

        // §3 and §5 together, checked against what the host actually held when each batch arrived
        // rather than against one batch in isolation: replaying the journal in order, no batch that
        // claims to be the complete pending set may leave out a dose the host is still holding as
        // mutable — that is the deletion.
        XCTExpectFailure(
            "jwoglom/TandemKit#330 (the complete batch builder never returns state.bolusDose) and "
                + "jwoglom/TandemKit#344 (the temp basal is re-keyed when it ends early, so finalizing it does not "
                + "match the mutable row the host holds): a complete batch drops a live mutable dose"
        ) {
            let omissions = completeBatchOmissions()
            XCTAssertTrue(
                omissions.isEmpty,
                "guide §3/§5: nothing live may be dropped by silence:\n" + omissions.joined(separator: "\n")
            )
        }

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("after a pump-side suspend during a bolus and a temp basal")
        XCTAssertEqual(
            loop.doses.filter { $0.dose.type == .bolus }.count, 1,
            "the partial bolus is accounted for exactly once: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        XCTAssertEqual(
            loop.doses.filter { $0.dose.type == .suspend }.count, 1,
            "one suspend: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        XCTAssertEqual(trio.boluses.count, 1, "Trio ignores replacePendingEvents, so its bolus row survives: \(trio.boluses)")
        XCTAssertEqual(trio.suspends.count, 1, "one suspend row: \(trio.suspends)")
        for event in suspendBatches.flatMap(\.events) where event.dose?.type == .bolus {
            XCTAssertEqual(event.raw, bolusRaw, "the bolus changed identity when the pump stopped it")
        }
        XCTExpectFailure(
            "jwoglom/TandemKit#344: the temp basal's raw embeds its programmed units, so ending it early re-keys it "
                + "instead of finalizing the dose the host already holds"
        ) {
            for event in suspendBatches.flatMap(\.events) where event.dose?.type == .tempBasal {
                XCTAssertEqual(
                    event.raw, tempRaw,
                    "guide §4: a dose keeps one identity from first report to finalization"
                )
            }
        }

        // Resume: the batch that reopens delivery must not purge anything still live either.
        _ = try harness.client.resume()
        let beforeResumeSync = allPumpEventBatches.count
        _ = try sync()
        let resumeBatches = newBatches(since: beforeResumeSync)
        XCTAssertFalse(
            resumeBatches.flatMap(\.events).isEmpty,
            "the pump came off suspend; the host must be told: \(resumeBatches.map(describe))"
        )

        let timeline = try timeline()
        XCTAssertEqual(timeline.suspends.count, 1, "the pump recorded one suspend: \(timeline.suspends)")
        XCTAssertTrue(
            timeline.boluses.contains { $0.bolusId == bolusId && $0.isFinished },
            "the pump stopped the bolus at the suspend: \(timeline.boluses)"
        )
        // At the host's resolution, not the pump's: LoopKit's `reconciled` rebuilds a temp basal that
        // a suspend truncated without the delivered volume the driver reported and re-derives it
        // through `unitsInDeliverableIncrements`, which rounds to the 0.05 U basal grid. Everything
        // else in the diff is still exact.
        timeline.assertMatches(
            feedOracles().loop,
            tolerance: PumpTimeline.Tolerance(units: 0.05),
            "suspend during a bolus and a temp basal"
        )
    }

    // MARK: - C4 (§6, §9 item 1, §11 empty syncs; P01-1, P18-2; #332)

    func testEmptySyncStillReportsAndAdvancesTheTrustBoundary() throws {
        let driver = try startPairedDriver()
        let firstBoundary = try XCTUnwrap(driver.manager.state.lastReconciliation)

        var boundaries: [Date] = [firstBoundary]
        for round in 1 ... 2 {
            try clock.advanceBoth(seconds: .minutes(5))
            let before = allPumpEventBatches.count
            let lastSync = try XCTUnwrap(try sync(), "round \(round): an answered sync hands the host a lastSync")

            let batches = newBatches(since: before)
            XCTAssertFalse(
                batches.isEmpty,
                "round \(round): guide §9 item 1 — hasNewPumpEvents is called on every sync, even with no new doses"
            )
            XCTAssertTrue(
                batches.allSatisfy { $0.events.isEmpty },
                "round \(round): nothing was delivered, so there is nothing to report: \(batches.map(describe))"
            )
            for batch in batches where batch.events.isEmpty {
                XCTAssertFalse(
                    batch.replacePendingEvents,
                    "round \(round): a boundary-only report must not claim to be the complete pending set"
                )
            }
            let reported = try XCTUnwrap(batches.last?.lastReconciliation, "round \(round)")
            XCTAssertEqual(reported, lastSync, "round \(round): the boundary the host is given is the one the driver kept")
            XCTAssertGreaterThan(reported, boundaries.last!, "round \(round): the trust boundary moves forward")
            boundaries.append(reported)

            let (loop, trio) = feedOracles()
            XCTAssertEqual(loop.lastReconciliation, reported, "round \(round): the host's boundary follows every call")
            XCTAssertEqual(loop.callCount, allPumpEventBatches.count, "round \(round): every batch reached the host")
            XCTAssertTrue(loop.doses.isEmpty, "round \(round): no dose was ever delivered: \(loop.doses.map(LoopDoseStoreOracle.describe))")
            XCTAssertTrue(trio.events.isEmpty, "round \(round): \(trio.events)")
        }

        XCTAssertEqual(boundaries, boundaries.sorted(), "the boundary never goes backwards: \(boundaries)")
        XCTAssertEqual(Set(boundaries).count, boundaries.count, "each sync advances it: \(boundaries)")
        try timeline().assertMatches(feedOracles().loop, tolerance: .exact, "two quiet syncs")
    }

    // MARK: - C5 (§6 safety; P01-2)

    func testSyncThePumpDoesNotAnswerDoesNotAdvanceTheTrustBoundary() throws {
        let driver = try startPairedDriver()
        let boundaryBefore = try XCTUnwrap(driver.manager.state.lastReconciliation)
        let (loopBefore, _) = feedOracles()
        let reportedBefore = loopBefore.lastReconciliation

        // The delivery reads and nothing else: the link stays up and the rest of the sync answers,
        // so this is a pump that said nothing about *delivery* rather than a pump that is not
        // there. (A pump that answers nothing at all cannot be staged here — see the report: with
        // the radio off the driver's auto-reconnect spins hard enough to take the test process
        // down, and dropping every response costs a response timeout per read, more silence than
        // the test runner's progress watchdog allows.)
        let silentReads = ["InsulinStatusRequest", "CurrentBolusStatusRequest", "CurrentBasalStatusRequest"]
        let client = harness.client
        addTeardownBlock { _ = try? client.clearFaults() }
        for message in silentReads {
            var fault = FaketandemFaultSpec(.dropResponse, message: message)
            fault.every = true
            _ = try harness.client.armFault(fault)
        }

        try clock.advanceBoth(seconds: .minutes(5))
        let before = allPumpEventBatches.count
        let logBefore = try harness.client.snapshot().requestLog.lastSeq
        let lastSync = try sync(timeout: 420)

        // What the pump saw: each delivery read arrived and was answered with nothing, while the
        // rest of the sync went through.
        let entries = try harness.requestLog(since: logBefore)
        for message in silentReads {
            XCTAssertTrue(
                entries.contains { $0.isRequest && $0.message == message },
                "the sync must have asked \(message); pump saw \(entries.compactMap(\.message))"
            )
        }
        // A dropped answer is still logged, with the fault that swallowed it and no fragment sent.
        let dropped = entries.filter { $0.isResponse && $0.fault == FaketandemFaultSpec.Kind.dropResponse.rawValue }
        XCTAssertGreaterThanOrEqual(
            dropped.count, silentReads.count,
            "every delivery read's answer must have been swallowed: \(dropped.map { $0.message ?? "?" })"
        )
        XCTAssertTrue(dropped.allSatisfy { ($0.fragmentsSent ?? 0) == 0 }, "a swallowed answer must not reach the driver")
        XCTAssertTrue(
            entries.contains { $0.isResponse && $0.fault == nil && ($0.fragmentsSent ?? 0) > 0 },
            "the rest of the sync must have been answered, or this is a dead link rather than a silent pump"
        )

        XCTAssertEqual(lastSync, driver.manager.state.lastReconciliation, "the host is handed the driver's own boundary")
        XCTAssertTrue(loopBefore.doses.isEmpty, "nothing was invented for a pump that said nothing")

        XCTExpectFailure(
            "TandemKit audit P18-A2 / P01-A1 (no open issue; jwoglom/TandemKit#332 closed the empty-sync half of "
                + "this): the boundary is stamped when any read answers, so a sync whose delivery reads all went "
                + "unanswered still moves the host's trust boundary"
        ) {
            XCTAssertEqual(
                driver.manager.state.lastReconciliation, boundaryBefore,
                "guide §6: lastReconciliation is never advanced past delivery that has not actually been accounted for"
            )
            for batch in newBatches(since: before) {
                XCTAssertEqual(
                    batch.lastReconciliation, boundaryBefore,
                    "a sync whose delivery reads were not answered may only repeat the boundary it had: \(describe(batch))"
                )
            }
            XCTAssertEqual(feedOracles().loop.lastReconciliation, reportedBefore, "the host's boundary stands")
        }

        let (loop, _) = feedOracles()
        XCTAssertTrue(
            loop.doses.isEmpty,
            "no dose may be invented from reads the pump did not answer: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        try harness.client.clearFaults()
        try timeline().assertMatches(loop, tolerance: .exact, "after a sync whose delivery reads went unanswered")
    }

    // MARK: - C6 (§3, §11 idempotency; P04-2, P17-1; #326)

    func testRelaunchAndResyncNeitherDuplicatesNorDropsDoses() throws {
        let driver = try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        _ = try harness.client.setState([
            // Fast enough that the bolus finishes inside the driver's own estimate, so this
            // scenario is about the relaunch and not about a stale in-flight bolus (that is A3/#326).
            "bolus_rate_units_per_second": 1.0 / TandemPumpCapabilities.estimatedBolusDuration(toDeliver: 1.0)
        ])

        let beforeTemp = allPumpEventBatches.count
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: .minutes(60)))
        let tempRaw = try XCTUnwrap(newBatches(since: beforeTemp).flatMap(\.events).first { $0.dose?.type == .tempBasal }).raw

        let beforeBolus = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: 1.0))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let bolusRaw = try XCTUnwrap(newBatches(since: beforeBolus).flatMap(\.events).first { $0.dose?.type == .bolus }).raw

        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        XCTAssertEqual(lastBolus.deliveredUnits, 1.0, accuracy: 0.0005)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 1.0) + .minutes(2))
        _ = try sync()

        let finalized = try XCTUnwrap(
            feedOracles().loop.assertPermanent(raw: bolusRaw, "the bolus is finalized before the relaunch"),
            "the bolus must be finalized before the relaunch"
        )
        XCTAssertEqual(try XCTUnwrap(finalized.dose.deliveredUnits), 1.0, accuracy: 0.0005)

        let relaunched = try relaunch()
        XCTAssertEqual(relaunched.manager.state.basalDose.type, .tempBasal, "the running temp basal survives the relaunch")
        try clock.advanceBoth(seconds: .minutes(5))
        let beforeResync = allPumpEventBatches.count
        _ = try sync()

        // Identity is stable across the process boundary: anything re-reported comes back under the
        // raw the host already holds.
        for event in newBatches(since: beforeResync).flatMap(\.events) {
            switch event.dose?.type {
            case .bolus: XCTAssertEqual(event.raw, bolusRaw, "the finalized bolus came back under a new identity")
            case .tempBasal: XCTAssertEqual(event.raw, tempRaw, "the live temp basal came back under a new identity")
            default: break
            }
        }

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("after a relaunch")
        let bolus = try XCTUnwrap(loop.assertPermanent(raw: bolusRaw, "after a relaunch"))
        XCTAssertEqual(
            try XCTUnwrap(bolus.dose.deliveredUnits), 1.0, accuracy: 0.0005,
            "the finalized bolus is untouched by the relaunch"
        )
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        let temp = try XCTUnwrap(loop.assertSingleDose(raw: tempRaw, "after a relaunch"))
        XCTAssertTrue(temp.isMutable, "the temp basal is still running: \(LoopDoseStoreOracle.describe(temp))")
        XCTAssertEqual(trio.boluses.count, 1, "Trio holds one bolus row: \(trio.boluses)")
        XCTAssertEqual(trio.tempBasals.count, 1, "Trio holds one temp basal row: \(trio.tempBasals)")

        let timeline = try timeline()
        XCTAssertTrue(timeline.boluses.contains { $0.bolusId == bolusId && $0.isFinished }, "\(timeline.boluses)")
        timeline.assertMatches(loop, tolerance: .exact, "a finalized bolus and a live temp basal across a relaunch")
    }

    // MARK: - C7 (§6, §10; G04, P01-3, P18-5; #342, #332)

    func testTransitionSeenWithNoDelegateReachesTheHostWhenOneAttaches() throws {
        let driver = try startPairedDriver()
        let boundaryBefore = try XCTUnwrap(driver.manager.state.lastReconciliation)

        // The host has not adopted the manager (or has handed it back): the driver still polls, and
        // whatever it observes now has nowhere to go.
        driver.manager.pumpManagerDelegate = nil
        let journalBeforeDetach = driver.delegate.journal.count

        // Time moves before the stop, not between the stop and the sync: the driver's boundary has
        // to be able to advance, while its detection of the suspend still lands on the pump's own
        // suspend instant.
        try clock.advanceBoth(seconds: .minutes(5))
        _ = try harness.client.suspend(reason: "user")
        _ = try sync()
        XCTAssertEqual(driver.manager.state.basalDose.type, .suspend, "the driver consumed the transition into its state")
        XCTAssertGreaterThan(
            try XCTUnwrap(driver.manager.state.lastReconciliation), boundaryBefore,
            "the driver's own boundary moved while the host heard nothing"
        )
        drainDelegate()
        XCTAssertEqual(
            driver.delegate.journal.count, journalBeforeDetach,
            "nothing may reach a delegate that is not attached: \(driver.delegate.pumpEventJournal.compactMap(\.pumpEventBatch).map(describe))"
        )

        // The host adopts the manager.
        driver.manager.pumpManagerDelegate = driver.delegate
        drainDelegate()
        try clock.advanceBoth(seconds: .minutes(5))
        _ = try sync()

        let afterAttach = driver.delegate.journal
            .filter { $0.index >= journalBeforeDetach }
            .compactMap(\.pumpEventBatch)
        XCTAssertTrue(
            afterAttach.contains { batch in batch.events.contains { $0.dose?.type == .suspend } },
            "guide §10 / G04: a suspend observed before the delegate attached must still reach the host — "
                + "fetchBasalStatus consumes the transition into state.basalDose, so a dropped batch is lost for good. "
                + "Batches after attach: \(afterAttach.map(describe))"
        )

        let (loop, trio) = feedOracles()
        let suspend = try XCTUnwrap(
            loop.doses.first { $0.dose.type == .suspend },
            "the host must hold the suspend: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        XCTAssertEqual(trio.suspends.count, 1, "one suspend row in Trio: \(trio.suspends)")
        XCTAssertEqual(
            loop.doses.filter { $0.dose.type == .suspend }.count, 1,
            "the replay must not duplicate it: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )

        let timeline = try timeline()
        let pumpSuspend = try XCTUnwrap(timeline.suspends.first, "the pump recorded the suspend: \(timeline.suspends)")
        XCTAssertEqual(
            suspend.dose.startDate.timeIntervalSince(pumpSuspend.start), 0, accuracy: 2,
            "the suspend is dated at the pump's stop"
        )
        timeline.assertMatches(loop, tolerance: .exact, "a suspend observed with no delegate attached")
    }

    // MARK: - Helpers

    /// Pair, sync, and give both sides the same scheduled basal rate: the driver computes the temp
    /// basal percentage from its own schedule and the pump applies it to its profile rate, so a
    /// mismatch would make the reported rate disagree with the delivered one (#335).
    @discardableResult
    private func startPairedDriver(scheduledBasalRate rate: Double) throws -> FaketandemHarness.Driver {
        _ = try harness.client.setState(["basal_rate": rate])
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: rate)]))
        let driver = startDriver(state: TandemPumpManagerState(basalRateSchedule: schedule))
        try harness.pair(driver)
        _ = try sync()
        return driver
    }

    /// Replays every batch the host has received, in order, and reports each dose that was live and
    /// mutable at the host when a `replacePendingEvents: true` batch arrived without carrying it —
    /// the doses LoopKit's report-or-delete rule (guide §3, §5) deletes.
    private func completeBatchOmissions() -> [String] {
        let oracle = LoopDoseStoreOracle()
        var omissions: [String] = []
        for delegate in delegates {
            for entry in delegate.journal {
                guard let batch = entry.pumpEventBatch else { continue }
                if batch.replacePendingEvents {
                    let carried = Set(batch.events.map(\.raw))
                    for dose in oracle.doses where dose.isMutable && !carried.contains(dose.raw ?? Data()) {
                        omissions.append("  \(LoopDoseStoreOracle.describe(dose)) dropped by \(describe(batch))")
                    }
                }
                oracle.addPumpEvents(
                    batch.events,
                    lastReconciliation: batch.lastReconciliation,
                    replacePendingEvents: batch.replacePendingEvents,
                    now: entry.hostNow
                )
            }
        }
        return omissions
    }

    private func newBatches(since index: Int) -> [MockPumpManagerDelegate.PumpEventBatch] {
        Array(allPumpEventBatches.dropFirst(index))
    }

    private func describe(_ batch: MockPumpManagerDelegate.PumpEventBatch) -> String {
        let events = batch.events.map { event -> String in
            let mutable = event.dose.map { $0.isMutable ? " mutable" : " final" } ?? ""
            return "\(LoopDoseStoreOracle.describe(event.raw))\(mutable)"
        }
        return "[replace=\(batch.replacePendingEvents) boundary=\(batch.lastReconciliation?.description ?? "nil") "
            + "events=\(events)]"
    }
}
