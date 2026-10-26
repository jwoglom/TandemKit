import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Conformance group K (`docs/conformance-test-plan.md`): the host deletes the pump manager and sets
/// the same pump up again, loading its history. Each manager is set up as TandemKitUI does it: paired
/// before the host has it, the sync setup runs, the Load Pump History step, and only then adopted.
/// Both managers' batches reach one host, and it must end up with every dose the pump gave exactly
/// once: what the first manager reported is not reported again under another identity, and what the
/// pump did while no manager was attached reaches it from the second manager's load.
///
/// faketandem runs the pump's 5-minute cycle (`basal_cycle_enabled`) throughout, so both managers
/// reconcile basal against BasalDelivery records and the app's temps carry `SetTempRateResponse`
/// records.
final class RepairConformanceTests: ConformanceTestCase {
    private static let profileRate = 1.0
    private static let defaultDeliveryRate = 0.05
    /// The app's schedule, which `stagePump()` gives the pump as its profile.
    private var scheduleItems = [RepeatingScheduleValue(startTime: 0, value: profileRate)]

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        if let harness {
            do {
                try harness.client.setState(["basal_cycle_enabled": false])
                try harness.client.setState(["basal_rate": Self.profileRate, "bolus_rate_units_per_second": Self.defaultDeliveryRate])
                if try harness.client.snapshot().basal.suspended {
                    try harness.client.resume(clearAlarms: true)
                }
            } catch {
                XCTFail("restoring the pump failed: \(error)")
            }
        }
        try super.tearDownWithError()
    }

    // MARK: - Staging

    /// An empty log, the app's schedule as the pump's profile, and the pump's cycle running from now.
    private func stagePump() throws {
        try eraseHistory()
        try harness.client.setIDPProfiles([FaketandemIDPProfile(id: 1, segments: scheduleItems.map {
            .init(startTime: Int($0.startTime.minutes), basalRate: Int(($0.value * 1000).rounded()))
        })])
        try harness.client.setState(["basal_rate": scheduledRate(at: clock.now)])
        try harness.client.setState(["basal_cycle_enabled": true])
    }

    private func schedule() throws -> BasalRateSchedule {
        try XCTUnwrap(BasalRateSchedule(dailyItems: scheduleItems, timeZone: .current))
    }

    private func scheduledRate(at date: Date) -> Double {
        let offset = date.timeIntervalSince(Calendar.current.startOfDay(for: date))
        return scheduleItems.last { $0.startTime <= offset }?.value ?? Self.profileRate
    }

    /// Setup as TandemKitUI runs it, with Load chosen at the Load Pump History step.
    @discardableResult
    private func setUpPump(loadingHistory: Bool = true) throws -> FaketandemHarness.Driver {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.featureFlags[.basalHistoryReporting] = true
        // The default stamps the wall clock, hours behind the scenario's.
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        state.reportedBasal = ReportedBasalLedger(trackingSince: clock.now)
        state.insulinType = .novolog
        state.basalRateSchedule = try schedule()
        let driver = startDriver(state: state, attachDelegate: false)
        try harness.pair(driver)
        // `TandemKitScanViewModel.finishSetup`, which reads the serial the load keys its reports on.
        _ = try sync()
        if loadingHistory {
            XCTAssertNil(try loadHistoryForSetup(), "the pump's history loads")
        }
        driver.adoptByHost()
        return driver
    }

    private func advance(by seconds: TimeInterval) throws {
        try clock.advanceBoth(seconds: seconds, ticks: max(1, Int(seconds / 60)))
    }

    /// To `offset` past the pump's next BasalDelivery record, so a change lands mid-cycle.
    private func advance(pastTheNextCycleBy offset: TimeInterval) throws {
        let next = try XCTUnwrap(harness.client.snapshot().basalCycle?.nextCycle?.date, "the pump's cycle runs")
        try advance(by: next.addingTimeInterval(offset).timeIntervalSince(clock.now))
    }

    /// A bolus on the pump's screen, run to its end; returns its id.
    @discardableResult
    private func pumpBolus(units: Double) throws -> Int {
        let bolusId = try harness.client.startBolus(units: units, source: "pump").bolus.bolusId
        try advanceUntilBolusFinishes(bolusId: bolusId)
        return bolusId
    }

    private func appBolus(units: Double) throws -> (bolusId: Int, raw: Data) {
        let before = allPumpEventBatches.count
        XCTAssertNil(try enactBolus(units: units))
        let bolusId = try XCTUnwrap(current?.manager.state.bolusDose?.bolusId)
        let raw = try XCTUnwrap(eventsSince(before).first { $0.dose?.type == .bolus }?.raw, "the app's bolus is reported")
        return (bolusId, raw)
    }

    private func appTemp(unitsPerHour: Double, minutes: Double) throws -> Data {
        let before = allPumpEventBatches.count
        XCTAssertNil(try enactTempBasal(unitsPerHour: unitsPerHour, duration: .minutes(minutes)))
        return try XCTUnwrap(
            eventsSince(before).first { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }?.raw,
            "the app's temp basal is reported"
        )
    }

    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        allPumpEventBatches.dropFirst(count).flatMap(\.events)
    }

    private func lastSequence() throws -> Int {
        try harness.client.snapshot().history.lastSequence
    }

    private func lastCycle() throws -> Int {
        try XCTUnwrap(try harness.client.history(since: historyStartSequence).last { $0.type == "BasalDelivery" }, "no BasalDelivery record yet").sequence
    }

    private func waitForBackfill(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 180) throws {
        let last = try lastSequence()
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy
        }
    }

    private func waitForReconciliation(_ driver: FaketandemHarness.Driver, through sequence: Int, timeout: TimeInterval = 120) throws {
        try IntegrationWait.until("the driver to reconcile the pump's basal through record \(sequence)", timeout: timeout) {
            driver.manager.state.reportedBasal.reconciledThrough.map { Int($0) >= sequence } == true
        }
        // The pass moves reconciledThrough before it reports, in the same command job.
        let jobsDone = ResultBox<Void>()
        driver.bluetooth.ensureConnected { _ in jobsDone.set(()) }
        try jobsDone.wait("the reconciliation's command job to finish", timeout: timeout)
    }

    /// Closes the cycle under way and has `driver` read and reconcile the pump's history through it.
    private func settle(_ driver: FaketandemHarness.Driver) throws {
        try advance(pastTheNextCycleBy: .minutes(1))
        let lastClosed = try lastCycle()
        try advance(pastTheNextCycleBy: .minutes(1))
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)
        _ = try sync()
    }

    private static func isKeyedOnARecord(_ raw: Data?) -> Bool {
        raw.flatMap(HistoryLogSyncIdentifier.decode)?.scheme == .logSequence
    }

    /// Both hosts count what each closed BasalDelivery record delivered, except the cycles a change
    /// the app commanded falls in: the host counts it from the command, the pump from its next record.
    private func assertHostsCountThePumpsBasal(
        loop: LoopDoseStoreOracle?,
        trio: TrioDoseStoreOracle?,
        exceptCyclesHolding commands: [Date],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let scheduled: (Date) -> Double = { self.scheduledRate(at: $0) }
        let cycles = try timeline().basalCycles.filter { cycle in
            cycle.end <= clock.now && !commands.contains { cycle.start <= $0 && $0 < cycle.end }
        }
        XCTAssertFalse(cycles.isEmpty, file: file, line: line)
        for cycle in cycles {
            let pump = cycle.rate * cycle.end.timeIntervalSince(cycle.start) / .hours(1)
                - TrioDoseStoreOracle.integrate(from: cycle.start, to: cycle.end, scheduled)
            let span = "cycle \(cycle.sequence) from \(cycle.start) at \(cycle.rate) U/hr"
            if let loop {
                XCTAssertEqual(loop.netBasalUnits(from: cycle.start, to: cycle.end, scheduledRate: scheduled), pump, accuracy: 0.002, "Loop counts \(span)", file: file, line: line)
            }
            if let trio {
                XCTAssertEqual(try trio.netBasalUnits(from: cycle.start, to: cycle.end, clock: clock.now, scheduledRate: scheduled), pump, accuracy: 0.002, "Trio counts \(span)", file: file, line: line)
            }
        }
    }

    // MARK: - K1

    /// The whole journey. Before any manager the pump gives a bolus and stops for 10 minutes; the
    /// first manager loads them. With it the app gives a bolus, a temp it cancels, a suspend and
    /// resume, and the pump a bolus and a temp from its screen. The app's next temp and a slow bolus
    /// still run when the host deletes the manager. With no manager the pump finishes both, gives a
    /// bolus, stops and starts again and runs a temp from its screen. The second manager pairs and
    /// loads six hours of history: the host keeps every row it holds, gains the interim's, and no
    /// cycle of the app's temps is corrected.
    func testK1_aPumpSetUpAgainLeavesTheHostEveryDoseOnce() throws {
        try stagePump()
        try advance(pastTheNextCycleBy: .minutes(1))
        let beforeSetup = try pumpBolus(units: 0.5)
        try advance(pastTheNextCycleBy: .minutes(1))
        try harness.client.suspend(reason: "user")
        try advance(by: .minutes(10))
        try harness.client.resume()
        try advance(pastTheNextCycleBy: .minutes(1))

        let first = try setUpPump()
        let serial = try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(first.manager.state.pumpState.pumpSerial))
        try advance(pastTheNextCycleBy: .minutes(1))
        let appsBolus = try appBolus(units: 1.0)
        XCTAssertEqual(appsBolus.raw, HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: appsBolus.bolusId), "keyed on the pump's bolus id")
        try advanceUntilBolusFinishes(bolusId: appsBolus.bolusId)
        _ = try syncUntilFinalized(raw: appsBolus.raw)

        try advance(pastTheNextCycleBy: .minutes(1))
        let tempA = try appTemp(unitsPerHour: 1.5, minutes: 30)
        let tempAStart = clock.now
        try advance(by: .minutes(10))
        let tempACancel = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: 0), "cancel")

        try advance(pastTheNextCycleBy: .minutes(1))
        XCTAssertNil(try suspendDelivery())
        try advance(by: .minutes(10))
        XCTAssertNil(try resumeDelivery())

        try advance(pastTheNextCycleBy: .minutes(1))
        let duringFirst = try pumpBolus(units: 0.8)
        _ = try syncUntilFinalized(raw: HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: duringFirst))
        try advance(pastTheNextCycleBy: .minutes(1))
        try harness.client.startTempBasal(percent: 175, durationMinutes: 15)
        try advance(by: .minutes(15))
        try settle(first)
        let correctedByTheFirst = first.delegate.pumpEvents.filter { $0.dose?.type == .tempBasal && Self.isKeyedOnARecord($0.raw) }
        XCTAssertEqual(correctedByTheFirst.map(\.dose?.unitsPerHour), [1.75, 1.75, 1.75], "the pump's temp, a correction per cycle")

        try advance(pastTheNextCycleBy: .minutes(1))
        let tempB = try appTemp(unitsPerHour: 2.0, minutes: 60)
        let tempBStart = clock.now
        try advance(by: .minutes(2))
        try harness.client.setState(["bolus_rate_units_per_second": 0.005])
        let runningBolus = try appBolus(units: 1.0)
        // Whole minutes into the temp: Trio keeps a temp's duration in whole minutes.
        try advance(by: .minutes(1))
        XCTAssertTrue(try harness.client.snapshot().bolus.active, "the bolus still runs")
        let deletedAt = clock.now
        try deactivateDriver()
        let firstsBatches = first.delegate.pumpEventBatches
        let remainder = try XCTUnwrap(
            firstsBatches.last?.events.first { $0.dose?.type == .tempBasal && $0.raw != tempB },
            "the deletion reports what remains of the temp"
        )

        try advanceUntilBolusFinishes(bolusId: runningBolus.bolusId)
        try harness.client.setState(["bolus_rate_units_per_second": Self.defaultDeliveryRate])
        try advance(pastTheNextCycleBy: .minutes(1))
        let interimBolus = try pumpBolus(units: 1.2)
        try advance(by: tempBStart.addingTimeInterval(.minutes(60)).timeIntervalSince(clock.now))
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the pump ran the app's temp to its end")
        try advance(pastTheNextCycleBy: .minutes(1))
        try harness.client.suspend(reason: "user")
        try advance(by: .minutes(10))
        try harness.client.resume()
        try advance(pastTheNextCycleBy: .minutes(1))
        try harness.client.startTempBasal(percent: 50, durationMinutes: 30)
        try advance(by: .minutes(30))
        try advance(pastTheNextCycleBy: .minutes(1))

        let second = try setUpPump()
        try settle(second)

        let timeline = try timeline()
        let (loop, trio) = feedOracles()
        assertHostsHoldEachDoseOnce(loop: loop, trio: trio)

        let firstsRaws = Set(first.delegate.pumpEvents.map(\.raw))
        let secondsEvents = second.delegate.pumpEvents.filter { $0.dose != nil }
        for event in secondsEvents where event.date < deletedAt {
            XCTAssertTrue(firstsRaws.contains(event.raw), "reported again under another identity: \(event)")
        }
        let secondsRaws = Set(secondsEvents.map(\.raw))
        let bolusRaws = [beforeSetup, appsBolus.bolusId, duringFirst, runningBolus.bolusId].map {
            HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: $0)
        }
        XCTAssertTrue(secondsRaws.isSuperset(of: bolusRaws + [tempA, tempB] + correctedByTheFirst.map(\.raw)), "the load reports what the host already holds")
        for row in trio.events where row.timestamp <= deletedAt {
            XCTAssertLessThan(row.createdInCall, firstsBatches.count, "Trio row created from the second manager's report: \(row)")
        }

        let pumpBoluses = timeline.boluses
        XCTAssertEqual(
            pumpBoluses.map(\.bolusId).sorted(),
            [beforeSetup, appsBolus.bolusId, duringFirst, runningBolus.bolusId, interimBolus].sorted()
        )
        for bolus in pumpBoluses {
            let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: bolus.bolusId)
            let stored = loop.assertPermanent(raw: raw, "bolus \(bolus.bolusId)")
            XCTAssertEqual(stored?.dose.deliveredUnits ?? -1, try XCTUnwrap(bolus.deliveredUnits), accuracy: 0.0005, "bolus \(bolus.bolusId)")
            XCTAssertNotNil(trio.event(syncIdentifier: raw.hexadecimalString), "Trio holds bolus \(bolus.bolusId)")
        }
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.count, pumpBoluses.count, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(trio.boluses.count, pumpBoluses.count, "\(trio.boluses)")
        let delivered = pumpBoluses.compactMap(\.deliveredUnits).reduce(0, +)
        XCTAssertEqual(loop.doses.filter { $0.dose.type == .bolus }.map(\.value).reduce(0, +), delivered, accuracy: 0.001)
        XCTAssertEqual(trio.boluses.compactMap(\.bolusAmount).reduce(0, +).doubleValue, delivered, accuracy: 0.001)
        let interim = try XCTUnwrap(secondsEvents.first { $0.raw == HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: interimBolus) })
        XCTAssertEqual(interim.dose?.wasProgrammedByPumpUI, true)

        XCTAssertEqual(timeline.suspends.count, 3, "\(timeline.suspends)")
        let suspends = loop.doses.filter { $0.dose.type == .suspend }
        XCTAssertEqual(suspends.count, timeline.suspends.count, "\(suspends.map(LoopDoseStoreOracle.describe))")
        for suspend in timeline.suspends {
            let stored = suspends.first { abs($0.dose.startDate.timeIntervalSince(suspend.start)) <= 2 }
            XCTAssertNotNil(stored, "Loop holds the suspend at \(suspend.start)")
            XCTAssertEqual(stored?.dose.endDate.timeIntervalSince(try XCTUnwrap(suspend.resumed)) ?? .infinity, 0, accuracy: 2)
        }
        XCTAssertEqual(trio.suspends.count, 3, "\(trio.suspends)")
        XCTAssertEqual(trio.resumes.count, 3, "\(trio.resumes)")
        for row in trio.suspends + trio.resumes {
            XCTAssertTrue(Self.isKeyedOnARecord(row.syncIdentifier.flatMap { Data(hexadecimalString: $0) }), "keyed on its record: \(row)")
        }

        let offSchedule = timeline.basalCycles.filter { cycle in
            cycle.end <= clock.now && [1.75, 0.5].contains { abs(cycle.rate - $0) < 0.001 }
        }
        XCTAssertEqual(offSchedule.count, 9, "the pump's two temps ran 3 and 6 cycles: \(timeline.basalCycles)")
        let corrections = loop.doses.filter { $0.dose.type == .tempBasal && Self.isKeyedOnARecord($0.raw) }
        XCTAssertEqual(
            Set(corrections.compactMap(\.raw)),
            Set(offSchedule.map { HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: UInt32($0.sequence)) }),
            "one correction per cycle of the pump's temps: \(corrections.map(LoopDoseStoreOracle.describe))"
        )
        for manager in [first.manager, second.manager] {
            XCTAssertTrue(
                manager.loggedBasalDifferences.isSubset(of: offSchedule.map { UInt32($0.sequence) }),
                "a cycle of the app's temps differed: \(manager.loggedBasalDifferences.sorted())"
            )
        }
        let appTemps = loop.doses.filter { $0.dose.type == .tempBasal && !Self.isKeyedOnARecord($0.raw) }
        XCTAssertEqual(Set(appTemps.compactMap(\.raw)), [tempA, tempB, remainder.raw], "\(appTemps.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(tempA, HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: try XCTUnwrap(timeline.tempRates.first?.tempRateId)))
        let storedA = loop.assertPermanent(raw: tempA)
        XCTAssertEqual(storedA?.dose.startDate.timeIntervalSince(tempAStart) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(storedA?.dose.endDate.timeIntervalSince(tempACancel) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(loop.assertPermanent(raw: tempB)?.dose.endDate.timeIntervalSince(deletedAt) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(loop.assertPermanent(raw: remainder.raw)?.dose.endDate.timeIntervalSince(tempBStart.addingTimeInterval(.minutes(60))) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(trio.tempBasals.count, appTemps.count + corrections.count, "\(trio.tempBasals)")

        try assertHostsCountThePumpsBasal(
            loop: loop,
            trio: trio,
            exceptCyclesHolding: [tempAStart, tempACancel, tempBStart, tempBStart.addingTimeInterval(.minutes(60))]
        )
    }

    /// Nothing duplicated or left live in either host, nothing live dropped by a replacing batch, and
    /// Trio's IOB runs.
    private func assertHostsHoldEachDoseOnce(loop: LoopDoseStoreOracle?, trio: TrioDoseStoreOracle?, file: StaticString = #filePath, line: UInt = #line) {
        if let loop {
            loop.assertNoDuplicates("set up again", file: file, line: line)
            let omissions = completeBatchOmissions()
            XCTAssertTrue(omissions.isEmpty, "nothing live dropped by silence:\n" + omissions.joined(separator: "\n"), file: file, line: line)
            XCTAssertTrue(loop.mutableDoses.isEmpty, "\(loop.mutableDoses.map(LoopDoseStoreOracle.describe))", file: file, line: line)
        }
        if let trio {
            trio.assertNoDuplicates("set up again", file: file, line: line)
            trio.assertNoSameSecondBasalRows(file: file, line: line)
            XCTAssertNoThrow(try trio.basalSegments(clock: clock.now), "Trio's IOB runs", file: file, line: line)
            XCTAssertTrue(trio.events.allSatisfy { !$0.isMutable }, "\(trio.events.filter(\.isMutable))", file: file, line: line)
        }
    }

    /// A strict expected failure: the assertions inside must fail today, and a fix turns the block
    /// into an unexpected pass so the wrapper is removed with it.
    private func expectDefect<R>(_ reason: String, _ body: () throws -> R) rethrows -> R {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        return try XCTExpectFailure(reason, options: options, failingBlock: body)
    }

    // MARK: - K2

    /// The host deletes the manager while the app's temp runs and sets the pump up again before it
    /// ends, and the new manager's first temp replaces it on the pump. The host keeps the deleted
    /// manager's two rows for it, the second cut where the new temp starts, and no cycle is corrected.
    func testK2_aTempRunningAcrossTheDeletionIsCountedOnceUntilTheNextManagersTemp() throws {
        try stagePump()
        let first = try setUpPump()
        try advance(pastTheNextCycleBy: .minutes(1))
        let tempB = try appTemp(unitsPerHour: 2.0, minutes: 60)
        let tempBStart = clock.now
        try advance(by: .minutes(12))
        let deletedAt = clock.now
        try deactivateDriver()
        let remainder = try XCTUnwrap(first.delegate.pumpEventBatches.last?.events.first { $0.dose?.type == .tempBasal && $0.raw != tempB })
        try advance(by: .minutes(3))

        let second = try setUpPump()
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive, "the app's temp still runs")
        try advance(pastTheNextCycleBy: .minutes(1))
        let tempC = try appTemp(unitsPerHour: 0.5, minutes: 30)
        let tempCStart = clock.now
        try advance(by: .minutes(15))
        let tempCCancel = clock.now
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: 0), "cancel")
        try settle(second)

        let (loop, trio) = feedOracles()
        assertHostsHoldEachDoseOnce(loop: loop, trio: trio)
        let secondsTemps = second.delegate.pumpEvents.filter { $0.dose?.type == .tempBasal }
        XCTAssertEqual(Set(secondsTemps.map(\.raw)), [tempB, tempC], "the load reports the app's temp under its identity, and nothing is corrected: \(secondsTemps)")
        XCTAssertTrue(first.manager.loggedBasalDifferences.isEmpty, "\(first.manager.loggedBasalDifferences.sorted())")
        XCTAssertTrue(second.manager.loggedBasalDifferences.isEmpty, "\(second.manager.loggedBasalDifferences.sorted())")

        let temps = loop.doses.filter { $0.dose.type == .tempBasal }.sorted { $0.dose.startDate < $1.dose.startDate }
        XCTAssertEqual(temps.compactMap(\.raw), [tempB, remainder.raw, tempC], "\(temps.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(temps.first?.dose.endDate.timeIntervalSince(deletedAt) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(temps.dropFirst().first?.dose.endDate.timeIntervalSince(tempCStart) ?? .infinity, 0, accuracy: 1, "Loop cuts the remainder at the next temp")
        XCTAssertEqual(trio.tempBasals.compactMap(\.syncIdentifier), [tempB, remainder.raw, tempC].map(\.hexadecimalString), "\(trio.tempBasals)")
        try assertHostsCountThePumpsBasal(loop: loop, trio: trio, exceptCyclesHolding: [tempBStart, tempCStart, tempCCancel])
    }

    // MARK: - K3

    /// A profile segment change falls in what remains of the app's temp after the deletion. The
    /// deleted manager cut the remainder at the change into the temp's first part, as the pump rescales
    /// it there, and the next manager's load reports the temp and that part under the same identities.
    func testK3_aSegmentChangeInTheRemainderIsCountedOnceAtThePumpsRates() throws {
        let calendar = Calendar.current
        var start = try XCTUnwrap(calendar.nextDate(after: clock.now, matching: DateComponents(second: 0), matchingPolicy: .nextTime))
        // Clear of midnight, where the schedule changes again.
        if calendar.component(.hour, from: start) >= 22 {
            start = try XCTUnwrap(calendar.nextDate(after: start, matching: DateComponents(hour: 0, minute: 10), matchingPolicy: .nextTime))
        }
        try clock.start(at: start)
        let change = start.addingTimeInterval(.minutes(37))
        scheduleItems = [
            RepeatingScheduleValue(startTime: 0, value: Self.profileRate),
            RepeatingScheduleValue(startTime: change.timeIntervalSince(calendar.startOfDay(for: change)), value: 0.8),
        ]
        try stagePump()
        let first = try setUpPump()
        let serial = try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(first.manager.state.pumpState.pumpSerial))
        try advance(pastTheNextCycleBy: .minutes(1))
        let tempB = try appTemp(unitsPerHour: 2.0, minutes: 60)
        let tempBStart = clock.now
        let tempRateId = try XCTUnwrap(harness.client.snapshot().basal.tempRateId)
        try advance(by: .minutes(14))
        XCTAssertLessThan(clock.now, change)
        try deactivateDriver()
        let deletion = try XCTUnwrap(first.delegate.pumpEventBatches.last?.events.filter { $0.dose?.type == .tempBasal })
        let firstPart = HistoryLogSyncIdentifier.tempRatePart(pumpSerial: serial, tempRateId: tempRateId, part: 1)
        XCTAssertEqual(deletion.count, 3, "the temp to the deletion, the remainder to the change and the temp's first part: \(deletion)")
        XCTAssertTrue(deletion.contains { $0.raw == firstPart }, "\(deletion)")

        let tempBEnd = tempBStart.addingTimeInterval(.minutes(60))
        try advance(by: tempBEnd.timeIntervalSince(clock.now))
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive)
        try advance(pastTheNextCycleBy: .minutes(1))
        let second = try setUpPump()
        try settle(second)

        let (loop, trio) = feedOracles()
        assertHostsHoldEachDoseOnce(loop: loop, trio: nil)
        let secondsTemps = second.delegate.pumpEvents.filter { $0.dose?.type == .tempBasal }
        XCTAssertEqual(Set(secondsTemps.map(\.raw)), [tempB, firstPart], "\(secondsTemps)")
        XCTAssertTrue(first.manager.loggedBasalDifferences.isEmpty, "\(first.manager.loggedBasalDifferences.sorted())")
        XCTAssertTrue(second.manager.loggedBasalDifferences.isEmpty, "\(second.manager.loggedBasalDifferences.sorted())")
        let temps = loop.doses.filter { $0.dose.type == .tempBasal }.sorted { $0.dose.startDate < $1.dose.startDate }
        XCTAssertEqual(Set(temps.compactMap(\.raw)), Set(deletion.map(\.raw)), "\(temps.map(LoopDoseStoreOracle.describe))")
        XCTAssertEqual(temps.map(\.dose.unitsPerHour), [2.0, 2.0, 1.6], "the pump rescales the temp at the change")
        XCTAssertEqual(temps.last?.dose.startDate.timeIntervalSince(change) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(temps.last?.dose.endDate.timeIntervalSince(tempBEnd) ?? .infinity, 0, accuracy: 1)
        XCTAssertEqual(trio.tempBasals.count, 3, "\(trio.tempBasals)")
        try assertHostsCountThePumpsBasal(loop: loop, trio: nil, exceptCyclesHolding: [tempBStart, change, tempBEnd])
        try expectDefect("The deletion reports the part after the segment change starting ahead of Trio's clock; Trio stores it at its clock, in the remainder's second, and its IOB counts one of the two") {
            assertHostsHoldEachDoseOnce(loop: nil, trio: trio)
            try assertHostsCountThePumpsBasal(loop: nil, trio: trio, exceptCyclesHolding: [tempBStart, change, tempBEnd])
        }
    }

    // MARK: - K4

    /// The host deletes the manager while the app's suspend stands, and the user resumes on the pump
    /// before setting it up again. The next manager's load closes the suspend the host holds.
    func testK4a_aSuspendLeftOpenByTheDeletionIsClosedByTheResumeTheLoadReports() throws {
        try stagePump()
        let first = try setUpPump()
        try advance(pastTheNextCycleBy: .minutes(1))
        let suspendedAt = clock.now
        XCTAssertNil(try suspendDelivery())
        try advance(by: .minutes(5))
        try deactivateDriver()
        try advance(by: .minutes(10))
        let resumedAt = clock.now
        try harness.client.resume()
        try advance(pastTheNextCycleBy: .minutes(1))
        let second = try setUpPump()
        try settle(second)

        try assertOneSuspend(from: suspendedAt, to: resumedAt, first: first, second: second)
    }

    /// As K4a, but the pump is still stopped when the next manager is set up, and that manager resumes it.
    func testK4b_aSuspendLeftOpenByTheDeletionIsClosedByTheNextManagersResume() throws {
        try stagePump()
        let first = try setUpPump()
        try advance(pastTheNextCycleBy: .minutes(1))
        let suspendedAt = clock.now
        XCTAssertNil(try suspendDelivery())
        try advance(by: .minutes(5))
        try deactivateDriver()
        try advance(by: .minutes(5))
        let second = try setUpPump()
        XCTAssertTrue(try harness.client.snapshot().basal.suspended)
        try advance(by: .minutes(2))
        let resumedAt = clock.now
        XCTAssertNil(try resumeDelivery())
        try settle(second)

        try assertOneSuspend(from: suspendedAt, to: resumedAt, first: first, second: second)
    }

    // MARK: - K5

    /// The user chooses Do Not Load when setting the pump up again, with the app's temp still running:
    /// nothing from before the pairing is reported, the pump's bolus meanwhile included, and nothing the
    /// host holds is reported again. The temp's cycles after the pairing are corrected at the pump's
    /// rate, which both hosts take in place of the remainder they hold, so each counts the pump's basal.
    func testK5_doNotLoadReportsNothingFromBeforeThePairingAndNothingTwice() throws {
        try stagePump()
        try setUpPump()
        try advance(pastTheNextCycleBy: .minutes(1))
        let tempB = try appTemp(unitsPerHour: 2.0, minutes: 60)
        let tempBStart = clock.now
        try advance(by: .minutes(10))
        try deactivateDriver()
        try advance(pastTheNextCycleBy: .minutes(1))
        try pumpBolus(units: 1.0)
        try advance(pastTheNextCycleBy: .minutes(1))
        let pairedAt = clock.now

        let second = try setUpPump(loadingHistory: false)
        let tempBEnd = tempBStart.addingTimeInterval(.minutes(60))
        try advance(by: tempBEnd.timeIntervalSince(clock.now))
        try settle(second)

        let (loop, trio) = feedOracles()
        assertHostsHoldEachDoseOnce(loop: loop, trio: trio)
        let secondsDoses = second.delegate.pumpEvents.filter { $0.dose != nil }
        XCTAssertTrue(secondsDoses.allSatisfy { $0.date >= pairedAt }, "nothing from before the pairing: \(secondsDoses)")
        XCTAssertFalse(secondsDoses.contains { $0.raw == tempB })
        XCTAssertTrue(loop.doses.filter { $0.dose.type == .bolus }.isEmpty, "\(loop.doses.map(LoopDoseStoreOracle.describe))")
        XCTAssertTrue(trio.boluses.isEmpty, "\(trio.boluses)")
        try assertHostsCountThePumpsBasal(loop: loop, trio: trio, exceptCyclesHolding: [tempBStart])
    }

    /// The host holds the first manager's suspend once, closed at the resume, both keyed on their records.
    private func assertOneSuspend(
        from suspendedAt: Date,
        to resumedAt: Date,
        first: FaketandemHarness.Driver,
        second: FaketandemHarness.Driver,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let (loop, trio) = feedOracles()
        assertHostsHoldEachDoseOnce(loop: loop, trio: trio, file: file, line: line)
        let firstsSuspends = first.delegate.pumpEvents.filter { $0.type == .suspend }
        XCTAssertEqual(firstsSuspends.count, 1, "\(firstsSuspends)", file: file, line: line)
        let suspendRaw = try XCTUnwrap(firstsSuspends.first?.raw, file: file, line: line)
        XCTAssertTrue(Self.isKeyedOnARecord(suspendRaw), file: file, line: line)
        for event in second.delegate.pumpEvents where event.type == .suspend {
            XCTAssertEqual(event.raw, suspendRaw, "the suspend reported again under another identity: \(event)", file: file, line: line)
        }
        let resumes = (first.delegate.pumpEvents + second.delegate.pumpEvents).filter { $0.type == .resume }
        XCTAssertEqual(Set(resumes.map(\.raw)).count, 1, "\(resumes)", file: file, line: line)
        XCTAssertTrue(Self.isKeyedOnARecord(resumes.first?.raw), file: file, line: line)

        let suspends = loop.doses.filter { $0.dose.type == .suspend }
        XCTAssertEqual(suspends.count, 1, "\(loop.doses.map(LoopDoseStoreOracle.describe))", file: file, line: line)
        XCTAssertEqual(suspends.first?.dose.startDate.timeIntervalSince(suspendedAt) ?? .infinity, 0, accuracy: 2, file: file, line: line)
        XCTAssertEqual(suspends.first?.dose.endDate.timeIntervalSince(resumedAt) ?? .infinity, 0, accuracy: 2, file: file, line: line)
        XCTAssertEqual(trio.suspends.count, 1, "\(trio.suspends)", file: file, line: line)
        XCTAssertEqual(trio.resumes.count, 1, "\(trio.resumes)", file: file, line: line)
        XCTAssertEqual(trio.resumes.first?.timestamp.timeIntervalSince(resumedAt) ?? .infinity, 0, accuracy: 2, file: file, line: line)
        try assertHostsCountThePumpsBasal(loop: loop, trio: trio, exceptCyclesHolding: [], file: file, line: line)
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
