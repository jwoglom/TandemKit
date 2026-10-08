@testable import TandemKit
import XCTest

final class PumpBasalTimelineTests: XCTestCase {
    private static let origin: UInt32 = 590_000_000

    /// Records in the order the pump writes them, `seconds` after `origin` on the pump's clock.
    private struct PumpLog {
        private(set) var logs: [HistoryLog] = []
        private var sequenceNum: UInt32 = 1000

        private mutating func next() -> UInt32 {
            sequenceNum += 1
            return sequenceNum
        }

        @discardableResult
        mutating func delivery(_ seconds: Int, source: Int, rate: Int, profile: Int = 1000) -> UInt32 {
            let log = BasalDeliveryHistoryLog(
                pumpTimeSec: origin + UInt32(seconds),
                sequenceNum: next(),
                commandedRateSource: source,
                commandedRate: rate,
                profileBasalRate: profile,
                algorithmRate: source >= 3 ? rate : 0,
                tempRate: source == 2 ? rate : 0
            )
            logs.append(log)
            return log.sequenceNum
        }

        mutating func profile(_ seconds: Int, rate: Int = 1000) {
            delivery(seconds, source: 1, rate: rate, profile: rate)
        }

        mutating func tempStarted(_ seconds: Int, percent: Float, minutes: Float, id: Int) {
            logs.append(TempRateActivatedHistoryLog(
                pumpTimeSec: origin + UInt32(seconds),
                sequenceNum: next(),
                percent: percent,
                durationMilliseconds: minutes * 60_000,
                tempRateId: id
            ))
        }

        mutating func tempEnded(_ seconds: Int, id: Int, timeLeft: UInt32 = 0) {
            logs.append(TempRateCompletedHistoryLog(pumpTimeSec: origin + UInt32(seconds), sequenceNum: next(), tempRateId: id, timeLeft: timeLeft))
        }

        mutating func suspended(_ seconds: Int, reason: Int = 0) {
            logs.append(PumpingSuspendedHistoryLog(
                pumpTimeSec: origin + UInt32(seconds),
                sequenceNum: next(),
                preSuspendState: 0,
                insulinAmount: 0,
                reasonId: reason,
                rpaTimeout: 0
            ))
        }

        mutating func resumed(_ seconds: Int) {
            logs.append(PumpingResumedHistoryLog(pumpTimeSec: origin + UInt32(seconds), sequenceNum: next(), preResumeState: 0, insulinAmount: 0))
        }

        mutating func pcm(_ seconds: Int, _ pcm: ControlIQPcmChangeHistoryLog.PCM) {
            logs.append(ControlIQPcmChangeHistoryLog(
                pumpTimeSec: origin + UInt32(seconds),
                sequenceNum: next(),
                currentPcm: pcm.rawValue,
                previousPcm: 0,
                pumpSuspended: 0,
                calculationAvailable: 1,
                cgmAvailable: 1,
                closedLoopPreferred: 1,
                sufficientClosedLoopParams: 1
            ))
        }

        mutating func dailyBasal(_ seconds: Int, total: Float) {
            logs.append(DailyBasalHistoryLog(
                pumpTimeSec: origin + UInt32(seconds),
                sequenceNum: next(),
                dailyTotalBasal: total,
                lastBasalRate: 0,
                iob: 0,
                finalEventForDay: false,
                batteryChargeRaw: 80,
                lipoMv: 0
            ))
        }

        mutating func bolusStarted(_ seconds: Int) {
            logs.append(BolusActivatedHistoryLog(pumpTimeSec: origin + UInt32(seconds), sequenceNum: next(), bolusId: 9, selectedIob: 0, iob: 0, bolusSize: 1))
        }

        mutating func other(_ seconds: Int) {
            logs.append(AlarmClearedHistoryLog(pumpTimeSec: origin + UInt32(seconds), sequenceNum: next(), alarmId: 1))
        }

        mutating func timeChanged(_ seconds: Int, by delta: Int) {
            logs.append(TimeChangedHistoryLog(
                pumpTimeSec: origin + UInt32(seconds),
                sequenceNum: next(),
                timePrior: 0,
                timeAfter: UInt32(delta * 1000),
                rawRTC: 0
            ))
        }

        /// Drops the record with this sequence number, as a gap in the store.
        mutating func lose(_ sequenceNum: UInt32) {
            logs.removeAll { $0.sequenceNum == sequenceNum }
        }
    }

