import Foundation

/// Feeds the session `historyLogStore` from the history log stream and applies retention.
extension TandemPumpManager {
    /// How often `storeHistoryLogs` re-applies the retention policy. Retention exists to bound
    /// the store's memory across a long-lived session; checking it more than hourly buys nothing.
    static let historyLogPruneInterval: TimeInterval = .hours(1)

    /// The serial the store is keyed by, validated the same way identifiers are: nil until a
    /// `PumpVersionResponse` has populated `PumpState.pumpSerial`. Logs that stream in before
    /// then are not stored — an entry filed under a placeholder serial would be invisible to
    /// every query made once the real serial is known.
    var historyLogStoreSerial: HistoryLogSyncIdentifier.PumpSerial? {
        HistoryLogSyncIdentifier.PumpSerial(state.pumpState.pumpSerial)
    }

    /// Inserts streamed logs into the session store (idempotently — re-streamed chunks are
    /// ignored by contract) and opportunistically applies retention.
    func storeHistoryLogs(_ logs: [HistoryLog], now: Date? = nil) {
        let now = now ?? self.now
        guard !logs.isEmpty, let serial = historyLogStoreSerial else {
            return
        }

        do {
            try historyLogStore.insert(logs, pumpSerial: serial.rawValue, receivedAt: now)
        } catch {
            logger.error("Failed to store \(logs.count) history logs: \(error)")
        }

        pruneHistoryLogStoreIfNeeded(now: now)
    }

    /// Applies the retention policy at most once per `historyLogPruneInterval`. Piggybacked on
    /// the insert path rather than a timer: a store that nothing feeds can't grow, so there is
    /// nothing to prune between inserts.
    func pruneHistoryLogStoreIfNeeded(now: Date? = nil) {
        let now = now ?? self.now
        guard let serial = historyLogStoreSerial else {
            return
        }

        historyLogPruneLock.lock()
        if let last = lastHistoryLogPruneAt, now.timeIntervalSince(last) < Self.historyLogPruneInterval {
            historyLogPruneLock.unlock()
            return
        }
        lastHistoryLogPruneAt = now
        historyLogPruneLock.unlock()

        do {
            let pruned = try historyLogStore.pruneExpired(pumpSerial: serial.rawValue, now: now)
            if pruned > 0 {
                logger.info("Pruned \(pruned) expired history logs from the session store")
            }
        } catch {
            logger.error("Failed to prune history log store: \(error)")
        }
    }
}
