import Foundation
import LoopKit
@testable import TandemKit
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

    // MARK: - D1

    /// A suspend and resume the pump did on its own: the suspend is dated at the pump's stop and
    /// paired by a `.resume` so the host closes it after 10 minutes.
    func testD1PumpInitiatedSuspendAndResumeArePairedAndDatedAtThePump() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
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

        try expectDefect("jwoglom/TandemKit#331: a resume the app did not command is reported as a .basal dose, never as .resume, so the host's suspend stays open") {
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

        try expectDefect("jwoglom/TandemKit#331: the pump-side resume after the occlusion is reported as .basal, never .resume, so the suspend stays open") {
            let resume = eventsSince(batchesBefore).first { $0.type == .resume }
            XCTAssertNotNil(resume, "\(eventsSince(batchesBefore))")
            XCTAssertEqual(resume?.date.timeIntervalSince(resumedAt) ?? .infinity, 0, accuracy: 1)
            let stored = loop.doses.first { $0.dose.type == .suspend }
            XCTAssertEqual(stored?.isMutable, false)
            XCTAssertEqual(stored?.dose.endDate.timeIntervalSince(stoppedAt) ?? 0, .minutes(5), accuracy: 2)
            XCTAssertEqual(trio.resumes.count, 1)
            timeline.assertMatches(loop)
        }
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

        try expectDefect("jwoglom/TandemKit (unfiled): TandemPeripheralManager logs an ErrorResponse on CurrentStatus and returns without resolving the pending Control write, so enactBolus fails only when the 30 s response timeout expires (TandemPeripheralManager.swift ErrorResponse branch)") {
            XCTAssertLessThan(elapsed, 10, "the refusal should be reported promptly, not after the response timeout; took \(elapsed)s")
        }

        // The pump has no bolus. (A real pump that answers ErrorResponse did not act.)
        let snapshot = try harness.client.snapshot()
        let pumpStartedBolusAnyway = snapshot.bolus.active
        if pumpStartedBolusAnyway {
            try expectDefect("faketandem gap: error_response is applied on the response path (pkg/handler/router.go sendWithFaults), after the InitiateBolus handler has already started the bolus; a real pump answering ErrorResponse would not have acted") {
                XCTAssertFalse(snapshot.bolus.active, "the pump must not be delivering a bolus it refused")
            }
            // Stop what the emulator started so nothing keeps running into the next scenario.
            try harness.client.abortBolus()
        } else {
            XCTAssertFalse(snapshot.bolus.active)
        }

        // The session survives the refusal.
        XCTAssertNotNil(try sync())

        let (loop, trio) = feedOracles()
        XCTAssertTrue(loop.doses.isEmpty, "no dose in Loop: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertTrue(loop.deletedDoses.isEmpty)
        XCTAssertTrue(trio.boluses.isEmpty, "no bolus row in Trio: \(trio.boluses)")

        let diff = try timeline().diff(against: loop)
        XCTAssertTrue(diff.duplicated.isEmpty && diff.mismatched.isEmpty && diff.extra.isEmpty, "\(diff)")
        // The only pump-side record the host does not know about is the bolus the emulator started
        // despite answering with an error.
        XCTAssertEqual(diff.missing.count, pumpStartedBolusAnyway ? 1 : 0, "\(diff)")
    }

    // MARK: - D4

    /// The pump completes a bolus but cannot say how much it delivered — first no `LastBolusStatus`
    /// answer at all, then an answer about a different bolus. The dose stays mutable rather than
    /// finalizing at 0 U or at the programmed total, and is closed with the estimate only once the
    /// retry window is over.
    func testD4DeliveredVolumeReadFailureKeepsTheBolusMutable() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
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

        XCTAssertTrue(
            try harness.requestsSeen().contains { $0.message.hasPrefix("LastBolusStatus") },
            "the driver asked for the delivered volume: \(try harness.requestsSeen().map(\.message))"
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

        // Phase 3: the retry window ends; the dose is closed with the estimate taken when delivery
        // stopped — a number, never a placeholder — under the same raw.
        try clock.advanceBoth(seconds: TandemPumpManager.bolusFinalizationWindow + .minutes(1))
        _ = try sync()
        XCTAssertNil(driver.manager.state.pendingBolusFinalization)

        let finalized = try IntegrationWait.value("finalized bolus report", timeout: 30) {
            self.eventsSince(batchesBefore).first { $0.raw == raw && $0.dose?.isMutable == false }
        }
        let delivered = try XCTUnwrap(finalized.dose?.deliveredUnits)
        XCTAssertGreaterThan(delivered, 0, "never finalized at 0 U")
        XCTAssertLessThanOrEqual(delivered, Self.bolusUnits + 0.0005)
        XCTAssertEqual(delivered, lastBolus.deliveredUnits, accuracy: 0.05, "the estimate is close to what the pump delivered")
        assertFieldSemantics(finalized, programmed: Self.bolusUnits, automatic: false)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, delivered)
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1)
        trio.assertSingleBolus(at: started.date, amount: Self.bolusUnits, accuracy: 0.1)

        // Pump side: the app's bolus agrees with Loop; the only record Loop lacks is the pump-side
        // 0.05 U bolus staged to make last_bolus stale.
        let timeline = try timeline()
        let diff = timeline.diff(against: loop, tolerance: PumpTimeline.Tolerance(time: 2, units: 0.05, rate: 0.005))
        XCTAssertTrue(diff.duplicated.isEmpty && diff.mismatched.isEmpty && diff.extra.isEmpty, "\(diff)")
        XCTAssertEqual(diff.missing, ["bolus \(staleId) (0.05 U)"], "\(diff)")
    }

    // MARK: - D5

    /// The pump's clock runs 15 minutes ahead of the phone's. Dose dates must come from the pump's
    /// ledger reconciled to phone time, temp-basal amounts from the pump's own rate, and the
    /// measured offset must reach the host through `didAdjustPumpClockBy`.
    func testD5PumpClockSkewIsMeasuredAndDosesFollowThePumpsLedger() throws {
        let skew: Double = 900
        try clock.setSkew(seconds: skew)

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
        try expectDefect("jwoglom/TandemKit#343 (G03): the measured pump clock offset is surfaced in settings but never reported through didAdjustPumpClockBy") {
            XCTAssertFalse(driver.delegate.clockAdjustments.isEmpty, "didAdjustPumpClockBy after measuring a \(skew)s offset")
        }

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
        assertFieldSemantics(finalizedBolus, programmed: Self.bolusUnits, automatic: false)

        let bolusTimeline = try timeline()
        let pumpBolus = try XCTUnwrap(bolusTimeline.boluses.first { $0.bolusId == bolusId }, "timeline: \(bolusTimeline)")
        let pumpEnd = try XCTUnwrap(pumpBolus.end)
        XCTAssertGreaterThan(pumpEnd, programmedAt)
        XCTAssertEqual(
            finalizedBolus.dose?.startDate.timeIntervalSince(pumpBolus.start ?? .distantPast) ?? .infinity, 0, accuracy: 2,
            "the dose starts when the pump began, in phone time"
        )
        try expectDefect("jwoglom/TandemKit (unfiled): with the pump clock ahead, BolusEndDate takes LastBolusStatus.timestamp raw and clamps it to detection time instead of subtracting the offset the driver has just measured, so the bolus end is dated at the poll that noticed it (Sources/TandemKit/PumpManager/BolusEndDate.swift)") {
            XCTAssertEqual(
                finalizedBolus.dose?.endDate.timeIntervalSince(pumpEnd) ?? .infinity, 0, accuracy: 2,
                "the dose ends when the pump's record says, in phone time"
            )
        }

        // Temp basal: 1.5 U/h asked for; the driver programs 150 % of what it believes the segment
        // is; the pump applies 150 % to the segment it is in.
        let tbrBatchesBefore = allPumpEventBatches.count
        let tbrStart = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        let running = try harness.client.snapshot().basal
        XCTAssertTrue(running.tempActive)
        XCTAssertEqual(running.tempPercent, 150)
        XCTAssertEqual(running.tempRate, pumpSegmentRate * 1.5, accuracy: 0.0005, "the pump runs percent × its own segment")
        let tbrEvent = try XCTUnwrap(eventsSince(tbrBatchesBefore).first { $0.dose?.type == .tempBasal })
        let tbrRaw = tbrEvent.raw
        XCTAssertEqual(tbrEvent.dose?.isMutable, true)
        try expectDefect("jwoglom/TandemKit#343 / #335: the temp basal's value is the phone's schedule segment × percent (getScheduledBasalRate at phone time); the pump applies the percent to its own current segment on its own clock, and CurrentBasalStatusResponse.profileBasalRate is fetched but unused") {
            XCTAssertEqual(tbrEvent.dose?.unitsPerHour ?? -1, running.tempRate, accuracy: 0.005, "value must be the rate the pump is running")
        }

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
        let pumpTBR = try XCTUnwrap(timeline.tempRates.first, "timeline: \(timeline)")
        XCTAssertTrue(pumpTBR.isFinished)
        try expectDefect("jwoglom/TandemKit#343 / #335: deliveredUnits is the phone-side value × elapsed time, inheriting the wrong rate") {
            XCTAssertEqual(finalizedTBR.dose?.deliveredUnits ?? -1, pumpTBR.deliveredUnits ?? -2, accuracy: 0.005, "delivered units follow the pump's rate")
        }

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        loop.assertPermanent(raw: bolusRaw)
        loop.assertPermanent(raw: tbrRaw)
        XCTAssertEqual(trio.boluses.count, 1)
        XCTAssertEqual(trio.tempBasals.count, 1)
        try expectDefect("jwoglom/TandemKit#343 / #335 and the unfiled end-date clamp above: the host's ledger disagrees with the pump's under clock skew") {
            timeline.assertMatches(loop)
        }
    }

    // MARK: - D6

    /// The pump drops the link while nothing is running. The driver reconnects on its own — and a
    /// reconnect should sync and report a fresh boundary, since anything can have happened meanwhile.
    func testD6AutoReconnectAfterAPumpSideDropSyncsAndReports() throws {
        let driver = try startPairedDriver(scheduledRate: Self.profileRate)
        // Move time on so a post-reconnect boundary would be strictly newer than the last one.
        try clock.advanceBoth(seconds: .minutes(1))
        let batchesBefore = allPumpEventBatches.count
        let reconciliationBefore = try XCTUnwrap(driver.manager.state.lastReconciliation)
        let logStart = try harness.client.snapshot().requestLog.lastSeq

        try disconnectFromPump()
        XCTAssertFalse(try harness.client.snapshot().connection.connected)

        // Real time: the auto-reconnect is the driver's own timer, not the modelled clock.
        try IntegrationWait.until("the driver to reconnect and re-authenticate", timeout: 60) {
            try driver.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }
        let connections = try harness.requestLog(since: logStart).filter { $0.kind == "connection" }.compactMap(\.connected)
        XCTAssertEqual(connections, [false, true], "one drop, one reconnect")

        // A bounded real-time window for the driver to sync on its own after reconnecting.
        let reportedOnReconnect = (try? IntegrationWait.until("a hasNewPumpEvents after the reconnect", timeout: 15) {
            self.allPumpEventBatches.count > batchesBefore
        }) != nil

        try expectDefect("jwoglom/TandemKit#351: BLE auto-reconnect completes authenticated setup and flips isConnected only; no sync, no lastReconciliation stamp and no hasNewPumpEvents until the next throttled poll") {
            XCTAssertTrue(reportedOnReconnect, "the reconnect itself should produce a delegate report")
            let latest = allPumpEventBatches.dropFirst(batchesBefore).last
            XCTAssertNotNil(latest?.lastReconciliation)
            XCTAssertGreaterThan(latest?.lastReconciliation ?? .distantPast, reconciliationBefore, "a fresh boundary")
            XCTAssertGreaterThan(driver.manager.state.lastReconciliation ?? .distantPast, reconciliationBefore)
        }

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
        let reading = try XCTUnwrap(driver.delegate.reservoirReadings.last)
        XCTAssertEqual(reading.units, newLevel, accuracy: 0.5, "the reservoir reading follows the refill")

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

    // MARK: - Helpers

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
