import LoopKit
@testable import TandemKit
import XCTest

final class BasalReconcilerTests: XCTestCase {
    private typealias PumpLog = PumpBasalHistory

    private func at(_ seconds: TimeInterval) -> Date {
        PumpBasalHistory.date(0).addingTimeInterval(seconds)
    }

    private func schedule(_ rate: Double = 1.0) -> HostBasalSchedule {
        HostBasalSchedule(BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: rate)])!)
    }

    // MARK: - What the host was told

    private func temp(_ rate: Double, at start: TimeInterval, minutes: Double = 30, endingAt end: TimeInterval? = nil) -> NewPumpEvent {
        let dose = UnfinalizedDose(tempRate: rate, duration: .minutes(minutes), automatic: true, insulinType: .novolog, startDate: at(start))
        let entry = dose.toDoseEntry(isMutable: end == nil, endDate: end.map(at), now: at(start))
        return NewPumpEvent.tempBasal(dose: entry, of: dose)
    }

    private func marker(_ rate: Double = 1.0, at start: TimeInterval) -> NewPumpEvent {
        let dose = UnfinalizedDose(basalRate: rate, insulinType: .novolog, startDate: at(start))
        return NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate)
    }

    private func suspend(at start: TimeInterval) -> NewPumpEvent {
        NewPumpEvent.suspend(dose: UnfinalizedDose(suspendStartTime: at(start)).toDoseEntry(), date: at(start))
    }

    private func resume(at start: TimeInterval) -> NewPumpEvent {
        NewPumpEvent.resume(dose: UnfinalizedDose(resumeStartTime: at(start), insulinType: .novolog).toDoseEntry(), date: at(start))
    }

    private static let serial = HistoryLogSyncIdentifier.PumpSerial(123_456)!

    /// A basal correction for the 279 `sequenceNum`, as the driver reports one.
    private func correction(for sequenceNum: UInt32, _ rate: Double, from start: TimeInterval, to end: TimeInterval) -> NewPumpEvent {
        let entry = DoseEntry(
            type: .tempBasal,
            startDate: at(start),
            endDate: at(end),
            value: rate,
            unit: .unitsPerHour,
            deliveredUnits: rate * (end - start) / .hours(1)
        )
        let raw = HistoryLogSyncIdentifier.logSequence(pumpSerial: Self.serial, sequenceNum: sequenceNum)
        return NewPumpEvent(date: at(start), dose: entry, raw: raw, title: "Control-IQ Basal")
    }

    private func told(_ batches: [NewPumpEvent]...) -> ReportedBasalLedger {
        var ledger = ReportedBasalLedger(trackingSince: .distantPast)
        ledger.track(pumpSerial: Self.serial.rawValue, after: nil)
        for batch in batches {
            ledger.record(batch, replacePendingEvents: false)
        }
        return ledger
    }

    // MARK: - Running it

    private func reconcile(
        _ log: PumpLog,
        _ ledger: ReportedBasalLedger,
        schedule: HostBasalSchedule? = nil,
        floor: Date = .distantPast,
        now: Date? = nil,
        isExempt: (PumpBasalTimeline.Chunk) -> Bool = { _ in false }
    ) -> BasalReconciler.Result {
        let dates = HistoryRecordDates(log.logs) { $0 }
        let timeline = PumpBasalTimeline(logs: log.logs, date: dates.phoneDate(of:), gaps: [], readThrough: .distantFuture)
        return BasalReconciler.reconcile(
            timeline,
            against: ledger,
            schedule: schedule ?? self.schedule(),
            floor: floor,
            now: now ?? at(.hours(24)),
            isExempt: isExempt
        )
    }

    private func differing(_ result: BasalReconciler.Result) -> [String] {
        result.differences.map { difference in
            "\(Int(difference.chunk.start.timeIntervalSince(at(0)))) \(difference.chunk.commandedRate) \(difference.host.rate)"
        }
    }

    /// The pump's 279s every 300 s from `from` up to `to`, each at what `rate` gives.
    private func cycles(_ log: inout PumpLog, from: Int, to: Int, source: Int = 1, rate: Int = 1000, profile: Int = 1000) {
        for seconds in stride(from: from, to: to, by: 300) {
            log.delivery(seconds, source: source, rate: rate, profile: profile)
        }
    }

    // MARK: - Nothing in normal use

    func testAppTempsAndCancelsMatch() {
        var log = PumpLog()
        log.profile(0)
        log.tempStarted(100, percent: 150, minutes: 30, id: 1)
        cycles(&log, from: 300, to: 1200, source: 2, rate: 1500)
        log.tempEnded(1000, id: 1, timeLeft: 900_000)
        cycles(&log, from: 1200, to: 1800)

        let ledger = told([temp(1.5, at: 100)], [temp(1.5, at: 100, endingAt: 1000), marker(at: 1000)])
        let result = reconcile(log, ledger)

        XCTAssertEqual(differing(result), [])
        XCTAssertEqual(result.matched, 6)
        XCTAssertEqual(result.residualByDay.values.reduce(0, +), (200 * 0.5 + 200 * 0.5) / 3600, accuracy: 1e-9, "the change at 100 and the cancel at 1000 each count 200 s early")
    }

    func testATempReplacedWithinACycleMatches() {
        var log = PumpLog()
        log.profile(0)
        log.profile(300)
        log.tempStarted(310, percent: 200, minutes: 30, id: 1)
        log.tempEnded(400, id: 1, timeLeft: 1_710_000)
        log.tempStarted(400, percent: 150, minutes: 30, id: 2)
        log.delivery(600, source: 2, rate: 1500)

        let ledger = told([temp(2.0, at: 310)], [temp(2.0, at: 310, endingAt: 400), temp(1.5, at: 400)])

        XCTAssertEqual(differing(reconcile(log, ledger)), [])
    }

    func testSkewCompensationMatchesWithinAPercentOfTheProfile() {
        var log = PumpLog()
        log.tempStarted(0, percent: 127, minutes: 60, id: 3)
        cycles(&log, from: 10, to: 1210, source: 2, rate: 2985, profile: 2350)

        XCTAssertEqual(differing(reconcile(log, told(), schedule: schedule(3.0))), [])
    }

    func testAChangeWithinAMinuteOfThe279Matches() {
        var log = PumpLog()
        log.tempStarted(0, percent: 150, minutes: 30, id: 1)
        log.delivery(300, source: 2, rate: 1500)
        log.delivery(600, source: 2, rate: 1500)

        XCTAssertEqual(differing(reconcile(log, told([temp(1.5, at: 330)]))), [])
        XCTAssertEqual(differing(reconcile(log, told([temp(1.5, at: 370)]))), ["300 1500 1.0"])
    }

    func testACommandJustBeforeThe279MatchesTheCorrectionBeforeIt() {
        var log = PumpLog()
        let first = log.delivery(0, source: 3, rate: 600)
        log.delivery(300, source: 3, rate: 600)

        let ledger = told([correction(for: first, 0.6, from: 0, to: 280), temp(2.0, at: 280)])

        XCTAssertEqual(differing(reconcile(log, ledger)), [])
    }

    func testARateWithin10mUPerHourMatches() {
        var close = PumpLog()
        close.profile(0, rate: 1009)
        var off = PumpLog()
        off.profile(0, rate: 1011)

        XCTAssertEqual(differing(reconcile(close, told())), [])
        XCTAssertEqual(differing(reconcile(off, told())), ["0 1011 1.0"])
    }

    func testAnExemptChunkIsSkipped() {
        var log = PumpLog()
        log.tempStarted(0, percent: 150, minutes: 30, id: 1)
        log.delivery(10, source: 2, rate: 1500)

        let result = reconcile(log, told([temp(2.0, at: 0)]), isExempt: { $0.kind == .temp })
        XCTAssertEqual(differing(result), [])
        XCTAssertEqual(result.skipped, 1)
    }

    func testARefusedSetAfterAStopMatchesOnceTheStopIsReported() {
        var log = PumpLog()
        log.tempStarted(0, percent: 150, minutes: 30, id: 1)
        cycles(&log, from: 10, to: 1000, source: 2, rate: 1500)
        log.tempEnded(1000, id: 1, timeLeft: 800_000)
        cycles(&log, from: 1210, to: 1800)

        let ledger = told([temp(1.5, at: 0)], [temp(1.5, at: 0, endingAt: 1000), marker(at: 1000)])

        XCTAssertEqual(differing(reconcile(log, ledger)), [])
    }

    // MARK: - What it finds

    func testControlIQChunksOffTheScheduleDiffer() {
        var log = PumpLog()
        log.delivery(0, source: 3, rate: 1000)
        log.delivery(300, source: 3, rate: 2200)
        log.delivery(600, source: 3, rate: 0)

        let result = reconcile(log, told())
        XCTAssertEqual(differing(result), ["300 2200 1.0", "600 0 1.0"])
        XCTAssertTrue(result.differences.allSatisfy { $0.host.source == .schedule })
    }

    func testACycleAfterACorrectionAtTheSameRateStillDiffers() {
        var log = PumpLog()
        let first = log.delivery(0, source: 3, rate: 2200)
        log.delivery(300, source: 3, rate: 2200)
        log.delivery(600, source: 3, rate: 2200)

        let ledger = told([correction(for: first, 2.2, from: 0, to: 300)])

        XCTAssertEqual(differing(reconcile(log, ledger)), ["300 2200 1.0", "600 2200 1.0"])
    }

    func testATempTheHostWasNeverToldOfDiffers() {
        var log = PumpLog()
        log.profile(0)
        log.tempStarted(100, percent: 150, minutes: 15, id: 12)
        cycles(&log, from: 300, to: 1200, source: 2, rate: 1500)
        log.tempEnded(1000, id: 12)
        log.profile(1200)

        XCTAssertEqual(differing(reconcile(log, told())), ["300 1500 1.0", "600 1500 1.0", "900 1500 1.0"])
    }

    func testATempTheHostEndedAtAnAlarmSuspendDiffersOnceItRunsAgain() {
        var log = PumpLog()
        log.tempStarted(0, percent: 150, minutes: 60, id: 8)
        log.delivery(10, source: 2, rate: 1500)
        log.suspended(400, reason: 1)
        log.delivery(610, source: 0, rate: 0)
        log.resumed(800)
        log.delivery(801, source: 2, rate: 1500)

        let ledger = told([temp(1.5, at: 0)], [temp(1.5, at: 0, endingAt: 400), suspend(at: 400)], [resume(at: 800)])
        let result = reconcile(log, ledger)

        XCTAssertEqual(differing(result), ["801 1500 1.0"])
        XCTAssertEqual(result.skipped, 1, "the suspended chunk")
    }

    func testAPumpProfileOffTheHostsScheduleDiffers() {
        var log = PumpLog()
        cycles(&log, from: 0, to: 900, rate: 1200, profile: 1200)

        XCTAssertEqual(differing(reconcile(log, told())).count, 3)
    }

    func testAHeldTempThePumpEndedDiffersFromTheHeldRow() {
        var log = PumpLog()
        log.tempStarted(0, percent: 150, minutes: 30, id: 5)
        log.delivery(10, source: 2, rate: 1500)
        log.tempEnded(200, id: 5, timeLeft: 1_600_000)
        log.profile(310)

        let result = reconcile(log, told([temp(1.5, at: 0)]))

        XCTAssertEqual(differing(result), ["310 1000 1.5"])
        guard case let .tempBasal(row)? = result.differences.first?.host.source else {
            return XCTFail("the host counts its held temp basal")
        }
        XCTAssertTrue(row.isMutable)
    }

    // MARK: - Skipped

    func testSuspendedTimeIsLeftToTheTransitionsPass() {
        var log = PumpLog()
        log.suspended(0)
        log.delivery(10, source: 0, rate: 0)
        log.resumed(400)
        log.profile(401)

        let ledger = told([suspend(at: 0)])
        let result = reconcile(log, ledger)

        XCTAssertEqual(differing(result), [])
        XCTAssertEqual(result.skipped, 2, "the pump's suspended chunk, and one the host still holds suspended")
    }

    func testChunksOutsideTheWindowAreSkipped() {
        var log = PumpLog()
        cycles(&log, from: 0, to: 1500, rate: 2000, profile: 2000)
        var ledger = ReportedBasalLedger(trackingSince: at(300))
        ledger.record([], replacePendingEvents: false)

        let result = reconcile(log, ledger, floor: at(600), now: at(1200))
        XCTAssertEqual(differing(result), ["600 2000 1.0", "900 2000 1.0"])
        XCTAssertEqual(result.skipped, 3)
    }

    func testA279WithACorrectionNeverDiffers() {
        var log = PumpLog()
        log.delivery(0, source: 3, rate: 1000)
        let corrected = log.delivery(300, source: 3, rate: 2200)

        // The host's marker in the 279's second put the correction a second after it.
        let ledger = told([marker(at: 300)], [correction(for: corrected, 2.2, from: 301, to: 600)])

        XCTAssertEqual(differing(reconcile(log, ledger)), [])
    }

    func testOnceCorrectedASecondRunFindsNothing() {
        var log = PumpLog()
        log.delivery(0, source: 3, rate: 2200)
        log.delivery(300, source: 3, rate: 400)

        var ledger = told()
        let first = reconcile(log, ledger)
        XCTAssertEqual(first.differences.count, 2)

        ledger.record(first.differences.map { difference in
            let chunk = difference.chunk
            let entry = DoseEntry(
                type: .tempBasal,
                startDate: chunk.start,
                endDate: chunk.end,
                value: chunk.unitsPerHour,
                unit: .unitsPerHour,
                deliveredUnits: chunk.units
            )
            return NewPumpEvent(date: chunk.start, dose: entry, raw: Data("\(chunk.sequenceNum)".utf8), title: "Control-IQ Basal")
        }, replacePendingEvents: false)

        XCTAssertEqual(differing(reconcile(log, ledger)), [])
    }
}
