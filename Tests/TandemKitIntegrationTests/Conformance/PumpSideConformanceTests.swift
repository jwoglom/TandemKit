import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Conformance group D (`docs/conformance-test-plan.md`): pump-side failures and events. The pump
/// does something the driver did not command — stops, alarms, refuses a command, loses a record,
/// runs its clock wrong, drops the link — or the host tears the driver down, and the question is
/// what the host is told. D9 is covered by group C (C7).
///
/// Every scenario asserts through both oracles and the journal and ends with the pump-timeline
/// diff. Where the driver is known not to conform, the assertion stays as the guide demands and
/// only the failing checks are wrapped in a strict `XCTExpectFailure` naming the issue, so a fix
/// flips the wrapper to an unexpected pass. Emulator gaps are wrapped the same way, naming the gap.
final class PumpSideConformanceTests: ConformanceTestCase {
    /// The scheduled basal rate both sides start from (the phone's schedule and the pump's profile).
    private static let profileRate = 1.0
    private static let bolusUnits = 1.0
    /// Delivery at the rate the driver's estimate assumes, as in the smoke test, so end-date fidelity
    /// is not what these scenarios trip on.
    private static let deliveryRate = bolusUnits / TandemPumpCapabilities.estimatedBolusDuration(toDeliver: bolusUnits)
    /// The emulator's default bolus delivery rate (`bolus_rate_units_per_second`).
    private static let defaultDeliveryRate = 0.05

    /// `harness.reset()` restores pairing, clock, faults and the link, not delivery: a suspend, a
    /// running bolus or temp rate and a changed profile rate would carry into the next scenario
    /// (the emulator answers 409 to a second suspend). Put the pump back before the base teardown,
    /// so the records this writes land before the next test's history start.
    override func setUpWithError() throws {
        try super.setUpWithError()
        // The base case stops a test at its first failure. XCTest applies that to an *expected*
        // failure too, which would end every scenario at its first wrapped defect and report it
        // passed; these scenarios must run to their timeline diff.
        continueAfterFailure = true

        // A scenario killed part-way (the simulator is shared with other runs) leaves the pump
        // stopped or a dose running, and the emulator answers 409 to a second suspend. Only then is
        // there anything to undo, so in the normal case this writes nothing to the pump's ledger
        // after the history start this test's timeline is taken from.
        let snapshot = try harness.client.snapshot()
        if snapshot.bolus.active || snapshot.basal.tempActive || snapshot.basal.suspended {
            try restorePumpDelivery(harness.client)
        }
    }

    override func tearDownWithError() throws {
        if let harness {
            do {
                try restorePumpDelivery(harness.client)
            } catch {
                XCTFail("restoring the pump's delivery state failed: \(error)")
            }
        }
        try super.tearDownWithError()
    }

    private func restorePumpDelivery(_ client: FaketandemClient) throws {
        let snapshot = try client.snapshot()
        if snapshot.bolus.active {
            try client.abortBolus()
        }
        if snapshot.basal.tempActive {
            try client.stopTempBasal()
        }
        if snapshot.basal.suspended {
            try client.resume(clearAlarms: true)
        }
        try client.setState(["basal_rate": Self.profileRate, "bolus_rate_units_per_second": Self.defaultDeliveryRate])
    }

    // MARK: - D1

    /// A suspend and resume the pump did on its own: the suspend is dated at the pump's stop and
    /// paired by a `.resume` so the host closes it after 10 minutes.
    func testD1PumpInitiatedSuspendAndResumeArePairedAndDatedAtThePump() throws {
        try startPairedDriver(scheduledRate: Self.profileRate)
        let batchesBefore = allPumpEventBatches.count

        // The pump stops on its own (a qualifying pumpSuspend event fires); then a sync.
        let suspendedAt = clock.now
        try harness.client.suspend(reason: "user")
        XCTAssertTrue(try harness.client.snapshot().basal.suspended)
        _ = waitForPumpEvent("the driver to report the pump-side suspend", since: batchesBefore, timeout: 20) { $0.type == .suspend }
        _ = try sync()

        let suspendEvents = eventsSince(batchesBefore).filter { $0.type == .suspend }
        XCTAssertEqual(suspendEvents.count, 1, "one suspend dose for one stop: \(suspendEvents)")
        let suspend = try XCTUnwrap(suspendEvents.first)
        XCTAssertEqual(suspend.date.timeIntervalSince(suspendedAt), 0, accuracy: 1, "the suspend is dated at the pump's stop")
        XCTAssertEqual(suspend.dose?.startDate.timeIntervalSince(suspendedAt) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(suspend.dose?.isMutable, false, "a suspend is an immutable point event")
        XCTAssertEqual(suspend.dose?.syncIdentifier, suspend.raw.hexadecimalString, "syncIdentifier derives from raw")

        // Ten minutes suspended, then the pump resumes on its own.
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        let resumedAt = clock.now
        try harness.client.resume()
        XCTAssertFalse(try harness.client.snapshot().basal.suspended)
        _ = waitForPumpEvent("the driver to report the pump-side resume", since: batchesBefore, timeout: 20) {
            ($0.type == .resume || $0.type == .basal) && $0.date >= resumedAt
        }
        _ = try sync()

        let afterResume = eventsSince(batchesBefore).filter { $0.date >= resumedAt }
        XCTAssertTrue(
            afterResume.contains { $0.type == .basal || $0.type == .resume },
            "the driver notices delivery is back: \(afterResume)"
        )
        if let marker = afterResume.first(where: { $0.type == .basal }) {
            XCTAssertEqual(marker.dose?.unitsPerHour ?? -1, Self.profileRate, accuracy: 0.005, "the basal picture is restored at the scheduled rate")
        }

        // Pump side: one suspend of ten minutes.
        let timeline = try timeline()
        let pumpSuspend = try XCTUnwrap(timeline.suspends.first, "timeline: \(timeline)")
        XCTAssertEqual(pumpSuspend.reason, "user")
        XCTAssertEqual(pumpSuspend.start.timeIntervalSince(suspendedAt), 0, accuracy: 1)
        XCTAssertEqual(pumpSuspend.resumed?.timeIntervalSince(resumedAt) ?? .infinity, 0, accuracy: 1)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .suspend }.count, 1, "Loop holds one suspend: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(trio.suspends.count, 1)
        XCTAssertEqual(trio.suspends.first?.timestamp, suspend.date)

        let resume = afterResume.first { $0.type == .resume }
        XCTAssertNotNil(resume, "a .resume dose for the pump-side resume: \(afterResume)")
        XCTAssertEqual(resume?.date.timeIntervalSince(resumedAt) ?? .infinity, 0, accuracy: 1, "the resume is dated at the pump's restart")
        XCTAssertEqual(resume?.dose?.isMutable, false, "a resume is an immutable point event")

        // Loop closes the suspend at the resume: ten minutes, immutable.
        let stored = loop.doses.first { $0.dose.type == .suspend }
        XCTAssertEqual(stored?.isMutable, false, "an unpaired suspend is held mutable (InsulinMath.reconciled): \(stored.map(LoopDoseStoreOracle.describe) ?? "nil")")
        XCTAssertEqual(stored?.dose.endDate.timeIntervalSince(suspendedAt) ?? 0, .minutes(10), accuracy: 2, "suspend duration")

        // Trio: a PumpResume row closes the PumpSuspend.
        XCTAssertEqual(trio.resumes.count, 1, "Trio resumes: \(trio.resumes)")
        timeline.assertMatches(loop)
    }

