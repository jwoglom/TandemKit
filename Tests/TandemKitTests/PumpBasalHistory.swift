import Foundation
@testable import TandemKit

/// Pump history records in the order the pump writes them, `seconds` after `origin` on the pump's clock.
struct PumpBasalHistory {
    /// 00:10 on the pump's clock, so the phone's calendar puts `date(0)` ten minutes into a day.
    static let origin: UInt32 = 590_026_200

    static func date(_ seconds: Int) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(origin) + TimeInterval(seconds))
    }

    private(set) var logs: [HistoryLog] = []
    private var sequenceNum: UInt32 = 1000

    private mutating func next() -> UInt32 {
        sequenceNum += 1
        return sequenceNum
    }

    @discardableResult
    mutating func delivery(_ seconds: Int, source: Int, rate: Int, profile: Int = 1000) -> UInt32 {
        let log = BasalDeliveryHistoryLog(
            pumpTimeSec: Self.origin + UInt32(seconds),
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
            pumpTimeSec: Self.origin + UInt32(seconds),
            sequenceNum: next(),
            percent: percent,
            durationMilliseconds: minutes * 60_000,
            tempRateId: id
        ))
    }

    mutating func tempEnded(_ seconds: Int, id: Int, timeLeft: UInt32 = 0) {
        logs.append(TempRateCompletedHistoryLog(pumpTimeSec: Self.origin + UInt32(seconds), sequenceNum: next(), tempRateId: id, timeLeft: timeLeft))
    }

    mutating func suspended(_ seconds: Int, reason: Int = 0) {
        logs.append(PumpingSuspendedHistoryLog(
            pumpTimeSec: Self.origin + UInt32(seconds),
            sequenceNum: next(),
            preSuspendState: 0,
            insulinAmount: 0,
            reasonId: reason,
            rpaTimeout: 0
        ))
    }

    mutating func resumed(_ seconds: Int) {
        logs.append(PumpingResumedHistoryLog(pumpTimeSec: Self.origin + UInt32(seconds), sequenceNum: next(), preResumeState: 0, insulinAmount: 0))
    }

    mutating func pcm(_ seconds: Int, _ pcm: ControlIQPcmChangeHistoryLog.PCM) {
        logs.append(ControlIQPcmChangeHistoryLog(
            pumpTimeSec: Self.origin + UInt32(seconds),
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
            pumpTimeSec: Self.origin + UInt32(seconds),
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
        logs.append(BolusActivatedHistoryLog(pumpTimeSec: Self.origin + UInt32(seconds), sequenceNum: next(), bolusId: 9, selectedIob: 0, iob: 0, bolusSize: 1))
    }

    mutating func other(_ seconds: Int) {
        logs.append(AlarmClearedHistoryLog(pumpTimeSec: Self.origin + UInt32(seconds), sequenceNum: next(), alarmId: 1))
    }

    mutating func timeChanged(_ seconds: Int, by delta: Int) {
        logs.append(TimeChangedHistoryLog(
            pumpTimeSec: Self.origin + UInt32(seconds),
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
