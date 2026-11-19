import Foundation

/// Per-type rollup of what the store holds for a pump. Mirrors ControlX2's `HistoryLogTypeStats`.
public struct HistoryLogTypeStats: Equatable {
    public let typeId: Int
    public let count: Int
    public let latestSequenceNum: UInt32
    public let latestPumpTimeSec: UInt32

    public init(typeId: Int, count: Int, latestSequenceNum: UInt32, latestPumpTimeSec: UInt32) {
        self.typeId = typeId
        self.count = count
        self.latestSequenceNum = latestSequenceNum
        self.latestPumpTimeSec = latestPumpTimeSec
    }
}

public enum HistoryLogStoreError: Error {
    /// The backing store could not be opened (bad directory, unreadable file, failed migration).
    case storeUnavailable(Error)
    /// A read or write against an opened store failed.
    case persistenceFailed(Error)
}

public enum HistoryLogRetention {
    /// How long the store keeps what it was given before `pruneExpired` removes it.
    ///
    /// 90 days covers the pump's own history depth for reporting and export purposes while keeping
    /// the SQLite file to a few tens of MB. Dose reconciliation only ever looks back hours, so this
    /// bound is about the history viewer and diagnostics, not about insulin accounting.
    public static let `default`: TimeInterval = .days(90)
}

/// A local database of raw pump history log entries.
///
/// This is the driver's own record of what it has read off the pump, distinct from the dose events
/// handed to the host app via `hasNewPumpEvents`. LoopKit does not provide plugin-facing storage:
/// `DoseStore` purges pump events outside the app's cache window (24 h by default) and is keyed by
/// date rather than pump sequence number, and under Trio it isn't used at all. Keeping the raw log
/// here means fetch bookkeeping (which sequence numbers do we already have?) survives relaunches,
/// and dose derivation can be re-run without going back to the pump.
///
/// Implementations must be safe to call from any thread. All methods are synchronous and may block;
/// call them off the BLE command queue.
public protocol HistoryLogStore: AnyObject {
    /// Insert entries, ignoring any whose `(pumpSerial, sequenceNum)` is already stored.
    ///
    /// Idempotent by contract, matching ControlX2's `onConflict = IGNORE`: re-inserting a sequence
    /// number keeps the row already present rather than overwriting it. Callers may therefore
    /// re-deliver overlapping chunks freely.
    func insert(_ logs: [StoredHistoryLog]) throws

    /// Number of entries stored for a pump.
    func count(pumpSerial: UInt32) throws -> Int

