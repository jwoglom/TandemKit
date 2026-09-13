import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Conformance group A, "interrupt everything" (`docs/conformance-test-plan.md` §A; guide §10
/// "bolus during BLE loss", §11; audit P11, P12, P15, G02).
///
/// Every scenario starts a dose, breaks something in the middle — the link, a response, the app
/// itself, the radio — and then asks what the two hosts would have stored against what the pump
/// actually did. Assertions go through the oracles and the journal, never only the last delegate
/// call, and every scenario ends with the timeline diff. Where the driver is known to be
/// non-conformant the assertion stays as the guide demands and only the failing checks are wrapped
/// in a strict `XCTExpectFailure` naming the issue, so a fix flips them to "unexpected pass".
///
/// Timing: both clocks are frozen and moved together with `advanceBoth`. The only real-time waits
/// are the driver's own — its 30 s response timeout when a response is lost (A2, A5) and the
/// seconds an auto-reconnect takes.
final class InterruptConformanceTests: ConformanceTestCase {
    /// The pump's profile basal rate and the driver's scheduled rate, kept equal so a percent temp
    /// rate means the same U/h on both sides.
    private static let profileRate = 1.0

    /// Bolus delivery rate on the pump, in U/s. Deliberately slower than the driver's model
    /// (`bolusInitiationDelay` + `estimatedBolusDuration`, 72.5 s for 2 U): `BolusEndDate.resolve`
    /// uses that model as a floor under the pump's `LastBolusStatus` timestamp, so only a pump that
    /// finishes *later* than the model proves the driver took its end from the pump's record. A
    /// 2 U bolus takes 100 s.
    private static let slowBolusRate = 0.02

    private static let bolusUnits = 2.0

    // MARK: - Setup helpers

    /// A paired, synced driver with what a host configures at onboarding (insulin type, basal
    /// schedule) and a pump whose profile rate and bolus speed are the fixture's.
    @discardableResult
    private func stageDriver(bolusRate: Double = InterruptConformanceTests.slowBolusRate) throws -> FaketandemHarness.Driver {
        try harness.client.setState([
            "basal_rate": Self.profileRate,
            "bolus_rate_units_per_second": bolusRate,
        ])
        let driver = try startPairedDriver()
        configureHostSettings(driver)
        return driver
    }

    private func configureHostSettings(_ driver: FaketandemHarness.Driver) {
        driver.manager.state.insulinType = .novolog
        driver.manager.state.basalRateSchedule = BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]
        )!
    }

    /// Blocks until the driver has a live authenticated session again after a link drop.
    private func waitForReconnect(timeout: TimeInterval = 90) throws {
        let running = try XCTUnwrap(driver, "no driver")
        try IntegrationWait.until("driver to reconnect and re-authenticate", timeout: timeout) {
            try running.manager.state.isConnected && harness.client.snapshot().auth.authenticated
        }
    }

    /// Blocks until the pump has logged the link going down since `logSequence`. The pump's record
    /// is used rather than the driver's `isConnected`, which an auto-reconnect can flip back within
    /// a second.
    private func waitForLinkDown(since logSequence: Int, timeout: TimeInterval = 30) throws {
        try IntegrationWait.until("pump to log the link down", timeout: timeout) {
            try harness.requestLog(since: logSequence).contains { $0.kind == "connection" && $0.connected == false }
        }
    }

    /// The finalized (`isMutable == false`) report of the dose with this `raw`, waiting for the
    /// delegate queue to deliver it.
    private func finalizedEvent(raw: Data, timeout: TimeInterval = 30) throws -> NewPumpEvent {
        try IntegrationWait.value("finalized report of \(LoopDoseStoreOracle.describe(raw))", timeout: timeout) {
            self.allPumpEventBatches.flatMap(\.events).first { $0.raw == raw && $0.dose?.isMutable == false }
        }
    }

    /// The pump's own record of when a bolus ended, from its history and `last_bolus`.
    private func pumpBolus(_ bolusId: Int) throws -> PumpTimeline.Bolus {
        let timeline = try timeline()
        return try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId }, "pump timeline has no bolus \(bolusId): \(timeline)")
    }

    /// Messages the pump parsed since `since`, by name.
    private func messagesSeen(since: Int) throws -> [String] {
        try harness.requestsSeen(since: since).map(\.message)
    }

    /// Whether `units` sits on the pump's 0.001 U reporting increment.
    private func isOnMilliunitGrid(_ units: Double) -> Bool {
        let milliunits = units * 1000
        return abs(milliunits - milliunits.rounded()) < 1e-6
    }

    /// Section E of the plan: field semantics every finalized dose is held to.
    private func assertFinalizedFieldSemantics(
        _ event: NewPumpEvent,
        programmed: Double,
        activationType: BolusActivationType? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let dose = try XCTUnwrap(event.dose, "finalized event carries no dose", file: file, line: line)
        XCTAssertFalse(dose.isMutable, "a finalized dose is immutable", file: file, line: line)
        XCTAssertEqual(dose.syncIdentifier, event.raw.hexadecimalString, "syncIdentifier is derived from raw", file: file, line: line)
        XCTAssertNotNil(dose.insulinType, "insulinType is set", file: file, line: line)

        let delivered = try XCTUnwrap(dose.deliveredUnits, "a finalized dose carries deliveredUnits", file: file, line: line)
        switch dose.type {
        case .bolus:
            XCTAssertEqual(dose.programmedUnits, programmed, "value is the programmed amount", file: file, line: line)
            XCTAssertTrue(isOnMilliunitGrid(delivered), "bolus deliveredUnits \(delivered) is on the 0.001 U increment", file: file, line: line)
            let activation = try XCTUnwrap(activationType, "bolus semantics need the activation type", file: file, line: line)
            XCTAssertEqual(dose.automatic, activation.isAutomatic, "automatic reflects the activation type", file: file, line: line)
            if activation == .manualNoRecommendation {
                XCTExpectFailure("jwoglom/TandemKit#337: manuallyEntered is set for a normal pump-delivered bolus (DoseEntry.bolus maps manualNoRecommendation to manuallyEntered)") {
                    XCTAssertFalse(dose.manuallyEntered, "a pump-delivered bolus is not manually entered", file: file, line: line)
                }
            } else {
                XCTAssertFalse(dose.manuallyEntered, "a pump-delivered bolus is not manually entered", file: file, line: line)
            }
        case .tempBasal:
            XCTAssertEqual(dose.unitsPerHour, programmed, accuracy: 0.0001, "value is the programmed rate", file: file, line: line)
            XCTAssertEqual(dose.automatic, true, "a loop-commanded temp basal is automatic", file: file, line: line)
            XCTAssertFalse(dose.manuallyEntered, file: file, line: line)
            XCTExpectFailure("audit P11-5 (no issue filed): temp basal deliveredUnits is value × hours with no rounding to the 0.001 U increment (UnfinalizedDose.toDoseEntry)") {
                XCTAssertTrue(isOnMilliunitGrid(delivered), "temp basal deliveredUnits \(delivered) is on the 0.001 U increment", file: file, line: line)
            }
        default:
            XCTFail("unexpected dose type \(dose.type) for a finalized dose check", file: file, line: line)
        }
    }

    // MARK: - A1

    /// BLE drops on the driver's first `CurrentBolusStatus` read after the pump accepted the
    /// bolus; the pump keeps delivering and finishes; the driver reconnects and syncs.
    func testA1_bleDropMidBolusPumpKeepsDeliveringIsFinalizedFromThePumpsRecord() throws {
        let driver = try stageDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        let batchesBefore = allPumpEventBatches.count

        // Armed before the enact: the pump raises BOLUS_CHANGE as soon as InitiateBolus is
        // applied, and the driver's very next message is the CurrentBolusStatus this cuts off.
        var fault = FaketandemFaultSpec(.disconnect, message: "CurrentBolusStatusRequest")
        fault.after = "request"
        try harness.client.armFault(fault)

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let enactBatches = Array(allPumpEventBatches.dropFirst(batchesBefore))
        let started = try XCTUnwrap(enactBatches.flatMap(\.events).first { $0.dose?.type == .bolus }, "the enact registers the bolus")
        XCTAssertEqual(started.dose?.isMutable, true, "registered as a mutable dose before contact can be lost")
        let raw = started.raw

        // The pump cut the link instead of answering the status read.
        let dropEntry = try IntegrationWait.value("pump to drop the link on CurrentBolusStatus", timeout: 30) {
            try harness.requestLog(since: logStart).first { $0.isResponse && $0.message == "CurrentBolusStatusResponse" && $0.fault == "disconnect" }
        }
        XCTAssertEqual(dropEntry.fragmentsSent ?? 0, 0, "the status answer never went out")
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the pump keeps delivering through the drop")
        try waitForLinkDown(since: logStart)

        // The pump finishes; the driver may or may not have its session back by then.
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId, step: 2)
        XCTAssertEqual(lastBolus.deliveredUnits, Self.bolusUnits)
        XCTAssertEqual(lastBolus.endReasonId, 3, "completed, not stopped")

        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))
        try waitForReconnect()
        _ = try sync()

        let finalized = try finalizedEvent(raw: raw)
        let pumpRecord = try pumpBolus(bolusId)
        XCTAssertEqual(finalized.raw, raw, "finalized under the same identity")
        XCTAssertEqual(finalized.dose?.deliveredUnits, lastBolus.deliveredUnits, "deliveredUnits is the pump's last_bolus.delivered")
        let pumpEnd = try XCTUnwrap(pumpRecord.end)
        XCTAssertEqual(
            try XCTUnwrap(finalized.dose?.endDate).timeIntervalSince(pumpEnd), 0, accuracy: 2,
            "endDate is the pump's completion time, not the driver's estimate (pump \(pumpEnd))"
        )
        try assertFinalizedFieldSemantics(finalized, programmed: Self.bolusUnits, activationType: .manualNoRecommendation)

        // Wire: the pump saw the delivered-volume read after the drop; nothing was guessed.
        let afterDrop = try harness.requestLog(since: dropEntry.seq).filter(\.isRequest).map { $0.message ?? "" }
        XCTAssertTrue(afterDrop.contains { $0.hasPrefix("LastBolusStatus") }, "finalization reads the pump's record; pump saw \(afterDrop)")

        // Hosts: exactly one dose in Loop, permanent, at the pump's amount; one bolus row in Trio.
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, lastBolus.deliveredUnits)
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1, "one bolus, not a 0 U or programmed-amount twin: \(loop.doses.map(LoopDoseStoreOracle.describe))")
        trio.assertNoDuplicates()
        trio.assertSingleBolus(at: started.date, amount: Self.bolusUnits)

        let timeline = try timeline()
        XCTAssertTrue(timeline.connections.contains { !$0.connected }, "the pump recorded the drop")
        XCTAssertTrue(timeline.connections.contains(where: \.connected), "and the reconnect")
        timeline.assertMatches(loop)
    }

    // MARK: - A2

    /// The pump applies `InitiateBolus` but its acknowledgement is lost (#327).
    func testA2_lostInitiateBolusAcknowledgementStillRegistersTheBolus() throws {
        let driver = try stageDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        let batchesBefore = allPumpEventBatches.count

        try harness.client.armFault(FaketandemFaultSpec(.dropResponse, message: "InitiateBolusRequest"))

        // The driver waits its 30 s response timeout (real time) before giving up.
        let error = try enactBolus(units: 1.0, timeout: 90)
        guard case .communication? = error else {
            return XCTFail("a lost acknowledgement is a communication error, got \(String(describing: error))")
        }

        // Pump side: the bolus is running under the id the driver was granted.
        let pumpBolus = try harness.client.snapshot().bolus
        XCTAssertTrue(pumpBolus.active, "the pump applied the bolus before the response was lost")
        XCTAssertEqual(pumpBolus.unitsTotal, 1.0)
        XCTAssertEqual(pumpBolus.sourceId, 8)
        let bolusId = pumpBolus.bolusId
        let suppressed = try harness.requestLog(since: logStart).first { $0.isResponse && $0.message == "InitiateBolusResponse" }
        XCTAssertEqual(suppressed?.fault, "drop_response", "the pump encoded the ack and suppressed it: \(String(describing: suppressed))")
        XCTAssertEqual(suppressed?.fragmentsSent ?? 0, 0, "no fragment of the ack went out")

        // Guide §10: register the dose up front, and say delivery is uncertain until the pump confirms.
        let enactBatches = Array(allPumpEventBatches.dropFirst(batchesBefore))
        let registered = enactBatches.flatMap(\.events).first { $0.dose?.type == .bolus }
        XCTExpectFailure("jwoglom/TandemKit#327: a lost InitiateBolus acknowledgement leaves a possibly-running bolus untracked; nothing is registered and deliveryIsUncertain is hard-coded false") {
            XCTAssertNotNil(registered, "a mutable, uncertain bolus is reported when the ack is lost; batches: \(enactBatches.map(\.events))")
            XCTAssertEqual(registered?.dose?.isMutable, true)
            XCTAssertTrue(driver.manager.status.deliveryIsUncertain, "delivery is uncertain until the pump confirms or denies the bolus")
            XCTAssertNotNil(driver.manager.state.bolusDose, "the bolus id and units are kept for reconciliation")
        }

        // Next contact: the pump is delivering the driver's bolus id; the driver must confirm it.
        try clock.advanceBoth(seconds: 5, ticks: 5)
        XCTAssertTrue(try harness.client.snapshot().bolus.active)
        _ = try sync()
        XCTAssertTrue(
            try messagesSeen(since: logStart).contains("CurrentBolusStatusRequest"),
            "the sync asked the pump about the bolus"
        )
        let midRun = feedOracles()
        XCTExpectFailure("jwoglom/TandemKit#327: the sync sees the pump delivering the driver's bolus id and confirms nothing") {
            XCTAssertEqual(midRun.loop.mutableDoses.filter { $0.dose.type == .bolus }.count, 1, "the running bolus is held as one mutable dose: \(midRun.loop.doses.map(LoopDoseStoreOracle.describe))")
        }

        // The pump finishes; a sync past the driver's model must finalize it at the pump's amount.
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId, step: 2)
        XCTAssertEqual(lastBolus.deliveredUnits, 1.0)
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: 1.0) + .minutes(2))
        _ = try sync()

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertLessThanOrEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1, "never two doses for one bolus")
        let finalizedBoluses = loop.permanentDoses.filter { $0.dose.type == .bolus }
        let timeline = try timeline()
        let pumpRecord = try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId })
        XCTAssertTrue(pumpRecord.isFinished)
        XCTExpectFailure("jwoglom/TandemKit#327: the bolus the pump delivered is never reported, so both hosts have no IOB for it") {
            XCTAssertEqual(finalizedBoluses.count, 1, "the delivered bolus is finalized once: \(loop.doses.map(LoopDoseStoreOracle.describe))")
            XCTAssertEqual(finalizedBoluses.first?.dose.deliveredUnits, lastBolus.deliveredUnits)
            XCTAssertEqual(trio.boluses.count, 1, "Trio has the bolus")
            timeline.assertMatches(loop)
        }
    }

    // MARK: - A3

    /// The app is killed and relaunched while the pump delivers (#326).
    func testA3_relaunchMidBolusFinalizesFromLastBolusStatus() throws {
        let first = try stageDriver()
        let batchesBefore = allPumpEventBatches.count

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(first.manager.state.bolusDose?.bolusId)
        let started = try XCTUnwrap(
            Array(allPumpEventBatches.dropFirst(batchesBefore)).flatMap(\.events).first { $0.dose?.type == .bolus }
        )
        let raw = started.raw
        let startDate = try XCTUnwrap(started.dose?.startDate)
        try clock.advanceBoth(seconds: 5, ticks: 5)
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the bolus is still running when the app dies")

        // Relaunch: persisted rawValue, new manager, new delegate. The pump keeps delivering.
        let relaunched = try relaunch()
        configureHostSettings(relaunched)
        XCTAssertNotNil(relaunched.manager.state.bolusDose, "the in-progress dose round-trips through rawValue")
        XCTAssertEqual(relaunched.manager.state.bolusDose?.bolusId, bolusId)
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the pump did not notice the relaunch")
        let logAfterRelaunch = try harness.client.snapshot().requestLog.lastSeq

        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId, step: 2)
        XCTAssertEqual(lastBolus.deliveredUnits, Self.bolusUnits)
        try clock.advanceBoth(seconds: relaunched.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))
        _ = try sync()

        let relaunchBatches = relaunched.delegate.pumpEventBatches
        XCTAssertFalse(relaunchBatches.isEmpty, "the relaunched driver's sync reports to the host")
        let firstBatch = relaunchBatches[0]
        let pumpRecord = try pumpBolus(bolusId)
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        trio.assertSingleBolus(at: started.date, amount: Self.bolusUnits)
        XCTAssertNotNil(pumpRecord.end, "the pump finished the bolus")

        try XCTExpectFailure("jwoglom/TandemKit#326: a bolus in flight across an app relaunch is never finalized; bolusProgressReport is memory-only and fetchBolusStatus clears the persisted dose silently") {
            let carried = firstBatch.events.first { $0.raw == raw }
            XCTAssertNotNil(carried, "the first batch after relaunch contains the bolus under its original raw; got \(firstBatch.events.map { LoopDoseStoreOracle.describe($0.raw) })")
            XCTAssertEqual(carried?.dose?.startDate, startDate, "with its original startDate")

            let finalized = relaunchBatches.flatMap(\.events).first { $0.raw == raw && $0.dose?.isMutable == false }
            XCTAssertNotNil(finalized, "the relaunched driver finalizes the bolus")
            XCTAssertEqual(finalized?.dose?.deliveredUnits, lastBolus.deliveredUnits, "from LastBolusStatus, not the estimate")
            XCTAssertTrue(
                try messagesSeen(since: logAfterRelaunch).contains { $0.hasPrefix("LastBolusStatus") },
                "the relaunched driver read the pump's record"
            )
            XCTAssertNil(relaunched.manager.state.bolusDose, "state is cleared only once the dose is finalized")

            let stored = loop.assertPermanent(raw: raw, "after relaunch")
            XCTAssertEqual(stored?.dose.deliveredUnits, lastBolus.deliveredUnits)
            try timeline().assertMatches(loop)
        }
        if let finalized = relaunchBatches.flatMap(\.events).first(where: { $0.raw == raw && $0.dose?.isMutable == false }) {
            try assertFinalizedFieldSemantics(finalized, programmed: Self.bolusUnits, activationType: .manualNoRecommendation)
        }
    }

    // MARK: - A4

    /// BLE drops after the pump accepted a temp rate; it runs and expires while the driver is
    /// away and after it is back (P11).
    func testA4_bleDropMidTempBasalKeepsTheDoseAndFinalizesOnExpiry() throws {
        try stageDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        let batchesBefore = allPumpEventBatches.count
        let rate = 1.13 // percent 113 of a 1.0 U/h profile
        let duration: TimeInterval = .minutes(45) // rate × 0.75 h = 0.8475 U, off the 0.001 U grid

        XCTAssertNil(try enactTempBasal(unitsPerHour: rate, duration: duration))
        let enactBatches = Array(allPumpEventBatches.dropFirst(batchesBefore))
        let started = try XCTUnwrap(enactBatches.flatMap(\.events).first { $0.dose?.type == .tempBasal }, "the enact reports the temp basal")
        XCTAssertEqual(started.dose?.isMutable, true, "reported mutable before the drop")
        XCTAssertEqual(try XCTUnwrap(started.dose?.unitsPerHour), rate, accuracy: 0.0001)
        let raw = started.raw
        let start = try XCTUnwrap(started.dose?.startDate)
        let scheduledEnd = start.addingTimeInterval(duration)
        XCTAssertEqual(started.dose?.endDate, scheduledEnd, "a running temp basal ends at its scheduled end")
        let pumpBasal = try harness.client.snapshot().basal
        XCTAssertTrue(pumpBasal.tempActive)
        XCTAssertEqual(pumpBasal.tempRate, rate, accuracy: 0.0001)

        // The link drops with the temp rate running; ten minutes pass before the driver is back.
        // (The pump's log, not `disconnectFromPump()`'s poll of the live flag: the driver's
        // auto-reconnect can bring the link back between two polls.)
        try harness.control.disconnectPump()
        try waitForLinkDown(since: logStart)
        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        try waitForReconnect()
        _ = try sync()

        let midRun = feedOracles()
        let running = try XCTUnwrap(midRun.loop.assertSingleDose(raw: raw, "after reconnect"))
        XCTAssertTrue(running.isMutable, "still mutable after the reconnect")
        XCTAssertEqual(running.dose.endDate, scheduledEnd, "endDate is still the scheduled end")
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive, "the pump is still running it")

        // Run out on the pump: to the scheduled end exactly, then one tick past it.
        try clock.advanceBoth(seconds: scheduledEnd.timeIntervalSince(clock.now), ticks: 5)
        try clock.advanceBoth(seconds: 1, ticks: 1)
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the temp rate expired on the pump")
        _ = try sync()

        let finalized = try finalizedEvent(raw: raw)
        XCTAssertEqual(finalized.dose?.endDate, scheduledEnd, "finalized at its scheduled end")
        XCTAssertEqual(try XCTUnwrap(finalized.dose?.deliveredUnits), rate * duration / .hours(1), accuracy: 0.0005)
        try assertFinalizedFieldSemantics(finalized, programmed: rate)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw, "expired temp basal"))
        XCTAssertEqual(stored.dose.endDate, scheduledEnd)
        XCTAssertTrue(
            loop.doses.contains { $0.dose.type == .basal && abs($0.dose.startDate.timeIntervalSince(scheduledEnd)) <= 2 },
            "the scheduled basal resumes at the temp basal's end: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        trio.assertNoDuplicates()
        XCTAssertEqual(trio.tempBasals.count, 1, "Trio holds one temp basal row: \(trio.tempBasals)")
        XCTAssertEqual(trio.tempBasals.first?.tempBasalDurationMinutes, Int(duration / 60))

        let timeline = try timeline()
        let pumpTemp = try XCTUnwrap(timeline.tempRates.first, "pump timeline has the temp rate: \(timeline)")
        XCTAssertTrue(pumpTemp.isFinished, "the pump recorded the expiry")
        XCTAssertEqual(pumpTemp.scheduledEnd, scheduledEnd)
        XCTAssertTrue(timeline.connections.contains { !$0.connected })
        timeline.assertMatches(loop)
    }

    // MARK: - A5

    /// A second temp rate replaces the first: the pump stops the first (irreversible), applies the
    /// second, and the `SetTempRate` acknowledgement is lost (#340, G02).
    func testA5_lostSetTempRateResponseAfterTheIrreversibleStopStep() throws {
        try stageDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        let batchesBefore = allPumpEventBatches.count
        let firstRate = 1.2
        let secondRate = 1.5
        let duration: TimeInterval = .minutes(30)

        XCTAssertNil(try enactTempBasal(unitsPerHour: firstRate, duration: duration))
        let firstEvent = try XCTUnwrap(
            Array(allPumpEventBatches.dropFirst(batchesBefore)).flatMap(\.events).first { $0.dose?.type == .tempBasal }
        )
        let firstRaw = firstEvent.raw
        let firstStart = try XCTUnwrap(firstEvent.dose?.startDate)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)

        // The stop step is answered; the set step is applied and its answer is lost.
        try harness.client.armFault(FaketandemFaultSpec(.dropResponse, message: "SetTempRateRequest"))
        let replacementStart = clock.now
        let error = try enactTempBasal(unitsPerHour: secondRate, duration: duration, timeout: 90)
        guard case .communication? = error else {
            return XCTFail("a lost SetTempRate acknowledgement is a communication error, got \(String(describing: error))")
        }

        // Wire: StopTempRate answered, SetTempRate applied but unanswered.
        let log = try harness.requestLog(since: logStart)
        let requests = log.filter(\.isRequest).map { $0.message ?? "" }
        XCTAssertEqual(requests.filter { $0 == "StopTempRateRequest" }.count, 1, "the running rate was stopped first: \(requests)")
        let stopResponse = log.first { $0.isResponse && $0.message == "StopTempRateResponse" }
        XCTAssertNil(stopResponse?.fault, "the stop was acknowledged")
        // The last SetTempRate answer is the replacement's; the first was the initial temp rate's.
        let setResponse = log.last { $0.isResponse && $0.message == "SetTempRateResponse" }
        XCTAssertEqual(setResponse?.fault, "drop_response", "the set was applied and its answer suppressed: \(String(describing: setResponse))")

        // Pump side: the second temp rate is running; the first ended when it was stopped.
        let pumpBasal = try harness.client.snapshot().basal
        XCTAssertTrue(pumpBasal.tempActive)
        XCTAssertEqual(pumpBasal.tempRate, secondRate, accuracy: 0.0001, "the pump runs the rate whose ack was lost")
        let pumpSecondStart = try XCTUnwrap(pumpBasal.tempStart?.date)
        XCTAssertEqual(pumpSecondStart.timeIntervalSince(replacementStart), 0, accuracy: 2)

        // Next sync: the pump's basal status must win.
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        _ = try sync()
        XCTAssertTrue(try messagesSeen(since: logStart).contains("CurrentBasalStatusRequest"), "the sync read the pump's basal status")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        let timeline = try timeline()
        // The protocol-path StopTempRate writes no TempRateCompleted record (emulator gap), so
        // the first temp rate's true end is the second one's start, which the pump does record.
        let pumpSecond = timeline.tempRates.first { abs($0.start.timeIntervalSince(pumpSecondStart)) <= 2 }
        XCTAssertNotNil(pumpSecond, "the pump recorded the second temp rate's activation: \(timeline)")

        XCTExpectFailure("jwoglom/TandemKit#340: after a lost SetTempRate response the driver keeps reporting the stopped temp rate and never notices the one the pump is running") {
            let liveTemps = loop.mutableDoses.filter { $0.dose.type == .tempBasal }
            XCTAssertEqual(liveTemps.count, 1, "exactly one temp basal is live, the one the pump runs: \(loop.doses.map(LoopDoseStoreOracle.describe))")
            let live = liveTemps.first
            XCTAssertEqual(live.map { abs($0.dose.startDate.timeIntervalSince(pumpSecondStart)) } ?? .infinity, 0, accuracy: 2, "the live temp basal starts when the pump's does")
            XCTAssertEqual(live?.dose.unitsPerHour ?? 0, secondRate, accuracy: 0.0001, "at the pump's rate")

            let previous = loop.assertPermanent(raw: firstRaw, "the replaced temp basal")
            XCTAssertEqual(previous?.dose.startDate, firstStart)
            XCTAssertEqual(previous.map { abs($0.dose.endDate.timeIntervalSince(pumpSecondStart)) } ?? .infinity, 0, accuracy: 2, "finalized at its true end, the stop")
            XCTAssertEqual(trio.tempBasals.count, 2, "Trio holds both temp basals: \(trio.tempBasals)")

            let diff = timeline.diff(against: loop)
            XCTAssertTrue(diff.isEmpty, "pump timeline and Loop oracle disagree:\n\(diff)")
        }
    }

    // MARK: - A6

    /// The link drops after the first fragment of a multi-fragment response during a sync.
    func testA6_linkDropInsideAMultiFragmentResponseDuringSync() throws {
        let driver = try stageDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        let batchesBefore = allPumpEventBatches.count
        let boundaryBefore = try XCTUnwrap(driver.manager.state.lastReconciliation)

        // PumpVersionB is read by the once-a-day settings pass; make this sync run it.
        driver.manager.state.lastSettingsCheckedAt = nil
        var fault = FaketandemFaultSpec(.disconnect, message: "PumpVersionBRequest")
        fault.after = "partial_response"
        fault.fragmentsSent = 1
        try harness.client.armFault(fault)

        try clock.advanceBoth(seconds: .minutes(5))
        let lastSync = try sync()

        // Wire: one fragment of many went out, then the pump dropped the link.
        let cut = try XCTUnwrap(
            try harness.requestLog(since: logStart).first { $0.isResponse && $0.message == "PumpVersionBResponse" },
            "the pump answered PumpVersionB"
        )
        XCTAssertEqual(cut.fault, "disconnect")
        XCTAssertEqual(cut.fragmentsSent, 1)
        XCTAssertGreaterThan(cut.fragments?.count ?? 0, 1, "a multi-fragment response")
        try waitForLinkDown(since: logStart)
        let afterCut = try harness.requestLog(since: cut.seq).filter(\.isRequest).map { $0.message ?? "" }
        XCTAssertFalse(afterCut.contains("CurrentBasalStatusRequest") || afterCut.contains("CurrentBolusStatusRequest"), "no dose status was read on the dropped link before the reconnect: \(afterCut)")

        // No dose was emitted or duplicated.
        let batches = Array(allPumpEventBatches.dropFirst(batchesBefore))
        XCTAssertTrue(batches.allSatisfy(\.events.isEmpty), "a failed sync emits no doses: \(batches.map(\.events))")
        let interrupted = feedOracles()
        XCTAssertTrue(interrupted.loop.doses.isEmpty)

        // The trust boundary must not move: bolus and basal status were never read.
        XCTExpectFailure("unfiled: syncPumpData stamps lastReconciliation whenever any response arrived (responseCount > responsesBefore), so a sync whose link dropped before the bolus and basal reads still advances the boundary") {
            XCTAssertEqual(lastSync, boundaryBefore, "the sync completed without reconciling; lastSync stays where it was")
            XCTAssertEqual(driver.manager.state.lastReconciliation, boundaryBefore)
            XCTAssertEqual(interrupted.loop.lastReconciliation, boundaryBefore, "the host's boundary did not advance")
        }

        // The next sync, on a fresh session, succeeds and moves the boundary.
        try waitForReconnect()
        try clock.advanceBoth(seconds: .minutes(5))
        let logBeforeRetry = try harness.client.snapshot().requestLog.lastSeq
        let retried = try XCTUnwrap(try sync())
        XCTAssertEqual(retried, clock.now, "a complete sync stamps now")
        XCTAssertGreaterThan(retried, boundaryBefore)
        XCTAssertTrue(try messagesSeen(since: logBeforeRetry).contains("CurrentBasalStatusRequest"))

        let (loop, _) = feedOracles()
        XCTAssertEqual(loop.lastReconciliation, retried)
        XCTAssertTrue(loop.doses.isEmpty, "no dose was ever delivered: \(loop.doses)")
        try timeline().assertMatches(loop)
    }

    // MARK: - A7

    /// The pump's radio goes away during a bolus and comes back after the bolus finished.
    func testA7_radioOffDuringABolusThenOnAgainLater() throws {
        let driver = try stageDriver()
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        let batchesBefore = allPumpEventBatches.count

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let started = try XCTUnwrap(
            Array(allPumpEventBatches.dropFirst(batchesBefore)).flatMap(\.events).first { $0.dose?.type == .bolus }
        )
        XCTAssertEqual(started.dose?.isMutable, true)
        let raw = started.raw
        XCTAssertNil(driver.manager.connectionIssue, "a fresh session has no connection issue")

        // Radio off: the pump drops the central and refuses to reconnect.
        try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        XCTAssertFalse(try harness.client.snapshot().connection.radioEnabled)
        try waitForLinkDown(since: logStart)
        try IntegrationWait.until("driver to notice the link is gone", timeout: 30) { !driver.manager.state.isConnected }
        XCTAssertEqual(driver.manager.connectionIssue, .pumpUnreachable, "the outage is surfaced")

        // The bolus finishes with nobody listening.
        let lastBolus = try advanceUntilBolusFinishes(bolusId: bolusId, step: 2)
        XCTAssertEqual(lastBolus.deliveredUnits, Self.bolusUnits)
        XCTAssertFalse(driver.manager.state.isConnected, "still out of contact when the bolus finished")
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))

        // Radio on; the next sync has to rebuild the session and reconcile.
        try harness.client.armFault(FaketandemFaultSpec(.radioOn))
        XCTAssertTrue(try harness.client.snapshot().connection.radioEnabled)
        _ = try sync()
        try IntegrationWait.until("driver to be connected after the sync", timeout: 30) { driver.manager.state.isConnected }
        XCTAssertNil(driver.manager.connectionIssue, "the issue clears once the session is back and synced")

        let finalized = try finalizedEvent(raw: raw)
        let pumpRecord = try pumpBolus(bolusId)
        XCTAssertEqual(finalized.dose?.deliveredUnits, lastBolus.deliveredUnits, "deliveredUnits is the pump's last_bolus.delivered")
        let pumpEnd = try XCTUnwrap(pumpRecord.end)
        XCTAssertEqual(
            try XCTUnwrap(finalized.dose?.endDate).timeIntervalSince(pumpEnd), 0, accuracy: 2,
            "endDate is the pump's completion time (pump \(pumpEnd))"
        )
        try assertFinalizedFieldSemantics(finalized, programmed: Self.bolusUnits, activationType: .manualNoRecommendation)
        XCTAssertTrue(try messagesSeen(since: logStart).contains { $0.hasPrefix("LastBolusStatus") }, "finalization reads the pump's record")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw))
        XCTAssertEqual(stored.dose.deliveredUnits, lastBolus.deliveredUnits)
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, 1)
        trio.assertNoDuplicates()
        trio.assertSingleBolus(at: started.date, amount: Self.bolusUnits)

        let timeline = try timeline()
        let connections = timeline.connections.map(\.connected)
        XCTAssertTrue(connections.contains(false) && connections.last == true, "the pump saw the outage and the return: \(connections)")
        timeline.assertMatches(loop)
    }
}
