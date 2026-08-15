import Foundation

/// A `HistoryLogStore` that keeps everything in memory.
///
/// Used by unit tests and by any code path that wants the store's semantics without a file on disk
/// (for example the CLI, or a manager constructed before a storage directory is available). Nothing
/// survives process exit — the shipping driver uses `CoreDataHistoryLogStore`.
public final class InMemoryHistoryLogStore: HistoryLogStore {
    private let lock = NSLock()
    /// pumpSerial -> sequenceNum -> entry
    private var entries: [UInt32: [UInt32: StoredHistoryLog]] = [:]
    /// pumpSerial -> retention watermark. Stored as Int64 so `highestPruned + 1` can't overflow.
    private var prunedBelow: [UInt32: Int64] = [:]

    public init() {}

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func insert(_ logs: [StoredHistoryLog]) throws {
        withLock {
            for log in logs where entries[log.pumpSerial]?[log.sequenceNum] == nil {
                entries[log.pumpSerial, default: [:]][log.sequenceNum] = log
            }
        }
    }

    public func count(pumpSerial: UInt32) throws -> Int {
        withLock { entries[pumpSerial]?.count ?? 0 }
    }

    public func sequenceNumbers(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [UInt32] {
        withLock {
            (entries[pumpSerial] ?? [:])
                .keys
                .filter { range.contains($0) }
                .sorted()
        }
    }

    public func logs(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [StoredHistoryLog] {
        withLock {
            (entries[pumpSerial] ?? [:])
                .values
                .filter { range.contains($0.sequenceNum) }
                .sorted { $0.sequenceNum < $1.sequenceNum }
        }
    }

    public func logs(
        pumpSerial: UInt32,
        ofTypes typeIds: [Int],
        sincePumpTimeSec: UInt32
    ) throws -> [StoredHistoryLog] {
        let wanted = Set(typeIds)
        return withLock {
            (entries[pumpSerial] ?? [:])
                .values
                .filter { wanted.contains($0.typeId) && $0.pumpTimeSec >= sincePumpTimeSec }
                .sorted { $0.sequenceNum < $1.sequenceNum }
        }
    }

    public func oldest(pumpSerial: UInt32) throws -> StoredHistoryLog? {
        withLock { (entries[pumpSerial] ?? [:]).values.min { $0.sequenceNum < $1.sequenceNum } }
    }

    public func newest(pumpSerial: UInt32) throws -> StoredHistoryLog? {
        withLock { (entries[pumpSerial] ?? [:]).values.max { $0.sequenceNum < $1.sequenceNum } }
    }

    public func newest(pumpSerial: UInt32, ofType typeId: Int) throws -> StoredHistoryLog? {
        withLock {
            (entries[pumpSerial] ?? [:])
                .values
                .filter { $0.typeId == typeId }
                .max { $0.sequenceNum < $1.sequenceNum }
        }
    }

    public func typeStats(pumpSerial: UInt32) throws -> [HistoryLogTypeStats] {
        withLock {
            Dictionary(grouping: (entries[pumpSerial] ?? [:]).values, by: \.typeId)
                .map { typeId, logs in
                    HistoryLogTypeStats(
                        typeId: typeId,
                        count: logs.count,
                        latestSequenceNum: logs.map(\.sequenceNum).max() ?? 0,
                        latestPumpTimeSec: logs.map(\.pumpTimeSec).max() ?? 0
                    )
                }
                .sorted { $0.typeId < $1.typeId }
        }
    }

    public func prunedBelowSequenceNum(pumpSerial: UInt32) throws -> UInt32? {
        withLock { prunedBelow[pumpSerial].map { UInt32(clamping: $0) } }
    }

    @discardableResult
    public func prune(pumpSerial: UInt32, beforePumpTimeSec: UInt32) throws -> Int {
        withLock {
            guard var stored = entries[pumpSerial] else {
                return 0
            }

            let doomed = stored.values.filter { $0.pumpTimeSec < beforePumpTimeSec }
            guard let highest = doomed.map(\.sequenceNum).max() else {
                return 0
            }

            for log in doomed {
                stored.removeValue(forKey: log.sequenceNum)
            }
            entries[pumpSerial] = stored

            let watermark = Int64(highest) + 1
            prunedBelow[pumpSerial] = max(prunedBelow[pumpSerial] ?? 0, watermark)
            return doomed.count
        }
    }

    public func deleteAll(pumpSerial: UInt32?) throws {
        withLock {
            if let pumpSerial {
                entries.removeValue(forKey: pumpSerial)
                prunedBelow.removeValue(forKey: pumpSerial)
            } else {
                entries.removeAll()
                prunedBelow.removeAll()
            }
        }
    }
}
