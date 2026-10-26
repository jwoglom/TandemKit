import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Conformance group J (`docs/conformance-test-plan.md`): extended boluses programmed off the app
/// (#424), through their life on the pump, and the standard boluses given around one. Every
/// scenario runs with History Backfill and History Dose Reporting on, and ends with both oracles,
/// the complete-batch check and, where the pump's records are whole, the pump-timeline diff.
final class ExtendedBolusConformanceTests: ConformanceTestCase {
    private static let defaultDeliveryRate = 0.05

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        if let harness {
            try? harness.client.setState(["basal_rate": 1.0, "bolus_rate_units_per_second": Self.defaultDeliveryRate])
        }
        try super.tearDownWithError()
    }

    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        allPumpEventBatches.dropFirst(count).flatMap(\.events)
    }

    /// A finalized report as the guide wants it: immutable, delivered on the 0.001 U grid, pump
    /// delivered, typed insulin, identity from `raw`.
    private func assertFinalized(_ event: NewPumpEvent, delivered: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(event.dose?.isMutable, false, "finalized: \(event)", file: file, line: line)
        XCTAssertEqual(event.dose?.deliveredUnits ?? -1, delivered, accuracy: 0.0005, file: file, line: line)
        let units = event.dose?.deliveredUnits ?? 0
        XCTAssertEqual(units * 1000, (units * 1000).rounded(), accuracy: 1e-6, "on the 0.001 U grid", file: file, line: line)
        XCTAssertEqual(event.dose?.manuallyEntered, false, file: file, line: line)
        XCTAssertNotNil(event.dose?.insulinType, file: file, line: line)
        XCTAssertEqual(event.dose?.syncIdentifier, event.raw.hexadecimalString, file: file, line: line)
    }

    private func assertNothingLiveDropped(file: StaticString = #filePath, line: UInt = #line) {
        let omissions = completeBatchOmissions()
        XCTAssertTrue(omissions.isEmpty, "nothing live may be dropped by silence:\n" + omissions.joined(separator: "\n"), file: file, line: line)
    }

    /// A 100% extended bolus programmed in Tandem's Mobi app, with its BolusDelivery record, read
    /// while it runs. Returns when it started.
    private func startFullyExtendedBolus(
        bolusId: Int,
        units: Double,
        minutes: Int,
        _ driver: FaketandemHarness.Driver
    ) throws -> (startedAt: Date, held: NewPumpEvent) {
        let batchesBefore = allPumpEventBatches.count
        let startedAt = clock.now
        try appendExtendedRequest(bolusId: bolusId, standardPercent: 0, minutes: minutes, options: 5)
        try appendExtendedBolusDelivery(bolusId: bolusId, upFrontUnits: 0, extendedUnits: units, minutes: minutes)
        let activated = try appendBolexActivated(bolusId: bolusId, units: units)
        try syncUntilHistoryRead(through: activated, driver)
        let raw = try extendedPartRaw(bolusId: bolusId, driver)
        let held = try XCTUnwrap(eventsSince(batchesBefore).first { $0.raw == raw }, "reported while it runs: \(eventsSince(batchesBefore))")
        XCTAssertEqual(held.dose?.isMutable, true)
        XCTAssertEqual(held.dose?.programmedUnits ?? -1, units, accuracy: 0.0005)
        XCTAssertEqual(held.dose?.startDate.timeIntervalSince(startedAt) ?? .infinity, 0, accuracy: 2)
        XCTAssertEqual(held.dose?.endDate.timeIntervalSince(startedAt) ?? .infinity, .minutes(Double(minutes)), accuracy: 2)
        return (startedAt, held)
    }

    // MARK: - J1

    /// Every sync re-sends the running extended part in its replacing batch, unchanged, and Loop and
    /// Trio hold one dose for it throughout; it is finalized once, at its programmed end.
    func testJ1AnExtendedBolusRunningAcrossSyncsIsReSentUnchangedUntilItCompletes() throws {
        let driver = try startPairedDriverReportingHistory()
        let batchesBefore = allPumpEventBatches.count
        let bolusId = 7101
        let units = 3.0
        let minutes = 60
        let (startedAt, held) = try startFullyExtendedBolus(bolusId: bolusId, units: units, minutes: minutes, driver)
        let raw = held.raw

        for step in 1 ... 4 {
            try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
            try appendExtendedBolusDelivery(
                bolusId: bolusId, upFrontUnits: 0, extendedUnits: units, minutes: minutes,
                deliveredUnits: units * Double(step * 5) / Double(minutes)
            )
            let before = allPumpEventBatches.count
            _ = try sync()
            let replacing = allPumpEventBatches.dropFirst(before).filter(\.replacePendingEvents)
            XCTAssertFalse(replacing.isEmpty, "sync \(step) re-sends what the host holds")
            for batch in replacing {
                let carried = batch.events.first { $0.raw == raw }
                XCTAssertEqual(carried?.dose?.isMutable, true, "sync \(step) carries it: \(batch.events)")
                XCTAssertEqual(carried?.date, held.date)
                XCTAssertEqual(carried?.dose?.startDate, held.dose?.startDate)
                XCTAssertEqual(carried?.dose?.endDate, held.dose?.endDate, "its programmed end, not a guess from the delivered total")
                XCTAssertEqual(carried?.dose?.programmedUnits, held.dose?.programmedUnits)
            }
            let (loop, trio) = feedOracles()
            XCTAssertEqual(loop.normalizedDoses().filter { $0.syncIdentifier == raw.hexadecimalString }.count, 1, "Loop counts one dose at sync \(step)")
            XCTAssertEqual(trio.boluses.count, 1, "Trio holds one row at sync \(step): \(trio.boluses)")
        }

        try clock.advanceBoth(seconds: startedAt.addingTimeInterval(.minutes(Double(minutes))).timeIntervalSince(clock.now), ticks: 20)
        let completedAt = clock.now
        try appendExtendedBolusDelivery(bolusId: bolusId, upFrontUnits: 0, extendedUnits: units, minutes: minutes, status: .completed, deliveredUnits: units)
        let completed = try appendBolexCompleted(bolusId: bolusId, delivered: units, requested: units)
        try syncUntilHistoryRead(through: completed, driver)
        _ = try sync()

        let finals = eventsSince(batchesBefore).filter { $0.raw == raw && $0.dose?.isMutable == false }
        XCTAssertEqual(finals.count, 1, "finalized once: \(finals)")
        let final = try XCTUnwrap(finals.first)
        assertFinalized(final, delivered: units)
        XCTAssertEqual(final.date, held.date, "under the date it was first reported at")
        XCTAssertEqual(final.dose?.endDate.timeIntervalSince(completedAt) ?? .infinity, 0, accuracy: 2)
        assertNothingLiveDropped()

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(loop.assertPermanent(raw: raw)?.dose.deliveredUnits ?? -1, units, accuracy: 0.0005)
        let row = trio.event(syncIdentifier: raw.hexadecimalString)
        XCTAssertEqual(row?.isMutable, false)
        XCTAssertEqual(row?.bolusAmount, Decimal(units))
        XCTAssertEqual(row?.isSMB, false)
        try timeline().assertMatches(loop)
    }

    // MARK: - J2

    /// Older t:slim X2 firmware writes no BolusDelivery records, so the running extended part takes
    /// its programmed duration from BolusRequestedMsg2. The up-front part is reported once, finished.
    func testJ2OnFirmwareWithoutBolusDeliveryRecordsTheDurationComesFromTheRequest() throws {
        let driver = try startPairedDriverReportingHistory()
        let batchesBefore = allPumpEventBatches.count
        let bolusId = 7102
        let upFront = 1.0
        let extended = 1.0
        let minutes = 30

        try appendExtendedRequest(bolusId: bolusId, standardPercent: 50, minutes: minutes)
        try clock.advanceBoth(seconds: 15)
        let upFrontStartedAt = clock.now
        try appendBolusActivated(bolusId: bolusId, units: upFront)
        try clock.advanceBoth(seconds: 40)
        let extendedAt = clock.now
        try appendBolusCompleted(bolusId: bolusId, units: upFront)
        let activated = try appendBolexActivated(bolusId: bolusId, units: extended)
        try syncUntilHistoryRead(through: activated, driver)

        let upFrontRaw = try upFrontPartRaw(bolusId: bolusId, driver)
        let raw = try extendedPartRaw(bolusId: bolusId, driver)
        let upFrontReports = eventsSince(batchesBefore).filter { $0.raw == upFrontRaw }
        XCTAssertEqual(upFrontReports.count, 1, "the up-front part, once: \(upFrontReports)")
        let upFrontPart = try XCTUnwrap(upFrontReports.first)
        assertFinalized(upFrontPart, delivered: upFront)
        XCTAssertEqual(upFrontPart.dose?.startDate.timeIntervalSince(upFrontStartedAt) ?? .infinity, 0, accuracy: 2)
        let held = try XCTUnwrap(eventsSince(batchesBefore).first { $0.raw == raw })
        XCTAssertEqual(held.dose?.isMutable, true)
        XCTAssertEqual(held.dose?.startDate.timeIntervalSince(extendedAt) ?? .infinity, 0, accuracy: 2)
        XCTAssertEqual(
            held.dose?.endDate.timeIntervalSince(extendedAt) ?? .infinity,
            .minutes(Double(minutes)),
            accuracy: 2,
            "from BolusRequestedMsg2's duration"
        )

        try clock.advanceBoth(seconds: .minutes(Double(minutes)), ticks: 15)
        let completedAt = clock.now
        let completed = try appendBolexCompleted(bolusId: bolusId, delivered: extended, requested: extended)
        try syncUntilHistoryRead(through: completed, driver)

        let final = try XCTUnwrap(eventsSince(batchesBefore).last { $0.raw == raw && $0.dose?.isMutable == false })
        assertFinalized(final, delivered: extended)
        XCTAssertEqual(final.dose?.endDate.timeIntervalSince(completedAt) ?? .infinity, 0, accuracy: 2)
        XCTAssertEqual(eventsSince(batchesBefore).filter { $0.raw == upFrontRaw }.count, 1, "the up-front part is not reported again")
        assertNothingLiveDropped()

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertNotNil(loop.assertPermanent(raw: upFrontRaw))
        XCTAssertNotNil(loop.assertPermanent(raw: raw))
        XCTAssertEqual(trio.boluses.map(\.bolusAmount), [Decimal(upFront), Decimal(extended)], "\(trio.boluses)")
        try timeline().assertMatches(loop)
    }

    // MARK: - J3

    /// Suspending the pump stops the extended part: the pump logs BolexCompleted with status 0 and
    /// what it delivered, then PumpingSuspended in the same second, as a Mobi capture shows. The part
    /// is finalized at that amount and ended at the stop, and the suspend is reported at the stop.
    func testJ3ASuspendStopsTheExtendedPartAndItIsFinalizedAtWhatItDelivered() throws {
        let driver = try startPairedDriverReportingHistory()
        let batchesBefore = allPumpEventBatches.count
        let bolusId = 7103
        let upFront = 1.5
        let extended = 1.5
        let delivered = 0.3

        try appendExtendedRequest(bolusId: bolusId, standardPercent: 50, minutes: 60)
        try clock.advanceBoth(seconds: 15)
        try appendBolusActivated(bolusId: bolusId, units: upFront)
        try clock.advanceBoth(seconds: 60)
        try appendBolusCompleted(bolusId: bolusId, units: upFront)
        let activated = try appendBolexActivated(bolusId: bolusId, units: extended)
        try syncUntilHistoryRead(through: activated, driver)
        let raw = try extendedPartRaw(bolusId: bolusId, driver)
        let held = try XCTUnwrap(eventsSince(batchesBefore).first { $0.raw == raw })
        XCTAssertEqual(held.dose?.isMutable, true)

        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        let stoppedAt = clock.now
        let stopped = try appendBolexCompleted(bolusId: bolusId, delivered: delivered, requested: extended, completionStatus: 0)
        try harness.client.suspend(reason: "user")
        try clock.advanceBoth(seconds: .minutes(15), ticks: 15)
        let resumedAt = clock.now
        try harness.client.resume()
        try syncUntilHistoryRead(through: stopped, driver)
        _ = try sync()

        let finals = eventsSince(batchesBefore).filter { $0.raw == raw && $0.dose?.isMutable == false }
        XCTAssertEqual(finals.count, 1, "\(finals)")
        let final = try XCTUnwrap(finals.first)
        assertFinalized(final, delivered: delivered)
        XCTAssertEqual(final.dose?.programmedUnits ?? -1, extended, accuracy: 0.0005)
        XCTAssertEqual(final.dose?.endDate.timeIntervalSince(stoppedAt) ?? .infinity, 0, accuracy: 2, "at the stop")
        let suspends = eventsSince(batchesBefore).filter { $0.type == .suspend }
        XCTAssertEqual(suspends.count, 1, "\(suspends)")
        XCTAssertEqual(suspends.first?.date.timeIntervalSince(stoppedAt) ?? .infinity, 0, accuracy: 2, "the suspend at the pump's stop")
        XCTAssertTrue(
            eventsSince(batchesBefore).contains { ($0.type == .resume || $0.type == .basal) && $0.date >= resumedAt.addingTimeInterval(-2) },
            "delivery is back after the resume: \(eventsSince(batchesBefore))"
        )
        assertNothingLiveDropped()

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertEqual(loop.assertPermanent(raw: raw)?.dose.deliveredUnits ?? -1, delivered, accuracy: 0.0005)
        XCTAssertEqual(trio.suspends.count, 1)
        let row = try XCTUnwrap(trio.event(syncIdentifier: raw.hexadecimalString))
        XCTAssertEqual(NSDecimalNumber(decimal: row.bolusAmount ?? -1).doubleValue, delivered, accuracy: 0.0005)
        try timeline().assertMatches(loop)
    }

    // MARK: - J4

    /// A relaunch while the extended part runs: the new driver re-reads the pump's history, finds the
    /// part in its ledger, carries it in its replacing batches and never reports it anew.
    func testJ4AHeldExtendedPartIsCarriedAcrossARelaunchAndFinalizedOnce() throws {
        let driver = try startPairedDriverReportingHistory()
        let batchesBefore = allPumpEventBatches.count
        let bolusId = 7104
        let units = 2.0
        let minutes = 60
        let (startedAt, held) = try startFullyExtendedBolus(bolusId: bolusId, units: units, minutes: minutes, driver)
        let raw = held.raw
        XCTAssertNotNil(driver.manager.state.historyBackfill)

        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let relaunched = try relaunch()
        let batchesAfterRelaunch = allPumpEventBatches.count
        _ = try sync()
        try IntegrationWait.until("the relaunched driver to read history again", timeout: 180) {
            relaunched.manager.historyLogStoreSerial.map { serial in
                ((try? relaunched.manager.historyLogStore.logs(pumpSerial: serial.rawValue, in: 0 ... UInt32.max)) ?? []).contains {
                    $0.parsed() is BolexActivatedHistoryLog
                }
            } ?? false
        }
        _ = try sync()

        let sinceRelaunch = Array(allPumpEventBatches.dropFirst(batchesAfterRelaunch))
        let replacing = sinceRelaunch.filter(\.replacePendingEvents)
        XCTAssertFalse(replacing.isEmpty)
        for batch in replacing {
            let carried = batch.events.first { $0.raw == raw }
            XCTAssertEqual(carried?.dose?.isMutable, true, "carried by the relaunched driver: \(batch.events)")
            XCTAssertEqual(carried?.date, held.date)
            XCTAssertEqual(carried?.dose?.endDate, held.dose?.endDate)
        }
        XCTAssertFalse(
            sinceRelaunch.filter { !$0.replacePendingEvents }.contains { $0.events.contains { $0.raw == raw } },
            "not reported anew"
        )

        try clock.advanceBoth(seconds: startedAt.addingTimeInterval(.minutes(Double(minutes))).timeIntervalSince(clock.now), ticks: 20)
        let completed = try appendBolexCompleted(bolusId: bolusId, delivered: units, requested: units)
        try syncUntilHistoryRead(through: completed, relaunched)

        let finals = eventsSince(batchesBefore).filter { $0.raw == raw && $0.dose?.isMutable == false }
        XCTAssertEqual(finals.count, 1, "\(finals)")
        assertFinalized(try XCTUnwrap(finals.first), delivered: units)
        assertNothingLiveDropped()
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertNotNil(loop.assertPermanent(raw: raw))
        XCTAssertEqual(trio.boluses.count, 1, "\(trio.boluses)")
        try timeline().assertMatches(loop)
    }

    // MARK: - J5

    /// Deleting the pump manager while the extended part runs: the one replacing batch before
    /// `pumpManagerWillDeactivate` finalizes it at the deletion, at its share of the programmed
    /// amount, and reports the rest, which the pump goes on delivering, as a finalized dose of its own
    /// to the programmed end. Loop stores the first at once and the rest once it has ended; neither
    /// host holds anything mutable.
    func testJ5DeletingThePumpManagerSplitsAHeldExtendedPartAtTheDeletion() throws {
        let driver = try startPairedDriverReportingHistory()
        let units = 4.0
        let minutes = 120
        let (startedAt, held) = try startFullyExtendedBolus(bolusId: 7105, units: units, minutes: minutes, driver)
        let programmedEnd = startedAt.addingTimeInterval(.minutes(Double(minutes)))

        try clock.advanceBoth(seconds: .minutes(10), ticks: 10)
        let deactivatedAt = clock.now
        let batchesBeforeDeactivation = allPumpEventBatches.count
        try deactivateDriver()
        driver.drainDelegate()

        let journal = driver.delegate.journal
        let willDeactivate = try XCTUnwrap(journal.first { if case .willDeactivate = $0.kind { true } else { false } }?.index)
        let lastBatch = try XCTUnwrap(journal.last { $0.pumpEventBatch != nil }?.index)
        XCTAssertLessThan(lastBatch, willDeactivate, "the final batch reaches the host while it still has the pump manager")
        let finalBatches = Array(allPumpEventBatches.dropFirst(batchesBeforeDeactivation))
        XCTAssertEqual(finalBatches.count, 1, "\(finalBatches)")
        let finalBatch = try XCTUnwrap(finalBatches.first)
        XCTAssertTrue(finalBatch.replacePendingEvents)

        let ranSoFar = try XCTUnwrap(finalBatch.events.first { $0.raw == held.raw })
        let share = units * deactivatedAt.timeIntervalSince(held.dose?.startDate ?? startedAt) / programmedEnd.timeIntervalSince(held.dose?.startDate ?? startedAt)
        assertFinalized(ranSoFar, delivered: TandemPumpCapabilities.roundToReportingResolution(share))
        XCTAssertEqual(ranSoFar.dose?.endDate.timeIntervalSince(deactivatedAt) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(ranSoFar.date, held.date)
        let remainderEvent = try XCTUnwrap(finalBatch.events.first { $0.dose?.type == .bolus && $0.raw != held.raw }, "\(finalBatch.events)")
        let remainder = try XCTUnwrap(remainderEvent.dose)
        XCTAssertFalse(remainder.isMutable)
        XCTAssertEqual(remainder.startDate, ranSoFar.dose?.endDate)
        XCTAssertEqual(remainder.endDate.timeIntervalSince(programmedEnd), 0, accuracy: 2, "the pump runs it to its programmed end")
        XCTAssertEqual((ranSoFar.dose?.deliveredUnits ?? 0) + (remainder.deliveredUnits ?? 0), units, accuracy: 0.0005)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertTrue(loop.mutableDoses.isEmpty, "\(loop.mutableDoses.map(LoopDoseStoreOracle.describe))")
        XCTAssertNotNil(loop.assertPermanent(raw: held.raw))
        let counted = loop.normalizedDoses().filter { $0.type == .bolus }.compactMap(\.syncIdentifier)
        XCTAssertEqual(counted.sorted(), [held.raw.hexadecimalString, remainderEvent.raw.hexadecimalString].sorted(), "each once")
        XCTAssertEqual(trio.boluses.map(\.isMutable), [false, false])

        let next = programmedEnd.addingTimeInterval(.minutes(1))
        let nextManagersReport = NewPumpEvent.basal(
            dose: UnfinalizedDose(basalRate: 1.0, insulinType: .novolog, startDate: next).toDoseEntry(),
            date: next
        )
        loop.addPumpEvents([nextManagersReport], lastReconciliation: next, replacePendingEvents: true, now: next)
        XCTAssertNotNil(loop.assertPermanent(raw: remainderEvent.raw), "Loop stores the rest once it has ended")
    }

    // MARK: - J6

    /// A BolexCompleted the driver never reads (here never logged): the part stays held through its
    /// programmed end and `extendedPartFinalizationWindow` after it, then the next replacing batch
    /// finalizes it at its programmed amount, ending at its programmed end.
    func testJ6AnExtendedPartWhoseCompletionIsNeverReadIsFinalizedAtItsProgrammedAmount() throws {
        let driver = try startPairedDriverReportingHistory()
        let batchesBefore = allPumpEventBatches.count
        let units = 2.0
        let minutes = 30
        let (startedAt, held) = try startFullyExtendedBolus(bolusId: 7106, units: units, minutes: minutes, driver)
        let programmedEnd = startedAt.addingTimeInterval(.minutes(Double(minutes)))
        let window = TandemPumpManager.extendedPartFinalizationWindow

        try clock.advanceBoth(seconds: programmedEnd.addingTimeInterval(window - .minutes(5)).timeIntervalSince(clock.now), ticks: 30)
        _ = try sync()
        XCTAssertTrue(
            eventsSince(batchesBefore).filter { $0.raw == held.raw }.allSatisfy { $0.dose?.isMutable == true },
            "held while history may still show its end"
        )

        try clock.advanceBoth(seconds: .minutes(10), ticks: 5)
        _ = try sync()

        let finals = eventsSince(batchesBefore).filter { $0.raw == held.raw && $0.dose?.isMutable == false }
        XCTAssertEqual(finals.count, 1, "\(finals)")
        let final = try XCTUnwrap(finals.first)
        assertFinalized(final, delivered: units)
        XCTAssertEqual(final.dose?.endDate.timeIntervalSince(programmedEnd) ?? .infinity, 0, accuracy: 2)
        XCTAssertTrue(
            try XCTUnwrap(allPumpEventBatches.dropFirst(batchesBefore).first { $0.events.contains { $0.raw == held.raw && $0.dose?.isMutable == false } }).replacePendingEvents,
            "finalized in a replacing batch"
        )
        assertNothingLiveDropped()
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        XCTAssertNotNil(loop.assertPermanent(raw: held.raw))
        XCTAssertEqual(trio.boluses.map(\.isMutable), [false])
    }

    // MARK: - J7

    /// Standard boluses around an extended one are reported as without it: an app bolus live and
    /// never again from history, a quick bolus on the pump once from history. An app bolus given
    /// after the extended part ends on the pump, but before history has read its end, rides the
    /// batch that finalizes the extended part, and every replacing batch carries both while held.
    func testJ7StandardBolusesAroundAnExtendedOneAreReportedAsWithoutIt() throws {
        let driver = try startPairedDriverReportingHistory()
        let batchesBefore = allPumpEventBatches.count

        XCTAssertNil(try enactBolus(units: 1.0))
        let firstAppBolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let firstAppRaw = try XCTUnwrap(eventsSince(batchesBefore).first { $0.dose?.type == .bolus }?.raw)
        _ = try advanceUntilBolusFinishes(bolusId: firstAppBolusId)
        assertFinalized(try syncUntilFinalized(raw: firstAppRaw), delivered: 1.0)

        try harness.client.startBolus(units: 0.5, source: "pump")
        let pumpBolusId = try harness.client.snapshot().bolus.bolusId
        _ = try advanceUntilBolusFinishes(bolusId: pumpBolusId)
        let pumpRaw = try upFrontPartRaw(bolusId: pumpBolusId, driver)
        try clock.advanceBoth(seconds: 30, ticks: 3)
        _ = try sync()
        let pumpBolus = try IntegrationWait.value("the pump's quick bolus reported from its history", timeout: 120) {
            self.eventsSince(batchesBefore).first { $0.raw == pumpRaw }
        }
        assertFinalized(pumpBolus, delivered: 0.5)
        XCTAssertEqual(pumpBolus.dose?.wasProgrammedByPumpUI, true)

        let extendedBolusId = 7107
        let (startedAt, held) = try startFullyExtendedBolus(bolusId: extendedBolusId, units: 2.0, minutes: 30, driver)
        try clock.advanceBoth(seconds: startedAt.addingTimeInterval(.minutes(30)).timeIntervalSince(clock.now), ticks: 15)
        let completed = try appendBolexCompleted(bolusId: extendedBolusId, delivered: 2.0, requested: 2.0)

        // Slow enough that the second app bolus still runs when history reads the extended part's end.
        try harness.client.setState(["bolus_rate_units_per_second": 0.002])
        let beforeSecondBolus = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: 0.5))
        let secondAppBolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        let secondAppRaw = try XCTUnwrap(eventsSince(beforeSecondBolus).first { $0.dose?.type == .bolus && $0.raw != held.raw }?.raw)
        try syncUntilHistoryRead(through: completed, driver)

        let finalizing = try XCTUnwrap(allPumpEventBatches.dropFirst(beforeSecondBolus).first { batch in
            batch.events.contains { $0.raw == held.raw && $0.dose?.isMutable == false }
        })
        XCTAssertTrue(finalizing.replacePendingEvents)
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the second app bolus still runs")
        XCTAssertEqual(
            finalizing.events.first { $0.raw == secondAppRaw }?.dose?.isMutable,
            true,
            "the batch that finalizes the extended part carries the running app bolus"
        )

        _ = try advanceUntilBolusFinishes(bolusId: secondAppBolusId)
        assertFinalized(try syncUntilFinalized(raw: secondAppRaw), delivered: 0.5)
        _ = try sync()

        let events = eventsSince(batchesBefore)
        for raw in [firstAppRaw, pumpRaw, held.raw, secondAppRaw] {
            XCTAssertEqual(events.filter { $0.raw == raw && $0.dose?.isMutable == false }.count, 1, "finalized once: \(LoopDoseStoreOracle.describe(raw))")
        }
        for (appBolusId, appRaw) in [(firstAppBolusId, firstAppRaw), (secondAppBolusId, secondAppRaw)] {
            XCTAssertEqual(try upFrontPartRaw(bolusId: appBolusId, driver), appRaw, "an app bolus is keyed as history keys it")
        }
        assertNothingLiveDropped()

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates()
        trio.assertNoDuplicates()
        for raw in [firstAppRaw, pumpRaw, held.raw, secondAppRaw] {
            XCTAssertNotNil(loop.assertPermanent(raw: raw))
        }
        XCTAssertEqual(trio.boluses.count, 4, "\(trio.boluses)")
        XCTAssertTrue(trio.boluses.allSatisfy { !$0.isMutable })
        try timeline().assertMatches(loop)
    }
}
