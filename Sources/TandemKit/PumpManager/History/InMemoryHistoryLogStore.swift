import Foundation

/// A `HistoryLogStore` that keeps everything in memory.
///
/// Used by unit tests and by any code path that wants the store's semantics without a file on disk
/// (for example the CLI, or a manager constructed before a storage directory is available). Nothing
/// survives process exit, and that is the shipping behaviour too: the pump-manager layer stays
/// storage-free (#232), so durable dose storage is the host app's job and only fetch bookkeeping
/// (`HistoryBackfillState`) is persisted, in `TandemPumpManagerState`.
public final class InMemoryHistoryLogStore: HistoryLogStore {
    private let lock = NSLock()
    /// pumpSerial -> sequenceNum -> entry
    private var entries: [UInt32: [UInt32: StoredHistoryLog]] = [:]
    /// pumpSerial -> retention watermark.
    private var prunedBelow: [UInt32: UInt32] = [:]

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
        in range: ClosedRange<UInt32>
    ) throws -> [StoredHistoryLog] {
        let wanted = Set(typeIds)
        return withLock {
            (entries[pumpSerial] ?? [:])
                .values
                .filter { wanted.contains($0.typeId) && range.contains($0.sequenceNum) }
                .sorted { $0.sequenceNum < $1.sequenceNum }
        }
    }

    public func lowestSequenceNum(pumpSerial: UInt32, receivedSince date: Date) throws -> UInt32? {
        withLock {
            (entries[pumpSerial] ?? [:])
                .values
                .filter { $0.receivedAt >= date }
                .map(\.sequenceNum)
                .min()
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
        withLock { prunedBelow[pumpSerial] }
    }

    @discardableResult
    public func prune(pumpSerial: UInt32, belowSequenceNum: UInt32) throws -> Int {
        withLock {
            guard var stored = entries[pumpSerial] else {
                return 0
            }

            let doomed = stored.keys.filter { $0 < belowSequenceNum }
            guard !doomed.isEmpty else {
                return 0
            }

            for sequenceNum in doomed {
                stored.removeValue(forKey: sequenceNum)
            }
            entries[pumpSerial] = stored
            prunedBelow[pumpSerial] = max(prunedBelow[pumpSerial] ?? 0, belowSequenceNum)
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
