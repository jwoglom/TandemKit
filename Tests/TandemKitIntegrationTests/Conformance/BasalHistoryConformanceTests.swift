import Foundation
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Conformance group H (`docs/conformance-test-plan.md`): the basal the pump delivered, read back
/// from its `BasalDelivery` (279) records and compared with what the host was told. Where the two
/// differ the driver reports a correction at the pump's rate, one per BasalDelivery record, and a
/// second pass reports nothing.
///
/// faketandem runs the pump's 5-minute cycle (`basal_cycle_enabled`) from the end of
/// `stageDriver()`, so every BasalDelivery record lands on a five-minute step from there: its rate
/// and source, the `DailyBasal` totals, the Control-IQ PCM changes and the resume rules are the
/// emulator's own.
final class BasalHistoryConformanceTests: ConformanceTestCase {
    private static let profileRate = 1.0
    private static let cycle: TimeInterval = 300

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        if let harness {
            do {
                try harness.client.setState(["basal_cycle_enabled": false])
                try harness.client.armFault(FaketandemFaultSpec(.radioOn))
                try harness.client.setState(["basal_rate": Self.profileRate])
                let snapshot = try harness.client.snapshot()
                if snapshot.basal.suspended { try harness.client.resume(clearAlarms: true) }
            } catch {
                XCTFail("restoring the pump failed: \(error)")
            }
        }
        try super.tearDownWithError()
    }

    // MARK: - Staging

    /// A paired driver with history backfill and basal reporting on, from an empty pump log, and the
    /// pump's cycle running from now: a BasalDelivery record now and every five minutes after.
    @discardableResult
    private func stageDriver(schedule: [RepeatingScheduleValue<Double>]? = nil) throws -> FaketandemHarness.Driver {
        try eraseHistory()
        let items = schedule ?? [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]
        try harness.client.setIDPProfiles([FaketandemIDPProfile(id: 1, segments: items.map {
            .init(startTime: Int($0.startTime.minutes), basalRate: Int(($0.value * 1000).rounded()))
        })])
        try harness.client.setState(["basal_rate": Self.profileRate])
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.basalHistoryReporting] = true
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        state.reportedBasal = ReportedBasalLedger(trackingSince: clock.now)
        state.insulinType = .novolog
        state.basalRateSchedule = try XCTUnwrap(BasalRateSchedule(dailyItems: items, timeZone: .current))
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        try waitForBackfill(driver)
        try harness.client.setState(["basal_cycle_enabled": true])
        return driver
    }

    /// Starts both clocks on a whole minute and returns a profile segment change 18 minutes on,
    /// which falls mid-cycle on the cadence `stageDriver()` starts. Past 23:00 the clocks start
    /// just after midnight instead, so the scenario and a pump running ahead stay in one day.
    private func startClocksBeforeASegmentChange(skewSeconds: Double = 0) throws -> Date {
        let calendar = Calendar.current
        var start = try XCTUnwrap(calendar.nextDate(after: clock.now, matching: DateComponents(second: 0), matchingPolicy: .nextTime))
        if calendar.component(.hour, from: start) == 23 {
            start = try XCTUnwrap(calendar.nextDate(after: start, matching: DateComponents(hour: 0, minute: 10), matchingPolicy: .nextTime))
        }
        try clock.start(at: start, skewSeconds: skewSeconds)
        return start.addingTimeInterval(.minutes(18))
    }

    /// The schedule, and the pump's profile, with `rate` from `change` to midnight.
    private func schedule(changingTo rate: Double, at change: Date) -> [RepeatingScheduleValue<Double>] {
        let midnight = Calendar.current.startOfDay(for: change)
        return [
            RepeatingScheduleValue(startTime: 0, value: Self.profileRate),
            RepeatingScheduleValue(startTime: change.timeIntervalSince(midnight), value: rate),
        ]
    }

    private func advance(to date: Date) throws {
        let seconds = date.timeIntervalSince(clock.now)
        try clock.advanceBoth(seconds: seconds, ticks: max(1, Int(seconds / 60)))
    }

    private func waitForBackfill(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 180) throws {
        let last = try lastSequence()
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy
        }
    }

    /// The reconciliation runs after the tick that reads a record, so a test that expects nothing
    /// reported waits for it to be done with the last closed BasalDelivery record.
    private func waitForReconciliation(_ driver: FaketandemHarness.Driver, through sequence: Int, timeout: TimeInterval = 120) throws {
        try IntegrationWait.until("the driver to reconcile the pump's basal through record \(sequence)", timeout: timeout) {
            driver.manager.state.reportedBasal.reconciledThrough.map { Int($0) >= sequence } == true
        }
        // The pass moves reconciledThrough before it reports, in the same command job; one queued behind it runs after both.
        let jobsDone = ResultBox<Void>()
        driver.bluetooth.ensureConnected { _ in jobsDone.set(()) }
        try jobsDone.wait("the reconciliation's command job to finish", timeout: timeout)
    }

    private func radioOff(_ driver: FaketandemHarness.Driver) throws {
        try harness.client.armFault(FaketandemFaultSpec(.radioOff))
        try IntegrationWait.until("the emulator to drop the link", timeout: 30) {
            try !self.harness.client.snapshot().connection.connected
        }
        try IntegrationWait.until("the driver to notice the link is gone", timeout: 30) { !driver.manager.state.isConnected }
    }

    private func radioOnAndSync() throws {
        try harness.client.armFault(FaketandemFaultSpec(.radioOn))
        _ = try sync()
    }

    private func lastSequence() throws -> Int {
        try harness.client.snapshot().history.lastSequence
    }

    /// The latest BasalDelivery record's sequence.
    private func lastCycle() throws -> Int {
        try XCTUnwrap(try harness.client.history(since: historyStartSequence).last { $0.type == "BasalDelivery" }, "no BasalDelivery record yet").sequence
    }

    /// The rate Control-IQ runs from the next BasalDelivery record, in milliunits per hour.
    private func setControlIQRate(_ rate: Int) throws {
        try harness.client.setState(["controliq_algorithm_rate": Double(rate) / 1000])
    }

    /// Control-IQ switched on at the pump for a BasalDelivery record at each of `rates`, then off,
    /// and a cycle on the profile that closes the last. Starts on a BasalDelivery record; returns
    /// the records it wrote.
    @discardableResult
    private func controlIQOnThePump(_ rates: [Int]) throws -> ClosedRange<Int> {
        XCTAssertEqual(try harness.client.snapshot().basalCycle?.nextCycle?.date, clock.now.addingTimeInterval(Self.cycle), "starts on a BasalDelivery record")
        let first = try lastSequence() + 1
        try harness.client.setState(["closed_loop_enabled": true])
        for rate in rates {
            try setControlIQRate(rate)
            try clock.advanceBoth(seconds: Self.cycle, ticks: 1)
        }
        try harness.client.setState(["closed_loop_enabled": false])
        try clock.advanceBoth(seconds: Self.cycle, ticks: 1)
        return first ... (try lastSequence())
    }

    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        Array(allPumpEventBatches.dropFirst(count)).flatMap(\.events)
    }

    private func corrections(since count: Int) -> [NewPumpEvent] {
        eventsSince(count).filter(Self.isCorrection)
    }

    /// A suspend or resume is keyed on its record too.
    private static func isCorrection(_ event: NewPumpEvent) -> Bool {
        event.dose?.type == .tempBasal && HistoryLogSyncIdentifier.decode(event.raw)?.scheme == .logSequence
    }

    private func waitForCorrections(_ count: Int, since batches: Int, timeout: TimeInterval = 120) throws -> [NewPumpEvent] {
        try IntegrationWait.value("\(count) basal correction(s)", timeout: timeout) {
            let found = self.corrections(since: batches)
            return found.count >= count ? found : nil
        }
    }

    /// The closed BasalDelivery records in `sequences` that delivered off the schedule.
    private func cyclesOffTheSchedule(in sequences: ClosedRange<Int>) throws -> [PumpTimeline.BasalCycle] {
        try timeline().basalCycles.filter {
            sequences.contains($0.sequence) && $0.end <= clock.now && $0.source != 0 && abs($0.rate - Self.profileRate) > 0.01
        }
    }

    /// One correction per closed BasalDelivery record in `sequences` off the schedule, ascending,
    /// at its rate and start.
    private func assertCorrections(_ corrections: [NewPumpEvent], match sequences: ClosedRange<Int>, file: StaticString = #filePath, line: UInt = #line) throws {
        let differing = try cyclesOffTheSchedule(in: sequences)
        XCTAssertEqual(corrections.count, differing.count, "one correction per BasalDelivery record off the schedule: \(corrections)", file: file, line: line)
        XCTAssertEqual(corrections.map(\.date), corrections.map(\.date).sorted(), "ascending", file: file, line: line)
        for (correction, cycle) in zip(corrections, differing) {
            XCTAssertEqual(correction.dose?.type, .tempBasal, file: file, line: line)
            XCTAssertEqual(correction.dose?.isMutable, false, file: file, line: line)
            XCTAssertEqual(correction.dose?.unitsPerHour ?? -1, cycle.rate, accuracy: 0.0005, file: file, line: line)
            XCTAssertEqual(correction.date.timeIntervalSince(cycle.start), 0, accuracy: 2, file: file, line: line)
        }
    }

    /// Both hosts count the basal the closed BasalDelivery records in `sequences` delivered: over
    /// all of them, and each.
    private func assertHostsCountThePumpsBasal(over sequences: ClosedRange<Int>, file: StaticString = #filePath, line: UInt = #line) throws {
        let timeline = try timeline()
        let cycles = timeline.basalCycles.filter { sequences.contains($0.sequence) && $0.end <= clock.now }
        guard let first = cycles.first, let last = cycles.last else {
            return XCTFail("no closed BasalDelivery records in \(sequences)", file: file, line: line)
        }
        let (loop, trio) = feedOracles()
        let scheduled: (Date) -> Double = { _ in Self.profileRate }
        let windows = [(start: first.start, end: last.end, accuracy: 0.01)] + cycles.map { (start: $0.start, end: $0.end, accuracy: 0.002) }
        for window in windows {
            let pump = timeline.netBasalUnits(from: window.start, to: window.end, scheduledRate: scheduled)
            let span = "from \(window.start) to \(window.end)"
            // Loop rebuilds the temp basal before a suspend without its deliveredUnits (IM:480-497),
            // so counts it in 0.05 U steps.
            let suspends = timeline.suspends.filter { $0.start > window.start && $0.start <= window.end }.count
            XCTAssertEqual(
                loop.netBasalUnits(from: window.start, to: window.end, scheduledRate: scheduled),
                pump,
                accuracy: window.accuracy + 0.025 * Double(suspends),
                "Loop counts the pump's basal \(span)",
                file: file,
                line: line
            )
            XCTAssertEqual(
                try trio.netBasalUnits(from: window.start, to: window.end, clock: clock.now, scheduledRate: scheduled),
                pump,
                accuracy: window.accuracy,
                "Trio counts the pump's basal \(span)",
                file: file,
                line: line
            )
        }
    }

    private func configureControlIQ(_ enabled: Bool) throws {
        let manager = try XCTUnwrap(driver, "no driver").manager
        let done = expectation(description: "configureControlIQMode")
        var failure: Error?
        manager.configureControlIQMode(ChangeControlIQSettingsRequest(enabled: enabled, weightLbs: 150, totalDailyInsulinUnits: 40)) { result in
            if case let .failure(error) = result { failure = error }
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
        XCTAssertNil(failure, "the pump took Control-IQ \(enabled ? "on" : "off")")
    }

    // MARK: - H1

    /// The app's temp runs, Control-IQ takes over for an hour with a sync every cycle, then hands
    /// back: the temp ends where Control-IQ stopped it, every BasalDelivery record off the schedule
    /// is corrected by the time the sync after the hand-back returns, and the app's next temp
    /// follows them.
    func testH1_aControlIQHourBetweenAppTempsIsCorrectedAndHandedBack() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        _ = try sync()

        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        try configureControlIQ(true)
        XCTAssertTrue(driver.manager.state.useControlIQ)
        XCTAssertEqual(try harness.client.snapshot().basalCycle?.pcm, 3, "the pump runs closed loop")
        let appTempEnd = clock.now

        let rates = [1400, 600, 1000, 2200, 400, 1000, 1800, 1800, 300, 1000, 1200, 700]
        var controlIQ: [Int] = []
        for (index, rate) in rates.enumerated() {
            try setControlIQRate(rate)
            try clock.advanceBoth(seconds: .minutes(index == 0 ? 4 : 5), ticks: 5)
            controlIQ.append(try lastCycle())
            _ = try sync()
        }
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        try configureControlIQ(false)
        XCTAssertFalse(driver.manager.state.useControlIQ)

        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        _ = try sync()
        let offSchedule = rates.filter { abs($0 - Int(Self.profileRate * 1000)) > 10 }.count
        let found = corrections(since: before)
        XCTAssertEqual(found.count, offSchedule, "every BasalDelivery record off the schedule is corrected by the time the sync after the hand-back returns")
        XCTAssertNil(driver.manager.state.controlIQEndedAt, "the hand-back is reconciled")
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0.8, duration: .minutes(30)))
        let nextTemp = clock.now

        let timeline = try timeline()
        let cycles = timeline.basalCycles.filter { controlIQ.contains($0.sequence) && abs(Int(($0.rate * 1000).rounded()) - 1000) > 10 }
        XCTAssertTrue(timeline.basalCycles.filter { controlIQ.contains($0.sequence) }.allSatisfy { $0.source == 3 }, "the pump's own Control-IQ cycles")
        XCTAssertEqual(found.map(\.date), found.map(\.date).sorted(), "ascending")
        for (correction, cycle) in zip(found, cycles) {
            XCTAssertEqual(correction.dose?.unitsPerHour ?? -1, cycle.rate, accuracy: 0.0005)
            XCTAssertEqual(correction.date.timeIntervalSince(cycle.start), 0, accuracy: 2)
            XCTAssertEqual(correction.dose?.automatic, true)
            XCTAssertLessThanOrEqual(try XCTUnwrap(correction.dose?.endDate), nextTemp, "before the app's next temp")
        }
        let appTemp = try XCTUnwrap(timeline.tempRates.first, "the pump recorded the app's temp")
        XCTAssertEqual(appTemp.end.map { $0.timeIntervalSince(appTempEnd) } ?? .infinity, 0, accuracy: 2, "the pump stopped it when Control-IQ took over")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("Control-IQ hand-back")
        trio.assertNoDuplicates("Control-IQ hand-back")
        trio.assertNoSameSecondBasalRows()
        let appTempDose = loop.permanentDoses.first { $0.dose.type == .tempBasal && abs($0.dose.unitsPerHour - 1.5) < 0.001 }
        XCTAssertEqual(appTempDose.map { $0.dose.endDate.timeIntervalSince(appTemp.end ?? .distantFuture) } ?? .infinity, 0, accuracy: 2, "the app's temp ends at its completion record")
        for correction in found {
            _ = loop.assertPermanent(raw: correction.raw, "Loop keeps every correction")
            XCTAssertNotNil(trio.event(syncIdentifier: correction.raw.hexadecimalString), "Trio stores every correction")
        }
        let firstControlIQ = try XCTUnwrap(controlIQ.first)
        let lastControlIQ = try XCTUnwrap(controlIQ.last)
        try assertHostsCountThePumpsBasal(over: firstControlIQ ... lastControlIQ)
    }

    // MARK: - H2

    /// Two hours of Control-IQ while the phone was out of range reach the host in one ascending
    /// batch, a correction per BasalDelivery record off the schedule.
    func testH2_anOutageDuringControlIQIsCorrectedInOneAscendingBatch() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try radioOff(driver)
        let outage = try controlIQOnThePump((0 ..< 22).map { [1000, 2200, 400][$0 % 3] })

        try radioOnAndSync()
        let found = try waitForCorrections(14, since: before)

        try assertCorrections(found, match: outage)
        let carrying = allPumpEventBatches.dropFirst(before).filter { batch in
            batch.events.contains(where: Self.isCorrection)
        }
        XCTAssertEqual(carrying.count, 1, "every correction in one batch")
        XCTAssertEqual(carrying.first?.replacePendingEvents, false)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("Control-IQ outage")
        trio.assertNoDuplicates("Control-IQ outage")
        for correction in found {
            _ = loop.assertPermanent(raw: correction.raw, "Loop keeps every correction")
            XCTAssertNotNil(trio.event(syncIdentifier: correction.raw.hexadecimalString), "Trio stores every correction")
        }
        trio.assertNoSameSecondBasalRows()
        try assertHostsCountThePumpsBasal(over: outage)

        _ = try sync()
        try waitForBackfill(driver)
        XCTAssertEqual(corrections(since: before).count, found.count, "a second pass reports nothing")
    }

    // MARK: - H3

    /// The app relaunches during Control-IQ: nothing is reported twice and corrections go on.
    func testH3_aRelaunchReportsNothingTwice() throws {
        try stageDriver()
        let before = allPumpEventBatches.count
        let first = try controlIQOnThePump([2200, 1000, 400, 2200, 1000, 400, 2200, 1000, 400, 2200])
        _ = try sync()
        let found = try waitForCorrections(7, since: before)
        try assertCorrections(found, match: first)

        let relaunched = try relaunch()
        _ = try sync()
        try waitForBackfill(relaunched)
        XCTAssertEqual(corrections(since: before).count, found.count, "nothing reported again after the relaunch")

        try clock.advanceBoth(seconds: .minutes(30), ticks: 6)
        let second = try controlIQOnThePump([600, 600, 1000, 1500, 1500])
        _ = try sync()
        let all = try waitForCorrections(found.count + 4, since: before)
        try assertCorrections(Array(all.dropFirst(found.count)), match: second)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("relaunch")
        trio.assertNoDuplicates("relaunch")
        XCTAssertEqual(Set(all.map(\.raw)).count, all.count, "one correction per BasalDelivery record")
        try assertHostsCountThePumpsBasal(over: first)
        try assertHostsCountThePumpsBasal(over: second)
    }

    // MARK: - H4

    /// The pump stops and starts again during Control-IQ: the chunk under way ends at the stop, and
    /// the suspend, the resume and the corrections reach the host in one batch.
    func testH4_aSuspendDuringControlIQGoesInTheSameBatch() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try radioOff(driver)
        let first = try lastSequence() + 1
        try harness.client.setState(["closed_loop_enabled": true])
        try setControlIQRate(2200)
        try clock.advanceBoth(seconds: .minutes(10), ticks: 2)
        try clock.advanceBoth(seconds: 100, ticks: 1)
        let suspendedAt = clock.now
        try harness.client.suspend(reason: "user")
        try clock.advanceBoth(seconds: .minutes(10), ticks: 2)
        try setControlIQRate(400)
        let resumedAt = clock.now
        try harness.client.resume()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        try setControlIQRate(1000)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        try harness.client.setState(["closed_loop_enabled": false])
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        let outage = first ... (try lastSequence())
        let cycles = try timeline().basalCycles.filter { outage.contains($0.sequence) }
        XCTAssertEqual(cycles.map(\.source), [3, 3, 0, 0, 3, 3, 3, 1], "suspended BasalDelivery records, and one at the resume")
        XCTAssertEqual(cycles.first { $0.start >= resumedAt }?.start, resumedAt, "the resume restarts the cadence")

        try radioOnAndSync()
        let found = try waitForCorrections(4, since: before)

        XCTAssertEqual(found.map(\.dose?.unitsPerHour), [2.2, 2.2, 0.4, 0.4])
        XCTAssertEqual(found[1].dose?.endDate.timeIntervalSince(suspendedAt) ?? -1, 0, accuracy: 1, "the chunk under way ends at the stop")
        XCTAssertGreaterThan(try XCTUnwrap(found[2].dose?.startDate), resumedAt, "never in the resume's second")
        let batch = try XCTUnwrap(allPumpEventBatches.dropFirst(before).first { batch in
            batch.events.contains(where: Self.isCorrection)
        })
        XCTAssertTrue(batch.events.contains { $0.type == .suspend }, "the suspend rides with the corrections")
        XCTAssertTrue(batch.events.contains { $0.type == .resume }, "the resume rides with the corrections")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("suspend during Control-IQ")
        trio.assertNoDuplicates("suspend during Control-IQ")
        XCTAssertNoThrow(try trio.basalSegments(clock: clock.now), "Trio's IOB runs")
        try assertHostsCountThePumpsBasal(over: outage)
    }

    // MARK: - H5

    /// A5 with basal reporting on (#340): the link drops in place of the `SetTempRate` answer, the
    /// next sync adopts the pump's temp from history, and its BasalDelivery records find nothing
    /// left to correct.
    func testH5_aLostSetTempRateIsReportedLiveAndLeavesNothingToCorrect() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.2, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        _ = try sync()

        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        try harness.client.armFault(FaketandemFaultSpec(.disconnect, message: "SetTempRateRequest"))
        guard case .communication? = try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30), timeout: 90) else {
            return XCTFail("a link lost in place of the SetTempRate answer is a communication error")
        }
        let pumpStart = try XCTUnwrap(try harness.client.snapshot().basal.tempStart?.date)
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        let lastClosed = try lastCycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        XCTAssertTrue(corrections(since: before).isEmpty, "the live path reported what the pump ran")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "no BasalDelivery record differs from what the host was told")
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("lost SetTempRate answer")
        trio.assertNoDuplicates("lost SetTempRate answer")
        let live = loop.mutableDoses.filter { $0.dose.type == .tempBasal }
        XCTAssertEqual(live.count, 1)
        XCTAssertEqual(live.first.map { abs($0.dose.startDate.timeIntervalSince(pumpStart)) } ?? .infinity, 0, accuracy: 2, "at the pump's start")
        XCTAssertEqual(live.first?.dose.unitsPerHour ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(trio.tempBasals.count, 2)
        XCTAssertNoThrow(try trio.basalSegments(clock: clock.now), "Trio's IOB runs")
    }

    // MARK: - H6

    /// App temps, a cancel, and a temp replaced within one cycle: the host counts each change from
    /// its command and the pump from its next BasalDelivery record, so nothing differs and nothing
    /// is reported.
    func testH6_appTempsAndACancelReportNothing() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: 0), "cancel")
        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 2.0, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0.5, duration: .minutes(30)), "replaces the last before the pump's next BasalDelivery record")
        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let lastClosed = try lastCycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        XCTAssertTrue(corrections(since: before).isEmpty, "nothing reported: \(corrections(since: before))")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "no BasalDelivery record differs from what the host was told")
        let rates = try timeline().basalCycles.map { Int(($0.rate * 1000).rounded()) }
        XCTAssertEqual(rates, [1000, 1500, 1000, 500, 500, 500], "the 2.0 U/hr temp was replaced before a BasalDelivery record ran it")
    }

    /// An app temp across a profile segment change: the pump rescales it at the change and runs the
    /// new rate from its next BasalDelivery record, the driver cuts the temp there, and nothing
    /// differs.
    func testH6_aTempAcrossASegmentChangeReportsNothing() throws {
        let change = try startClocksBeforeASegmentChange()
        let driver = try stageDriver(schedule: schedule(changingTo: 0.8, at: change))
        let before = allPumpEventBatches.count
        try advance(to: change - .minutes(17))
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        for minutes in [13.0, 8, 3] {
            try advance(to: change - .minutes(minutes))
            _ = try sync()
        }
        try advance(to: change + 30)
        _ = try sync()
        XCTAssertEqual(try harness.client.snapshot().basal.tempRate, 1.2, accuracy: 0.001, "the pump rescaled the temp at its segment change")
        try advance(to: change + .minutes(2))
        _ = try sync()
        try advance(to: change + .minutes(7))
        let lastClosed = try lastCycle()
        _ = try sync()
        try advance(to: change + .minutes(12))
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        XCTAssertTrue(corrections(since: before).isEmpty, "nothing reported: \(corrections(since: before))")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "no BasalDelivery record differs from what the host was told")
        let rates = try timeline().basalCycles.map { Int(($0.rate * 1000).rounded()) }
        XCTAssertEqual(rates, [1000, 1500, 1500, 1500, 1200, 1200, 1200], "1.2 U/hr from the first BasalDelivery record after the change")
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("segment change")
        trio.assertNoDuplicates("segment change")
        trio.assertNoSameSecondBasalRows()
        let temps = loop.doses.filter { $0.dose.type == .tempBasal }.sorted { $0.dose.startDate < $1.dose.startDate }
        XCTAssertEqual(temps.map(\.dose.unitsPerHour), [1.5, 1.2], "cut at the change, at the rescaled rate after it")
        XCTAssertEqual(temps.first.map { $0.dose.endDate.timeIntervalSince(change) } ?? .infinity, 0, accuracy: 2)
        XCTAssertEqual(temps.last.map { $0.dose.startDate.timeIntervalSince(change) } ?? .infinity, 0, accuracy: 2)
    }

    /// The pump's clock runs 11 minutes ahead, so it reaches its 2.0 U/hr segment 11 minutes before
    /// the phone does. The driver runs a temp that delivers the host's 1.0 until the phone gets
    /// there, and the host, never told of it, counts what the pump's BasalDelivery records ran:
    /// nothing differs.
    func testH6_aSkewedPumpClocksCompensationReportsNothing() throws {
        let change = try startClocksBeforeASegmentChange(skewSeconds: 660)
        let driver = try stageDriver(schedule: schedule(changingTo: 2.0, at: change))
        XCTAssertTrue(driver.manager.state.isPumpClockSkewed)
        let before = allPumpEventBatches.count
        try advance(to: change - .minutes(11) + 30)
        _ = try sync()
        let compensating = try harness.client.snapshot().basal
        XCTAssertTrue(compensating.tempActive, "the pump runs the host's 1.0 U/hr")
        XCTAssertEqual(compensating.tempRate, 1.0, accuracy: 0.001)
        for minutes in [8.0, 3] {
            try advance(to: change - .minutes(minutes))
            _ = try sync()
        }
        try advance(to: change + 30)
        _ = try sync()
        XCTAssertFalse(try harness.client.snapshot().basal.tempActive, "the phone reached the pump's segment")
        try advance(to: change + .minutes(7))
        let lastClosed = try lastCycle()
        _ = try sync()
        try advance(to: change + .minutes(12))
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        XCTAssertTrue(corrections(since: before).isEmpty, "nothing reported: \(corrections(since: before))")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "no BasalDelivery record differs from what the host was told")
        let cycles = try timeline().basalCycles
        XCTAssertEqual(cycles.map { Int(($0.rate * 1000).rounded()) }, [1000, 1000, 1000, 1000, 2000, 2000, 2000])
        XCTAssertEqual(cycles.map(\.source), [1, 1, 2, 2, 1, 1, 1], "the compensation ran as a temp")
        let (loop, _) = feedOracles()
        XCTAssertTrue(loop.doses.filter { $0.dose.type == .tempBasal }.isEmpty, "the host counts its own scheduled rate")
    }

    // MARK: - H7

    /// A temp basal set on the pump's own screen is reported as its chunks close.
    func testH7_aTempSetOnThePumpIsReportedFromItsChunks() throws {
        try stageDriver()
        let before = allPumpEventBatches.count
        let first = try lastSequence() + 1
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        try harness.client.startTempBasal(percent: 150, durationMinutes: 30)
        try clock.advanceBoth(seconds: .minutes(35), ticks: 7)
        let staged = first ... (try lastSequence())

        _ = try sync()
        let found = try waitForCorrections(6, since: before)

        try assertCorrections(found, match: staged)
        for correction in found {
            XCTAssertEqual(correction.dose?.wasProgrammedByPumpUI, true)
            XCTAssertEqual(correction.dose?.automatic, false)
            XCTAssertEqual(correction.title, "Temp Basal")
        }
        try assertHostsCountThePumpsBasal(over: staged)
    }

    // MARK: - H8

    /// The pump runs a profile off the app's schedule while out of range: its chunks are corrected
    /// at the pump's rate, and the driver writes the schedule back. The cycle under way when the
    /// write lands runs on at the old rate, which, as for any command, is left to the residual.
    func testH8_aPumpProfileOffTheScheduleIsCorrectedAndWrittenOver() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try radioOff(driver)
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        try harness.client.setIDPProfiles([FaketandemIDPProfile(id: 1, segments: [.init(startTime: 0, basalRate: 1200)])])
        try harness.client.setState(["basal_rate": 1.2])
        let first = try lastSequence() + 1
        try clock.advanceBoth(seconds: .minutes(19), ticks: 4)
        let outage = first ... (try lastSequence())
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        let underWay = try lastCycle()

        try radioOnAndSync()
        try IntegrationWait.until("the driver to write the schedule over the pump's profile", timeout: 60) {
            try driver.manager.state.basalProfileUpdateStatus == .none
                && abs(self.harness.client.snapshot().basal.profileRate - Self.profileRate) < 0.001
        }
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: underWay)

        let found = corrections(since: before)
        try assertCorrections(found, match: outage)
        XCTAssertTrue(found.allSatisfy { $0.dose?.automatic == false && $0.dose?.wasProgrammedByPumpUI == false })
        XCTAssertEqual(try timeline().basalCycles.last?.rate, Self.profileRate, "the pump runs the schedule from its next BasalDelivery record")
        XCTAssertNil(driver.manager.state.basalRateMismatchDetectedAt)
        try assertHostsCountThePumpsBasal(over: outage)
    }

    // MARK: - H9

    /// An alarm stops delivery during the app's temp and the pump keeps the temp: it ends for the
    /// host at the stop, and the driver reports it again from the resume until the app's next temp,
    /// leaving basal reconciliation nothing to correct.
    func testH9_aTempAnAlarmSuspendKeptIsReportedAfterTheResume() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(60)))
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        let suspendedAt = clock.now
        try harness.client.suspend(reason: "alarm", keepTemp: true)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        let resumedAt = clock.now
        let resumeCycle = try lastSequence() + 1
        try harness.client.resume(clearAlarms: true)
        XCTAssertTrue(try harness.client.snapshot().basal.tempActive, "the temp runs again")
        _ = try sync()
        for _ in 0 ..< 3 {
            try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
            _ = try sync()
        }
        let lastResumed = try lastCycle()
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0.8, duration: .minutes(30)))
        let nextTemp = clock.now
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        let lastClosed = try lastCycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        let found = corrections(since: before)
        XCTAssertTrue(found.isEmpty, "the host already counts the temp it ran after the resume: \(found.map(\.dose))")
        let resumed = eventsSince(before).filter { event in
            guard let dose = event.dose, dose.type == .tempBasal else { return false }
            return dose.startDate > resumedAt && dose.startDate < nextTemp
        }
        let resumedStart = try XCTUnwrap(resumed.first?.dose?.startDate)
        XCTAssertGreaterThan(resumedStart, resumedAt, "never in the resume's second")
        XCTAssertEqual(resumedStart.timeIntervalSince(resumedAt), 1, accuracy: 2, "from the resume")
        XCTAssertEqual(Set(resumed.map(\.dose?.unitsPerHour)), [1.5])
        XCTAssertEqual(resumed.last?.dose?.isMutable, false)
        XCTAssertEqual(resumed.last?.dose?.endDate.timeIntervalSince(nextTemp) ?? .infinity, 0, accuracy: 2, "it ends at the app's next temp")
        XCTAssertTrue(resumed.allSatisfy { $0.dose?.automatic == true }, "the app set the temp")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("alarm suspend keeping the temp")
        trio.assertNoDuplicates("alarm suspend keeping the temp")
        trio.assertNoSameSecondBasalRows()
        let appTemp = loop.permanentDoses.first { $0.dose.type == .tempBasal }
        XCTAssertEqual(appTemp.map { $0.dose.endDate.timeIntervalSince(suspendedAt) } ?? .infinity, 0, accuracy: 2, "the app's temp ends at the stop")
        try assertHostsCountThePumpsBasal(over: resumeCycle ... lastResumed - 1)
    }

    // MARK: - H10

    /// The CGM drops out under Control-IQ and the pump runs its profile, which is the app's
    /// schedule: only the Control-IQ chunks off it are corrected.
    func testH10_aCGMDropoutRunsTheProfileAndReportsNothingForIt() throws {
        try stageDriver()
        let before = allPumpEventBatches.count
        let first = try lastSequence() + 1
        try harness.client.setState(["closed_loop_enabled": true])
        try setControlIQRate(2200)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        try harness.client.setState(["cgm_available": false])
        try clock.advanceBoth(seconds: .minutes(15), ticks: 3)
        try harness.client.setState(["cgm_available": true])
        try setControlIQRate(400)
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        try harness.client.setState(["closed_loop_enabled": false])
        try clock.advanceBoth(seconds: .minutes(5), ticks: 1)
        let staged = first ... (try lastSequence())
        let cycles = try timeline().basalCycles.filter { staged.contains($0.sequence) }
        XCTAssertEqual(cycles.map(\.source), [3, 1, 1, 1, 3, 1], "the profile while the CGM is gone")

        _ = try sync()
        let found = try waitForCorrections(2, since: before)
        try assertCorrections(found, match: staged)
        try assertHostsCountThePumpsBasal(over: staged)
    }

    // MARK: - H11

    /// The same app temp enacted a minute into every cycle, as hosts keep one running, with a sync between.
    func testH11_theSameTempEveryCycleIsCountedOnceAndReportsNothing() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        var raws: [Data] = []
        var cycles: [Int] = []
        for _ in 1 ... 4 {
            try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
            let beforeTemp = allPumpEventBatches.count
            XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
            raws += eventsSince(beforeTemp).filter { $0.dose?.type == .tempBasal && $0.dose?.isMutable == true }.map(\.raw)
            try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
            cycles.append(try lastCycle())
            _ = try sync()
        }
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let lastClosed = try lastCycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        XCTAssertTrue(corrections(since: before).isEmpty, "nothing reported: \(corrections(since: before))")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "no BasalDelivery record differs from what the host was told")
        XCTAssertEqual(raws.count, 4)
        XCTAssertEqual(Set(raws).count, raws.count, "one identity per enactment")
        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("the same temp every cycle")
        trio.assertNoDuplicates("the same temp every cycle")
        trio.assertNoSameSecondBasalRows()
        XCTAssertEqual(
            loop.doses.filter { $0.dose.type == .tempBasal }.compactMap(\.raw).sorted { $0.hexadecimalString < $1.hexadecimalString },
            raws.sorted { $0.hexadecimalString < $1.hexadecimalString },
            "one Loop dose per enactment: \(loop.doses.map(LoopDoseStoreOracle.describe))"
        )
        XCTAssertEqual(trio.tempBasals.count, raws.count, "one Trio row per enactment: \(trio.tempBasals)")
        // The host counts the first temp from its command, the pump from its next BasalDelivery
        // record.
        try assertHostsCountThePumpsBasal(over: try XCTUnwrap(cycles.first) ... lastClosed)
    }
}
