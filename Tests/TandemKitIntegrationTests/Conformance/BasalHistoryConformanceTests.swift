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
/// faketandem writes no 279s of its own yet, so each scenario appends the pump's records for the
/// stretch it stages, as `HistoryBackfillIntegrationTests` does (`docs/integration-harness.md`).
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
        try append(deliveries.map(\.record))

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
        let from = instant(deliveries[0].secondsAgo, from: stagedAt)
        let expected = deliveries.reduce(0.0) { $0 + (Double($1.rate) / 1000 - Self.profileRate) * Self.cycle / .hours(1) }
        XCTAssertEqual(
            try trio.netBasalUnits(from: from, to: stagedAt, clock: clock.now, scheduledRate: { _ in Self.profileRate }),
            expected,
            accuracy: 0.01,
            "Trio's IOB counts the pump's basal"
        )

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
        try append(first.map(\.record))
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
        try append(second.map(\.record))
        _ = try sync()
        let all = try waitForCorrections(found.count + 4, since: before)
        assertCorrections(Array(all.dropFirst(found.count)), match: second, stagedAt: secondAt)

        let (loop, trio) = feedOracles()
        loop.assertNoDuplicates("relaunch")
        trio.assertNoDuplicates("relaunch")
        XCTAssertEqual(Set(all.map(\.raw)).count, all.count, "one correction per 279")
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
        try append([
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
    }

    // MARK: - H7

    /// A temp basal set on the pump's own screen is reported as its chunks close.
    func testH7_aTempSetOnThePumpIsReportedFromItsChunks() throws {
        try stageDriver()
        let before = allPumpEventBatches.count
        try clock.advanceBoth(seconds: .hours(1), ticks: 12)
        let stagedAt = clock.now
        let deliveries = [1800.0, 1500, 1200, 900, 600].map { Delivery(secondsAgo: $0 - 10, source: 2, rate: 1500) }
        try append(
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
        try append(deliveries.map(\.record))

        for _ in 0 ..< 3 {
            _ = try sync()
            try clock.advanceBoth(seconds: TandemPumpManager.basalMismatchConfirmationInterval / 2, ticks: 2)
        }
        _ = try sync()
        let found = try waitForCorrections(4, since: before)

        assertCorrections(Array(found.prefix(4)), match: deliveries, stagedAt: stagedAt)
        XCTAssertTrue(found.prefix(4).allSatisfy { $0.dose?.automatic == false && $0.dose?.wasProgrammedByPumpUI == false })
        XCTAssertTrue(driver.manager.state.basalRateMismatchConfirmed, "the mismatch still shows")
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
        try append(deliveries.map(\.record))

        _ = try sync()
        let found = try waitForCorrections(2, since: before)
        assertCorrections(found, match: deliveries, stagedAt: stagedAt)
    }
}