    // MARK: - D2

    /// An occlusion stops delivery: an `.alarm` event with its type, a `.suspend`, and on the pump's
    /// resume with the alarm cleared an alarm-clear and a `.resume`.
    func testD2OcclusionAlarmIsReportedWithItsSuspendAndClear() throws {
        try startPairedDriver(scheduledRate: Self.profileRate)
        let batchesBefore = allPumpEventBatches.count

        let stoppedAt = clock.now
        try harness.client.suspend(reason: "occlusion")
        let stopped = try harness.client.snapshot()
        XCTAssertTrue(stopped.basal.suspended)
        XCTAssertEqual(stopped.basal.suspendReason, "occlusion")
        XCTAssertEqual(stopped.alerts.count, 1, "the pump raised the occlusion alarm: \(stopped.alerts)")
        _ = waitForPumpEvent("the driver to report the occlusion stop", since: batchesBefore, timeout: 20) { $0.type == .suspend }
        _ = try sync()

        // The stop itself is reported, dated at the pump's stop (P02-5 / #333 is about the poll
        // delay; in lock-step the pump's stop and the driver's now coincide).
        let suspendEvents = eventsSince(batchesBefore).filter { $0.type == .suspend }
        XCTAssertEqual(suspendEvents.count, 1, "\(suspendEvents)")
        let suspend = try XCTUnwrap(suspendEvents.first)
        XCTAssertEqual(suspend.date.timeIntervalSince(stoppedAt), 0, accuracy: 1)
        XCTAssertEqual(suspend.dose?.isMutable, false)

        // Pump side: the alarm is on the ledger.
        let stoppedTimeline = try timeline()
        XCTAssertEqual(stoppedTimeline.alarms.count, 1, "timeline alarms: \(stoppedTimeline.alarms)")
        XCTAssertEqual(stoppedTimeline.alarms.first?.reason, "occlusion")
        XCTAssertEqual(stoppedTimeline.suspends.first?.reason, "occlusion")

        let midway = feedOracles()
        try expectDefect("jwoglom/TandemKit#349: pump alarms are surfaced only as LoopKit Alerts; no live path emits NewPumpEvent(type: .alarm) and alarmType is never populated (P14-1, P14-2, P10-6)") {
            let alarm = eventsSince(batchesBefore).first { $0.type == .alarm }
            XCTAssertNotNil(alarm, "an .alarm pump event for the occlusion: \(eventsSince(batchesBefore))")
            XCTAssertEqual(alarm?.alarmType, .occlusion, "alarmType names the fault")
            XCTAssertEqual(alarm?.date.timeIntervalSince(stoppedAt) ?? .infinity, 0, accuracy: 1, "the alarm is dated at the pump's alarm")
            XCTAssertEqual(midway.trio.alarms.count, 1, "Trio stores the alarm as PumpAlarm: \(midway.trio.events)")
        }

        // The pump resumes with the alarm acknowledged.
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let resumedAt = clock.now
        try harness.client.resume(clearAlarms: true)
        let resumed = try harness.client.snapshot()
        XCTAssertFalse(resumed.basal.suspended)
        XCTAssertTrue(resumed.alerts.isEmpty, "clear_alarms dropped the alarm: \(resumed.alerts)")
        _ = waitForPumpEvent("the driver to report the resume", since: batchesBefore, timeout: 20) {
            ($0.type == .resume || $0.type == .basal) && $0.date >= resumedAt
        }
        _ = try sync()

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .suspend }.count, 1)
        XCTAssertEqual(trio.suspends.count, 1)
        let timeline = try timeline()

        try expectDefect("jwoglom/TandemKit#349: no .alarmClear pump event when the pump's alarm clears (the LoopKit Alert channel is the only one retracted)") {
            let cleared = eventsSince(batchesBefore).first { $0.type == .alarmClear }
            XCTAssertNotNil(cleared, "an .alarmClear event once the alarm is acknowledged: \(eventsSince(batchesBefore))")
        }

        let resume = eventsSince(batchesBefore).first { $0.type == .resume }
        XCTAssertNotNil(resume, "\(eventsSince(batchesBefore))")
        XCTAssertEqual(resume?.date.timeIntervalSince(resumedAt) ?? .infinity, 0, accuracy: 1)
        let stored = loop.doses.first { $0.dose.type == .suspend }
        XCTAssertEqual(stored?.isMutable, false)
        XCTAssertEqual(stored?.dose.endDate.timeIntervalSince(stoppedAt) ?? 0, .minutes(5), accuracy: 2)
        XCTAssertEqual(trio.resumes.count, 1)
        timeline.assertMatches(loop)
    }

    // MARK: - D3

    /// The pump answers `InitiateBolus` with an `ErrorResponse`: the enact fails promptly, nothing is
    /// reported, nothing runs.
    func testD3ErrorResponseToInitiateBolusFailsPromptlyWithNoDose() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        let batchesBefore = allPumpEventBatches.count
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        var fault = FaketandemFaultSpec(.errorResponse, message: "InitiateBolusRequest")
        fault.errorCode = 3
        XCTAssertNotNil(try harness.client.armFault(fault))

        let started = Date()
        let error = try enactBolus(units: Self.bolusUnits)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertNotNil(error, "an ErrorResponse must fail the enact")
        XCTAssertNil(driver.manager.state.bolusDose, "no bolus is recorded for a refused command")
        XCTAssertTrue(
            eventsSince(batchesBefore).filter { $0.dose?.type == .bolus }.isEmpty,
            "no dose may be reported for a bolus the pump refused: \(eventsSince(batchesBefore))"
        )

        // The pump's side: the fault fired on the InitiateBolus exchange.
        let log = try harness.requestLog(since: logStart)
        XCTAssertTrue(log.contains { $0.fault == "error_response" }, "the emulator sent the ErrorResponse: \(log.map { "\($0.kind) \($0.message ?? "") \($0.fault ?? "")" })")
        XCTAssertTrue(
            try harness.requestsSeen(since: logStart).contains { $0.message == "InitiateBolusRequest" },
            "InitiateBolus reached the pump"
        )

        XCTAssertLessThan(
            elapsed,
            FaketandemHarness.responseTimeout / 2,
            "the refusal should be reported promptly, not after the response timeout; took \(elapsed)s"
        )

        // A pump that answers ErrorResponse did not act.
        XCTAssertFalse(try harness.client.snapshot().bolus.active, "the pump must not be delivering a bolus it refused")

        // The session survives the refusal.
        XCTAssertNotNil(try sync())

        let (loop, trio) = feedOracles()
        XCTAssertTrue(loop.doses.isEmpty, "no dose in Loop: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertTrue(loop.deletedDoses.isEmpty)
        XCTAssertTrue(trio.boluses.isEmpty, "no bolus row in Trio: \(trio.boluses)")

        let diff = try timeline().diff(against: loop)
        XCTAssertTrue(diff.duplicated.isEmpty && diff.mismatched.isEmpty && diff.extra.isEmpty, "\(diff)")
        XCTAssertTrue(diff.missing.isEmpty, "\(diff)")
    }

    // MARK: - D4

    /// The pump completes a bolus but cannot say how much it delivered — first no `LastBolusStatus`
    /// answer at all, then an answer about a different bolus — and with history backfill off there
    /// is no other record. The dose stays mutable while the driver retries, and once the window is
    /// over is finalized at its programmed amount, never 0 U (#448).
    func testD4DeliveredVolumeReadFailureKeepsTheBolusMutable() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        turnOffHistoryBackfill(driver)
        try harness.client.setState(["bolus_rate_units_per_second": Self.deliveryRate])
        let batchesBefore = allPumpEventBatches.count

        // Whichever last-bolus message the driver picks for this pump, the answer is lost.
        for name in ["LastBolusStatusV3Request", "LastBolusStatusV2Request", "LastBolusStatusRequest"] {
            var fault = FaketandemFaultSpec(.dropResponse, message: name)
            fault.every = true
            XCTAssertNotNil(try harness.client.armFault(fault))
        }

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let started = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus })
        let raw = started.raw
        XCTAssertEqual(started.dose?.isMutable, true)

        // Phase 1: the bolus finishes on the pump; the driver notices but gets no delivered volume.
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        XCTAssertEqual(lastBolus.deliveredUnits, Self.bolusUnits, accuracy: 0.0005)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))
        _ = try sync()

        let requestsSeen = try harness.requestsSeen().map(\.message)
        XCTAssertTrue(
            requestsSeen.contains { $0.hasPrefix("LastBolusStatus") },
            "the driver asked for the delivered volume: \(requestsSeen)"
        )
        XCTAssertNotNil(driver.manager.state.pendingBolusFinalization, "the bolus is held for finalization")
        assertNoFinalizedGuess(raw: raw, since: batchesBefore)
        let afterDrop = feedOracles()
        let heldAfterDrop = try XCTUnwrap(afterDrop.loop.assertSingleDose(raw: raw, "after the dropped LastBolusStatus"))
        XCTAssertTrue(heldAfterDrop.isMutable, "unknown volume: the dose stays mutable, \(LoopDoseStoreOracle.describe(heldAfterDrop))")
        XCTAssertNil(heldAfterDrop.dose.deliveredUnits, "a mutable bolus carries no deliveredUnits")

        // Phase 2: the pump answers, but its last-bolus record is a different bolus.
        try harness.client.clearFaults()
        let staleId = bolusId + 100
        try harness.client.startBolus(units: 0.05, bolusId: staleId, source: "pump")
        try harness.client.completeBolus()
        XCTAssertEqual(try harness.client.snapshot().lastBolus?.bolusId, staleId, "last_bolus is now the stale record")
        let logBeforeRetry = try harness.client.snapshot().requestLog.lastSeq
        try clock.advanceBoth(seconds: .minutes(1))
        _ = try sync()

        let retryLog = try harness.requestLog(since: logBeforeRetry)
        XCTAssertTrue(retryLog.contains { $0.isRequest && ($0.message ?? "").hasPrefix("LastBolusStatus") }, "the driver retried the read")
        XCTAssertTrue(retryLog.contains { $0.isResponse && ($0.message ?? "").hasPrefix("LastBolusStatus") }, "and the pump answered this time")
        XCTAssertNotNil(driver.manager.state.pendingBolusFinalization, "a record for another bolus is not this bolus's volume")
        assertNoFinalizedGuess(raw: raw, since: batchesBefore)
        let afterStale = feedOracles()
        let heldAfterStale = try XCTUnwrap(afterStale.loop.assertSingleDose(raw: raw, "after the stale LastBolusStatus"))
        XCTAssertTrue(heldAfterStale.isMutable, LoopDoseStoreOracle.describe(heldAfterStale))

        // Phase 3: the retry window ends; the dose is closed at the programmed amount Loop counted
        // while it was held, under the same raw.
        try clock.advanceBoth(seconds: TandemPumpManager.bolusFinalizationWindow + .minutes(1))
        _ = try sync()
        XCTAssertNil(driver.manager.state.pendingBolusFinalization)

        let finalized = try IntegrationWait.value("finalized bolus report", timeout: 30) {
            self.eventsSince(batchesBefore).first { $0.raw == raw && $0.dose?.isMutable == false }
        }
        let delivered = try XCTUnwrap(finalized.dose?.deliveredUnits)
        XCTAssertLessThanOrEqual(delivered, Self.bolusUnits + 0.0005)
        assertFieldSemantics(finalized, programmed: Self.bolusUnits, automatic: false)
        XCTAssertEqual(delivered, Self.bolusUnits, "the programmed amount, which the pump delivered in full")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, delivered)
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1)

        // Pump side: the app's bolus agrees with Loop; the only record Loop lacks is the pump-side
        // 0.05 U bolus staged to make last_bolus stale.
        // With no pump timestamp the end is the driver's model, which counts the 15 s lead-in the
        // emulator does not.
        let timeline = try timeline()
        let diff = timeline.diff(
            against: loop,
            tolerance: PumpTimeline.Tolerance(time: TandemPumpCapabilities.bolusInitiationDelay + 2, units: 0.001, rate: 0.005)
        )
        XCTAssertEqual(diff.missing, ["bolus \(staleId) (0.05 U)"], "\(diff)")
        trio.assertSingleBolus(at: started.date, amount: Self.bolusUnits)
        XCTAssertTrue(diff.duplicated.isEmpty && diff.mismatched.isEmpty && diff.extra.isEmpty, "\(diff)")
    }

    /// D4 with history backfill on, and a bolus the pump stops short: `LastBolusStatus` never
    /// answers, so the volume comes from the `BolusCompleted` record backfill reads, before the
    /// retry window ends and below the programmed-amount fallback (#448).
    func testD4bAnUnreadableBolusIsFinalizedFromThePumpsHistory() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        // Slower than the driver's model, so the pump's timestamp, not the model, dates the end.
        try harness.client.setState(["bolus_rate_units_per_second": Self.bolusUnits / 100])
        let batchesBefore = allPumpEventBatches.count
        try dropEveryLastBolusStatus()

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let started = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus })
        let raw = started.raw

        try clock.advanceBoth(seconds: 60, ticks: 12)
        try harness.client.abortBolus()
        let lastBolus = try XCTUnwrap(try harness.client.snapshot().lastBolus)
        XCTAssertEqual(lastBolus.bolusId, bolusId)
        XCTAssertLessThan(lastBolus.deliveredUnits, Self.bolusUnits - 0.2, "stopped short of the programmed amount")
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))

        let heldFrom = clock.now
        let finalized = try syncUntilFinalized(raw: raw)
        XCTAssertLessThan(clock.now.timeIntervalSince(heldFrom), TandemPumpManager.bolusFinalizationWindow, "without waiting out the window")
        XCTAssertFalse(
            try harness.requestLog().contains { $0.isResponse && ($0.message ?? "").hasPrefix("LastBolusStatus") && $0.fault == nil },
            "no LastBolusStatus answer ever reached the driver"
        )

        let dose = try XCTUnwrap(finalized.dose)
        XCTAssertEqual(dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005, "the pump's recorded volume")
        XCTAssertEqual(dose.endDate.timeIntervalSince(lastBolus.endTime), 0, accuracy: 2, "dated by the pump's record")
        XCTAssertNil(driver.manager.state.pendingBolusFinalization)
        assertFieldSemantics(finalized, programmed: Self.bolusUnits, automatic: false)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(loop.assertPermanent(raw: raw)?.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)
        trio.assertSingleBolus(at: started.date, amount: lastBolus.deliveredUnits)
        try timeline().assertMatches(loop, tolerance: PumpTimeline.Tolerance(time: 2, units: 0.001, rate: 0.005))
    }

    // MARK: - D5

    /// The pump's clock runs 15 minutes ahead of the phone's. Dose dates must come from the pump's
    /// ledger reconciled to phone time, a temp basal the pump runs at another rate is stopped and
    /// never reported, and setting the pump's clock must tell the host through `didAdjustPumpClockBy`.
    func testD5PumpClockSkewIsMeasuredAndDosesFollowThePumpsLedger() throws {
        let skew: Double = 900
        // A minute behind the wall clock: #339's start-date clamp is to Date.now, so its error is
        // this lag, and a fast emulator would otherwise shrink it inside the tolerance.
        try clock.start(at: Date().addingTimeInterval(-60), skewSeconds: skew)

        // The phone's schedule: the current segment at 1.0 U/h, the next (in 5 minutes of phone
        // time) at 2.0 U/h. On its own clock the pump is already 15 minutes on, i.e. in that next
        // segment, so its profile rate is 2.0 U/h.
        let pumpSegmentRate = 2.0
        let secondsIntoDay = clock.now.timeIntervalSince(Calendar.current.startOfDay(for: clock.now))
        var items = [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]
        if secondsIntoDay + .minutes(10) < .hours(24) {
            items.append(RepeatingScheduleValue(startTime: secondsIntoDay + .minutes(5), value: pumpSegmentRate))
        }
        let schedule = try XCTUnwrap(BasalRateSchedule(dailyItems: items))
        let driver = try startPairedDriver(scheduledRate: Self.profileRate, pumpProfileRate: pumpSegmentRate, schedule: schedule)
        try harness.client.setState(["bolus_rate_units_per_second": Self.deliveryRate])
        XCTAssertEqual(driver.manager.getScheduledBasalRate(), Self.profileRate, "the phone is still in the 1.0 U/h segment")

        // The driver measured the skew on the first sync.
        let pumpTime = try XCTUnwrap(driver.manager.state.currentPumpTime, "TimeSinceReset was read")
        XCTAssertEqual(pumpTime.timeIntervalSince(clock.now), skew, accuracy: 5, "the pump reads \(skew)s ahead")

        // Bolus: programmed, observed delivering, completed on the pump, finalized.
        let batchesBefore = allPumpEventBatches.count
        let programmedAt = clock.now
        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let bolusStart = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus })
        let bolusRaw = bolusStart.raw
        _ = try sync() // a status poll while delivering, as a loop cycle would do
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        XCTAssertEqual(lastBolus.deliveredUnits, Self.bolusUnits, accuracy: 0.0005)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))
        _ = try sync()
        let finalizedBolus = try IntegrationWait.value("finalized bolus report", timeout: 30) {
            self.eventsSince(batchesBefore).first { $0.raw == bolusRaw && $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalizedBolus.dose?.deliveredUnits, Self.bolusUnits)
        assertFieldSemantics(
            finalizedBolus,
            programmed: Self.bolusUnits,
            automatic: false
        )

        let bolusTimeline = try timeline()
        let pumpBolus = try XCTUnwrap(bolusTimeline.boluses.first { $0.bolusId == bolusId }, "timeline: \(bolusTimeline)")
        let pumpEnd = try XCTUnwrap(pumpBolus.end)
        XCTAssertGreaterThan(pumpEnd, programmedAt)
        XCTAssertEqual(
            finalizedBolus.dose?.startDate.timeIntervalSince(pumpBolus.start ?? .distantPast) ?? .infinity, 0, accuracy: 2,
            "the dose starts when the pump began, in phone time"
        )
        XCTAssertEqual(
            finalizedBolus.dose?.endDate.timeIntervalSince(pumpEnd) ?? .infinity, 0, accuracy: 2,
            "the dose ends when the pump's record says, in phone time"
        )

        // Temp basal: 1.5 U/h asked for; the driver works the percent out against the segment the
        // pump is in.
        let tbrBatchesBefore = allPumpEventBatches.count
        let tbrStart = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        let running = try harness.client.snapshot().basal
        XCTAssertTrue(running.tempActive)
        XCTAssertEqual(running.tempPercent, 75)
        XCTAssertEqual(running.tempRate, 1.5, accuracy: 0.0005, "75 % of the pump's 2.0 U/h segment")
        let tbrEvent = try XCTUnwrap(eventsSince(tbrBatchesBefore).first { $0.dose?.type == .tempBasal })
        let tbrRaw = tbrEvent.raw
        XCTAssertEqual(tbrEvent.dose?.isMutable, true)
        XCTAssertEqual(tbrEvent.dose?.unitsPerHour ?? -1, running.tempRate, accuracy: 0.005, "value must be the rate the pump is running")

        // Let it expire on the pump and be finalized.
        try clock.advanceBoth(seconds: .minutes(31), ticks: 31)
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive)
        _ = try sync()
        let finalizedTBR = try IntegrationWait.value("finalized temp basal report", timeout: 30) {
            self.eventsSince(tbrBatchesBefore).first { $0.raw == tbrRaw && $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalizedTBR.dose?.endDate.timeIntervalSince(tbrStart) ?? 0, .minutes(30), accuracy: 2, "finalized at the scheduled end")
        assertFieldSemantics(finalizedTBR, programmed: nil, automatic: true)

        let timeline = try timeline()
        let pumpTBR = try XCTUnwrap(timeline.tempRates.first { $0.percent == 75 }, "timeline: \(timeline)")
        XCTAssertTrue(pumpTBR.isFinished)
        XCTAssertEqual(finalizedTBR.dose?.deliveredUnits ?? -1, pumpTBR.deliveredUnits ?? -2, accuracy: 0.005, "delivered units follow the pump's rate")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        loop.assertPermanent(raw: bolusRaw)
        loop.assertPermanent(raw: tbrRaw)
        XCTAssertEqual(trio.boluses.count, 1)
        XCTAssertEqual(trio.tempBasals.count, 1)
        try expectDefect("the clock skew temp the pump runs while the phone's segment lags is on its record and, by design, not the host's; and #339's end-date clamp above") {
            timeline.assertMatches(loop)
        }

        XCTAssertEqual(driver.delegate.clockAdjustments, [], "measuring the skew does not move the pump's clock")
        XCTAssertNoThrow(try syncPumpTime().get())
        XCTAssertEqual(driver.delegate.clockAdjustments.count, 1)
        XCTAssertEqual(driver.delegate.clockAdjustments.first ?? 0, -skew, accuracy: 5, "moved back by the skew")
        XCTAssertEqual(driver.manager.state.pumpClockOffset, 0, accuracy: 5)
    }

    // MARK: - D6

    /// The pump drops the link while nothing is running. The driver reconnects on its own, then syncs
    /// and reports a fresh boundary, since anything can have happened meanwhile (#351).
    func testD6AutoReconnectAfterAPumpSideDropSyncsAndReports() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        // Move time on so a post-reconnect boundary would be strictly newer than the last one.
        try clock.advanceBoth(seconds: .minutes(1))
        let batchesBefore = allPumpEventBatches.count
        let reconciliationBefore = try XCTUnwrap(driver.manager.state.lastReconciliation)
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        // The pump drops the link. The driver reconnects faster than a snapshot poll can catch the
        // link down, so the pump's request log is the record of the drop.
        try harness.control.disconnectPump()

        // Real time: the auto-reconnect is the driver's own timer, not the modelled clock.
        let connections = try IntegrationWait.value("the pump to log the drop and a new connection", timeout: 60) {
            let entries = try harness.requestLog(since: logStart).filter { $0.kind == "connection" }.compactMap(\.connected)
            return entries == [false, true] ? entries : nil
        }
        XCTAssertEqual(connections, [false, true], "one drop, one reconnect")
        try IntegrationWait.until("the driver to reconnect and re-authenticate", timeout: 60) {
            try driver.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }

        try IntegrationWait.until("a hasNewPumpEvents after the reconnect", timeout: 30) {
            self.allPumpEventBatches.count > batchesBefore
        }
        let latest = allPumpEventBatches.dropFirst(batchesBefore).last
        XCTAssertNotNil(latest?.lastReconciliation)
        XCTAssertGreaterThan(latest?.lastReconciliation ?? .distantPast, reconciliationBefore, "a fresh boundary")
        XCTAssertGreaterThan(driver.manager.state.lastReconciliation ?? .distantPast, reconciliationBefore)
        let reads = try harness.requestLog(since: logStart).filter(\.isRequest).compactMap(\.message)
        XCTAssertTrue(reads.contains("CurrentBasalStatusRequest"), "the reconnect's sync read the pump: \(reads)")

        // The new session serves a sync and the host is left consistent.
        try clock.advanceBoth(seconds: .minutes(1))
        XCTAssertNotNil(try sync())
        XCTAssertGreaterThan(try XCTUnwrap(driver.manager.state.lastReconciliation), reconciliationBefore)
        XCTAssertTrue(driver.delegate.errors.isEmpty, "\(driver.delegate.errors)")

        let (loop, trio) = feedOracles()
        XCTAssertTrue(loop.doses.isEmpty, "nothing was delivered: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertTrue(trio.events.isEmpty, "\(trio.events)")
        XCTAssertEqual(loop.lastReconciliation, driver.manager.state.lastReconciliation)
        try timeline().assertMatches(loop)
    }

    // MARK: - D7

    /// The host deletes the pump manager while a bolus and a temp basal are running. The teardown
    /// path Loop and Trio call is `prepareForDeactivation`, which is what the harness's shutdown
    /// drives; the host must be left with finalized (or at least resolved) doses and told it is
    /// happening. A Tandem pump keeps delivering after the app forgets it, so no `.suspend` is due.
    func testD7DeactivatingWithLiveDosesResolvesThemAndNotifiesTheHost() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        // Slow enough that 2 U is still running minutes later.
        try harness.client.setState(["bolus_rate_units_per_second": 0.005])
        let batchesBefore = allPumpEventBatches.count

        // The temp basal first: the driver refuses a TBR while it has a bolus running.
        let tbrStart = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        let tbrEvent = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .tempBasal })
        let tbrRaw = tbrEvent.raw
        XCTAssertEqual(tbrEvent.dose?.isMutable, true)

        let bolusUnits = 2.0
        XCTAssertNil(try enactBolus(units: bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let bolusEvent = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus })
        let bolusRaw = bolusEvent.raw
        XCTAssertEqual(bolusEvent.dose?.isMutable, true)

        // A minute into both.
        try clock.advanceBoth(seconds: 60, ticks: 6)
        let live = try harness.client.snapshot()
        XCTAssertTrue(live.bolus.active && live.bolus.bolusId == bolusId, "the bolus is still running: \(live.bolus)")
        XCTAssertTrue(live.basal.tempActive, "the temp basal is still running")
        let batchesBeforeDeactivation = allPumpEventBatches.count
        let deactivatedAt = clock.now

        // Loop's teardown: prepareForDeactivation (bluetooth.deactivate + notifyDelegateOfDeactivation).
        try shutDownDriver()
        driver.drainDelegate()

        XCTAssertEqual(driver.delegate.willDeactivateCount, 1, "pumpManagerWillDeactivate fires once")
        let journal = driver.delegate.journal
        XCTAssertTrue(journal.contains { if case .willDeactivate = $0.kind { return true } else { return false } })

        // The pump keeps delivering both; the driver must not invent a stop.
        let afterDeactivation = try harness.client.snapshot()
        XCTAssertTrue(afterDeactivation.bolus.active, "a Tandem pump finishes the bolus after the app is gone")
        XCTAssertTrue(afterDeactivation.basal.tempActive, "and runs the temp rate to its end")
        let finalBatches = Array(allPumpEventBatches.dropFirst(batchesBeforeDeactivation))
        let finalEvents = finalBatches.flatMap(\.events)
        XCTAssertFalse(finalEvents.contains { $0.type == .suspend }, "no phantom suspend: delivery did not stop: \(finalEvents)")

        try expectDefect("jwoglom/TandemKit#350 (G06): prepareForDeactivation tears down the transport without a final batch, so the host's mutable temp basal and bolus rows can never be finalized, reach HealthKit or advance the boundary") {
            XCTAssertFalse(finalBatches.isEmpty, "a final hasNewPumpEvents before deactivation")
            XCTAssertEqual(finalBatches.last?.replacePendingEvents, true, "the final batch is a complete, replacing one")
            let finalTBR = finalEvents.last { $0.raw == tbrRaw }
            XCTAssertNotNil(finalTBR, "the temp basal is in the final batch")
            XCTAssertEqual(finalTBR?.dose?.isMutable, false, "finalized")
            XCTAssertNotNil(finalTBR?.dose?.deliveredUnits)
            XCTAssertEqual(finalTBR?.dose?.endDate.timeIntervalSince(deactivatedAt) ?? .infinity, 0, accuracy: 2, "at the real end of what the host can vouch for")
            let finalBolus = finalEvents.last { $0.raw == bolusRaw }
            XCTAssertNotNil(finalBolus, "the bolus is resolved or marked in the final batch")
            if let finalTBR { assertFieldSemantics(finalTBR, programmed: nil, automatic: true) }
        }

        // What the host does hold: one identity each, no duplicates, mutable rows that agree with a
        // pump that is still running both.
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let storedTBR = try XCTUnwrap(loop.assertSingleDose(raw: tbrRaw))
        let storedBolus = try XCTUnwrap(loop.assertSingleDose(raw: bolusRaw))
        XCTAssertEqual(storedTBR.dose.endDate.timeIntervalSince(tbrStart), .minutes(30), accuracy: 1, "a running TBR ends at its scheduled end")
        XCTAssertEqual(storedBolus.dose.programmedUnits, bolusUnits)
        XCTAssertEqual(trio.boluses.count, 1)
        XCTAssertEqual(trio.tempBasals.count, 1)
        for event in eventsSince(batchesBefore) where event.dose != nil {
            XCTAssertEqual(event.dose?.manuallyEntered, false, "pump-delivered doses are not manually entered: \(event)")
            XCTAssertNotNil(event.dose?.insulinType, "insulinType is set: \(event)")
            XCTAssertEqual(event.dose?.syncIdentifier, event.raw.hexadecimalString, "syncIdentifier derives from raw")
        }
        try timeline().assertMatches(loop)
    }

    // MARK: - D8

    /// The pump records a cartridge fill and its reservoir jumps: the host needs a component
    /// replacement event (the guide's `.replaceComponent(.reservoir)`; the audit accepts the
    /// `.rewind` idiom Trio consumes) or a `.prime`.
    func testD8CartridgeChangeOnThePumpIsReportedAsAComponentReplacement() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        let before = try harness.client.snapshot().insulin.reservoirUnits
        let newLevel = 300.0
        XCTAssertNotEqual(before, newLevel)
        let batchesBefore = allPumpEventBatches.count

        // The pump's ledger: a CartridgeFilled record now, the reservoir reset, and the
        // remaining-insulin qualifying event a real pump raises with it.
        let changedAt = clock.now
        try harness.client.appendHistory(type: "CartridgeFilled", secondsAgo: 0, data: ["insulinDisplay": newLevel, "insulinActual": newLevel])
        try harness.client.setState(["reservoir_units": newLevel])
        try harness.client.raiseQualifyingEvent(bitmask: 262_144)
        try clock.advanceBoth(seconds: 5)
        _ = try sync()

        // The host learns the new level.
        // `InsulinStatusResponse.currentInsulinAmount` is whole units on the wire, so a 300 U fill
        // that has already drained a few milliunits of basal is reported as 299: one unit is the
        // resolution the reading can follow the refill to, on a real pump as much as on this one.
        let reading = try XCTUnwrap(driver.delegate.reservoirReadings.last)
        XCTAssertEqual(reading.units, newLevel, accuracy: 1, "the reservoir reading follows the refill")
        XCTAssertNotEqual(reading.units, before, "and is not still the pre-fill level")

        let (loop, trio) = feedOracles()
        let timeline = try timeline()
        XCTAssertTrue(timeline.unplaced.contains { $0.type == "CartridgeFilled" }, "the pump recorded the fill: \(timeline.unplaced)")

        try expectDefect("jwoglom/TandemKit#349: a cartridge fill recorded by the pump (CartridgeFilledHistoryLog) is never turned into a pump event — the history mapper drops it and is unwired behind default-off flags; only the app's own wizard emits a component event (P14-4)") {
            let event = eventsSince(batchesBefore).first(where: Self.isComponentReplacement)
            XCTAssertNotNil(event, "a .replaceComponent(.reservoir) / .rewind / .prime for the pump's cartridge fill: \(eventsSince(batchesBefore))")
            XCTAssertEqual(event?.date.timeIntervalSince(changedAt) ?? .infinity, 0, accuracy: 2, "dated at the pump's record")
            XCTAssertTrue(trio.events.contains { $0.type == .rewind || $0.type == .prime || $0.type == .siteChange }, "Trio stores the change marker: \(trio.events)")
        }

        // The app-side wizard path (the only emitter today) reports the change with the shape the
        // guide wants: a dose-less event of a component-replacement type.
        let wizardBatchesBefore = allPumpEventBatches.count
        driver.manager.recordCartridgeChange(at: clock.now)
        drainDelegate()
        let wizard = try XCTUnwrap(eventsSince(wizardBatchesBefore).first(where: Self.isComponentReplacement), "\(eventsSince(wizardBatchesBefore))")
        XCTAssertNil(wizard.dose, "a component change carries no dose")
        XCTAssertEqual(wizard.date, clock.now)
        XCTAssertEqual(allPumpEventBatches.last?.replacePendingEvents, false, "a marker event does not purge pending doses")

        let after = feedOracles()
        XCTAssertTrue(after.loop.doses.isEmpty, "no insulin dose came out of a cartridge change: \(after.loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(after.trio.events.filter { $0.type == .rewind || $0.type == .prime }.count, 1, "\(after.trio.events)")
        XCTAssertTrue(loop.doses.isEmpty)
        timeline.assertMatches(after.loop)
    }

    // MARK: - D10

    /// A fill wizard finds the pump already stopped, by the pump itself out of the driver's hearing, and
    /// later resumes. Unless the stop reaches the host, the host counts it as delivered basal.
    func testD10ASuspendAWizardFindsIsReportedBeforeItsResume() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        // A first history read the outage cuts short would start tracking after the stop.
        try IntegrationWait.until("the driver to start tracking the pump's history", timeout: 60) {
            driver.manager.state.deliveryTransitions.trackedAfter != nil
        }
        let batchesBefore = allPumpEventBatches.count

        let suspendedAt = try suspendOutOfEarshot(thenAdvance: .minutes(5))
        XCTAssertEqual(driver.manager.state.basalDose.type, .basal, "the driver never heard of the stop")

        // The wizards' first step (TandemKit{ChangeCartridge,FillTubing,FillCannula}ViewModel).
        let checkedAt = clock.now
        XCTAssertEqual(try fetchSuspendStatus(driver.manager), true, "the pump says it is suspended")

        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        let resumedAt = clock.now
        XCTAssertNil(try resumeDelivery(), "the wizard's resume")
        _ = try sync()

        let events = eventsSince(batchesBefore)
        let resume = try XCTUnwrap(events.first { $0.type == .resume }, "the app's resume reaches the host: \(events)")
        XCTAssertEqual(resume.date.timeIntervalSince(resumedAt), 0, accuracy: 1)

        let timeline = try timeline()
        let pumpSuspend = try XCTUnwrap(timeline.suspends.first, "timeline: \(timeline)")
        XCTAssertEqual(pumpSuspend.start.timeIntervalSince(suspendedAt), 0, accuracy: 1)
        XCTAssertEqual(pumpSuspend.resumed?.timeIntervalSince(resumedAt) ?? .infinity, 0, accuracy: 1)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()

        let suspend = events.first { $0.type == .suspend }
        XCTAssertNotNil(suspend, "a .suspend for the stop the wizard found: \(events)")
        XCTAssertLessThan(
            events.firstIndex { $0.type == .suspend } ?? .max,
            events.firstIndex { $0.type == .resume } ?? .min,
            "reported before the resume: Trio takes a resume with no suspend before it as suspended since its history began"
        )
        XCTAssertLessThanOrEqual(suspend?.date ?? .distantFuture, checkedAt, "dated no later than the check that found it")
        let stored = loop.doses.first { $0.dose.type == .suspend }
        XCTAssertEqual(stored?.isMutable, false, "the resume closes the host's suspend: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(suspend?.date.timeIntervalSince(suspendedAt) ?? .infinity, 0, accuracy: 1, "the suspend is dated at the pump's stop")
        timeline.assertMatches(loop)
    }

    // MARK: - D11

    /// The pump stops on its own under a running temp basal, out of the driver's hearing, and the app
    /// resumes as a fill wizard does: the resume's replacing batch has to account for that temp basal.
    func testD11AResumeOverATempBasalTheDriverStillHoldsFinalizesIt() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        let batchesBefore = allPumpEventBatches.count

        let tempStart = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(60)))
        XCTAssertTrue(eventsSince(batchesBefore).contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true })
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)

        let suspendedAt = try suspendOutOfEarshot(thenAdvance: .minutes(5))
        XCTAssertEqual(driver.manager.state.basalDose.type, .tempBasal, "the driver still holds the temp basal as running")

        let resumedAt = clock.now
        XCTAssertNil(try resumeDelivery(), "the wizard's resume")
        _ = try sync()
        XCTAssertTrue(eventsSince(batchesBefore).contains { $0.type == .resume }, "the app's resume reaches the host")

        let timeline = try timeline()
        let pumpTemp = try XCTUnwrap(timeline.tempRates.first, "timeline: \(timeline)")
        XCTAssertEqual(pumpTemp.start.timeIntervalSince(tempStart), 0, accuracy: 2)
        XCTAssertTrue(pumpTemp.isFinished, "the stop ended the temp rate on the pump: \(timeline)")
        let pumpSuspend = try XCTUnwrap(timeline.suspends.first, "timeline: \(timeline)")
        XCTAssertEqual(pumpSuspend.start.timeIntervalSince(suspendedAt), 0, accuracy: 1)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()

        let omissions = completeBatchOmissions()
        XCTAssertTrue(omissions.isEmpty, "nothing live may be dropped by silence:\n" + omissions.joined(separator: "\n"))
        let finished = loop.permanentDoses.first { $0.dose.type == .tempBasal && abs($0.dose.startDate.timeIntervalSince(tempStart)) <= 1 }
        XCTAssertNotNil(finished, "the host holds the temp basal, finalized: \(loop.doses.map(LoopDoseStoreOracle.describe)); deleted: \(loop.deletedDoses.map(LoopDoseStoreOracle.describe))")
        XCTAssertLessThanOrEqual(finished?.dose.endDate ?? .distantFuture, resumedAt, "it ended no later than the resume")
        XCTAssertGreaterThan(finished?.dose.deliveredUnits ?? 0, 0, "with what it delivered")
        expectDefect("jwoglom/TandemKit#348: resumeDelivery does not read the pump first, so the temp basal its stop ended is finished at the resume, and Loop does not count the stop history reports after it (#354)") {
            timeline.assertMatches(loop)
        }
    }

    // MARK: - D12

    /// Guide §7 and §11 "external doses", but reported only once the pump's completion is read: one
    /// finalized dose at the pump's delivered amount, and nothing while it runs (#452).
    func testD12ABolusProgrammedOnThePumpIsReportedFromItsHistory() throws {
        let driver = try startPairedDriverReportingHistory()
        try harness.client.setState(["bolus_rate_units_per_second": 0.01])
        let batchesBefore = allPumpEventBatches.count

        let startedAt = clock.now
        try harness.client.startBolus(units: Self.bolusUnits, source: "pump")
        let bolusId = try harness.client.snapshot().bolus.bolusId
        try clock.advanceBoth(seconds: 20, ticks: 4)
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the pump is still delivering")
        let activatedSequence = try harness.client.snapshot().history.lastSequence
        _ = try sync()
        try IntegrationWait.until("the backfill to read the running bolus", timeout: 120) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= activatedSequence } ?? false
        }
        // The report runs as a command job after the tick; a sync queues behind it.
        _ = try sync()
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "still delivering once the backfill has read it")
        XCTAssertFalse(
            eventsSince(batchesBefore).contains { $0.dose?.type == .bolus },
            "a running pump bolus is not reported: \(eventsSince(batchesBefore))"
        )

        // The loop sets a temp basal meanwhile, as it does every few minutes.
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        let omissions = completeBatchOmissions()
        XCTAssertTrue(omissions.isEmpty, "nothing live may be dropped by silence:\n" + omissions.joined(separator: "\n"))

        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId)
        XCTAssertEqual(lastBolus.deliveredUnits, Self.bolusUnits, accuracy: 0.0005)
        try clock.advanceBoth(seconds: 30, ticks: 3)
        _ = try sync()
        let reported = try IntegrationWait.value("the pump's bolus reported from its history", timeout: 120) {
            self.eventsSince(batchesBefore).first { $0.dose?.type == .bolus }
        }
        let raw = reported.raw
        XCTAssertEqual(reported.dose?.isMutable, false, "reported finished")
        XCTAssertEqual(reported.dose?.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005, "at the pump's delivered amount")
        XCTAssertEqual(reported.dose?.programmedUnits ?? -1, Self.bolusUnits, accuracy: 0.0005)
        XCTAssertEqual(reported.dose?.wasProgrammedByPumpUI, true, "marked as programmed on the pump (§7)")
        XCTAssertEqual(reported.dose?.automatic, false)
        XCTAssertEqual(reported.dose?.startDate.timeIntervalSince(startedAt) ?? .infinity, 0, accuracy: 2, "dated when the pump started it")

        _ = try sync()
        XCTAssertEqual(eventsSince(batchesBefore).filter { $0.raw == raw }.count, 1, "reported once")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let timeline = try timeline()
        XCTAssertTrue(timeline.boluses.contains { $0.bolusId == bolusId && $0.isFinished }, "timeline: \(timeline.boluses)")
        let stored = loop.assertPermanent(raw: raw, "the pump's bolus once it finished")
        XCTAssertEqual(stored?.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.0005)
        timeline.assertMatches(loop)
    }

    // MARK: - D13

    /// A 100% extended bolus logs no BolusActivated/BolusCompleted pair, only BolexActivated (59) and
    /// BolexCompleted (21).
    func testD13AnExtendedBolusProgrammedOnThePumpIsReportedFromItsHistory() throws {
        let driver = try startPairedDriverReportingHistory()
        let batchesBefore = allPumpEventBatches.count
        let bolusId = 7024
        let units = 2.0

        let startedAt = clock.now
        try harness.client.appendHistory(type: "BolexActivated", secondsAgo: 0, data: [
            "bolusId": bolusId, "selectedIob": 0, "iob": 0.0, "bolexSize": units,
        ])
        try clock.advanceBoth(seconds: .minutes(30), ticks: 30)
        let completedAt = clock.now
        let completedSequence = try harness.client.appendHistory(type: "BolexCompleted", secondsAgo: 0, data: [
            "completionStatus": 3, "bolusId": bolusId, "iob": 0.0, "insulinDelivered": units, "insulinRequested": units,
        ]).history.lastSequence

        _ = try sync()
        try IntegrationWait.until("the backfill to read the extended bolus's completion", timeout: 180) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= completedSequence } ?? false
        }
        // The report runs as a command job after the tick; a sync queues behind it.
        _ = try sync()

        let events = eventsSince(batchesBefore)
        expectDefect("jwoglom/TandemKit#424: BolexActivated (59) and BolexCompleted (21) fall through HistoryToDoseMapper's default: continue, so an extended bolus programmed on the pump never reaches the host") {
            let extended = events.first { $0.dose?.type == .bolus }
            XCTAssertNotNil(extended, "a dose for the pump's extended bolus: \(events)")
            XCTAssertEqual(extended?.dose?.deliveredUnits ?? -1, units, accuracy: 0.0005, "at BolexCompleted's insulinDelivered")
            XCTAssertEqual(extended?.dose?.startDate.timeIntervalSince(startedAt) ?? .infinity, 0, accuracy: 2, "from BolexActivated")
            XCTAssertEqual(extended?.dose?.endDate.timeIntervalSince(completedAt) ?? .infinity, 0, accuracy: 2, "to BolexCompleted")
            XCTAssertEqual(extended?.dose?.wasProgrammedByPumpUI, true)
            XCTAssertGreaterThan(feedOracles().loop.iob(at: completedAt), 0, "the extended bolus counts towards IOB")
        }
    }

    // MARK: - Helpers

    /// Waits out the first backfill tick, so anything the pump logs from here on is newer than the
    /// floor it reports from.
    @discardableResult
    private func startPairedDriverReportingHistory() throws -> FaketandemHarness.Driver {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        state.insulinType = .novolog
        state.basalRateSchedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]))
        let driver = startDriver(state: state)
        try harness.client.setState(["basal_rate": Self.profileRate])
        try harness.pair(driver)
        _ = try sync()
        try IntegrationWait.until("the first backfill tick", timeout: 180) {
            driver.manager.state.historyBackfill != nil
        }
        return driver
    }

    /// The pump stops delivery while the link is down, so none of its qualifying events reach the driver;
    /// the next command's own connect queues the reconnect's sync behind it, so it finds the state as it was.
    private func suspendOutOfEarshot(reason: String = "user", thenAdvance seconds: TimeInterval) throws -> Date {
        _ = try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the emulator to drop the link", timeout: 30) {
            try !self.harness.client.snapshot().connection.connected
        }
        let suspendedAt = clock.now
        _ = try harness.client.suspend(reason: reason)
        XCTAssertTrue(try harness.client.snapshot().basal.suspended, "the pump stopped")
        try clock.advanceBoth(seconds: seconds, ticks: max(1, Int(seconds / 60)))
        _ = try harness.client.armFault(FaketandemFaultSpec(.radioOn))
        return suspendedAt
    }

    private func fetchSuspendStatus(_ manager: TandemPumpManager, timeout: TimeInterval = 60) throws -> Bool? {
        let box = ResultBox<Bool?>()
        manager.fetchSuspendStatus { box.set($0) }
        let result = try box.wait("fetchSuspendStatus completion", timeout: timeout)
        drainDelegate()
        return result
    }

    /// Start, configure the schedule both sides agree on, pair and sync. `schedule` overrides the
    /// flat one; `pumpProfileRate` lets the pump's profile differ from the phone's current segment.
    @discardableResult
    private func startPairedDriver(
        scheduledRate: Double,
        pumpProfileRate: Double? = nil,
        schedule: BasalRateSchedule? = nil
    ) throws -> FaketandemHarness.Driver {
        let driver = startDriver()
        driver.manager.state.insulinType = .novolog
        driver.manager.state.basalRateSchedule = try XCTUnwrap(
            schedule ?? BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: scheduledRate)])
        )
        try harness.client.setState(["basal_rate": pumpProfileRate ?? scheduledRate])
        try harness.pair(driver)
        _ = try sync()
        return driver
    }

    /// Every event in the batches journaled after the first `count`.
    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        allPumpEventBatches.dropFirst(count).flatMap(\.events)
    }

    /// Waits (real time) for the driver to report an event matching `predicate` on its own — the
    /// qualifying-event path — and returns nil rather than failing when it does not, since the
    /// following sync is the guide's fallback and the scenario asserts on the result either way.
    private func waitForPumpEvent(
        _ what: String,
        since count: Int,
        timeout: TimeInterval,
        where predicate: @escaping (NewPumpEvent) -> Bool
    ) -> NewPumpEvent? {
        try? IntegrationWait.value(what, timeout: timeout) {
            self.eventsSince(count).first(where: predicate)
        }
    }

    /// Section E on a finalized dose: programmed `value`, `deliveredUnits` on the 0.001 U grid,
    /// immutable, pump-delivered, typed insulin, identity from `raw`.
    private func assertFieldSemantics(
        _ event: NewPumpEvent,
        programmed: Double?,
        automatic: Bool?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let dose = event.dose else {
            XCTFail("finalized event has no dose: \(event)", file: file, line: line)
            return
        }
        XCTAssertFalse(dose.isMutable, "finalized doses are immutable: \(event)", file: file, line: line)
        if let programmed {
            XCTAssertEqual(LoopDoseStoreOracle.programmedValue(dose), programmed, accuracy: 0.0005, "value is the programmed amount", file: file, line: line)
        }
        if let delivered = dose.deliveredUnits {
            XCTAssertEqual(delivered * 1000, (delivered * 1000).rounded(), accuracy: 1e-6, "deliveredUnits \(delivered) is on the 0.001 U increment", file: file, line: line)
        } else {
            XCTFail("a finalized dose carries deliveredUnits: \(event)", file: file, line: line)
        }
        XCTAssertFalse(dose.manuallyEntered, "pump-delivered doses are not manually entered", file: file, line: line)
        if let automatic {
            XCTAssertEqual(dose.automatic, automatic, "automatic reflects the activation type", file: file, line: line)
        }
        XCTAssertNotNil(dose.insulinType, "insulinType is set", file: file, line: line)
        XCTAssertEqual(dose.syncIdentifier, event.raw.hexadecimalString, "syncIdentifier derives from raw", file: file, line: line)
    }

    /// No immutable report for `raw` has been made — in particular none guessing 0 U or the
    /// programmed total for a volume the pump never confirmed.
    private func assertNoFinalizedGuess(raw: Data, since count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let finalized = eventsSince(count).filter { $0.raw == raw && $0.dose?.isMutable == false }
        XCTAssertTrue(
            finalized.isEmpty,
            "the bolus was finalized without a confirmed volume: \(finalized.map { "\($0.dose?.deliveredUnits ?? -1) U" })",
            file: file,
            line: line
        )
    }

    private static func isComponentReplacement(_ event: NewPumpEvent) -> Bool {
        switch event.type {
        case .rewind, .prime, .replaceComponent(componentType: .reservoir):
            return true
        default:
            return false
        }
    }

    /// A strict expected failure: the assertions inside must fail today, and a fix turns the block
    /// into an unexpected pass so the wrapper is removed with it.
    private func expectDefect<R>(_ reason: String, _ body: () throws -> R) rethrows -> R {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        return try XCTExpectFailure(reason, options: options, failingBlock: body)
    }
}
