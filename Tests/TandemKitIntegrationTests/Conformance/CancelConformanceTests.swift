import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Conformance group B, "cancel everything" (`docs/conformance-test-plan.md` §B): every way a dose
/// can stop before it was supposed to — a bolus cancelled at three points, a cancel that delivered
/// nothing, a temp basal ended early, replaced early, neutralised, a cancel that cannot reach the
/// pump, and the pump stopping a bolus itself on an occlusion.
///
/// Every scenario asserts through both host oracles and the delegate journal rather than the last
/// delegate call, checks the §E field semantics on each finalized dose, and ends by diffing the
/// reported timeline against the pump's own record.
///
/// Where the driver is known to be non-conformant the guide's assertion is kept as written and only
/// the failing assertion is wrapped in a strict `XCTExpectFailure` naming the issue, so a fix flips
/// it to an unexpected pass and the marker comes out with the fix.
final class CancelConformanceTests: ConformanceTestCase {
    // MARK: - Fixture constants

    /// The emulator's default profile basal rate (`faketandem pkg/state/pump.go` `CurrentRate`).
    /// The driver's schedule is seeded with the same value so `percent` maths on both sides agree.
    private static let profileRate = 0.85
    /// 200% of the profile rate: a temp basal the driver can express exactly on its percent grid.
    private static let tempRate = profileRate * 2
    /// The pump delivers at exactly the rate the driver's estimate assumes, so a finalized
    /// `endDate` is the pump's completion second rather than "within a tolerance".
    private static let bolusDeliveryRate = TandemPumpCapabilities.bolusSpeedUnder10U
    private static let bolusUnits = 3.0
    /// The pump's reporting increment for both volumes and rates (`TandemPumpCapabilities.roundToReportingResolution`).
    private static let reportingIncrement = 0.001

    private static func deliverySeconds(forUnits units: Double) -> TimeInterval {
        TandemPumpCapabilities.estimatedBolusDuration(toDeliver: units)
    }