    /// Sequence numbers present within `range`, ascending.
    func sequenceNumbers(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [UInt32]

    /// Sequence ranges within `range` that are not stored and have not been pruned — the work list
    /// for a gap-healing fetch. See the default implementation.
    func missingRanges(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [ClosedRange<UInt32>]

    /// Entries within `range`, ordered by sequence number ascending.
    func logs(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [StoredHistoryLog]

    /// Entries of the given types within `range`, ordered by sequence number ascending. No query takes a
    /// pump time: a stamp is on whatever clock the pump ran then, so records are dated (`HistoryRecordDates`).
    func logs(pumpSerial: UInt32, ofTypes typeIds: [Int], in range: ClosedRange<UInt32>) throws -> [StoredHistoryLog]

    /// Lowest sequence number among entries this driver stored at or after `date`, on the phone's clock.
    func lowestSequenceNum(pumpSerial: UInt32, receivedSince date: Date) throws -> UInt32?

    /// Lowest-sequence entry stored for a pump.
    func oldest(pumpSerial: UInt32) throws -> StoredHistoryLog?

    /// Highest-sequence entry stored for a pump — the resume point for an incremental fetch.
    func newest(pumpSerial: UInt32) throws -> StoredHistoryLog?

    /// Highest-sequence entry of a given type.
    func newest(pumpSerial: UInt32, ofType typeId: Int) throws -> StoredHistoryLog?

    /// Per-type counts and latest entry, for the history viewer and diagnostics.
    func typeStats(pumpSerial: UInt32) throws -> [HistoryLogTypeStats]

    /// Retention watermark: every sequence number strictly below this value has been pruned, so a
    /// gap there is expected and must not trigger a re-fetch. `nil` when nothing has been pruned.
    func prunedBelowSequenceNum(pumpSerial: UInt32) throws -> UInt32?

    /// Delete every entry below `belowSequenceNum` and advance the retention watermark to it.
    /// - Returns: the number of entries deleted.
    @discardableResult
    func prune(pumpSerial: UInt32, belowSequenceNum: UInt32) throws -> Int

    /// Delete everything for one pump, or for every pump when `pumpSerial` is nil. Also clears the
    /// retention watermark, so a subsequent fetch treats the pump as never read.
    func deleteAll(pumpSerial: UInt32?) throws
}

public extension HistoryLogStore {
    /// Convenience for the fetch path, which works in `HistoryLog` objects.
    func insert(_ logs: [HistoryLog], pumpSerial: UInt32, receivedAt: Date = Date()) throws {
        try insert(logs.map { StoredHistoryLog(log: $0, pumpSerial: pumpSerial, receivedAt: receivedAt) })
    }

    /// Default gap detection: everything in `range` that is neither stored nor below the retention
    /// watermark. Port of ControlX2's `getMissingIds()`, with the watermark clamp added so pruned
    /// history isn't mistaken for a hole and fetched forever.
    ///
    /// A store with a cheaper query for this may override it.
    func missingRanges(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [ClosedRange<UInt32>] {
        var lowerBound = range.lowerBound
        if let prunedBelow = try prunedBelowSequenceNum(pumpSerial: pumpSerial) {
            lowerBound = max(lowerBound, prunedBelow)
        }
        guard lowerBound <= range.upperBound else {
            return []
        }

        let clamped = lowerBound ... range.upperBound
        let present = try sequenceNumbers(pumpSerial: pumpSerial, in: clamped)
        return HistoryLogSequenceGaps.missingRanges(present: present, in: clamped)
    }

    /// Deletes everything below the oldest entry stored within `retention`. By when it was stored, since a
    /// stamp after a clock reset reads years old; by sequence number, so the watermark claims nothing kept.
    @discardableResult
    func pruneExpired(
        pumpSerial: UInt32,
        retention: TimeInterval = HistoryLogRetention.default,
        now: Date = Date()
    ) throws -> Int {
        let keepFrom = try lowestSequenceNum(pumpSerial: pumpSerial, receivedSince: now.addingTimeInterval(-retention))
            ?? newest(pumpSerial: pumpSerial)?.sequenceNum
        guard let keepFrom else {
            return 0
        }
        return try prune(pumpSerial: pumpSerial, belowSequenceNum: keepFrom)
    }
}

/// Pure sequence-gap arithmetic, shared by every `HistoryLogStore` implementation.
enum HistoryLogSequenceGaps {
    /// Ranges within `range` that are absent from `present`.
    /// - Parameter present: sequence numbers known to be stored. Order and duplicates don't matter.
    static func missingRanges(present: [UInt32], in range: ClosedRange<UInt32>) -> [ClosedRange<UInt32>] {
        let sorted = Set(present.filter { range.contains($0) }).sorted()
        guard let first = sorted.first else {
            return [range]
        }

        var missing: [ClosedRange<UInt32>] = []

        // Gap below the first stored sequence. `first > lowerBound` implies `first >= 1`.
        if first > range.lowerBound {
            missing.append(range.lowerBound ... (first - 1))
        }

        var previous = first
        for current in sorted.dropFirst() {
            if current > previous + 1 {
                missing.append((previous + 1) ... (current - 1))
            }
            previous = current
        }

        // Gap above the last stored sequence. `previous < upperBound` keeps `previous + 1` in range.
        if previous < range.upperBound {
            missing.append((previous + 1) ... range.upperBound)
        }

        return missing
    }
}