    private static func date(_ seconds: Int) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(origin) + TimeInterval(seconds))
    }

    private func timeline(
        _ log: PumpLog,
        gaps: [ClosedRange<UInt32>] = [],
        readThrough: Date? = .distantFuture,
        hostDate: @escaping (Date) -> Date = { $0 }
    ) -> PumpBasalTimeline {
        let dates = HistoryRecordDates(log.logs, hostDate: hostDate)
        return PumpBasalTimeline(logs: log.logs, date: dates.phoneDate(of:), gaps: gaps, readThrough: readThrough)
    }

    private func spans(_ timeline: PumpBasalTimeline) -> [String] {
        timeline.chunks.map { chunk in
            let start = Int(chunk.start.timeIntervalSince(Self.date(0)))
            let end = Int(chunk.end.timeIntervalSince(Self.date(0)))
            return "\(start)-\(end) \(chunk.kind) \(chunk.commandedRate)"
        }
    }

    // MARK: - Chunks

    func testEach279DeliversAFiveMinuteChunkOfItsKind() {
        var log = PumpLog()
        log.profile(0)
        log.tempStarted(100, percent: 150, minutes: 30, id: 3)
        log.delivery(300, source: 2, rate: 1500)
        log.delivery(600, source: 3, rate: 2200)
        log.suspended(700)
        log.delivery(900, source: 0, rate: 0)

        let timeline = timeline(log)

        XCTAssertEqual(spans(timeline), ["0-300 profile 1000", "300-600 temp 1500", "600-700 algorithm 2200", "900-1200 suspended 0"])
        XCTAssertEqual(timeline.chunks.map(\.tempRateId), [nil, 3, nil, nil])
        XCTAssertEqual(timeline.chunks[1].units, 0.125, accuracy: 1e-9)
        XCTAssertTrue(timeline.chunks[2].endsAtSuspend)
    }

    func testA279WrittenLateLeavesTheTimeBeforeItUncovered() {
        var log = PumpLog()
        log.profile(0)
        log.profile(540)
        log.profile(840)

        XCTAssertEqual(spans(timeline(log)), ["0-300 profile 1000", "540-840 profile 1000", "840-1140 profile 1000"])
    }

    func testACycleWithout279HasNoChunk() {
        var log = PumpLog()
        log.profile(0)
        log.other(450)
        log.profile(600)

        XCTAssertEqual(spans(timeline(log)), ["0-300 profile 1000", "600-900 profile 1000"])
    }

    func testAResumeAfterASuspendedCycleRestartsTheCadence() {
        var log = PumpLog()
        log.profile(0)
        log.suspended(100)
        log.delivery(300, source: 0, rate: 0)
        log.resumed(420)
        log.profile(421)
        log.profile(721)

        XCTAssertEqual(spans(timeline(log)), ["0-100 profile 1000", "300-421 suspended 0", "421-721 profile 1000", "721-1021 profile 1000"])
    }

    func testAResumeInsideTheSuspendsCycleWritesNo279AndDeliversNothingUntilTheNext() {
        var log = PumpLog()
        log.profile(0)
        log.suspended(100)
        log.resumed(200)
        log.profile(300)

        XCTAssertEqual(spans(timeline(log)), ["0-100 profile 1000", "300-600 profile 1000"])
    }

    func testTheTopChunkClosesOnlyOnceTheLogIsRead300sPastIt() {
        var log = PumpLog()
        log.profile(0)
        log.profile(300)

        XCTAssertEqual(spans(timeline(log, readThrough: nil)), ["0-300 profile 1000"])
        XCTAssertEqual(spans(timeline(log, readThrough: Self.date(599))), ["0-300 profile 1000"])
        XCTAssertEqual(spans(timeline(log, readThrough: Self.date(600))), ["0-300 profile 1000", "300-600 profile 1000"])
    }

    func testARecordPastTheChunkClosesItWithoutTheNext279() {
        var log = PumpLog()
        log.profile(0)
        log.other(310)

        XCTAssertEqual(spans(timeline(log, readThrough: nil)), ["0-300 profile 1000"])
    }

    func testAStoreGapInsideAChunkLeavesItOpen() {
        var log = PumpLog()
        log.profile(0)
        log.other(100)
        log.other(200)
        log.profile(300)
        log.profile(600)
        log.lose(1002)

        XCTAssertEqual(spans(timeline(log, gaps: [1002 ... 1002])), ["300-600 profile 1000", "600-900 profile 1000"])
    }

    func testAStoreGapPastAChunksEndDoesNotHoldItOpen() {
        var log = PumpLog()
        log.profile(0)
        log.other(310)
        log.other(320)
        log.profile(600)
        log.lose(1003)

        XCTAssertEqual(spans(timeline(log, gaps: [1003 ... 1003])), ["0-300 profile 1000", "600-900 profile 1000"])
    }

    func testA279WithoutARateHasNoChunk() {
        var log = PumpLog()
        log.profile(0)
        log.delivery(300, source: 1, rate: PumpBasalTimeline.notAvailable)
        log.profile(600)

        XCTAssertEqual(spans(timeline(log)), ["0-300 profile 1000", "600-900 profile 1000"])
    }

    // MARK: - Dates

    func testChunksAreOnThePhonesClock() {
        var log = PumpLog()
        log.profile(0)
        log.profile(300)
        log.timeChanged(400, by: 3600)
        log.profile(4200)

        let timeline = timeline(log) { $0.addingTimeInterval(-.hours(2)) }

        XCTAssertEqual(timeline.chunks.map(\.start), [
            Self.date(3600 - 7200),
            Self.date(300 + 3600 - 7200),
            Self.date(4200 - 7200)
        ])
    }

    // MARK: - Cross-check

    private func trusted(_ timeline: PumpBasalTimeline) -> [Bool] {
        timeline.chunks.map(\.isTrusted)
    }

    func testATempChunkAtExactlyItsPercentOfTheProfilePasses() {
        var log = PumpLog()
        log.profile(0, rate: 850)
        log.tempStarted(100, percent: 37, minutes: 30, id: 4)
        log.delivery(300, source: 2, rate: 315, profile: 850)
        log.delivery(600, source: 2, rate: 315, profile: 850)
        log.tempEnded(650, id: 4, timeLeft: 1_450_000)
        log.profile(900, rate: 850)

        let timeline = timeline(log)
        XCTAssertEqual(trusted(timeline), [true, true, true, true])
        XCTAssertTrue(timeline.problems.isEmpty, "\(timeline.problems)")
    }

    func testATempAtTheWrongRateFailsWithItsNeighbours() {
        var log = PumpLog()
        log.profile(0)
        log.profile(300)
        log.tempStarted(400, percent: 150, minutes: 30, id: 5)
        log.delivery(600, source: 2, rate: 1600)
        log.delivery(900, source: 2, rate: 1500)
        log.delivery(1200, source: 2, rate: 1500)

        XCTAssertEqual(trusted(timeline(log)), [true, false, false, false, true])
    }

    func testAStopAndSetInA279sSecondPassesEitherWay() {
        var log = PumpLog()
        log.profile(0)
        log.tempStarted(100, percent: 150, minutes: 30, id: 6)
        log.delivery(300, source: 2, rate: 1500)
        log.delivery(600, source: 2, rate: 2000)
        log.tempEnded(600, id: 6, timeLeft: 1_200_000)
        log.tempStarted(600, percent: 200, minutes: 30, id: 7)
        log.delivery(900, source: 2, rate: 2000)

        XCTAssertEqual(trusted(timeline(log)), [true, true, true, true])
    }

    func testATempResumedAfterAnAlarmSuspendPasses() {
        var log = PumpLog()
        log.profile(0)
        log.tempStarted(100, percent: 150, minutes: 60, id: 8)
        log.delivery(300, source: 2, rate: 1500)
        log.suspended(400, reason: 1)
        log.delivery(600, source: 0, rate: 0)
        log.resumed(800)
        log.delivery(801, source: 2, rate: 1500)
        log.delivery(1101, source: 2, rate: 1500)

        let timeline = timeline(log)
        XCTAssertEqual(trusted(timeline), [true, true, true, true, true])
        XCTAssertEqual(timeline.chunks.last?.tempRateId, 8)
    }

    func testATempPastItsDurationIsExpectedToHaveEnded() {
        var log = PumpLog()
        log.profile(0)
        log.tempStarted(100, percent: 150, minutes: 10, id: 9)
        log.delivery(300, source: 2, rate: 1500)
        log.delivery(600, source: 2, rate: 1500)
        log.delivery(900, source: 2, rate: 1500)
        log.profile(1200)
        log.profile(1500)

        XCTAssertEqual(trusted(timeline(log)), [true, true, false, false, false, true], "ran out at 700")
    }

    func testAControlIQChunkFailsUnderOpenLoopOrNoControl() {
        for (pcm, passes) in [(ControlIQPcmChangeHistoryLog.PCM.closedLoop, true), (.cgmInactive, true), (.openLoop, false), (.noControl, false)] {
            var log = PumpLog()
            log.pcm(0, pcm)
            log.delivery(10, source: 3, rate: 2200)

            let timeline = timeline(log)
            XCTAssertEqual(trusted(timeline), [passes], "PCM \(pcm)")
        }
    }

    func testAProfileChunkWhileControlIQRunsWithoutACGMPasses() {
        var log = PumpLog()
        log.pcm(0, .closedLoop)
        log.delivery(10, source: 3, rate: 2200)
        log.pcm(200, .cgmInactive)
        log.profile(310)

        XCTAssertEqual(trusted(timeline(log)), [true, true])
    }

    // MARK: - DailyBasal

    func testAStretchMatchingDailyBasalLeavesItsChunksTrusted() {
        var log = PumpLog()
        log.profile(0)
        log.dailyBasal(100, total: 1)
        for cycle in 1 ... 13 {
            log.profile(cycle * 300)
        }
        log.dailyBasal(13 * 300 + 100, total: 2.0833333)

        let timeline = timeline(log)
        XCTAssertTrue(timeline.chunks.allSatisfy(\.isTrusted))
        XCTAssertTrue(timeline.problems.isEmpty, "\(timeline.problems)")
    }

    func testAStretchThatDisagreesWithDailyBasalIsNotTrusted() {
        var log = PumpLog()
        log.profile(0)
        log.dailyBasal(100, total: 1)
        for cycle in 1 ... 13 {
            log.profile(cycle * 300)
        }
        log.dailyBasal(13 * 300 + 100, total: 2.1)
        log.profile(14 * 300)

        let timeline = timeline(log)
        XCTAssertEqual(trusted(timeline), [true] + Array(repeating: false, count: 13) + [true])
        XCTAssertEqual(timeline.problems.count, 1)
    }

    func testAShortCycleAfterABolusMayFallShort() {
        var log = PumpLog()
        log.profile(0)
        log.dailyBasal(100, total: 1)
        for cycle in 1 ... 13 {
            log.profile(cycle * 300)
            if cycle == 5 {
                log.bolusStarted(cycle * 300 + 10)
            }
        }
        log.dailyBasal(13 * 300 + 100, total: 2.05)

        XCTAssertTrue(timeline(log).chunks.allSatisfy(\.isTrusted))
    }

    func testAShortfallWithoutAnInterruptionFails() {
        var log = PumpLog()
        log.profile(0)
        log.dailyBasal(100, total: 1)
        for cycle in 1 ... 13 {
            log.profile(cycle * 300)
        }
        log.dailyBasal(13 * 300 + 100, total: 2.05)

        XCTAssertFalse(timeline(log).chunks.allSatisfy(\.isTrusted))
    }

    func testAChunkCutBySuspendCountsItsFullCycle() {
        var log = PumpLog()
        log.profile(0)
        log.dailyBasal(100, total: 1)
        for cycle in 1 ... 12 {
            log.profile(cycle * 300)
        }
        log.suspended(13 * 300 - 200)
        log.delivery(13 * 300, source: 0, rate: 0)
        log.dailyBasal(13 * 300 + 100, total: 2)

        XCTAssertTrue(timeline(log).chunks.allSatisfy(\.isTrusted))
    }

    func testADailyBasalTooSoonAfterA279IsNotUsed() {
        var log = PumpLog()
        log.profile(0)
        log.dailyBasal(100, total: 1)
        for cycle in 1 ... 13 {
            log.profile(cycle * 300)
        }
        log.dailyBasal(13 * 300 + 30, total: 5)

        let timeline = timeline(log)
        XCTAssertTrue(timeline.chunks.allSatisfy(\.isTrusted))
        XCTAssertTrue(timeline.problems.isEmpty)
    }

    func testAStretchShorterThanAnHourIsNotChecked() {
        var log = PumpLog()
        log.profile(0)
        log.dailyBasal(100, total: 1)
        for cycle in 1 ... 6 {
            log.profile(cycle * 300)
        }
        log.dailyBasal(6 * 300 + 100, total: 5)

        XCTAssertTrue(timeline(log).chunks.allSatisfy(\.isTrusted))
    }
}