    // MARK: - Fixture

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The base case stops at the first issue, which would end a scenario at its first expected
        // failure and leave the rest of its assertions unrun. Every scenario here is written to be
        // read to the end.
        continueAfterFailure = true
    }

    /// A paired, synced driver whose basal schedule matches the pump's profile rate, whose insulin
    /// type is set the way a host sets it, and whose pump delivers boluses at the driver's nominal
    /// rate. Everything in this class starts here.
    @discardableResult
    private func startCancelDriver() throws -> FaketandemHarness.Driver {
        let schedule = try XCTUnwrap(BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)],
            timeZone: .current
        ))
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.insulinType = .novolog
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        _ = try harness.client.setState(["bolus_rate_units_per_second": Self.bolusDeliveryRate])
        return driver
    }

    // MARK: - Journal helpers

    /// Every event of `type` reported after `batchIndex` batches had been journaled, oldest first.
    private func events(ofType type: DoseType, after batchIndex: Int) -> [NewPumpEvent] {
        Array(allPumpEventBatches.dropFirst(batchIndex)).flatMap(\.events).filter { $0.dose?.type == type }
    }

    /// The batches journaled after `batchIndex`, oldest first.
    private func batches(after batchIndex: Int) -> [MockPumpManagerDelegate.PumpEventBatch] {
        Array(allPumpEventBatches.dropFirst(batchIndex))
    }

    /// The first mutable dose of `type` reported after `batchIndex`; the identity every later report
    /// of that dose has to keep.
    private func firstMutable(_ type: DoseType, after batchIndex: Int, _ what: String) throws -> NewPumpEvent {
        try XCTUnwrap(
            events(ofType: type, after: batchIndex).first { $0.dose?.isMutable == true },
            "\(what): no mutable \(type) was ever reported. batches: \(describe(batches(after: batchIndex)))"
        )
    }

    /// The last immutable dose of `type` reported after `batchIndex` — the finalized report.
    private func lastFinalized(_ type: DoseType, after batchIndex: Int, _ what: String) throws -> NewPumpEvent {
        try XCTUnwrap(
            events(ofType: type, after: batchIndex).last { $0.dose?.isMutable == false },
            "\(what): no finalized \(type) was ever reported. batches: \(describe(batches(after: batchIndex)))"
        )
    }

    private func describe(_ batches: [MockPumpManagerDelegate.PumpEventBatch]) -> String {
        batches.enumerated().map { index, batch in
            let events = batch.events.map { event -> String in
                let dose = event.dose
                let mutability = dose.map { $0.isMutable ? "mutable" : "final" } ?? "-"
                let delivered = dose?.deliveredUnits.map { "\($0)" } ?? "nil"
                let value = dose.map { $0.unit == .unitsPerHour ? "\($0.unitsPerHour) U/h" : "\($0.programmedUnits) U" } ?? "-"
                return "\(LoopDoseStoreOracle.describe(event.raw)) type=\(String(describing: event.type)) "
                    + "\(mutability) value=\(value) delivered=\(delivered)"
            }
            return "#\(index) replace=\(batch.replacePendingEvents) recon=\(String(describing: batch.lastReconciliation)) [\(events.joined(separator: " | "))]"
        }.joined(separator: "\n")
    }

    // MARK: - Section E: field semantics on a finalized dose

    /// The §E checks every finalized dose in this plan is subject to: programmed `value`, actual
    /// `deliveredUnits` on the pump's increment, `isMutable` false, `manuallyEntered` false for a
    /// pump-delivered dose, `automatic` matching the activation, `insulinType` set, and
    /// `syncIdentifier` derived from `raw` rather than set independently.
    private func assertFieldSemantics(
        _ event: NewPumpEvent,
        programmedValue: Double,
        expectedDelivered: Double,
        automatic: Bool,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let dose = try XCTUnwrap(event.dose, "\(what): event carries no dose", file: file, line: line)

        XCTAssertFalse(dose.isMutable, "\(what): a finalized dose must be immutable", file: file, line: line)
        let reportedValue = dose.unit == .unitsPerHour ? dose.unitsPerHour : dose.programmedUnits
        XCTAssertEqual(reportedValue, programmedValue, accuracy: Self.reportingIncrement / 2, "\(what): value is the programmed amount", file: file, line: line)

        let delivered = try XCTUnwrap(dose.deliveredUnits, "\(what): a finalized dose must carry deliveredUnits", file: file, line: line)
        XCTAssertEqual(delivered, expectedDelivered, accuracy: Self.reportingIncrement, "\(what): deliveredUnits is the actual amount", file: file, line: line)
        XCTAssertEqual(
            delivered,
            (delivered / Self.reportingIncrement).rounded() * Self.reportingIncrement,
            accuracy: 1e-9,
            "\(what): deliveredUnits \(delivered) is not on the pump's \(Self.reportingIncrement) U increment",
            file: file,
            line: line
        )

        XCTAssertEqual(dose.automatic, automatic, "\(what): automatic reflects the activation type", file: file, line: line)
        XCTAssertNotNil(dose.insulinType, "\(what): insulinType is set", file: file, line: line)
        XCTAssertEqual(
            dose.syncIdentifier,
            event.raw.hexadecimalString,
            "\(what): syncIdentifier is derived from raw, not set independently",
            file: file,
            line: line
        )
        XCTAssertEqual(dose.manuallyEntered, false, "\(what): a pump-delivered dose is not manually entered", file: file, line: line)
    }

    // MARK: - B1. Cancel a bolus at three points

    /// Requires the 0 U finalized dose that B2 marks as a defect; #455 decides which of the two stays.
    func testB1CancelBolusImmediatelyReportsZeroDelivered() throws {
        try runCancelBolus(deliverUnits: 0)
    }

    func testB1CancelBolusAfterOneUnitReportsThePumpsPartialAmount() throws {
        try runCancelBolus(deliverUnits: 1.0)
    }

    func testB1CancelBolusJustBeforeCompletionReportsThePumpsPartialAmount() throws {
        try runCancelBolus(deliverUnits: 2.9)
    }

    /// The pump's clock 15 minutes ahead of the phone's: both ends of the cancelled dose are its
    /// stamps moved back by the offset the first sync measured.
    func testB1CancelBolusUnderPumpClockSkewIsDatedOnThePhonesClock() throws {
        try runCancelBolus(deliverUnits: 1.0, pumpClockSkew: .minutes(15))
    }

    /// Plan B1: enact 3 U, let `deliverUnits` go in, cancel. The finalized dose must carry the
    /// pump's delivered volume, the programmed 3 U as `value`, and the `raw` the mutable report
    /// was made under.
    private func runCancelBolus(
        deliverUnits: Double,
        pumpClockSkew: TimeInterval = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if pumpClockSkew != 0 {
            try clock.setSkew(seconds: pumpClockSkew)
        }
        let driver = try startCancelDriver()
        let start = allPumpEventBatches.count
        let what = "cancel after \(deliverUnits) U of \(Self.bolusUnits) U" + (pumpClockSkew == 0 ? "" : ", pump clock \(Int(pumpClockSkew)) s ahead")
        XCTAssertEqual(driver.manager.state.pumpClockOffset, pumpClockSkew, accuracy: 5, "\(what): the sync measured the skew", file: file, line: line)

        // Register up front (guide §10): a mutable dose before anything can go wrong.
        XCTAssertNil(try enactBolus(units: Self.bolusUnits), "\(what): enact", file: file, line: line)
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId, "\(what): no bolus id", file: file, line: line)
        let mutable = try firstMutable(.bolus, after: start, what)
        let raw = mutable.raw
        XCTAssertNil(mutable.dose?.deliveredUnits, "\(what): a mutable dose carries no deliveredUnits", file: file, line: line)
        XCTAssertEqual(mutable.dose?.programmedUnits, Self.bolusUnits, "\(what): the mutable dose is the programmed amount", file: file, line: line)

        // Deliver exactly as much as the scenario asks for. The pump's clock is frozen, so nothing
        // is delivered except while the clock is being stepped.
        if deliverUnits > 0 {
            let seconds = Self.deliverySeconds(forUnits: deliverUnits)
            try clock.advanceBoth(seconds: seconds, ticks: max(1, Int(seconds.rounded())))
        }
        let running = try harness.client.snapshot()
        XCTAssertTrue(running.bolus.active, "\(what): the pump should still be delivering", file: file, line: line)
        XCTAssertEqual(running.bolus.unitsDelivered, deliverUnits, accuracy: 0.02, "\(what): pump-side delivered", file: file, line: line)

        let result = try cancelBolus()
        switch result {
        case let .failure(error):
            XCTFail("\(what): cancelBolus failed: \(error)", file: file, line: line)
            return
        case let .success(dose):
            XCTAssertNotNil(dose, "\(what): cancelBolus must hand the host the dose it finalized", file: file, line: line)
        }

        // The pump's own number is the only truth about how much went in.
        let lastBolus = try XCTUnwrap(try harness.client.snapshot().lastBolus, "\(what): pump kept no last-bolus record", file: file, line: line)
        XCTAssertEqual(lastBolus.bolusId, bolusId, "\(what): the pump's record is this bolus", file: file, line: line)
        let pumpEnd = lastBolus.endTime

        let finalized = try lastFinalized(.bolus, after: start, what)
        XCTAssertEqual(
            finalized.raw,
            raw,
            "\(what): raw changed over the dose's life: \(LoopDoseStoreOracle.describe(raw)) -> \(LoopDoseStoreOracle.describe(finalized.raw))",
            file: file,
            line: line
        )
        try assertFieldSemantics(
            finalized,
            programmedValue: Self.bolusUnits,
            expectedDelivered: lastBolus.deliveredUnits,
            automatic: false,
            what,
            file: file,
            line: line
        )

        // Hosts: one dose, permanent, at the pump's amount.
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates(what, file: file, line: line)
        let stored = try XCTUnwrap(loop.assertPermanent(raw: finalized.raw, what, file: file, line: line), file: file, line: line)
        XCTAssertEqual(stored.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: Self.reportingIncrement, "\(what): Loop stored the pump's amount", file: file, line: line)
        XCTAssertEqual(loop.callCount, batchesFedToOracles, "\(what): every batch reached the oracle", file: file, line: line)
        if lastBolus.deliveredUnits > 0 {
            XCTAssertGreaterThan(loop.iob(at: clock.now), 0, "\(what): the partial delivery counts towards IOB", file: file, line: line)
        }

        trio.assertNoDuplicates(what, file: file, line: line)
        trio.assertSingleBolus(at: mutable.date, amount: lastBolus.deliveredUnits, accuracy: 0.051, what, file: file, line: line)

        // Pump side.
        let timeline = try timeline()
        let pumpBolus = try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId }, "\(what): timeline \(timeline)", file: file, line: line)
        XCTAssertEqual(pumpBolus.programmedUnits, Self.bolusUnits, "\(what): the pump programmed 3 U", file: file, line: line)
        XCTAssertEqual(pumpBolus.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 1e-9, file: file, line: line)
        // Not `pumpBolus.endReason`: the emulator's stopped-bolus id and `PumpTimeline`'s enum
        // disagree (see the report), so the raw id from the pump's own record is the check.
        XCTAssertNotEqual(lastBolus.endReasonId, 3, "\(what): the pump recorded a completion, not a stop", file: file, line: line)

        // The pump's volume is a continuous simulation and the driver reports on the 0.001 U grid,
        // so the ledgers are compared at that resolution rather than at the diff's default 0.0005.
        if deliverUnits > 0 {
            XCTAssertEqual(
                (finalized.dose?.endDate).map { $0.timeIntervalSince(pumpEnd) } ?? .nan,
                0,
                accuracy: 2,
                "\(what): the dose ends when the pump stopped delivering (\(pumpEnd)), not when the driver got round to it",
                file: file,
                line: line
            )
            timeline.assertMatches(
                loop,
                tolerance: PumpTimeline.Tolerance(time: 2, units: Self.reportingIncrement, rate: 0.005),
                what,
                file: file,
                line: line
            )
        } else {
            // Nothing was delivered, so `BolusEndDate` has only the start and the 15 s initiation
            // lead-in to work with; the ledgers can differ by no more than that window.
            timeline.assertMatches(
                loop,
                tolerance: PumpTimeline.Tolerance(
                    time: TandemPumpCapabilities.bolusInitiationDelay + 2,
                    units: Self.reportingIncrement,
                    rate: 0.005
                ),
                what,
                file: file,
                line: line
            )
        }
    }

    // MARK: - B2. Cancel with zero delivery

    /// Plan B2 (audit P23, #455): a bolus the pump confirms delivered nothing never happened. It has
    /// to stop being sent in a `replacePendingEvents: true` batch so LoopKit removes it, rather than
    /// being frozen as a 0 U immutable dose that can never be revised.
    func testB2CancelWithZeroDeliveryRetractsTheDose() throws {
        let driver = try startCancelDriver()
        let start = allPumpEventBatches.count

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let mutable = try firstMutable(.bolus, after: start, "zero-delivery cancel")
        let raw = mutable.raw

        // No clock movement: the pump has delivered nothing at all.
        XCTAssertEqual(try harness.client.snapshot().bolus.unitsDelivered, 0, "the pump delivered nothing")

        let result = try cancelBolus()
        guard case .success = result else {
            XCTFail("cancelBolus failed: \(result)")
            return
        }
        let lastBolus = try XCTUnwrap(try harness.client.snapshot().lastBolus)
        XCTAssertEqual(lastBolus.bolusId, bolusId)
        XCTAssertEqual(lastBolus.deliveredUnits, 0, "the pump confirms nothing was delivered")

        // The retraction has to arrive in a complete batch, or LoopKit has no reason to purge.
        let after = batches(after: start)
        XCTAssertTrue(
            after.contains { $0.replacePendingEvents },
            "the cancel must be reported in a complete (replacePendingEvents: true) batch: \(describe(after))"
        )

        let (loop, trio) = feedOracles()

        XCTExpectFailure(
            "jwoglom/TandemKit#455: a cancel the pump confirms delivered 0 U is finalized as a 0 U immutable dose instead of being withdrawn (audit P23)",
            strict: true
        ) {
            let zero = self.events(ofType: .bolus, after: start).filter { $0.dose?.isMutable == false }
            XCTAssertTrue(
                zero.isEmpty,
                "a dose that never happened must stop being reported, not be finalized at 0 U: \(self.describe(after))"
            )
            loop.assertDeleted(raw: raw, "zero-delivery cancel")
            XCTAssertTrue(
                loop.doses.filter { $0.dose.type == .bolus }.isEmpty,
                "Loop still holds a bolus for a delivery that never happened: \(loop.doses.map(LoopDoseStoreOracle.describe))"
            )
        }

        // Whatever the driver reports, it must not report it twice or under two identities.
        loop.assertNoDuplicates("zero-delivery cancel")
        trio.assertNoDuplicates("zero-delivery cancel")
        XCTAssertEqual(loop.callCount, batchesFedToOracles)

        // The pump's own ledger: a 3 U bolus that stopped with nothing delivered.
        let timeline = try timeline()
        let pumpBolus = try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId }, "timeline \(timeline)")
        XCTAssertEqual(pumpBolus.deliveredUnits, 0)
        XCTAssertNotEqual(lastBolus.endReasonId, 3, "the pump recorded a completion, not a stop")
        // Today the driver reports the 0 U dose, so the ledgers agree; once #455's withdrawal lands
        // the pump will hold a 0 U record with no dose against it, which is the correct end state.
        timeline.assertMatches(
            loop,
            tolerance: PumpTimeline.Tolerance(
                time: TandemPumpCapabilities.bolusInitiationDelay + 2,
                units: Self.reportingIncrement,
                rate: 0.005
            ),
            "zero-delivery cancel"
        )
    }

    // MARK: - B3. Cancel a temp basal early

    /// Plan B3 (#329, #344): a 60 minute temp basal stopped after 12 minutes is one dose, finalized
    /// at the pump's stop time with `rate × 12 min` delivered, under the `raw` it started life with.
    func testB3CancelTempBasalEarlyFinalizesItAtTheCancel() throws {
        let driver = try startCancelDriver()
        let start = allPumpEventBatches.count
        let ranFor = TimeInterval.minutes(12)

        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempRate, duration: .minutes(60)), "enact the temp basal")
        let mutable = try firstMutable(.tempBasal, after: start, "temp basal cancel")
        let rawA = mutable.raw
        let tempStart = try XCTUnwrap(mutable.dose?.startDate)
        XCTAssertEqual(mutable.dose?.unitsPerHour ?? -1, Self.tempRate, accuracy: 0.005, "the mutable temp basal runs at the pump's rate")
        XCTAssertNil(mutable.dose?.deliveredUnits, "a mutable temp basal carries no deliveredUnits")
        XCTAssertEqual(
            mutable.dose?.endDate,
            tempStart.addingTimeInterval(.minutes(60)),
            "while mutable, endDate is the scheduled end (guide §9 item 7)"
        )
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive, "the pump is running the temp rate")

        try clock.advanceBoth(seconds: ranFor, ticks: 12)
        let cancelAt = clock.now

        // Cancel: duration 0 is how a host ends a temp basal without replacing it.
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: 0), "cancel the temp basal")
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the pump stopped the temp rate")

        let finalized = try lastFinalized(.tempBasal, after: start, "temp basal cancel")
        let expectedDelivered = Self.tempRate * ranFor / .hours(1)

        XCTAssertEqual(
            finalized.dose?.endDate,
            cancelAt,
            "the temp basal ends when it was cancelled, not at its scheduled end"
        )
        try assertFieldSemantics(
            finalized,
            programmedValue: Self.tempRate,
            expectedDelivered: expectedDelivered,
            automatic: true,
            "temp basal cancel"
        )

        XCTAssertEqual(
            finalized.raw,
            rawA,
            "raw changed over the dose's life: \(LoopDoseStoreOracle.describe(rawA)) -> \(LoopDoseStoreOracle.describe(finalized.raw))"
        )

        // Loop: exactly one temp basal, permanent, at the truncated amount.
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("temp basal cancel")
        XCTAssertEqual(
            loop.doses.filter { $0.dose.type == .tempBasal }.count,
            1,
            "one temp basal ran, so Loop holds one: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        let stored = try XCTUnwrap(loop.assertPermanent(raw: finalized.raw, "temp basal cancel"))
        XCTAssertEqual(stored.dose.deliveredUnits ?? -1, expectedDelivered, accuracy: Self.reportingIncrement)

        // Trio: the stored temp basal must be truncated, or oref keeps counting the old rate for
        // the remaining 48 minutes.
        let truncating = trio.tempBasals.contains { row in
            row.timestamp == tempStart && row.tempBasalDurationMinutes == Int(ranFor / 60)
        } || trio.tempBasals.contains { $0.timestamp >= cancelAt.addingTimeInterval(-1) }
        XCTAssertTrue(
            truncating,
            "Trio holds no truncating record; its temp basals are \(trio.tempBasals) and it skipped \(trio.skipped.map(\.reason))"
        )

        // Pump side. The driver's stop now ends the temp rate through one writer, which records
        // exactly one TempRateCompleted at the true end instant, so the whole diff closes.
        let timeline = try timeline()
        let pumpTemp = try XCTUnwrap(timeline.tempRates.last, "timeline \(timeline)")
        XCTAssertEqual(pumpTemp.rate ?? -1, Self.tempRate, accuracy: 0.005, "the pump ran the rate the driver reported")
        XCTAssertEqual(pumpTemp.start.timeIntervalSince(tempStart), 0, accuracy: 2, "the pump started it when the driver said")
        XCTAssertTrue(pumpTemp.isFinished, "the pump recorded the stop: \(timeline)")
        timeline.assertMatches(loop, "temp basal cancel")
        _ = driver
    }

    // MARK: - B4. Replace a temp basal early

    /// Plan B4 (#344): temp basal A replaced after 7 minutes by B. A must be finalized with its real
    /// end and delivered volume in the very batch that introduces mutable B, B must have its own
    /// identity, and no later complete batch may drop B while it runs.
    func testB4ReplaceTempBasalEarlyFinalizesAInTheBatchThatIntroducesB() throws {
        try startCancelDriver()
        let start = allPumpEventBatches.count
        let ranFor = TimeInterval.minutes(7)
        // 60% of the profile rate: an integer percent whose product lands exactly on the driver's
        // 0.01 U/h grid, so the rate it reports is the rate the test asked for.
        let rateB = (Self.profileRate * 0.6 * 100).rounded() / 100

        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempRate, duration: .minutes(60)), "enact temp basal A")
        let mutableA = try firstMutable(.tempBasal, after: start, "temp basal replace")
        let rawA = mutableA.raw
        let startA = try XCTUnwrap(mutableA.dose?.startDate)

        try clock.advanceBoth(seconds: ranFor, ticks: 7)
        let replaceAt = clock.now
        let beforeReplace = allPumpEventBatches.count

        XCTAssertNil(try enactTempBasal(unitsPerHour: rateB, duration: .minutes(30)), "enact temp basal B")

        // One batch carries both transitions: nothing in between where A is gone and B is not there.
        let replaceBatches = batches(after: beforeReplace)
        let combined = try XCTUnwrap(
            replaceBatches.first { batch in
                batch.events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false }
                    && batch.events.contains { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }
            },
            "A's finalization and B's introduction must share a batch: \(describe(replaceBatches))"
        )
        let finalizedA = try XCTUnwrap(combined.events.first { $0.dose?.type == .tempBasal && $0.dose?.isMutable == false })
        let mutableB = try XCTUnwrap(combined.events.first { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true })
        let rawB = mutableB.raw

        let deliveredA = Self.tempRate * ranFor / .hours(1)
        XCTAssertEqual(finalizedA.dose?.startDate, startA, "A keeps its start")
        XCTAssertEqual(finalizedA.dose?.endDate, replaceAt, "A ends when B replaced it")
        try assertFieldSemantics(
            finalizedA,
            programmedValue: Self.tempRate,
            expectedDelivered: deliveredA,
            automatic: true,
            "temp basal A"
        )

        XCTAssertEqual(mutableB.dose?.startDate, replaceAt, "B starts where A stopped")
        XCTAssertEqual(mutableB.dose?.endDate, replaceAt.addingTimeInterval(.minutes(30)), "B's endDate is its scheduled end while mutable")
        XCTAssertNil(mutableB.dose?.deliveredUnits, "a mutable temp basal carries no deliveredUnits")
        XCTAssertEqual(mutableB.dose?.unitsPerHour ?? -1, rateB, accuracy: 0.005)
        XCTAssertNotEqual(rawB, rawA, "B is a different dose and needs a different identity")

        XCTAssertEqual(
            finalizedA.raw,
            rawA,
            "A's raw changed when it was cut short: \(LoopDoseStoreOracle.describe(rawA)) -> \(LoopDoseStoreOracle.describe(finalizedA.raw))"
        )

        // B stays live across further syncs: nothing complete may drop it by silence (guide §3).
        let beforeSyncs = allPumpEventBatches.count
        for _ in 0 ..< 2 {
            try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
            _ = try sync()
        }
        // Whether a quiet sync re-reports a running temp basal at all is plan C2's subject; what B4
        // requires is that nothing emitted while B runs drops it.
        for batch in batches(after: beforeSyncs).filter(\.replacePendingEvents) {
            XCTAssertTrue(
                batch.events.contains { $0.raw == rawB && $0.dose?.isMutable == true },
                "a complete batch emitted while B runs must re-report it: \(describe([batch]))"
            )
        }
        let acrossSyncs = feedOracles()
        let liveB = try XCTUnwrap(acrossSyncs.loop.assertSingleDose(raw: rawB, "B across two syncs"))
        XCTAssertTrue(liveB.isMutable, "B is still running and still mutable: \(LoopDoseStoreOracle.describe(liveB))")

        // Hosts.
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("temp basal replace")
        let storedA = try XCTUnwrap(loop.assertPermanent(raw: finalizedA.raw, "temp basal A"))
        XCTAssertEqual(storedA.dose.deliveredUnits ?? -1, deliveredA, accuracy: Self.reportingIncrement)
        let storedB = try XCTUnwrap(loop.assertSingleDose(raw: rawB, "temp basal B"))
        XCTAssertTrue(storedB.isMutable, "B is still running: \(LoopDoseStoreOracle.describe(storedB))")
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .tempBasal }.count, 2, "two temp basals ran: \(loop.doses.map(LoopDoseStoreOracle.describe))")

        trio.assertNoDuplicates("temp basal replace")
        XCTAssertTrue(
            trio.tempBasals.contains { $0.timestamp == mutableB.date },
            "Trio must store B, which is what truncates A for oref: \(trio.tempBasals)"
        )

        let timeline = try timeline()
        XCTAssertEqual(timeline.tempRates.count, 2, "the pump ran two temp rates: \(timeline)")
        XCTAssertEqual(timeline.tempRates.first?.isFinished, true, "A was closed at the instant B replaced it: \(timeline)")
        timeline.assertMatches(loop, "temp basal replace")
    }

    // MARK: - B5. Neutral / profile-rate temp

    /// Plan B5 (#329): a neutral temp (100% of profile) with nothing running must invent no dose;
    /// the same command with a temp basal running must finalize it rather than drop it silently.
    func testB5NeutralTempInventsNoDoseAndFinalizesARunningOne() throws {
        try startCancelDriver()

        // Part 1: neutral with nothing running.
        let beforeNeutral = allPumpEventBatches.count
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.profileRate, duration: .minutes(30)), "neutral temp basal")
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "a neutral temp starts nothing on the pump")
        XCTAssertTrue(
            events(ofType: .tempBasal, after: beforeNeutral).isEmpty,
            "a neutral temp with nothing running is not a temp basal dose: \(describe(batches(after: beforeNeutral)))"
        )

        let (loopAfterNeutral, trioAfterNeutral) = feedOracles()
        XCTAssertTrue(
            loopAfterNeutral.doses.filter { $0.dose.type == .tempBasal }.isEmpty,
            "Loop holds a phantom temp basal: \(loopAfterNeutral.doses.map(LoopDoseStoreOracle.describe))"
        )
        XCTAssertTrue(trioAfterNeutral.tempBasals.isEmpty, "Trio holds a phantom temp basal: \(trioAfterNeutral.tempBasals)")

        // Part 2: a real temp basal, then the same neutral command.
        let beforeTemp = allPumpEventBatches.count
        let ranFor = TimeInterval.minutes(10)
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.tempRate, duration: .minutes(60)), "enact the temp basal")
        let mutable = try firstMutable(.tempBasal, after: beforeTemp, "neutral over a running temp")
        let tempStart = try XCTUnwrap(mutable.dose?.startDate)

        try clock.advanceBoth(seconds: ranFor, ticks: 10)
        let neutralAt = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: Self.profileRate, duration: .minutes(30)), "neutral temp basal over a running one")
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the pump stopped the temp rate")

        let finalized = try lastFinalized(.tempBasal, after: beforeTemp, "neutral over a running temp")
        let expectedDelivered = Self.tempRate * ranFor / .hours(1)
        XCTAssertEqual(finalized.dose?.endDate, neutralAt, "the running temp basal ends at the neutral command")
        try assertFieldSemantics(
            finalized,
            programmedValue: Self.tempRate,
            expectedDelivered: expectedDelivered,
            automatic: true,
            "neutral over a running temp"
        )

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("neutral temp")
        XCTAssertEqual(
            loop.doses.filter { $0.dose.type == .tempBasal }.count,
            1,
            "one temp basal ran: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        try XCTUnwrap(loop.assertPermanent(raw: finalized.raw, "neutral over a running temp"))

        let truncating = trio.tempBasals.contains { row in
            row.timestamp == tempStart && row.tempBasalDurationMinutes == Int(ranFor / 60)
        } || trio.tempBasals.contains { $0.timestamp >= neutralAt.addingTimeInterval(-1) }
        XCTAssertTrue(
            truncating,
            "Trio holds no truncating record; its temp basals are \(trio.tempBasals) and it skipped \(trio.skipped.map(\.reason))"
        )

        let timeline = try timeline()
        XCTAssertEqual(timeline.tempRates.count, 1, "only the real temp rate reached the pump: \(timeline)")
        XCTAssertEqual(timeline.tempRates.first?.isFinished, true, "the neutralised temp rate was closed: \(timeline)")
        timeline.assertMatches(loop, "neutral temp")
    }

    // MARK: - B6. Cancel while disconnected

    /// Plan B6: a cancel that cannot reach the pump reports a communication error and leaves the
    /// bolus mutable; what the pump is doing decides what the dose becomes.
    func testB6CancelWhileDisconnectedLeavesTheBolusMutableUntilThePumpDecides() throws {
        let driver = try startCancelDriver()
        let start = allPumpEventBatches.count

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let mutable = try firstMutable(.bolus, after: start, "cancel while disconnected")
        let raw = mutable.raw

        try clock.advanceBoth(seconds: Self.deliverySeconds(forUnits: 1.0), ticks: 29)

        // The pump acts on nothing and the link goes down instead of answering.
        var fault = FaketandemFaultSpec(.disconnect)
        fault.message = "CancelBolusRequest"
        fault.after = "request"
        _ = try harness.client.armFault(fault)
        // The pump raises BOLUS_CHANGE before it drops the link, and the driver reconnects to read the
        // bolus status, which settles the bolus, often before the checks below. Held off until they run.
        var refusal = FaketandemFaultSpec(.errorResponse, message: "CurrentBolusStatusRequest")
        refusal.every = true
        refusal.errorCode = 3
        let statusRefusal = try XCTUnwrap(harness.client.armFault(refusal))

        let result = try cancelBolus()
        switch result {
        case let .success(dose):
            XCTFail("cancelBolus reported success (\(String(describing: dose))) although the link dropped before the pump answered")
            return
        case let .failure(error):
            switch error {
            case .communication, .connection:
                break
            default:
                XCTFail("cancelBolus should report a communication error, reported \(error)")
            }
        }

        // The bolus is still the pump's business: it must not be dropped or finalized on a guess.
        XCTAssertNotNil(driver.manager.state.bolusDose, "the driver forgot a bolus the pump may still be delivering")
        let midway = feedOracles()
        let pending = try XCTUnwrap(midway.loop.assertSingleDose(raw: raw, "after a failed cancel"))
        XCTAssertTrue(pending.isMutable, "a bolus whose cancel never reached the pump stays mutable: \(LoopDoseStoreOracle.describe(pending))")
        XCTAssertTrue(
            events(ofType: .bolus, after: start).allSatisfy { $0.dose?.isMutable == true },
            "nothing may be finalized while the cancel's outcome is unknown: \(describe(batches(after: start)))"
        )
        try harness.client.clearFault(id: statusRefusal.id)

        // The link comes back and the pump's state decides. The emulator applies a command's state
        // change before the fault fires (README "Fault injection"), so the cancel did land even
        // though the answer did not; the branch below keeps the scenario honest either way.
        try IntegrationWait.until("the driver to reconnect", timeout: 120) {
            try self.harness.client.snapshot().connection.connected
        }
        let pumpStoppedIt = try !harness.client.snapshot().bolus.active
        if !pumpStoppedIt {
            _ = try sync()
            let afterReconnect = feedOracles()
            let stillRunning = try XCTUnwrap(afterReconnect.loop.assertSingleDose(raw: raw, "after reconnecting mid-bolus"))
            XCTAssertTrue(
                stillRunning.isMutable,
                "the pump is still delivering, so the dose is still mutable: \(LoopDoseStoreOracle.describe(stillRunning))"
            )
            _ = try advanceUntilBolusFinishes(bolusId: bolusId)
        }

        // Past the estimate plus the reconcile grace, so the next sync reconciles the bolus from
        // the pump's own record rather than deferring to the event-driven path.
        let lastBolus = try XCTUnwrap(try harness.client.snapshot().lastBolus)
        XCTAssertEqual(lastBolus.bolusId, bolusId, "the pump's record is this bolus")
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(2))
        _ = try sync()

        let finalized = try IntegrationWait.value("the finalized bolus report", timeout: 60) {
            self.events(ofType: .bolus, after: start).last { $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.raw, raw, "raw changed over the dose's life")
        try assertFieldSemantics(
            finalized,
            programmedValue: Self.bolusUnits,
            expectedDelivered: lastBolus.deliveredUnits,
            automatic: false,
            "cancel while disconnected"
        )

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("cancel while disconnected")
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw, "cancel while disconnected"))
        XCTAssertEqual(stored.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: Self.reportingIncrement)
        trio.assertNoDuplicates("cancel while disconnected")

        let timeline = try timeline()
        let pumpBolus = try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId }, "timeline \(timeline)")
        XCTAssertTrue(pumpBolus.isFinished)
        XCTAssertEqual(pumpBolus.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 1e-9)
        timeline.assertMatches(
            loop,
            tolerance: PumpTimeline.Tolerance(
                time: TandemPumpCapabilities.bolusInitiationDelay + 2,
                units: Self.reportingIncrement,
                rate: 0.005
            ),
            "cancel while disconnected"
        )
    }

    // MARK: - B7. Pump-side abort mid-bolus (occlusion)

    /// Plan B7 (#333, audit P14): the pump stops a bolus itself on an occlusion. The dose must be
    /// finalized at the pump's partial amount and at the pump's stop time, the suspend must be dated
    /// when delivery actually stopped, and the occlusion must reach the host as an `.alarm` event.
    ///
    /// The radio is taken down across the stop so detection is provably later than the stop: with
    /// the link up the pump's qualifying event reaches the driver in the same frozen instant, and
    /// "dated at detection" and "dated at the stop" would be the same second.
    func testB7PumpSideOcclusionFinalizesTheBolusAtThePumpsStop() throws {
        let driver = try startCancelDriver()
        let start = allPumpEventBatches.count

        XCTAssertNil(try enactBolus(units: Self.bolusUnits))
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let mutable = try firstMutable(.bolus, after: start, "occlusion")
        let raw = mutable.raw

        try clock.advanceBoth(seconds: Self.deliverySeconds(forUnits: 1.0), ticks: 29)
        let stoppedAt = clock.now

        // Take the radio down so the stop is not observed the instant it happens.
        _ = try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the emulator to drop the link", timeout: 30) {
            try !self.harness.client.snapshot().connection.connected
        }

        _ = try harness.client.suspend(reason: "occlusion")
        let suspended = try harness.client.snapshot()
        XCTAssertFalse(suspended.bolus.active, "the occlusion stopped the bolus")
        XCTAssertTrue(suspended.basal.suspended)
        let lastBolus = try XCTUnwrap(suspended.lastBolus)
        XCTAssertEqual(lastBolus.bolusId, bolusId)
        XCTAssertGreaterThan(lastBolus.deliveredUnits, 0, "some insulin went in before the occlusion")

        // Time passes before anyone can look, then the link comes back and the driver syncs. Past
        // the bolus estimate plus its reconcile grace, so the sync does reconcile the bolus.
        try clock.advanceBoth(seconds: driver.manager.estimatedDuration(toBolus: Self.bolusUnits) + .minutes(3))
        _ = try harness.client.armFault(FaketandemFaultSpec(.radioOn))
        let detectedAfter = clock.now
        // The sync reconnects at once rather than waiting out the reconnect retry's backoff.
        _ = try sync()
        XCTAssertTrue(try harness.client.snapshot().connection.connected, "the driver reconnected once the radio came back")

        // The bolus: the pump's partial amount, ended when the pump stopped it.
        let finalized = try IntegrationWait.value("the finalized bolus report", timeout: 60) {
            self.events(ofType: .bolus, after: start).last { $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.raw, raw, "raw changed over the dose's life")
        try assertFieldSemantics(
            finalized,
            programmedValue: Self.bolusUnits,
            expectedDelivered: lastBolus.deliveredUnits,
            automatic: false,
            "occlusion"
        )
        // Tolerance is the pump's initiation lead-in: `BolusEndDate` floors a finalized end at
        // `deliveryStart + estimatedBolusDuration(delivered)` and assumes delivery began
        // `bolusInitiationDelay` after the request, while the emulator starts delivering the
        // instant it accepts one (see the report). Detection is two minutes later either way, so
        // this still separates "the pump's stop" from "when the driver noticed".
        XCTAssertEqual(
            try XCTUnwrap(finalized.dose?.endDate).timeIntervalSince(stoppedAt),
            0,
            accuracy: TandemPumpCapabilities.bolusInitiationDelay + 2,
            "the bolus ended when the pump stopped it, not when the driver noticed (\(detectedAfter))"
        )

        // The suspend: dated when delivery stopped.
        let suspends = events(ofType: .suspend, after: start)
        let suspendEvent = try XCTUnwrap(
            suspends.first,
            "the pump stopped delivering and no .suspend was reported: \(describe(batches(after: start)))"
        )
        XCTAssertEqual(
            suspendEvent.date.timeIntervalSince(stoppedAt),
            0,
            accuracy: 2,
            "the suspend is dated \(suspendEvent.date), the pump stopped at \(stoppedAt), not at \(detectedAfter)"
        )

        // The occlusion itself, as an alarm the host can show and act on (audit P14).
        let alarms = allPumpEventBatches.dropFirst(start).flatMap(\.events).filter { $0.type == .alarm }
        XCTAssertEqual(
            alarms.map(\.alarmType),
            [.occlusion],
            "the pump raised an occlusion alarm (\(suspended.alerts)), and one .alarm event names it"
        )
        XCTAssertGreaterThanOrEqual(alarms.first?.date ?? .distantPast, detectedAfter, "dated when the driver read it: the alarm status gives no time")

        // Hosts.
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("occlusion")
        let stored = try XCTUnwrap(loop.assertPermanent(raw: raw, "occlusion"))
        XCTAssertEqual(stored.dose.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: Self.reportingIncrement)
        trio.assertNoDuplicates("occlusion")
        XCTAssertEqual(trio.suspends.count, 1, "Trio stores one PumpSuspend: \(trio.events)")

        let timeline = try timeline()
        let pumpBolus = try XCTUnwrap(timeline.boluses.first { $0.bolusId == bolusId }, "timeline \(timeline)")
        XCTAssertEqual(pumpBolus.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 1e-9)
        XCTAssertNotEqual(lastBolus.endReasonId, 3, "the occlusion stopped the bolus, it did not complete")
        XCTAssertEqual(timeline.suspends.count, 1, "the pump recorded one suspend: \(timeline)")
        XCTAssertFalse(timeline.alarms.isEmpty, "the pump recorded the occlusion alarm: \(timeline)")
        // The bolus end is floored by the pump's initiation lead-in, as in B1.
        timeline.assertMatches(
            loop,
            tolerance: PumpTimeline.Tolerance(
                time: TandemPumpCapabilities.bolusInitiationDelay + 2,
                units: Self.reportingIncrement,
                rate: 0.005
            ),
            "occlusion"
        )
    }

    // MARK: - B8. Cancel whose delivered volume cannot be read

    /// `LastBolusStatus` never answers after a cancel and history backfill is off: once the retry
    /// window is over the bolus is finalized with the time delivery ran, never 0 U (#448).
    func testB8CancelWithTheVolumeNeverReadableFinalizesWithTheTimeDeliveryRan() throws {
        try runCancelWithUnreadableVolume(historyBackfill: false)
    }

    /// As B8 with backfill on: the `BolusCompleted` record gives the pump's own volume, without
    /// waiting out the window (#448).
    func testB8bCancelWithAnUnreadableVolumeIsFinalizedFromThePumpsHistory() throws {
        try runCancelWithUnreadableVolume(historyBackfill: true)
    }

    private func runCancelWithUnreadableVolume(historyBackfill: Bool) throws {
        let driver = try startCancelDriver()
        if !historyBackfill {
            turnOffHistoryBackfill(driver)
        }
        let start = allPumpEventBatches.count
        let what = historyBackfill ? "cancel, volume from history" : "cancel, volume never readable"
        try dropEveryLastBolusStatus()
        // #448's case: the driver never sees a delivering status, so its progress estimate stays 0 U.
        var statusFault = FaketandemFaultSpec(.dropResponse, message: "CurrentBolusStatusRequest")
        statusFault.every = true
        let noStatus = try XCTUnwrap(try harness.client.armFault(statusFault))

        XCTAssertNil(try enactBolus(units: Self.bolusUnits), what)
        let raw = try firstMutable(.bolus, after: start, what).raw
        let seconds = Self.deliverySeconds(forUnits: 1.0)
        try clock.advanceBoth(seconds: seconds, ticks: max(1, Int(seconds.rounded())))
        XCTAssertNil(driver.manager.state.bolusDose?.deliveryStartDate, "\(what): no delivering status reached the driver")

        // The cancel waits out the driver's response timeout on the dropped LastBolusStatus.
        guard case let .success(returned) = try cancelBolus(timeout: 120) else {
            return XCTFail("\(what): cancelBolus failed")
        }
        try harness.client.clearFault(id: noStatus.id)
        XCTAssertEqual(returned?.isMutable, true, "\(what): an unconfirmed cancel is handed back mutable")
        let lastBolus = try XCTUnwrap(try harness.client.snapshot().lastBolus, what)
        XCTAssertEqual(lastBolus.deliveredUnits, 1.0, accuracy: 0.02, "\(what): the pump stopped after about 1 U")
        XCTAssertEqual(driver.manager.state.pendingBolusFinalization?.deliveredUnits ?? -1, lastBolus.deliveredUnits, accuracy: 0.02, "\(what): the fallback is the time delivery ran")

        let finalized: NewPumpEvent
        if historyBackfill {
            let heldFrom = clock.now
            finalized = try syncUntilFinalized(raw: raw)
            XCTAssertLessThan(clock.now.timeIntervalSince(heldFrom), TandemPumpManager.bolusFinalizationWindow, "\(what): without waiting out the window")
        } else {
            _ = try sync(timeout: 420)
            XCTAssertNotNil(driver.manager.state.pendingBolusFinalization, "\(what): held while the window runs")
            XCTAssertFalse(events(ofType: .bolus, after: start).contains { $0.dose?.isMutable == false }, "\(what): not finalized on a guess inside the window")
            try clock.advanceBoth(seconds: TandemPumpManager.bolusFinalizationWindow + .minutes(1))
            _ = try sync(timeout: 420)
            finalized = try lastFinalized(.bolus, after: start, what)
        }
        XCTAssertEqual(finalized.raw, raw, "\(what): raw kept")
        XCTAssertNil(driver.manager.state.pendingBolusFinalization, what)

        let delivered = try XCTUnwrap(finalized.dose?.deliveredUnits, what)
        XCTAssertGreaterThan(delivered, 0, "\(what): never 0 U for insulin that went in")
        // From history it is the pump's number; the fallback is the modelled rate over the same time.
        try assertFieldSemantics(
            finalized,
            programmedValue: Self.bolusUnits,
            expectedDelivered: historyBackfill ? lastBolus.deliveredUnits : delivered,
            automatic: false,
            what
        )
        XCTAssertEqual(delivered, lastBolus.deliveredUnits, accuracy: historyBackfill ? Self.reportingIncrement : 0.02, what)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates(what)
        trio.assertNoDuplicates(what)
        XCTAssertEqual(loop.assertPermanent(raw: raw, what)?.dose.deliveredUnits, delivered, what)
        trio.assertSingleBolus(at: try firstMutable(.bolus, after: start, what).date, amount: delivered, accuracy: Self.reportingIncrement, what)
        // With no delivering status seen, the driver's end model adds the 15 s lead-in the emulator lacks.
        try timeline().assertMatches(
            loop,
            tolerance: PumpTimeline.Tolerance(
                time: TandemPumpCapabilities.bolusInitiationDelay + 2,
                units: historyBackfill ? Self.reportingIncrement : 0.02,
                rate: 0.005
            ),
            what
        )
    }
}
