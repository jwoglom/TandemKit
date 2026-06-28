import Foundation

/// Tracks seen history log sequence numbers to prevent duplicate processing across fetches.
class HistoryDeduplicator {
    private var seenSequenceNumbers = Set<UInt32>()

    /// Check if a sequence number has been processed previously.
    func isSeen(_ sequenceNum: UInt32) -> Bool {
        seenSequenceNumbers.contains(sequenceNum)
    }

    /// Mark a sequence number as processed.
    func markSeen(_ sequenceNum: UInt32) {
        seenSequenceNumbers.insert(sequenceNum)
    }

    /// Filter a list of HistoryLog entries to only those not seen before.
    func filterUnseen(_ logs: [HistoryLog]) -> [HistoryLog] {
        logs.filter { log in
            let unseen = !seenSequenceNumbers.contains(log.sequenceNum)
            if unseen {
                seenSequenceNumbers.insert(log.sequenceNum)
            }
            return unseen
        }
    }

    /// Persist the seen sequence numbers to disk for cross-session deduplication.
    func persist(to url: URL) throws {
        let payload = Array(seenSequenceNumbers)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }

    /// Restore seen sequence numbers from disk.
    func restore(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode([UInt32].self, from: data)
        seenSequenceNumbers = Set(payload)
    }
}
