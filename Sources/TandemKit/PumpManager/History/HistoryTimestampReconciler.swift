import Foundation
import TandemCore

/// Tracks clock-change deltas and converts pump timestamps to UTC.
class HistoryTimestampReconciler {
    private var clockChangeDeltas: [(sequenceNum: UInt32, deltaSec: Int)] = []
    private var lastAdjustedPumpTimeSec: Int?

    /// Add a clock change event from DateChangeHistoryLog or TimeChangedHistoryLog.
    func recordClockChange(at sequenceNum: UInt32, deltaSec: Int) {
        clockChangeDeltas.append((sequenceNum, deltaSec))
        clockChangeDeltas.sort { $0.sequenceNum < $1.sequenceNum }
    }

    /// Convert a pump timestamp to a UTC `Date`, accounting for recorded clock changes.
    ///
    /// `Dates.fromJan12008EpochSecondsToDate` already converts the pump's local-wall-clock
    /// seconds (Tandem 2008 epoch) into a correct UTC instant — it subtracts the device's
    /// UTC offset internally — and is the same conversion the rest of TandemKit uses
    /// (e.g. `LastBolusStatus.timestampDate`). We therefore must NOT subtract the offset a
    /// second time; the previous implementation did, producing timestamps off by one UTC
    /// offset (e.g. ~4–5 h in US Eastern). `timeZone` is retained in the signature for a
    /// future refinement where the pump's timezone differs from the device's; today the
    /// pump clock is kept in sync with the device, so the shared helper is correct.
    func utcDate(pumpTimeSec: UInt32, sequenceNum: UInt32, timeZone _: TimeZone) -> Date {
        let adjustedPumpTimeSec = adjustedPumpTime(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        return Dates.fromJan12008EpochSecondsToDate(TimeInterval(adjustedPumpTimeSec))
    }

    /// Detect large forward jumps that invalidate chronological ordering (> 24 hours).
    func isValidTimestamp(_ pumpTimeSec: UInt32, sequenceNum: UInt32) -> Bool {
        let adjustedPumpTimeSec = adjustedPumpTime(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)

        if let lastAdjustedPumpTimeSec {
            if adjustedPumpTimeSec - lastAdjustedPumpTimeSec > 86400 {
                return false
            }
        }

        lastAdjustedPumpTimeSec = adjustedPumpTimeSec
        return true
    }

    private func adjustedPumpTime(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Int {
        let cumulativeDelta = clockChangeDeltas
            .filter { $0.sequenceNum < sequenceNum }
            .reduce(0) { $0 + $1.deltaSec }
        return Int(pumpTimeSec) + cumulativeDelta
    }
}
