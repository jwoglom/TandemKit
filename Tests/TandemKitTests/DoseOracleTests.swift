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
            decisionId: nil,
            deliveredUnits: mutable ? nil : delivered,
            insulinType: .novolog,
            automatic: false,
            isMutable: mutable
        )
        return NewPumpEvent.bolus(dose: dose, date: start)
    }

    /// Keyed on rate and start, so the identity survives an early end.
    private func tempBasal(rate: Double, start: Date, duration: TimeInterval, mutable: Bool, end: Date? = nil) -> NewPumpEvent {
        let actualEnd = end ?? start.addingTimeInterval(duration)
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: start,
            endDate: actualEnd,
            value: rate,
            unit: .unitsPerHour,
            decisionId: nil,
            deliveredUnits: mutable ? nil : rate * actualEnd.timeIntervalSince(start) / .hours(1),
            insulinType: .novolog,
            automatic: true,
            isMutable: mutable
        )
        return NewPumpEvent(
            date: start,
            dose: dose,
            raw: Data("tempBasal \(rate) \(start.timeIntervalSinceReferenceDate)".utf8),
            title: "Temp Basal"
        )
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
        XCTAssertEqual(
            oracle.assertPermanent(raw: first.raw)?.updateCount,
            1,
            "one update (the finalization); the re-send matched no mutable object and its insert was dropped"
        )
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

        // The PumpEvent row is final, but DS:1140 filters the dose out of the delivery-store save
        // (it has not ended by the host's now), DS:935 then skips addDoseEntries entirely, and the
        // stale mutable object stays live at the IDS tier: the dose is in limbo, still mutable.
        XCTAssertEqual(oracle.pumpEventRow(raw: first.raw)?.mutable, false)
        let limbo = oracle.assertSingleDose(raw: first.raw)
        XCTAssertEqual(limbo?.isMutable, true, "the delivery store never saw the finalization")
        XCTAssertEqual(limbo?.savedToHealthKit, false)

        // Once the host's clock passes the end, any non-empty save resolves it.
        let afterEnd = now.addingTimeInterval(60)
        oracle.addPumpEvents([final], lastReconciliation: afterEnd, replacePendingEvents: true, now: afterEnd)
        XCTAssertNotNil(oracle.assertPermanent(raw: first.raw))
    }

    func testAFinalizedDoseThatHasNotEndedIsCountedFromItsPumpEventUntilTheNextBatchStoresIt() {
        let oracle = LoopDoseStoreOracle()
        let now = t0.addingTimeInterval(.minutes(1))
        let ended = tempBasal(rate: 1.5, start: t0, duration: .minutes(1), mutable: false)
        let remainder = tempBasal(rate: 1.5, start: now, duration: .minutes(29), mutable: false)
        oracle.addPumpEvents([ended, remainder], lastReconciliation: now, replacePendingEvents: true, now: now)

        XCTAssertNotNil(oracle.assertPermanent(raw: ended.raw))
        XCTAssertNil(oracle.dose(raw: remainder.raw))
        XCTAssertEqual(oracle.normalizedDoses().compactMap(\.syncIdentifier), [ended.raw.hexadecimalString, remainder.raw.hexadecimalString])

        // An empty batch saves too, so a boundary past its end stores it.
        let afterEnd = t0.addingTimeInterval(.minutes(35))
        oracle.addPumpEvents([], lastReconciliation: afterEnd, replacePendingEvents: false, now: afterEnd)
        XCTAssertNotNil(oracle.assertPermanent(raw: remainder.raw))
        XCTAssertEqual(oracle.normalizedDoses().compactMap(\.syncIdentifier), [ended.raw.hexadecimalString, remainder.raw.hexadecimalString])
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

    func testABasalMarkerBeforeASuspendIsStoredAsAPumpEventButNeverAsADose() {
        let oracle = LoopDoseStoreOracle()
        let marker = scheduledBasal(rate: 1.0, at: t0)
        let resumedAt = t0.addingTimeInterval(.minutes(5))
        oracle.addPumpEvents(
            [marker, suspend(at: t0.addingTimeInterval(1)), resume(at: resumedAt)],
            lastReconciliation: resumedAt,
            replacePendingEvents: true,
            now: resumedAt
        )

        XCTAssertNotNil(oracle.pumpEventRow(raw: marker.raw))
        XCTAssertEqual(oracle.cachedDoses(raw: marker.raw), [], "HKQS:56-60 makes no sample for a basal with no duration")
        XCTAssertEqual(oracle.doses.map(\.dose.type), [.suspend])
    }

    func testIOBDoesNotDriftAcrossIdenticalReReports() {
        let oracle = LoopDoseStoreOracle()
        let first = bolus(units: 5, start: t0, mutable: true)
        // Read IOB at one fixed instant after delivery, so the only thing that could move it between
        // reports is a duplicate dose.
        let probe = t0.addingTimeInterval(.hours(1))
        let expected = LoopDoseStoreOracle.linearIOB(of: first.dose!, at: probe, duration: .hours(5))
        XCTAssertGreaterThan(expected, 0)
        for step in 0 ..< 8 {
            let now = t0.addingTimeInterval(Double(step) * 30)
            oracle.addPumpEvents([bolus(units: 5, start: t0, mutable: true)], lastReconciliation: now, replacePendingEvents: true, now: now)
            XCTAssertEqual(oracle.iob(at: probe), expected, accuracy: 1e-9, "IOB drifted at report \(step): duplicate insertion")
        }
        XCTAssertNotNil(oracle.assertSingleDose(raw: first.raw))
        XCTAssertEqual(oracle.iob(at: t0), 0, "nothing on board before delivery starts")
        XCTAssertEqual(oracle.iob(at: t0.addingTimeInterval(.hours(6))), 0, accuracy: 1e-9, "fully decayed after the action duration")
    }

    // MARK: - Loop: the basal schedule overlay

    private let utcSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)], timeZone: TimeZone(identifier: "UTC"))!

    /// The reference date is a UTC midnight.
    private func utcMidnight(of date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / .hours(24)).rounded(.down) * .hours(24))
    }

    private func scheduleFill(_ oracle: LoopDoseStoreOracle) -> [LoopDoseStoreOracle.StoredDose] {
        oracle.doses.filter { $0.syncIdentifier.hasPrefix("BasalRateSchedule ") }.sorted { $0.dose.startDate < $1.dose.startDate }
    }

    func testLoopFillsNothingBeforeTheFirstPumpEvent() {
        let oracle = LoopDoseStoreOracle(basalSchedule: utcSchedule)
        let now = t0.addingTimeInterval(.minutes(5))
        oracle.addPumpEvents([tempBasal(rate: 2.0, start: t0, duration: .minutes(30), mutable: true)], lastReconciliation: now, replacePendingEvents: true, now: now)

        XCTAssertEqual(scheduleFill(oracle).count, 0)
    }

    func testLoopFillsFromAFinishedTempBasalToTheBoundaryKeyedOnItsStartAndMutable() {
        let oracle = LoopDoseStoreOracle(basalSchedule: utcSchedule)
        let end = t0.addingTimeInterval(.minutes(10))
        let boundary = t0.addingTimeInterval(.minutes(20))
        oracle.addPumpEvents(
            [tempBasal(rate: 2.0, start: t0, duration: .minutes(30), mutable: false, end: end)],
            lastReconciliation: boundary,
            replacePendingEvents: true,
            now: boundary
        )

        let fill = scheduleFill(oracle)
        XCTAssertEqual(fill.map(\.dose.startDate), [end])
        XCTAssertEqual(fill.map(\.dose.endDate), [boundary])
        XCTAssertEqual(fill.map(\.syncIdentifier), ["BasalRateSchedule \(ISO8601DateFormatter().string(from: end))"])
        XCTAssertEqual(fill.map(\.isMutable), [true])
    }

    func testAnEmptyBatchExtendsLoopsMutableFillToTheNewBoundary() {
        let oracle = LoopDoseStoreOracle(basalSchedule: utcSchedule)
        let end = t0.addingTimeInterval(.minutes(10))
        oracle.addPumpEvents(
            [tempBasal(rate: 2.0, start: t0, duration: .minutes(30), mutable: false, end: end)],
            lastReconciliation: t0.addingTimeInterval(.minutes(20)),
            replacePendingEvents: true,
            now: t0.addingTimeInterval(.minutes(20))
        )

        let later = t0.addingTimeInterval(.minutes(25))
        oracle.addPumpEvents([], lastReconciliation: later, replacePendingEvents: false, now: later)

        let fill = scheduleFill(oracle)
        XCTAssertEqual(fill.map(\.dose.startDate), [end])
        XCTAssertEqual(fill.map(\.dose.endDate), [later])
        XCTAssertEqual(fill.map(\.isMutable), [true])
    }

    func testLoopEndsAResumedSuspendAtItsResume() {
        let oracle = LoopDoseStoreOracle(basalSchedule: utcSchedule)
        let resumeDate = t0.addingTimeInterval(.minutes(5))
        let boundary = t0.addingTimeInterval(.minutes(6))
        oracle.addPumpEvents(
            [suspend(at: t0), resume(at: resumeDate)],
            lastReconciliation: boundary,
            replacePendingEvents: true,
            now: boundary
        )

        let suspends = oracle.doses.filter { $0.dose.type == .suspend }
        XCTAssertEqual(suspends.map(\.dose.endDate), [resumeDate], "LoopKit/LoopKit#688 stretches it to the boundary")
        XCTAssertEqual(scheduleFill(oracle).map(\.dose.startDate), [resumeDate])
    }

    func testLoopsScheduleFillStartsTheNextSaveAtTheRunningTempBasal() {
        let oracle = LoopDoseStoreOracle(basalSchedule: utcSchedule)
        let running = tempBasal(rate: 2.0, start: t0, duration: .minutes(30), mutable: true)
        oracle.addPumpEvents([running], lastReconciliation: t0.addingTimeInterval(60), replacePendingEvents: true, now: t0.addingTimeInterval(60))
        let fillBefore = scheduleFill(oracle).count

        let end = t0.addingTimeInterval(.minutes(10))
        let finished = tempBasal(rate: 2.0, start: t0, duration: .minutes(30), mutable: false, end: end)
        oracle.addPumpEvents([finished], lastReconciliation: end, replacePendingEvents: true, now: end)

        XCTAssertEqual(scheduleFill(oracle).count, fillBefore, "no gap before the temp basal is filled twice")
        XCTAssertEqual(oracle.assertPermanent(raw: running.raw)?.dose.endDate, end)
    }

    func testLoopsScheduleRatesFollowItsSegments() {
        let schedule = BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0), RepeatingScheduleValue(startTime: .hours(6), value: 0.5)],
            timeZone: TimeZone(identifier: "UTC")
        )!
        let utcDay = utcMidnight(of: t0)
        let rates = LoopDoseStoreOracle.scheduledRates(schedule, from: utcDay.addingTimeInterval(.hours(5)), to: utcDay.addingTimeInterval(.hours(7)))
        XCTAssertEqual(rates.map(\.rate), [1.0, 0.5])
        XCTAssertEqual(rates.map(\.start), [utcDay, utcDay.addingTimeInterval(.hours(6))])
        XCTAssertEqual(rates.map(\.end), [utcDay.addingTimeInterval(.hours(6)), utcDay.addingTimeInterval(.hours(24))])
    }

    // MARK: - Trio

    private func scheduledBasal(rate: Double, at date: Date) -> NewPumpEvent {
        NewPumpEvent.basal(
            dose: DoseEntry(type: .basal, startDate: date, endDate: date, value: rate, unit: .unitsPerHour, decisionId: nil, insulinType: .novolog),
            date: date
        )
    }

    private func suspend(at date: Date) -> NewPumpEvent {
        NewPumpEvent.suspend(dose: DoseEntry(suspendDate: date), date: date)
    }

    private func resume(at date: Date) -> NewPumpEvent {
        NewPumpEvent.resume(dose: DoseEntry(resumeDate: date, insulinType: .novolog), date: date)
    }

    private func trio(_ batches: [NewPumpEvent]..., replacing: Bool = false, now: Date? = nil) -> TrioDoseStoreOracle {
        let oracle = TrioDoseStoreOracle()
        for batch in batches {
            oracle.addPumpEvents(batch, lastReconciliation: nil, replacePendingEvents: replacing, now: now ?? t0.addingTimeInterval(.hours(3)))
        }
        return oracle
    }

    func testTrioUpdatesAMutableBolusUntilItIsFinalized() {
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
        XCTAssertEqual(row?.updateCount, 2)
        XCTAssertEqual(row?.isMutable, false)
        XCTAssertEqual(row?.programmedAmount, 2)
        XCTAssertTrue(oracle.skipped.isEmpty)
        XCTAssertEqual(oracle.lastEventDate, t0)
    }

    func testTrioNeverChangesAFinalizedRow() {
        let oracle = trio(
            [bolus(units: 2, start: t0, delivered: 0, end: t0, mutable: false)],
            [bolus(units: 2, start: t0, delivered: 2, end: t0, mutable: false)]
        )
        oracle.assertSingleBolus(at: t0, amount: 0, "a 0 U placeholder sticks (audit G01-2)")
        XCTAssertEqual(oracle.skipped.map(\.reason), [.duplicate(.bolus)])
    }

    func testTrioFinalizesATempBasalAtItsDeliveredSpan() {
        let cancelAt = t0.addingTimeInterval(.minutes(12))
        let oracle = trio(
            [tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: true)],
            [tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: false, end: cancelAt)]
        )

        XCTAssertEqual(oracle.tempBasals.count, 1)
        let row = oracle.tempBasals.first
        XCTAssertEqual(row?.tempBasalDurationMinutes, 12)
        XCTAssertEqual(row?.deliveredUnits, Decimal(0.3))
        XCTAssertEqual(row?.isMutable, false)
    }

    func testTrioMatchesAReKeyedReportOnTimestampAndType() {
        let running = tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: true)
        let cancelAt = t0.addingTimeInterval(.minutes(12))
        let finished = NewPumpEvent(
            date: t0,
            dose: tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: false, end: cancelAt).dose,
            raw: Data("re-keyed".utf8),
            title: "Temp Basal"
        )

        let oracle = trio([running], [finished], replacing: true)

        XCTAssertEqual(oracle.tempBasals.count, 1, "\(oracle.events)")
        XCTAssertEqual(oracle.tempBasals.first?.syncIdentifier, running.dose?.syncIdentifier)
        XCTAssertEqual(oracle.tempBasals.first?.tempBasalDurationMinutes, 12)
        XCTAssertTrue(oracle.purged.isEmpty, "the re-keyed report asserted the row it matched")
    }

    func testTrioKeepsAScheduledBasalApartFromATempBasalInTheSameSecond() {
        let oracle = trio([
            tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: false, end: t0),
            scheduledBasal(rate: 0.8, at: t0)
        ])

        XCTAssertEqual(oracle.tempBasals.count, 1)
        XCTAssertEqual(oracle.scheduledBasals.count, 1)
        XCTAssertEqual(oracle.scheduledBasals.first?.tempBasalDurationMinutes, 0)
        XCTAssertEqual(oracle.scheduledBasals.first?.tempBasalRate, 0.8)
    }

    func testTrioPurgesTheMutableRowsAReplacingBatchLeavesOut() {
        let running = tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: true)
        let other = bolus(units: 1, start: t0.addingTimeInterval(60), delivered: 1, mutable: false)

        let kept = trio([running], [other])
        XCTAssertEqual(kept.tempBasals.count, 1, "a non-replacing batch leaves it")

        let purged = trio([running], [other], replacing: true)
        XCTAssertTrue(purged.tempBasals.isEmpty)
        XCTAssertEqual(purged.purged.map(\.row.syncIdentifier), [running.dose?.syncIdentifier])
    }

    func testAnEmptyReplacingBatchPurgesEveryMutableRow() {
        let oracle = trio([tempBasal(rate: 1.5, start: t0, duration: .minutes(30), mutable: true)], [], replacing: true)

        XCTAssertTrue(oracle.tempBasals.isEmpty)
        XCTAssertNil(oracle.lastEventDate)
        XCTAssertEqual(oracle.callCount, 2)
    }

    func testTrioDropsTempBasalsAboveMaxBasal() {
        let oracle = TrioDoseStoreOracle(maxBasal: 3)
        oracle.addPumpEvents([tempBasal(rate: 3.04, start: t0, duration: .minutes(30), mutable: true)], lastReconciliation: t0, replacePendingEvents: true, now: t0)
        XCTAssertTrue(oracle.tempBasals.isEmpty)
        XCTAssertEqual(oracle.skipped.first?.reason, .tempBasalAboveMaxBasal(unitsPerHour: 3.04))
    }

    func testTrioDatesARowFromTheFutureNow() {
        let oracle = trio([bolus(units: 1, start: t0.addingTimeInterval(120), delivered: 1, mutable: false)], now: t0)
        XCTAssertEqual(oracle.boluses.first?.timestamp, t0)
    }

    // MARK: - Trio IOB

    private let schedule: (Date) -> Double = { _ in 1.0 }

    func testTrioCutsEachBasalRowAtTheNextWhateverTheOrderItArrivedIn() throws {
        let temp = tempBasal(rate: 2, start: t0, duration: .minutes(60), mutable: false)
        let correction = tempBasal(rate: 3, start: t0.addingTimeInterval(.minutes(30)), duration: .minutes(5), mutable: false)
        let clock = t0.addingTimeInterval(.hours(2))

        for oracle in [trio([temp], [correction]), trio([correction], [temp])] {
            XCTAssertEqual(try oracle.basalSegments(clock: clock).filter { $0.rate > 0 }, [
                .init(start: t0, end: t0.addingTimeInterval(.minutes(30)), rate: 2),
                .init(start: t0.addingTimeInterval(.minutes(30)), end: t0.addingTimeInterval(.minutes(35)), rate: 3)
            ])
            XCTAssertEqual(try oracle.netBasalUnits(from: t0, to: clock, clock: clock, scheduledRate: schedule), 0.5 + 2.0 / 12, accuracy: 1e-6)
        }
    }

    func testATempBasalReportedAtAnotherTempsTimestampLandsOnItsRow() {
        let oracle = trio([
            tempBasal(rate: 2, start: t0, duration: .minutes(30), mutable: false),
            NewPumpEvent(date: t0, dose: tempBasal(rate: 3, start: t0, duration: .minutes(30), mutable: false).dose, raw: Data("other".utf8), title: "Temp Basal")
        ])

        XCTAssertEqual(oracle.tempBasals.map(\.tempBasalRate), [2])
        XCTAssertEqual(oracle.skipped.map(\.reason), [.duplicate(.tempBasal)])
    }

    func testTwoBasalRowsAtOneTimestampLeaveOneZeroLength() throws {
        let oracle = trio([
            tempBasal(rate: 2, start: t0, duration: .minutes(30), mutable: false),
            scheduledBasal(rate: 1, at: t0)
        ])

        XCTAssertEqual(try oracle.basalSegments(clock: t0.addingTimeInterval(.hours(1))).filter { $0.rate > 0 }, [])
    }

    func testAScheduledBasalRowEndsATempBasalForIOB() throws {
        let oracle = trio(
            [tempBasal(rate: 2, start: t0, duration: .minutes(30), mutable: true)],
            [scheduledBasal(rate: 1, at: t0.addingTimeInterval(.minutes(10)))]
        )
        let clock = t0.addingTimeInterval(.hours(1))

        XCTAssertEqual(try oracle.netBasalUnits(from: t0, to: clock, clock: clock, scheduledRate: schedule), 1.0 / 6, accuracy: 1e-6)
    }

    func testTrioIOBReadsTheRateAndDurationNotTheDeliveredUnits() throws {
        let entry = DoseEntry(
            type: .tempBasal,
            startDate: t0,
            endDate: t0.addingTimeInterval(.minutes(30)),
            value: 2,
            unit: .unitsPerHour,
            decisionId: nil,
            deliveredUnits: 5,
            insulinType: .novolog
        )
        let oracle = trio([NewPumpEvent(date: t0, dose: entry, raw: Data("t".utf8), title: "Temp Basal")])
        let clock = t0.addingTimeInterval(.hours(1))

        XCTAssertEqual(try oracle.netBasalUnits(from: t0, to: clock, clock: clock, scheduledRate: schedule), 0.5, accuracy: 1e-6)
    }

    func testASuspendCutsATempBasalAndRunsAtZero() throws {
        let oracle = trio([
            tempBasal(rate: 2, start: t0, duration: .minutes(60), mutable: false),
            suspend(at: t0.addingTimeInterval(.minutes(10))),
            resume(at: t0.addingTimeInterval(.minutes(20)))
        ])
        let clock = t0.addingTimeInterval(.hours(2))

        // Above the schedule for 10 + 40 minutes (oref resumes the temp after the suspend), below it for 10.
        XCTAssertEqual(try oracle.netBasalUnits(from: t0, to: clock, clock: clock, scheduledRate: schedule), 50.0 / 60 - 10.0 / 60, accuracy: 1e-6)
    }

    func testASuspendAndResumeInOneSecondFailTrioIOB() {
        let oracle = trio([suspend(at: t0), resume(at: t0)])
        XCTAssertThrowsError(try oracle.basalSegments(clock: t0.addingTimeInterval(60)))
    }

    func testTrioIOBDecaysBolusesAndNetBasal() throws {
        let oracle = trio([
            bolus(units: 2, start: t0, delivered: 2, mutable: false),
            tempBasal(rate: 3, start: t0, duration: .minutes(30), mutable: false)
        ])
        let probe = t0.addingTimeInterval(.minutes(30))

        let expectedBolus = 2 * (1 - 0.5 / 5)
        // 1 U net delivered evenly over 30 minutes, each part decayed from its delivery.
        let expectedBasal = 1 * (1 - 0.25 / 5)
        XCTAssertEqual(try oracle.iob(at: probe, scheduledRate: schedule), expectedBolus + expectedBasal, accuracy: 1e-4)
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
