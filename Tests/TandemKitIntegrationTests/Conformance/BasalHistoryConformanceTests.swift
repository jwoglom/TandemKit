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
/// differ the driver reports a correction at the pump's rate, one per 279, and a second pass
/// reports nothing.
///
/// faketandem writes no 279s of its own yet, so each scenario appends the pump's records, as
/// `HistoryBackfillIntegrationTests` does: for a stretch it stages, or one each cycle at what the
/// emulator runs while the app's commands do (`docs/integration-harness.md`).
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

    /// A paired driver with history backfill and basal reporting on, from an empty pump log.
    @discardableResult
    private func stageDriver() throws -> FaketandemHarness.Driver {
        try eraseHistory()
        try harness.client.setState(["basal_rate": Self.profileRate])
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.basalHistoryReporting] = true
        state.bolusReportLedger = BolusReportLedger(trackingSince: clock.now)
        state.reportedBasal = ReportedBasalLedger(trackingSince: clock.now)
        state.insulinType = .novolog
        state.basalRateSchedule = try XCTUnwrap(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: Self.profileRate)]))
        let driver = startDriver(state: state)
        try harness.pair(driver)
        _ = try sync()
        try waitForBackfill(driver)
        return driver
    }

    private func waitForBackfill(_ driver: FaketandemHarness.Driver, timeout: TimeInterval = 180) throws {
        let last = try harness.client.snapshot().history.lastSequence
        try IntegrationWait.until("the driver to read the pump's history through \(last)", timeout: timeout) {
            (driver.manager.state.historyBackfill?.watermark).map { Int($0) >= last } == true
                && !driver.manager.historyFetchGate.isBusy
        }
    }

    /// The reconciliation runs after the tick that reads a record, so a test that expects nothing
    /// reported waits for it to be done with the last closed 279.
    private func waitForReconciliation(_ driver: FaketandemHarness.Driver, through sequence: Int, timeout: TimeInterval = 120) throws {
        try IntegrationWait.until("the driver to reconcile the pump's basal through record \(sequence)", timeout: timeout) {
            driver.manager.state.reportedBasal.reconciledThrough.map { Int($0) >= sequence } == true
        }
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

    /// A 279 as the pump writes it. Rates in milliunits per hour.
    private struct Delivery {
        var secondsAgo: TimeInterval
        var source: Int
        var rate: Int
        var profile = 1000

        static func controlIQ(_ secondsAgo: TimeInterval, _ rate: Int) -> Delivery {
            Delivery(secondsAgo: secondsAgo, source: 3, rate: rate)
        }

        var record: [String: Any] {
            [
                "type": "BasalDelivery",
                "seconds_ago": secondsAgo,
                "data": [
                    "commandedRateSource": source,
                    "commandedRate": rate,
                    "profileBasalRate": profile,
                    "algorithmRate": source >= 3 ? rate : 0,
                    "tempRate": source == 2 || source == 4 ? rate : 0,
                ] as [String: Any],
            ]
        }
    }

    /// Control-IQ cycles ending one cycle before now, oldest first, at `rates`.
    private func controlIQCycles(_ rates: [Int], endingSecondsAgo end: TimeInterval = cycle + 30) -> [Delivery] {
        rates.enumerated().map { index, rate in
            .controlIQ(end + Double(rates.count - 1 - index) * Self.cycle, rate)
        }
    }

    @discardableResult
    private func append(_ records: [[String: Any]]) throws -> ClosedRange<Int> {
        try harness.client.appendHistory(records: records)
    }

    private func eventsSince(_ count: Int) -> [NewPumpEvent] {
        Array(allPumpEventBatches.dropFirst(count)).flatMap(\.events)
    }

    private func corrections(since count: Int) -> [NewPumpEvent] {
        eventsSince(count).filter { HistoryLogSyncIdentifier.decode($0.raw)?.scheme == .logSequence }
    }

    private func waitForCorrections(_ count: Int, since batches: Int, timeout: TimeInterval = 120) throws -> [NewPumpEvent] {
        try IntegrationWait.value("\(count) basal correction(s)", timeout: timeout) {
            let found = self.corrections(since: batches)
            return found.count >= count ? found : nil
        }
    }

    /// The instant a staged record's `seconds_ago` stands for.
    private func instant(_ secondsAgo: TimeInterval, from now: Date) -> Date {
        now.addingTimeInterval(-secondsAgo)
    }

    private func assertCorrections(
        _ corrections: [NewPumpEvent],
        match deliveries: [Delivery],
        stagedAt now: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let differing = deliveries.filter { abs($0.rate - Int(Self.profileRate * 1000)) > 10 }
        XCTAssertEqual(corrections.count, differing.count, "one correction per 279 off the schedule: \(corrections)", file: file, line: line)
        XCTAssertEqual(corrections.map(\.date), corrections.map(\.date).sorted(), "ascending", file: file, line: line)
        for (correction, delivery) in zip(corrections, differing) {
            XCTAssertEqual(correction.dose?.type, .tempBasal, file: file, line: line)
            XCTAssertEqual(correction.dose?.isMutable, false, file: file, line: line)
            XCTAssertEqual(correction.dose?.unitsPerHour ?? -1, Double(delivery.rate) / 1000, accuracy: 0.0005, file: file, line: line)
            XCTAssertEqual(correction.date.timeIntervalSince(instant(delivery.secondsAgo, from: now)), 0, accuracy: 2, file: file, line: line)
        }
    }

    /// Both hosts count the basal the 279s in `sequences` delivered: over all of them, and each.
    private func assertHostsCountThePumpsBasal(over sequences: ClosedRange<Int>, file: StaticString = #filePath, line: UInt = #line) throws {
        let timeline = try timeline()
        let cycles = timeline.basalCycles.filter { sequences.contains($0.sequence) }
        guard let first = cycles.first, let last = cycles.last else {
            return XCTFail("no 279s in \(sequences)", file: file, line: line)
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

    /// The 279 the pump writes now: at what the emulator runs, or at Control-IQ's `rate`.
    @discardableResult
    private func cycle(controlIQ rate: Int? = nil) throws -> Int {
        let basal = try harness.client.snapshot().basal
        let profile = Int((basal.profileRate * 1000).rounded())
        let delivery: Delivery = if let rate {
            Delivery(secondsAgo: 0, source: 3, rate: rate, profile: profile)
        } else if basal.suspended {
            Delivery(secondsAgo: 0, source: 0, rate: 0, profile: profile)
        } else if basal.tempActive {
            Delivery(secondsAgo: 0, source: 2, rate: Int((basal.tempRate * 1000).rounded()), profile: profile)
        } else {
            Delivery(secondsAgo: 0, source: 1, rate: profile, profile: profile)
        }
        return try append([delivery.record]).lowerBound
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
    /// back: the temp ends where the driver stopped it, every 279 off the schedule is corrected by
    /// the time the sync after the hand-back returns, and the app's next temp follows them.
    func testH1_aControlIQHourBetweenAppTempsIsCorrectedAndHandedBack() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try cycle()
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        try cycle()
        _ = try sync()

        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        try harness.client.setState(["closed_loop_enabled": true])
        try configureControlIQ(true)
        XCTAssertTrue(driver.manager.state.useControlIQ)
        let appTempEnd = clock.now

        let rates = [1400, 600, 1000, 2200, 400, 1000, 1800, 1800, 300, 1000, 1200, 700]
        var controlIQ: [Int] = []
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        for (index, rate) in rates.enumerated() {
            if index > 0 { try clock.advanceBoth(seconds: .minutes(5), ticks: 5) }
            controlIQ.append(try cycle(controlIQ: rate))
            _ = try sync()
        }
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        try harness.client.setState(["closed_loop_enabled": false])
        try configureControlIQ(false)
        XCTAssertFalse(driver.manager.state.useControlIQ)

        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        try cycle()
        _ = try sync()
        let offSchedule = rates.filter { abs($0 - Int(Self.profileRate * 1000)) > 10 }.count
        let found = corrections(since: before)
        XCTAssertEqual(found.count, offSchedule, "every 279 off the schedule is corrected by the time the sync after the hand-back returns")
        XCTAssertNil(driver.manager.state.controlIQEndedAt, "the hand-back is reconciled")
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0.8, duration: .minutes(30)))
        let nextTemp = clock.now

        let timeline = try timeline()
        let cycles = timeline.basalCycles.filter { controlIQ.contains($0.sequence) && abs(Int(($0.rate * 1000).rounded()) - 1000) > 10 }
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
    /// batch, a correction per 279 off the schedule.
    func testH2_anOutageDuringControlIQIsCorrectedInOneAscendingBatch() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try radioOff(driver)
        try clock.advanceBoth(seconds: .hours(2), ticks: 24)
        let stagedAt = clock.now
        let deliveries = controlIQCycles((0 ..< 22).map { [1000, 2200, 400][$0 % 3] })
        let staged = try append(deliveries.map(\.record))

        try radioOnAndSync()
        let found = try waitForCorrections(14, since: before)

        assertCorrections(found, match: deliveries, stagedAt: stagedAt)
        let carrying = allPumpEventBatches.dropFirst(before).filter { batch in
            batch.events.contains { HistoryLogSyncIdentifier.decode($0.raw)?.scheme == .logSequence }
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
        try assertHostsCountThePumpsBasal(over: staged)

        _ = try sync()
        try waitForBackfill(driver)
        XCTAssertEqual(corrections(since: before).count, found.count, "a second pass reports nothing")
    }

    // MARK: - H3

    /// The app relaunches during Control-IQ: nothing is reported twice and corrections go on.
    func testH3_aRelaunchReportsNothingTwice() throws {
        try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .hours(1), ticks: 12)
        let firstAt = clock.now
        let first = controlIQCycles([2200, 1000, 400, 2200, 1000, 400, 2200, 1000, 400, 2200])
        let firstStaged = try append(first.map(\.record))
        _ = try sync()
        let found = try waitForCorrections(7, since: before)
        assertCorrections(found, match: first, stagedAt: firstAt)

        let relaunched = try relaunch()
        _ = try sync()
        try waitForBackfill(relaunched)
        XCTAssertEqual(corrections(since: before).count, found.count, "nothing reported again after the relaunch")

        try clock.advanceBoth(seconds: .minutes(30), ticks: 6)
        let secondAt = clock.now
        let second = controlIQCycles([600, 600, 1000, 1500, 1500])
        let secondStaged = try append(second.map(\.record))
        _ = try sync()
        let all = try waitForCorrections(found.count + 4, since: before)
        assertCorrections(Array(all.dropFirst(found.count)), match: second, stagedAt: secondAt)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("relaunch")
        trio.assertNoDuplicates("relaunch")
        XCTAssertEqual(Set(all.map(\.raw)).count, all.count, "one correction per 279")
        try assertHostsCountThePumpsBasal(over: firstStaged)
        try assertHostsCountThePumpsBasal(over: secondStaged)
    }

    // MARK: - H4

    /// The pump stops and starts again during Control-IQ: the chunk under way ends at the stop, and
    /// the suspend, the resume and the corrections reach the host in one batch.
    func testH4_aSuspendDuringControlIQGoesInTheSameBatch() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try radioOff(driver)
        try clock.advanceBoth(seconds: .hours(1), ticks: 12)
        let stagedAt = clock.now
        let staged = try append([
            Delivery.controlIQ(3000, 2200).record,
            Delivery.controlIQ(2700, 2200).record,
            ["type": "PumpingSuspended", "seconds_ago": 2600.0, "data": ["reasonId": 0] as [String: Any]],
            Delivery(secondsAgo: 2400, source: 0, rate: 0).record,
            Delivery(secondsAgo: 2100, source: 0, rate: 0).record,
            ["type": "PumpingResumed", "seconds_ago": 2000.0, "data": [:] as [String: Any]],
            Delivery.controlIQ(2000, 400).record,
            Delivery.controlIQ(1700, 400).record,
            Delivery.controlIQ(1400, 1000).record,
        ])

        try radioOnAndSync()
        let found = try waitForCorrections(4, since: before)

        XCTAssertEqual(found.map(\.dose?.unitsPerHour), [2.2, 2.2, 0.4, 0.4])
        XCTAssertEqual(found[1].dose?.endDate.timeIntervalSince(instant(2600, from: stagedAt)) ?? -1, 0, accuracy: 1, "the chunk under way ends at the stop")
        XCTAssertGreaterThan(try XCTUnwrap(found[2].dose?.startDate), instant(2000, from: stagedAt), "never in the resume's second")
        let batch = try XCTUnwrap(allPumpEventBatches.dropFirst(before).first { batch in
            batch.events.contains { HistoryLogSyncIdentifier.decode($0.raw)?.scheme == .logSequence }
        })
        XCTAssertTrue(batch.events.contains { $0.type == .suspend }, "the suspend rides with the corrections")
        XCTAssertTrue(batch.events.contains { $0.type == .resume }, "the resume rides with the corrections")

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("suspend during Control-IQ")
        trio.assertNoDuplicates("suspend during Control-IQ")
        XCTAssertNoThrow(try trio.basalSegments(clock: clock.now), "Trio's IOB runs")
        try assertHostsCountThePumpsBasal(over: staged)
    }

    // MARK: - H7

    /// A temp basal set on the pump's own screen is reported as its chunks close.
    func testH7_aTempSetOnThePumpIsReportedFromItsChunks() throws {
        try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .hours(1), ticks: 12)
        let stagedAt = clock.now
        let deliveries = [1800.0, 1500, 1200, 900, 600].map { Delivery(secondsAgo: $0 - 10, source: 2, rate: 1500) }
        let staged = try append(
            [["type": "TempRateActivated", "seconds_ago": 1800.0, "data": ["percent": 150, "durationMilliseconds": 1_800_000, "tempRateId": 77] as [String: Any]]]
                + deliveries.map(\.record)
                + [["type": "TempRateCompleted", "seconds_ago": 0.0, "data": ["tempRateId": 77, "timeLeft": 0] as [String: Any]]]
        )

        _ = try sync()
        let found = try waitForCorrections(5, since: before)

        assertCorrections(found, match: deliveries, stagedAt: stagedAt)
        for correction in found {
            XCTAssertEqual(correction.dose?.wasProgrammedByPumpUI, true)
            XCTAssertEqual(correction.dose?.automatic, false)
            XCTAssertEqual(correction.title, "Temp Basal")
        }
        try assertHostsCountThePumpsBasal(over: staged)
    }

    // MARK: - H8

    /// The pump's profile is not the app's schedule: its chunks are corrected at the pump's rate,
    /// and the mismatch is still flagged.
    func testH8_aPumpProfileOffTheScheduleIsCorrectedAndFlagged() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try harness.client.setState(["basal_rate": 1.2])
        try clock.advanceBoth(seconds: .minutes(30), ticks: 6)
        let stagedAt = clock.now
        let deliveries = [1500.0, 1200, 900, 600].map { Delivery(secondsAgo: $0, source: 1, rate: 1200, profile: 1200) }
        let staged = try append(deliveries.map(\.record))

        for _ in 0 ..< 3 {
            _ = try sync()
            try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval / 2, ticks: 2)
        }
        _ = try sync()
        let found = try waitForCorrections(4, since: before)

        assertCorrections(Array(found.prefix(4)), match: deliveries, stagedAt: stagedAt)
        XCTAssertTrue(found.prefix(4).allSatisfy { $0.dose?.automatic == false && $0.dose?.wasProgrammedByPumpUI == false })
        XCTAssertTrue(driver.manager.state.basalRateMismatchConfirmed, "the mismatch still shows")
        try assertHostsCountThePumpsBasal(over: staged)
    }

    // MARK: - H10

    /// The CGM drops out under Control-IQ and the pump runs its profile, which is the app's
    /// schedule: only the Control-IQ chunks off it are corrected.
    func testH10_aCGMDropoutRunsTheProfileAndReportsNothingForIt() throws {
        try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .hours(1), ticks: 12)
        let stagedAt = clock.now
        let deliveries = [
            Delivery.controlIQ(1830, 2200),
            Delivery(secondsAgo: 1530, source: 1, rate: 1000),
            Delivery(secondsAgo: 1230, source: 1, rate: 1000),
            Delivery(secondsAgo: 930, source: 1, rate: 1000),
            Delivery.controlIQ(630, 400),
        ]
        let staged = try append(deliveries.map(\.record))

        _ = try sync()
        let found = try waitForCorrections(2, since: before)
        assertCorrections(found, match: deliveries, stagedAt: stagedAt)
        try assertHostsCountThePumpsBasal(over: staged)
    }

    // MARK: - H5

    /// A5 with basal reporting on (#340): the link drops in place of the `SetTempRate` answer, the
    /// next sync adopts the pump's temp from history, and its 279s find nothing left to correct.
    func testH5_aLostSetTempRateIsReportedLiveAndLeavesNothingToCorrect() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try cycle()
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.2, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        try cycle()
        _ = try sync()

        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        try harness.client.armFault(FaketandemFaultSpec(.disconnect, message: "SetTempRateRequest"))
        guard case .communication? = try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30), timeout: 90) else {
            return XCTFail("a link lost in place of the SetTempRate answer is a communication error")
        }
        let pumpStart = try XCTUnwrap(try harness.client.snapshot().basal.tempStart?.date)
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        let lastClosed = try cycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        try cycle()
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        XCTAssertTrue(corrections(since: before).isEmpty, "the live path reported what the pump ran")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "no 279 differs from what the host was told")
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

    /// App temps, a cancel, and a temp replaced within one cycle, with a 279 every five minutes:
    /// the host counts each change from its command and the pump from its next 279, so nothing
    /// differs and nothing is reported.
    func testH6_appTempsAndACancelReportNothing() throws {
        let driver = try stageDriver()
        let before = allPumpEventBatches.count
        try cycle()
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 1.5, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(4), ticks: 4)
        try cycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(2), ticks: 2)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0, duration: 0), "cancel")
        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        try cycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 2.0, duration: .minutes(30)))
        try clock.advanceBoth(seconds: .minutes(1), ticks: 1)
        XCTAssertNil(try enactTempBasal(unitsPerHour: 0.5, duration: .minutes(30)), "replaces the last before the pump's next 279")
        try clock.advanceBoth(seconds: .minutes(3), ticks: 3)
        try cycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        let lastClosed = try cycle()
        _ = try sync()
        try clock.advanceBoth(seconds: .minutes(5), ticks: 5)
        try cycle()
        _ = try sync()
        try waitForBackfill(driver)
        try waitForReconciliation(driver, through: lastClosed)

        XCTAssertTrue(corrections(since: before).isEmpty, "nothing reported: \(corrections(since: before))")
        XCTAssertTrue(driver.manager.loggedBasalDifferences.isEmpty, "no 279 differs from what the host was told")
        XCTAssertGreaterThanOrEqual(try timeline().basalCycles.count, 6)
    }
}
