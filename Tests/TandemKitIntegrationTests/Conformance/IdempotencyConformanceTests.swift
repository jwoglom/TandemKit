import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
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

            XCTAssertTrue(
                batches.contains { batch in
                    batch.replacePendingEvents && batch.events.contains { $0.raw == raw && $0.dose?.isMutable == true }
                },
                "round \(round): guide §9 item 4 — an in-progress dose is re-reported on every sync until it "
                    + "finalizes, in a complete batch, since Loop keeps its row over a non-replacing one; batches were "
                    + "\(batches.map(describe))"
            )

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

    // MARK: - C2 (§9 item 4, §11 idempotency; P04-3, P17-2; #450)

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

            XCTAssertTrue(
                batches.contains { batch in
                    batch.replacePendingEvents && batch.events.contains { $0.raw == raw && $0.dose?.isMutable == true }
                },
                "round \(round): guide §9 item 4 — the live temp basal is re-reported on every sync, in a complete batch"
            )

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
        let omissions = completeBatchOmissions()
        XCTAssertTrue(
            omissions.isEmpty,
            "guide §3/§5: nothing live may be dropped by silence:\n" + omissions.joined(separator: "\n")
        )

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
        for event in suspendBatches.flatMap(\.events) where event.dose?.type == .tempBasal {
            XCTAssertEqual(
                event.raw, tempRaw,
                "guide §4: a dose keeps one identity from first report to finalization"
            )
        }

        // Resume: the batch that reopens delivery must not purge anything still live either.
        // Counted before the resume: its qualifying event can report the resume ahead of the sync.
        let beforeResume = allPumpEventBatches.count
        _ = try harness.client.resume()
        _ = try sync()
        let resumeBatches = newBatches(since: beforeResume)
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
            XCTAssertEqual(loop.callCount, batchesFedToOracles, "round \(round): every batch reached the host")
            XCTAssertTrue(loop.doses.isEmpty, "round \(round): no dose was ever delivered: \(loop.doses.map(LoopDoseStoreOracle.describe))")
            XCTAssertEqual(trio.events.map(\.type), [.siteChange], "round \(round): only the pump added: \(trio.events)")
        }

        XCTAssertEqual(boundaries, boundaries.sorted(), "the boundary never goes backwards: \(boundaries)")
        XCTAssertEqual(Set(boundaries).count, boundaries.count, "each sync advances it: \(boundaries)")
        XCTAssertTrue(
            driver.delegate.reservoirReadingsAheadOfTheBoundary.isEmpty,
            "each sync's reservoir reading reaches the host behind the boundary it reports: \(driver.delegate.journal.map(\.kind))"
        )
        try timeline().assertMatches(feedOracles().loop, tolerance: .exact, "two quiet syncs")
    }

    // MARK: - C5 (§6 safety; P01-2; #449)

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

    // MARK: - C8 (§3 report-or-delete, §5; #347, #330)

    func testTempBasalEnactedWhileTheBolusOutlivesItsEstimateKeepsTheBolus() throws {
        let driver = try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        // 1 U takes 200 s on this pump and well under a minute in the driver's model.
        _ = try harness.client.setState(["bolus_rate_units_per_second": 0.005])
        let units = 1.0

        let beforeBolus = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: units))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let bolusRaw = try XCTUnwrap(newBatches(since: beforeBolus).flatMap(\.events).first { $0.dose?.type == .bolus }).raw
        // The estimate counts from the first delivering sample; stepping the clock before it is taken
        // would start the count after the step.
        try IntegrationWait.until("the driver to see the bolus delivering", timeout: 30) {
            driver.manager.bolusProgressReport?.bolusStatedOn != nil
        }

        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + 10, ticks: 10)
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the pump is still delivering")
        try IntegrationWait.until("the driver's estimate to reach the programmed amount", timeout: 15) {
            driver.manager.bolusProgressReport?.isUnfinalized() == false
        }

        let refused = try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: .minutes(30))
        let pump = try harness.client.snapshot()
        XCTAssertTrue(pump.bolus.active, "the pump was still delivering when the temp basal was asked for")

        // Refusing the temp basal and carrying the bolus in its batch both satisfy the guide; the
        // driver refuses it until the pump says the bolus is over (#347).
        guard case let .deviceState(underlying?)? = refused else {
            return XCTFail("the temp basal is refused while the pump delivers the bolus: \(String(describing: refused))")
        }
        XCTAssertEqual(underlying as? TandemPumpManagerValidationError, .bolusIsRunning)
        XCTAssertFalse(pump.basal.tempActive)
        let omissions = completeBatchOmissions()
        XCTAssertTrue(omissions.isEmpty, "guide §3/§5: nothing live may be dropped by silence:\n" + omissions.joined(separator: "\n"))
        let held = feedOracles().loop
        XCTAssertEqual(
            held.mutableDoses.filter { $0.dose.type == .bolus }.count, 1,
            "the running bolus is still held: \(held.doses.map(LoopDoseStoreOracle.describe))"
        )

        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + .minutes(2))
        _ = try sync()
        let finalized = try IntegrationWait.value("the finalized bolus report", timeout: 30) {
            self.newBatches(since: beforeBolus).flatMap(\.events).first { $0.raw == bolusRaw && $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.dose?.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let timeline = try timeline()
        let stored = loop.assertPermanent(raw: bolusRaw, "once the pump has finished")
        XCTAssertEqual(stored?.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)
        timeline.assertMatches(loop, "a temp basal enacted while the bolus outlived its estimate")
    }

    // MARK: - C9 (§4, §8: raw is the identity; #352)

    /// The phone's clock half a second ahead of the pump's, and a neutral temp in the second a temp
    /// basal was due to end: the batch that ends the temp basal also carries the neutral temp's marker.
    func testEventsInOneBatchNeverShareAnIdentity() throws {
        try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        let duration: TimeInterval = .minutes(30)

        let beforeTemp = allPumpEventBatches.count
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: duration))
        let temp = try XCTUnwrap(newBatches(since: beforeTemp).flatMap(\.events).first { $0.dose?.type == .tempBasal })
        let scheduledEnd = try XCTUnwrap(temp.dose?.endDate)

        // The pump stands 0.4 s short of the end; the phone reads 0.1 s past it, in the same second.
        try clock.advanceBoth(seconds: duration - 0.4, ticks: 30)
        manualClock.advance(by: 0.5)
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive, "the pump is still running the temp rate")
        XCTAssertEqual(
            clock.now.timeIntervalSince1970.rounded(.down), scheduledEnd.timeIntervalSince1970.rounded(.down),
            "the phone is in the temp basal's last second"
        )

        let beforeNeutral = allPumpEventBatches.count
        let neutralAt = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.scheduledBasalRate, duration: .minutes(30)), "a neutral temp")
        let neutralBatches = newBatches(since: beforeNeutral)
        XCTAssertTrue(
            neutralBatches.flatMap(\.events).contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false },
            "the neutral temp finalizes the running temp basal: \(neutralBatches.map(describe))"
        )

        for batch in neutralBatches {
            let raws = batch.events.map(\.raw)
            XCTAssertEqual(Set(raws).count, raws.count, "one identity per event in a batch: \(describe(batch))")
        }
        XCTAssertEqual(
            neutralBatches.flatMap(\.events).filter { $0.dose?.type == .basal }.map(\.date), [neutralAt],
            "the neutral temp's marker says the schedule is back; one at the temp basal's end would share its second: "
                + "\(neutralBatches.map(describe))"
        )

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        trio.assertNoSameSecondBasalRows()
        XCTAssertEqual(
            loop.permanentDoses.filter { $0.dose.type == .tempBasal }.count, 1,
            "one temp basal ran: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        // The pump stopped the temp rate 0.4 s before the phone's scheduled end.
        try timeline().assertMatches(loop, tolerance: PumpTimeline.Tolerance(time: 2, units: 0.001, rate: 0.005), "a neutral temp in a temp basal's last second")
    }

    // MARK: - C10 (§4, §8: raw is the identity; #352)

    /// A neutral temp, a temp basal and its cancel inside one second of the phone's clock: the
    /// neutral temp's marker and the cancel's go out in two batches, both in that second.
    func testMarkersInOneSecondAcrossBatchesKeepTheirOwnIdentities() throws {
        try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        let beforeNeutral = allPumpEventBatches.count
        let neutralAt = clock.now

        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.scheduledBasalRate, duration: .minutes(30)), "a neutral temp")
        manualClock.advance(by: 0.2)
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: .minutes(30)))
        manualClock.advance(by: 0.3)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: 0), "cancel")

        let batches = newBatches(since: beforeNeutral)
        let markers = batches.flatMap(\.events).filter { $0.dose?.type == .basal }
        XCTAssertEqual(markers.map(\.date), [neutralAt, neutralAt.addingTimeInterval(0.5)], "\(batches.map(describe))")
        XCTAssertEqual(Set(markers.map(\.raw)).count, markers.count, "two markers, two identities: \(batches.map(describe))")

        let (loop, trio) = feedOracles()
        XCTAssertEqual(
            loop.pumpEvents.filter { $0.dose?.type == .basal && $0.date >= neutralAt }.map(\.date),
            markers.map(\.date),
            "Loop keeps one PumpEvent row per raw"
        )
        XCTAssertEqual(
            trio.scheduledBasals.filter { $0.timestamp >= neutralAt }.map(\.timestamp),
            markers.map(\.date),
            "Trio matches a report on its syncIdentifier first"
        )
        XCTAssertFalse(trio.skipped.contains { $0.event.dose?.type == .basal }, "Trio dropped a marker: \(trio.skipped)")
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
    }

    // MARK: - C11 (§4, §11 idempotency; #330)

    func testIdenticalBolusesInARowAreEachCountedOnce() throws {
        try identicalBolusesInARow(historyDoseReporting: false)
    }

    /// The history pass reads each bolus's `BolusCompleted` too, and must find it already reported.
    func testIdenticalBolusesInARowAreEachCountedOnceWithHistoryDoseReporting() throws {
        try identicalBolusesInARow(historyDoseReporting: true)
    }

    /// Three boluses of one amount a few minutes apart, as SMBs go out, each re-sent while it runs.
    private func identicalBolusesInARow(historyDoseReporting: Bool) throws {
        let driver = try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate, historyDoseReporting: historyDoseReporting)
        // 1 U takes 50 s of pump time: a sync 20 s in finds it delivering, inside the driver's estimate.
        _ = try harness.client.setState(["bolus_rate_units_per_second": 0.02])
        let units = 1.0
        var raws: [Data] = []
        var bolusIds: [Int] = []

        for round in 1 ... 3 {
            let beforeEnact = allPumpEventBatches.count
            XCTAssertNil(try enactBolus(units: units), "round \(round)")
            let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId, "round \(round)")
            let raw = try XCTUnwrap(newBatches(since: beforeEnact).flatMap(\.events).first { $0.dose?.type == .bolus }, "round \(round)").raw
            XCTAssertFalse(raws.contains(raw), "round \(round): the same amount again is a dose of its own: \(LoopDoseStoreOracle.describe(raw))")
            raws.append(raw)
            bolusIds.append(bolusId)

            try clock.advanceBoth(seconds: 20, ticks: 4)
            let beforeSync = allPumpEventBatches.count
            _ = try sync()
            XCTAssertTrue(try harness.client.snapshot().bolus.active, "round \(round): the pump is still delivering")
            assertReSent(raw, in: newBatches(since: beforeSync), "round \(round)")
            try assertEachDeliveryCountedOnce(boluses: raws, "round \(round), delivering")

            try advanceUntilBolusFinishes(bolusId: bolusId)
            try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + .minutes(1))
            _ = try syncUntilFinalized(raw: raw)
            try assertEachDeliveryCountedOnce(boluses: raws, "round \(round), finished")

            try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
            _ = try sync()
        }
        if historyDoseReporting {
            try waitForHistoryPass(driver)
        }

        let reports = allPumpEventBatches.flatMap(\.events).filter { $0.dose?.type == .bolus }
        XCTAssertEqual(Set(reports.map(\.raw)), Set(raws), "every bolus report is of the app's three: \(reports.map { LoopDoseStoreOracle.describe($0.raw) })")
        for raw in raws {
            XCTAssertEqual(finalizedReports(of: raw), 1, "finalized once: \(LoopDoseStoreOracle.describe(raw))")
        }
        try assertEachDeliveryCountedOnce(boluses: raws, "after three boluses")

        let timeline = try timeline()
        let delivered = timeline.boluses.filter { bolusIds.contains($0.bolusId) }.compactMap(\.deliveredUnits)
        XCTAssertEqual(delivered.count, 3, "\(timeline.boluses)")
        try assertHostsCountTheBoluses(delivered.reduce(0, +), "three identical boluses")
        timeline.assertMatches(feedOracles().loop, tolerance: .exact, "three identical boluses")
    }

    // MARK: - C12 (§4, §11 idempotency; #450, #344)

    /// Enacted again every cycle, as hosts keep a temp running, with a sync between.
    func testTheSameTempBasalEveryCycleIsCountedOncePerEnactment() throws {
        try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        let firstStart = clock.now
        var raws: [Data] = []

        for round in 1 ... 4 {
            let beforeEnact = allPumpEventBatches.count
            XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: .minutes(30)), "round \(round)")
            let enacted = newBatches(since: beforeEnact).flatMap(\.events)
            let started = try XCTUnwrap(enacted.first { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }, "round \(round)")
            XCTAssertFalse(raws.contains(started.raw), "round \(round): the same rate again is a temp basal of its own: \(LoopDoseStoreOracle.describe(started.raw))")
            if let replaced = raws.last {
                XCTAssertEqual(enacted.filter { $0.raw == replaced }.map(\.dose?.isMutable), [false], "round \(round): the temp it replaced is finalized")
            }
            raws.append(started.raw)

            try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
            let beforeSync = allPumpEventBatches.count
            _ = try sync()
            let synced = newBatches(since: beforeSync)
            assertReSent(started.raw, in: synced, "round \(round)")
            XCTAssertFalse(
                synced.flatMap(\.events).contains { raws.dropLast().contains($0.raw) },
                "round \(round): a finished temp basal is not reported again: \(synced.map(describe))"
            )
            try assertEachDeliveryCountedOnce(temps: raws, "round \(round)")
            let (loop, trio) = feedOracles()
            XCTAssertEqual(loop.mutableDoses.compactMap(\.raw), [started.raw], "round \(round): only the latest runs")
            trio.assertNoSameSecondBasalRows("round \(round)")
        }

        for raw in raws {
            XCTAssertEqual(finalizedReports(of: raw), raw == raws.last ? 0 : 1, LoopDoseStoreOracle.describe(raw))
        }
        let loop = feedOracles().loop
        let temps = loop.doses.filter { $0.dose.type == .tempBasal }.sorted { $0.dose.startDate < $1.dose.startDate }
        for (finished, next) in zip(temps, temps.dropFirst()) {
            XCTAssertEqual(
                finished.dose.endDate, next.dose.startDate,
                "back to back: \(LoopDoseStoreOracle.describe(finished)) then \(LoopDoseStoreOracle.describe(next))"
            )
        }
        try assertHostsCountTheTempBasals(from: firstStart, "the same temp basal every cycle")
        try timeline().assertMatches(loop, tolerance: .exact, "the same temp basal every cycle")
    }

    // MARK: - C13 (§3, §11 idempotency; #450)

    func testATempBasalReSentUntilItRunsOutIsCountedOnce() throws {
        try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        let duration: TimeInterval = .minutes(30)
        let beforeEnact = allPumpEventBatches.count
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempBasalRate, duration: duration))
        let started = try XCTUnwrap(newBatches(since: beforeEnact).flatMap(\.events).first { $0.dose?.type == .tempBasal })
        let raw = started.raw
        let start = try XCTUnwrap(started.dose?.startDate)
        let scheduledEnd = try XCTUnwrap(started.dose?.endDate)

        for round in 1 ... 5 {
            try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
            let before = allPumpEventBatches.count
            _ = try sync()
            XCTAssertTrue(try harness.client.snapshot().basal.tempActive, "round \(round): the pump's temp rate still runs")
            assertReSent(raw, in: newBatches(since: before), "round \(round)")
            try assertEachDeliveryCountedOnce(temps: [raw], "round \(round)")
            XCTAssertEqual(feedOracles().loop.dose(raw: raw)?.dose.endDate, scheduledEnd, "round \(round): it runs to its scheduled end")
        }

        try clock.advanceBoth(seconds: .minutes(6), ticks: 6)
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the temp rate ran out")
        let finalized = try syncUntilFinalized(raw: raw)
        XCTAssertEqual(try XCTUnwrap(finalized.dose?.endDate).timeIntervalSince(scheduledEnd), 0, accuracy: 1, "it ran its whole duration")
        XCTAssertEqual(finalized.dose?.deliveredUnits ?? -1, Self.tempBasalRate * duration / .hours(1), accuracy: 0.001)

        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let afterEnd = allPumpEventBatches.count
        _ = try sync()
        XCTAssertFalse(newBatches(since: afterEnd).flatMap(\.events).contains { $0.raw == raw }, "a finished temp basal is not reported again")
        XCTAssertEqual(finalizedReports(of: raw), 1)
        try assertEachDeliveryCountedOnce(temps: [raw], "after it ran out")

        let (loop, trio) = feedOracles()
        XCTAssertNotNil(loop.assertPermanent(raw: raw, "after it ran out"))
        XCTAssertEqual(trio.tempBasals.map(\.isMutable), [false], "\(trio.tempBasals)")
        XCTAssertEqual(trio.tempBasals.first?.tempBasalDurationMinutes, 30)
        try assertHostsCountTheTempBasals(from: start, "a temp basal that ran out")
        try timeline().assertMatches(loop, tolerance: .exact, "a temp basal re-sent until it ran out")
    }

    // MARK: - C14 (§3, §11 idempotency; #330)

    func testABolusReSentThroughManySyncsAndARelaunchIsCountedOnce() throws {
        let driver = try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        // 2 U takes 200 s of pump time, past the driver's estimate: the later syncs read the bolus
        // status, and find it still delivering.
        _ = try harness.client.setState(["bolus_rate_units_per_second": 0.01])
        let units = 2.0
        let beforeEnact = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: units))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let raw = try XCTUnwrap(newBatches(since: beforeEnact).flatMap(\.events).first { $0.dose?.type == .bolus }).raw

        for round in 1 ... 8 {
            try clock.advanceBoth(seconds: 15, ticks: 3)
            if round == 4 {
                _ = try relaunch()
            }
            let before = allPumpEventBatches.count
            _ = try sync()
            XCTAssertTrue(try harness.client.snapshot().bolus.active, "round \(round): the pump is still delivering")
            assertReSent(raw, in: newBatches(since: before), "round \(round)")
            try assertEachDeliveryCountedOnce(boluses: [raw], "round \(round)")
            XCTAssertEqual(feedOracles().loop.dose(raw: raw)?.isMutable, true, "round \(round)")
        }

        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        try clock.advanceBoth(seconds: .minutes(1))
        let finalized = try syncUntilFinalized(raw: raw)
        XCTAssertEqual(finalized.dose?.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let afterEnd = allPumpEventBatches.count
        _ = try sync()
        XCTAssertFalse(newBatches(since: afterEnd).flatMap(\.events).contains { $0.raw == raw }, "a finished bolus is not reported again")
        XCTAssertEqual(finalizedReports(of: raw), 1)
        try assertEachDeliveryCountedOnce(boluses: [raw], "finished")

        let loop = feedOracles().loop
        XCTAssertEqual(loop.assertPermanent(raw: raw, "finished")?.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)
        try assertHostsCountTheBoluses(lastBolus.deliveredUnits, "one bolus through a relaunch")
        try timeline().assertMatches(loop, tolerance: .exact, "a bolus re-sent through a relaunch")
    }

    // MARK: - C15 (§3, §5, §11 idempotency; #330, #448)

    func testTwoIdenticalBolusesMutableAtOnceAreEachCountedOnce() throws {
        let driver = try startPairedDriver(scheduledBasalRate: Self.scheduledBasalRate)
        // With no history to read the first one's volume from, it stays held while the second runs.
        turnOffHistoryBackfill(driver)
        let client = harness.client
        addTeardownBlock { _ = try? client.clearFaults() }
        try dropEveryLastBolusStatus()
        let units = 2.0
        // The driver's own model of the pump's speed, which dates the first one's end without the
        // pump's timestamp. 2 U takes about a minute, so the second still runs at the third sync.
        _ = try harness.client.setState(["bolus_rate_units_per_second": units / TandemPumpCapabilities.estimatedBolusDuration(toDeliver: units)])

        let beforeFirst = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: units))
        let firstId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let first = try XCTUnwrap(newBatches(since: beforeFirst).flatMap(\.events).first { $0.dose?.type == .bolus }).raw
        try advanceUntilBolusFinishes(bolusId: firstId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + .minutes(1))
        _ = try sync()
        XCTAssertEqual(driver.manager.state.pendingBolusFinalization?.bolusId, firstId, "held for its delivered volume")

        let beforeSecond = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: units))
        let secondId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let second = try XCTUnwrap(newBatches(since: beforeSecond).flatMap(\.events).first { $0.dose?.type == .bolus && $0.raw != first }).raw

        for round in 1 ... 3 {
            try clock.advanceBoth(seconds: 10, ticks: 2)
            let before = allPumpEventBatches.count
            _ = try sync()
            XCTAssertTrue(try harness.client.snapshot().bolus.active, "round \(round): the second is still delivering")
            let batches = newBatches(since: before)
            XCTAssertTrue(
                batches.contains { batch in
                    batch.replacePendingEvents && [first, second].allSatisfy { raw in
                        batch.events.contains { $0.raw == raw && $0.dose?.isMutable == true }
                    }
                },
                "round \(round): both re-sent in one complete batch: \(batches.map(describe))"
            )
            try assertEachDeliveryCountedOnce(boluses: [first, second], "round \(round), both mutable")
            XCTAssertEqual(feedOracles().loop.mutableDoses.count, 2, "round \(round)")
        }

        // The second is held in the first's place, and the first, whose volume `LastBolusStatus` can
        // no longer give, is finalized at its programmed amount.
        try advanceUntilBolusFinishes(bolusId: secondId)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: units) + .minutes(1))
        _ = try sync()
        XCTAssertEqual(driver.manager.state.pendingBolusFinalization?.bolusId, secondId)
        try assertEachDeliveryCountedOnce(boluses: [first, second], "the first finalized, the second held")
        XCTAssertEqual(feedOracles().loop.dose(raw: first)?.isMutable, false)
        XCTAssertEqual(feedOracles().loop.dose(raw: second)?.isMutable, true)

        try harness.client.clearFaults()
        _ = try syncUntilFinalized(raw: second)
        for raw in [first, second] {
            XCTAssertEqual(finalizedReports(of: raw), 1, "finalized once: \(LoopDoseStoreOracle.describe(raw))")
        }
        try assertEachDeliveryCountedOnce(boluses: [first, second], "both finished")

        let timeline = try timeline()
        let delivered = timeline.boluses.filter { [firstId, secondId].contains($0.bolusId) }.compactMap(\.deliveredUnits)
        XCTAssertEqual(delivered.count, 2, "\(timeline.boluses)")
        try assertHostsCountTheBoluses(delivered.reduce(0, +), "two identical boluses mutable at once")
        // The first one's end is the driver's model, which counts the 15 s lead-in the emulator does not.
        timeline.assertMatches(
            feedOracles().loop,
            tolerance: PumpTimeline.Tolerance(time: TandemPumpCapabilities.bolusInitiationDelay + 2, units: 0.001, rate: 0.005),
            "two identical boluses mutable at once"
        )
    }

    // MARK: - C16 (§6, §11 empty syncs; P18-6)

    /// The host's first poll after a relaunch falls inside its 4.5-minute throttle, but the
    /// relaunched driver has no link, so the poll still reaches the pump.
    func testTheFirstPollAfterARelaunchReportsABoundaryFromThisLaunch() throws {
        let driver = try startPairedDriver()
        let persisted = try XCTUnwrap(driver.manager.state.lastReconciliation)

        let relaunched = try relaunch()
        try clock.advanceBoth(seconds: .minutes(1))
        let before = allPumpEventBatches.count
        let polled = try poll(relaunched)

        let reported = try XCTUnwrap(
            newBatches(since: before).last?.lastReconciliation,
            "the relaunched driver's host is handed a boundary by its first poll"
        )
        XCTAssertGreaterThan(reported, persisted)
        XCTAssertEqual(polled, reported)
        XCTAssertEqual(relaunched.manager.state.lastReconciliation, reported)

        let beforeSecond = allPumpEventBatches.count
        XCTAssertEqual(try poll(relaunched), reported, "a poll inside the throttle on a live link")
        XCTAssertTrue(newBatches(since: beforeSecond).isEmpty, "\(newBatches(since: beforeSecond).map(describe))")

        let (loop, trio) = feedOracles()
        XCTAssertEqual(loop.lastReconciliation, reported)
        XCTAssertTrue(loop.doses.isEmpty, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(trio.events.map(\.type), [.siteChange], "only the pump added: \(trio.events)")
        try timeline().assertMatches(loop, tolerance: .exact, "a quiet relaunch")
    }

    // MARK: - C17 (§6 safety; #449)

    /// The pump's remaining insulin changes between syncs, and its qualifying event reads the reservoir.
    func testAReservoirReadMovesNoBoundaryAndWaitsForTheNextSync() throws {
        let driver = try startPairedDriver()
        let boundaryBefore = try XCTUnwrap(driver.manager.state.lastReconciliation)
        drainDelegate()
        let readingsBefore = driver.delegate.reservoirReadings.count
        let batchesBefore = allPumpEventBatches.count

        try clock.advanceBoth(seconds: .minutes(2))
        let readAt = clock.now
        _ = try harness.client.raiseQualifyingEvent(bitmask: QualifyingEvent.remainingInsulin.id)
        try IntegrationWait.until("the driver to read the reservoir", timeout: 30) {
            driver.manager.reservoirLevel?.startDate == readAt
        }
        let jobsDone = ResultBox<Void>()
        driver.bluetooth.ensureConnected { _ in jobsDone.set(()) }
        try jobsDone.wait("the qualifying event's command job", timeout: commandTimeout)
        drainDelegate()

        XCTAssertEqual(
            driver.manager.state.lastReconciliation, boundaryBefore,
            "guide §6: a reservoir level says nothing about bolus or basal state"
        )
        XCTAssertTrue(newBatches(since: batchesBefore).isEmpty, "\(newBatches(since: batchesBefore).map(describe))")
        XCTAssertEqual(
            driver.delegate.reservoirReadings.count, readingsBefore,
            "a reading newer than the host's boundary would have Loop count reservoir drops in place of pump events"
        )

        try clock.advanceBoth(seconds: .minutes(3))
        let lastSync = try XCTUnwrap(try sync())

        XCTAssertGreaterThan(lastSync, boundaryBefore)
        let reading = try XCTUnwrap(driver.delegate.reservoirReadings.last)
        XCTAssertEqual(driver.delegate.reservoirReadings.count, readingsBefore + 1, "the sync's own reading supersedes the held one")
        XCTAssertLessThanOrEqual(reading.date, lastSync)
        XCTAssertTrue(driver.delegate.reservoirReadingsAheadOfTheBoundary.isEmpty, "\(driver.delegate.journal.map(\.kind))")
        let (loop, _) = feedOracles()
        XCTAssertEqual(loop.lastReconciliation, lastSync)
        XCTAssertTrue(loop.doses.isEmpty, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        try timeline().assertMatches(loop, tolerance: .exact, "after a reservoir read between syncs")
    }

    // MARK: - C18 (§6 safety; #449)

    func testASyncWhoseDeliveryReadsGoUnansweredHoldsItsReservoirReading() throws {
        let driver = try startPairedDriver()
        let boundaryBefore = try XCTUnwrap(driver.manager.state.lastReconciliation)
        drainDelegate()
        let readingsBefore = driver.delegate.reservoirReadings.count
        let reportedBefore = feedOracles().loop.lastReconciliation

        let silentReads = ["CurrentBolusStatusRequest", "CurrentBasalStatusRequest"]
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

        let entries = try harness.requestLog(since: logBefore)
        for message in silentReads {
            XCTAssertTrue(entries.contains { $0.isRequest && $0.message == message }, "the sync must have asked \(message)")
        }
        XCTAssertTrue(
            entries.contains { $0.isResponse && $0.message == "InsulinStatusResponse" && $0.fault == nil && ($0.fragmentsSent ?? 0) > 0 },
            "the reservoir read was answered"
        )
        XCTAssertEqual(lastSync, boundaryBefore)
        XCTAssertEqual(driver.manager.state.lastReconciliation, boundaryBefore)
        for batch in newBatches(since: before) {
            XCTAssertEqual(batch.lastReconciliation, boundaryBefore, describe(batch))
        }
        XCTAssertEqual(feedOracles().loop.lastReconciliation, reportedBefore, "the host's boundary stands")
        XCTAssertEqual(driver.delegate.reservoirReadings.count, readingsBefore, "the reading waits for a boundary that covers it")
        XCTAssertEqual(driver.manager.reservoirLevel?.startDate, clock.now, "the driver's own status shows it")
        XCTAssertTrue(driver.manager.state.lastReservoirReadingNeedsReport)

        try harness.client.clearFaults()
        try clock.advanceBoth(seconds: .minutes(5))
        let next = try XCTUnwrap(try sync())

        XCTAssertGreaterThan(next, boundaryBefore)
        XCTAssertEqual(driver.delegate.reservoirReadings.count, readingsBefore + 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(driver.delegate.reservoirReadings.last).date, next)
        XCTAssertTrue(driver.delegate.reservoirReadingsAheadOfTheBoundary.isEmpty, "\(driver.delegate.journal.map(\.kind))")
        let (loop, _) = feedOracles()
        XCTAssertEqual(loop.lastReconciliation, next)
        XCTAssertTrue(loop.doses.isEmpty, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        try timeline().assertMatches(loop, tolerance: .exact, "after a sync whose delivery reads went unanswered")
    }

    // MARK: - Helpers

    /// The host's periodic `ensureCurrentPumpData`; returns the lastSync it handed the host.
    private func poll(_ driver: FaketandemHarness.Driver) throws -> Date? {
        let box = ResultBox<Date?>()
        driver.manager.ensureCurrentPumpData { box.set($0) }
        let lastSync = try box.wait("ensureCurrentPumpData completion", timeout: syncTimeout)
        drainDelegate()
        return lastSync
    }

    /// Pair, sync, and give both sides the same scheduled basal rate: the driver computes the temp
    /// basal percentage from its own schedule and the pump applies it to its profile rate, so a
    /// mismatch would make the reported rate disagree with the delivered one (#335).
    @discardableResult
    private func startPairedDriver(scheduledBasalRate rate: Double, historyDoseReporting: Bool = false) throws -> FaketandemHarness.Driver {
        _ = try harness.client.setState(["basal_rate": rate])
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: rate)]))
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.featureFlags[.historyDoseReporting] = historyDoseReporting
        if historyDoseReporting {
            state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        }
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        if historyDoseReporting {
            // Past the first tick, whatever the pump logs is newer than the floor history reports from.
            try IntegrationWait.until("the first backfill tick", timeout: 180) { driver.manager.state.historyBackfill != nil }
        }
        return driver
    }

    /// A sync, then the history pass it starts: read through the pump's last record and reported.
    private func waitForHistoryPass(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 180) throws {
        let last = try harness.client.snapshot().history.lastSequence
        _ = try sync()
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy
        }
        // History's reports go out in a command job queued behind the tick.
        let jobsDone = ResultBox<Void>()
        driver.bluetooth.ensureConnected { _ in jobsDone.set(()) }
        try jobsDone.wait("the history reports' command job", timeout: timeout)
        drainDelegate()
    }

    private func assertReSent(_ raw: Data, in batches: [MockPumpManagerDelegate.PumpEventBatch], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            batches.contains { batch in
                batch.replacePendingEvents && batch.events.contains { $0.raw == raw && $0.dose?.isMutable == true }
            },
            "\(message): the running dose is re-sent in a complete batch: \(batches.map(describe))",
            file: file,
            line: line
        )
    }

    private func finalizedReports(of raw: Data) -> Int {
        allPumpEventBatches.flatMap(\.events).filter { $0.raw == raw && $0.dose?.isMutable == false }.count
    }

    /// Each `raw` is one live dose in Loop and one row in Trio, the hosts hold no other dose of its
    /// type, and neither has deleted one along the way.
    private func assertEachDeliveryCountedOnce(
        boluses: [Data] = [],
        temps: [Data] = [],
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates(message, file: file, line: line)
        trio.assertNoDuplicates(message, file: file, line: line)
        let live = loop.doses.map(LoopDoseStoreOracle.describe)
        for (type, raws) in [(DoseType.bolus, boluses), (DoseType.tempBasal, temps)] {
            for raw in raws {
                XCTAssertNotNil(loop.assertSingleDose(raw: raw, message, file: file, line: line))
                XCTAssertEqual(
                    trio.events.filter { $0.syncIdentifier == raw.hexadecimalString }.count, 1,
                    "\(message): one Trio row for \(LoopDoseStoreOracle.describe(raw)): \(trio.events)",
                    file: file,
                    line: line
                )
            }
            XCTAssertEqual(loop.doses.filter { $0.dose.type == type }.count, raws.count, "\(message): Loop's \(type) doses: \(live)", file: file, line: line)
            XCTAssertTrue(
                loop.deletedDoses.allSatisfy { $0.dose.type != type },
                "\(message): Loop deleted \(loop.deletedDoses.map(LoopDoseStoreOracle.describe))",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(trio.boluses.count, boluses.count, "\(message): \(trio.boluses)", file: file, line: line)
        XCTAssertEqual(trio.tempBasals.count, temps.count, "\(message): \(trio.tempBasals)", file: file, line: line)
        XCTAssertTrue(trio.purged.isEmpty, "\(message): Trio purged \(trio.purged)", file: file, line: line)
    }

    private func assertHostsCountTheBoluses(_ delivered: Double, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let (loop, trio) = feedOracles()
        let loopUnits = loop.doses.filter { $0.dose.type == .bolus }.compactMap(\.dose.deliveredUnits).reduce(0, +)
        XCTAssertEqual(loopUnits, delivered, accuracy: 0.0015, "Loop: \(message)", file: file, line: line)
        // Trio stores a bolus to its 0.1 U increment.
        let trioUnits = trio.boluses.compactMap(\.bolusAmount).map { NSDecimalNumber(decimal: $0).doubleValue }.reduce(0, +)
        XCTAssertEqual(trioUnits, delivered, accuracy: 0.05 * Double(max(1, trio.boluses.count)), "Trio: \(message)", file: file, line: line)
    }

    /// Both hosts count, above the schedule, what the pump's temp rates delivered from `start` to now.
    private func assertHostsCountTheTempBasals(from start: Date, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let now = clock.now
        let tempRates = try timeline().tempRates
        let pump = tempRates.reduce(0.0) { total, temp in
            let end = min(temp.end ?? now, now)
            guard let rate = temp.rate, end > temp.start else { return total }
            return total + (rate - Self.scheduledBasalRate) * end.timeIntervalSince(temp.start) / .hours(1)
        }
        let scheduled: (Date) -> Double = { _ in Self.scheduledBasalRate }
        let (loop, trio) = feedOracles()
        // A finished temp basal is reported to the pump's 0.001 U.
        let accuracy = 0.001 * Double(max(1, tempRates.count))
        XCTAssertEqual(loop.netBasalUnits(from: start, to: now, scheduledRate: scheduled), pump, accuracy: accuracy, "Loop: \(message)", file: file, line: line)
        XCTAssertEqual(
            try trio.netBasalUnits(from: start, to: now, clock: now, scheduledRate: scheduled),
            pump,
            accuracy: accuracy,
            "Trio: \(message)",
            file: file,
            line: line
        )
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
