import LoopKit
@testable import TandemKit
import XCTest

/// The oracles on their own, against the guide's three transitions (§3: still delivering, finished,
/// never happened), the identity-change pitfall (§4/§5) and the empty-sync rule (§6). No emulator:
/// batches are hand-built the way TandemKit's `NewPumpEvent` helpers build them.
final class DoseOracleTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func bolus(units: Double, start: Date, delivered: Double? = nil, end: Date? = nil, mutable: Bool) -> NewPumpEvent {
        let dose = DoseEntry(
            type: .bolus,
            startDate: start,
            endDate: end ?? start.addingTimeInterval(30),
            value: units,
            unit: .units,
            deliveredUnits: mutable ? nil : delivered,
            insulinType: .novolog,
            automatic: false,
            isMutable: mutable
        )
        return NewPumpEvent.bolus(dose: dose, date: start)
    }

    private func tempBasal(rate: Double, start: Date, duration: TimeInterval, mutable: Bool, end: Date? = nil) -> NewPumpEvent {
        let actualEnd = end ?? start.addingTimeInterval(duration)
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: start,
            endDate: actualEnd,
            value: rate,
            unit: .unitsPerHour,
            deliveredUnits: mutable ? nil : rate * actualEnd.timeIntervalSince(start) / .hours(1),
            insulinType: .novolog,
            automatic: true,
            isMutable: mutable
        )
        return NewPumpEvent.tempBasal(dose: dose, date: start)
    }

    // MARK: - Loop: the three transitions

    func testStillDeliveringReReportUpdatesTheOneDose() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        XCTAssertEqual(oracle.doses.count, 1)
        XCTAssertEqual(oracle.mutableDoses.count, 1)

        let later = t0.addingTimeInterval(60)
        oracle.addPumpEvents([bolus(units: 2, start: t0, mutable: true)], lastReconciliation: later, replacePendingEvents: true, now: later)

        let stored = oracle.assertSingleDose(raw: first.raw)
        XCTAssertEqual(stored?.isMutable, true)
        XCTAssertEqual(stored?.updateCount, 1, "the second report updates the object it matched by syncIdentifier")
        XCTAssertEqual(stored?.savedToHealthKit, false, "mutable doses never reach HealthKit")
        XCTAssertTrue(oracle.deletedDoses.isEmpty)
        oracle.assertNoDuplicates()
        XCTAssertEqual(oracle.pumpEvents.count, 1, "replacePendingEvents purged the old mutable row before the insert")
    }

    func testFinishedReportMakesTheDosePermanent() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)

        let end = t0.addingTimeInterval(40)
        let final = bolus(units: 2, start: t0, delivered: 2, end: end, mutable: false)
        XCTAssertEqual(final.raw, first.raw, "the fixture keys raw on the programmed amount")
        let later = t0.addingTimeInterval(120)
        oracle.addPumpEvents([final], lastReconciliation: later, replacePendingEvents: true, now: later)

        let stored = oracle.assertPermanent(raw: first.raw)
        XCTAssertEqual(stored?.dose.deliveredUnits, 2)
        XCTAssertEqual(stored?.dose.endDate, end)
        XCTAssertEqual(oracle.pumpEventQueryAfterDate, t0, "the upload cursor moves on the finalized record's date")
        XCTAssertEqual(oracle.doses.count, 1)

        // Re-sending the permanent dose later changes nothing (uniqueness on raw and syncIdentifier).
        let evenLater = later.addingTimeInterval(300)
        oracle.addPumpEvents([final], lastReconciliation: evenLater, replacePendingEvents: true, now: evenLater)
        XCTAssertEqual(oracle.doses.count, 1)
        XCTAssertEqual(oracle.pumpEvents.count, 1)
        XCTAssertEqual(oracle.assertPermanent(raw: first.raw)?.updateCount, 0)
    }

    func testOmittedMutableDoseIsDeleted() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)

        // The next complete batch does not mention it, but must contain something for the fold to
        // run (DS:682 returns early on an empty batch).
        let later = t0.addingTimeInterval(60)
        let unrelated = tempBasal(rate: 0.5, start: later, duration: .minutes(30), mutable: true)
        oracle.addPumpEvents([unrelated], lastReconciliation: later, replacePendingEvents: true, now: later)

        oracle.assertDeleted(raw: first.raw)
        XCTAssertNil(oracle.pumpEventRow(raw: first.raw), "the mutable PumpEvent row was purged")
        XCTAssertEqual(oracle.doses.count, 1)
        XCTAssertEqual(oracle.doses.first?.dose.type, .tempBasal)
    }

    func testOmittedMutableDoseSurvivesWhenNotReplacing() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)

        let later = t0.addingTimeInterval(60)
        let unrelated = tempBasal(rate: 0.5, start: later, duration: .minutes(30), mutable: true)
        oracle.addPumpEvents([unrelated], lastReconciliation: later, replacePendingEvents: false, now: later)

        XCTAssertNotNil(oracle.assertSingleDose(raw: first.raw), "an appending batch leaves live mutable doses alone")
        XCTAssertEqual(oracle.doses.count, 2)
    }

    // MARK: - Loop: identity pitfalls

    func testChangedRawWithoutReplacingDuplicatesTheDose() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)

        // A cancel that re-keys the dose on the delivered amount (the MedtrumKit shape, guide §4).
        let end = t0.addingTimeInterval(20)
        let rekeyed = bolus(units: 1.2, start: t0, delivered: 1.2, end: end, mutable: false)
        XCTAssertNotEqual(rekeyed.raw, first.raw)
        let later = t0.addingTimeInterval(60)
        oracle.addPumpEvents([rekeyed], lastReconciliation: later, replacePendingEvents: false, now: later)

        XCTAssertEqual(oracle.doses.count, 2, "the stale mutable copy survives next to the finalized one")
        XCTAssertEqual(oracle.doses.filter { $0.dose.type == .bolus && $0.dose.startDate == t0 }.count, 2)
        XCTAssertGreaterThan(oracle.iob(at: later), 1.2 + 1.9, "IOB double-counts")
    }

    func testChangedRawWithReplacingIsRescuedByThePurge() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        let end = t0.addingTimeInterval(20)
        let rekeyed = bolus(units: 1.2, start: t0, delivered: 1.2, end: end, mutable: false)
        let later = t0.addingTimeInterval(60)
        oracle.addPumpEvents([rekeyed], lastReconciliation: later, replacePendingEvents: true, now: later)

        XCTAssertEqual(oracle.doses.count, 1, "the mutable purge, not identity matching, removed the old copy")
        oracle.assertDeleted(raw: first.raw)
        XCTAssertNotNil(oracle.assertPermanent(raw: rekeyed.raw))
    }

    func testSameRawWithoutReplacingIsIgnoredByTheStoreTrumpMerge() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        let end = t0.addingTimeInterval(40)
        let final = bolus(units: 2, start: t0, delivered: 2, end: end, mutable: false)
        let later = t0.addingTimeInterval(120)
        oracle.addPumpEvents([final], lastReconciliation: later, replacePendingEvents: false, now: later)

        XCTAssertEqual(oracle.pumpEventRow(raw: first.raw)?.mutable, true, "the stored row wins the raw conflict")
        XCTAssertEqual(oracle.assertSingleDose(raw: first.raw)?.isMutable, true, "so the dose never finalizes")
    }

    // MARK: - Loop: lastReconciliation and timing

    func testEmptyBatchAdvancesLastReconciliationAndNothingElse() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)

        let later = t0.addingTimeInterval(300)
        oracle.addPumpEvents([], lastReconciliation: later, replacePendingEvents: true, now: later)

        XCTAssertEqual(oracle.lastReconciliation, later)
        XCTAssertEqual(oracle.callCount, 2)
        XCTAssertEqual(oracle.reconciliationHistory, [t0, later])
        XCTAssertNotNil(oracle.assertSingleDose(raw: first.raw), "an empty batch does not purge, even with replacePendingEvents")
        XCTAssertEqual(oracle.pumpEvents.count, 1)

        oracle.addPumpEvents([], lastReconciliation: nil, replacePendingEvents: false, now: later)
        XCTAssertNil(oracle.lastReconciliation, "set unconditionally, nil included")
    }

    func testNothingReachesTheDeliveryStoreWithoutAReconciliationBoundary() {
        let oracle = LoopDoseStoreOracle()
        oracle.addPumpEvents([bolus(units: 2, start: t0, mutable: true)], lastReconciliation: nil, replacePendingEvents: true, now: t0)
        XCTAssertEqual(oracle.pumpEvents.count, 1, "the PumpEvent row is stored")
        XCTAssertTrue(oracle.cachedDoses.isEmpty, "but no dose reaches the InsulinDeliveryStore without lastReconciliation")
    }

    func testFinalizedDoseEndingAfterNowIsDroppedByTheDeliveryStore() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 2, start: t0, mutable: true)
        oracle.addPumpEvents([first], lastReconciliation: t0, replacePendingEvents: true, now: t0)

        // The pump's clock runs ahead: the finalized end is 30 s after the host's now.
        let now = t0.addingTimeInterval(60)
        let final = bolus(units: 2, start: t0, delivered: 2, end: now.addingTimeInterval(30), mutable: false)
        oracle.addPumpEvents([final], lastReconciliation: now, replacePendingEvents: true, now: now)

        XCTAssertEqual(oracle.pumpEventRow(raw: first.raw)?.mutable, false)
        oracle.assertDeleted(raw: first.raw)
        XCTAssertTrue(oracle.doses.isEmpty, "DS:1140 filters doses that have not ended; the mutable object was already marked deleted")
    }

    func testTempBasalReplacementTrimsThePredecessor() {
        let oracle = LoopDoseStoreOracle()
        let a = tempBasal(rate: 1.0, start: t0, duration: .minutes(30), mutable: true)
        oracle.addPumpEvents([a], lastReconciliation: t0, replacePendingEvents: true, now: t0)

        let switchAt = t0.addingTimeInterval(.minutes(7))
        let aFinal = tempBasal(rate: 1.0, start: t0, duration: .minutes(30), mutable: false, end: switchAt)
        let b = tempBasal(rate: 2.0, start: switchAt, duration: .minutes(30), mutable: true)
        oracle.addPumpEvents([aFinal, b], lastReconciliation: switchAt, replacePendingEvents: true, now: switchAt)

        XCTAssertEqual(oracle.doses.count, 2)
        let storedA = oracle.assertPermanent(raw: a.raw)
        XCTAssertEqual(storedA?.dose.endDate, switchAt)
        XCTAssertEqual(storedA?.dose.deliveredUnits ?? -1, 1.0 * 7 / 60, accuracy: 0.0001)
        XCTAssertEqual(oracle.assertSingleDose(raw: b.raw)?.isMutable, true)
    }

    func testIOBIsMonotoneAcrossIdenticalReReports() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 5, start: t0, mutable: true)
        var previous = Double.infinity
        for step in 0 ..< 8 {
            let now = t0.addingTimeInterval(Double(step) * 30)
            oracle.addPumpEvents([bolus(units: 5, start: t0, mutable: true)], lastReconciliation: now, replacePendingEvents: true, now: now)
            let iob = oracle.iob(at: now.addingTimeInterval(1))
            XCTAssertLessThanOrEqual(iob, previous + 0.0001, "IOB stepped up at report \(step): duplicate insertion")
            XCTAssertLessThanOrEqual(iob, 5.0001)
            previous = iob
        }
        XCTAssertNotNil(oracle.assertSingleDose(raw: first.raw))
    }

    // MARK: - Trio

    func testTrioCollapsesTheThreeBolusReportsOntoOneRowCorrectedDownward() {
        let oracle = TrioDoseStoreOracle()
        oracle.addPumpEvents([bolus(units: 2, start: t0, mutable: true)], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        oracle.addPumpEvents([bolus(units: 2, start: t0, mutable: true)], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        let end = t0.addingTimeInterval(20)
        oracle.addPumpEvents(
            [bolus(units: 2, start: t0, delivered: 1.2, end: end, mutable: false)],
            lastReconciliation: end,
            replacePendingEvents: true,
            now: end
        )

        let row = oracle.assertSingleBolus(at: t0, amount: 1.2)
        XCTAssertEqual(row?.downwardUpdates, 1)
        XCTAssertEqual(oracle.skipped.filter { $0.reason == .duplicate(.bolus) }.count, 2)
        XCTAssertEqual(oracle.lastEventDate, t0)
    }

    func testTrioNeverCorrectsABolusUpward() {
        let oracle = TrioDoseStoreOracle()
        oracle.addPumpEvents([bolus(units: 2, start: t0, delivered: 0, end: t0, mutable: false)], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        oracle.addPumpEvents([bolus(units: 2, start: t0, delivered: 2, end: t0, mutable: false)], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        oracle.assertSingleBolus(at: t0, amount: 0, "a 0 U placeholder sticks (audit G01-2)")
    }

    func testTrioIgnoresReplaceAndReconciliationAndSkipsFinalizedTempBasals() {
        let oracle = TrioDoseStoreOracle()
        let running = tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: true)
        oracle.addPumpEvents([running], lastReconciliation: nil, replacePendingEvents: false, now: t0)
        XCTAssertEqual(oracle.tempBasals.count, 1)
        XCTAssertEqual(oracle.tempBasals.first?.tempBasalDurationMinutes, 30)
        XCTAssertEqual(oracle.tempBasals.first?.tempBasalRate, 1.5)

        let cancelAt = t0.addingTimeInterval(.minutes(12))
        let finalized = tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: false, end: cancelAt)
        oracle.addPumpEvents([finalized], lastReconciliation: cancelAt, replacePendingEvents: true, now: cancelAt)

        XCTAssertEqual(oracle.tempBasals.count, 1)
        XCTAssertEqual(oracle.tempBasals.first?.tempBasalDurationMinutes, 30, "Trio keeps the programmed duration (audit G01-4)")
        XCTAssertEqual(oracle.skipped.last?.reason, .tempBasalWithDeliveredUnits)

        oracle.addPumpEvents([], lastReconciliation: cancelAt, replacePendingEvents: true, now: cancelAt)
        XCTAssertEqual(oracle.tempBasals.count, 1, "an empty replacing batch changes nothing in Trio")
        XCTAssertEqual(oracle.callCount, 3)
    }

    func testTrioDropsTempBasalsAboveMaxBasal() {
        let oracle = TrioDoseStoreOracle(maxBasal: 3)
        oracle.addPumpEvents([tempBasal(rate: 3.04, start: t0, duration: .minutes(30), mutable: true)], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        XCTAssertTrue(oracle.tempBasals.isEmpty)
        XCTAssertEqual(oracle.skipped.first?.reason, .tempBasalAboveMaxBasal(unitsPerHour: 3.04))
    }

    // MARK: - Journal replay

    func testJournalFeedReplaysBatchesInOrderWithTheClockTime() {
        let delegate = MockPumpManagerDelegate()
        let clock = ManualClock(t0)
        delegate.journalClock = clock
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())

        let first = bolus(units: 2, start: t0, mutable: true)
        delegate.pumpManager(manager, hasNewPumpEvents: [first], lastReconciliation: t0, replacePendingEvents: true) { _ in }
        clock.advance(by: 60)
        delegate.pumpManager(manager, didError: .communication(PumpCommError.pumpNotConnected))
        delegate.pumpManager(manager, hasNewPumpEvents: [], lastReconciliation: clock.now, replacePendingEvents: false) { _ in }

        XCTAssertEqual(delegate.journal.count, 3)
        XCTAssertEqual(delegate.journal.map(\.index), [0, 1, 2])
        XCTAssertEqual(delegate.journal.map(\.clockTime), [t0, t0.addingTimeInterval(60), t0.addingTimeInterval(60)])
        XCTAssertEqual(delegate.pumpEventJournal.count, 2)
        XCTAssertEqual(delegate.errors.count, 1)

        let oracle = LoopDoseStoreOracle()
        XCTAssertEqual(delegate.feed(oracle), 2)
        XCTAssertEqual(oracle.callCount, 2)
        XCTAssertEqual(oracle.lastReconciliation, t0.addingTimeInterval(60))
        XCTAssertNotNil(oracle.assertSingleDose(raw: first.raw))

        XCTAssertEqual(delegate.feed(oracle, after: 2), 0, "nothing new after the last index")
    }
}
