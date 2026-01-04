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

    /// Convert pump timestamp to UTC accounting for recorded clock changes and the pump time zone.
    func utcDate(pumpTimeSec: UInt32, sequenceNum: UInt32, timeZone: TimeZone) -> Date {
        let adjustedPumpTimeSec = adjustedPumpTime(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum)
        let localDate = Date(timeIntervalSince1970: TimeInterval(adjustedPumpTimeSec))
        let offset = timeZone.secondsFromGMT(for: localDate)
        return Date(timeIntervalSince1970: TimeInterval(adjustedPumpTimeSec - offset))
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
