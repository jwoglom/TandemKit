import Foundation

/// Tracks fetched history log ranges and identifies gaps.
/// Ported from ControlX2's gap detection algorithm.
internal final class HistoryRangeTracker {
    private var fetchedRanges: [FetchedRange] = []

    internal init() {}

    /// Initialize with existing fetched ranges.
    internal init(fetchedRanges: [FetchedRange]) {
        self.fetchedRanges = fetchedRanges
        self.mergeOverlappingRanges()
    }

    /// Record a newly fetched range of sequence numbers.
    internal func recordFetched(start: UInt32, end: UInt32) {
        let newRange = FetchedRange(start: start, end: end)
        fetchedRanges.append(newRange)
        mergeOverlappingRanges()
    }

    /// Restore state from persisted ranges.
    internal func restore(from ranges: [FetchedRange]) {
        fetchedRanges = ranges
        mergeOverlappingRanges()
    }

    /// Export current ranges for persistence.
    internal func export() -> [FetchedRange] {
        return fetchedRanges
    }

    /// Check if a specific sequence number has been fetched.
    internal func hasFetched(_ sequenceNum: UInt32) -> Bool {
        return fetchedRanges.contains { $0.contains(sequenceNum) }
    }

    /// Find missing ranges within the specified range.
    /// Port of ControlX2's getMissingIds() logic (lines 176-196).
    internal func getMissingRanges(in range: ClosedRange<UInt32>) -> [ClosedRange<UInt32>] {
        let min = range.lowerBound
        let max = range.upperBound

        // Get all fetched sequence numbers in the range
        let fetched = getAllFetchedSequences(in: range).sorted()

        if fetched.isEmpty {
            return [min...max]
        }

        var missing: [ClosedRange<UInt32>] = []

        // Check for gap before first fetched sequence
        if fetched[0] > min {
            missing.append(min...(fetched[0] - 1))
        }

        // Find gaps between consecutive fetched sequences
        var prev = fetched[0]
        for i in 1..<fetched.count {
            let current = fetched[i]
            if current > prev + 1 {
                missing.append((prev + 1)...(current - 1))
            }
            prev = current
        }

        // Check for gap after last fetched sequence
        if prev < max {
            missing.append((prev + 1)...max)
        }

        return missing
    }

    /// Get all fetched sequence numbers within a range.
    private func getAllFetchedSequences(in range: ClosedRange<UInt32>) -> [UInt32] {
        var sequences: [UInt32] = []

        for fetchedRange in fetchedRanges {
            let rangeStart = max(fetchedRange.start, range.lowerBound)
            let rangeEnd = min(fetchedRange.end, range.upperBound)

            if rangeStart <= rangeEnd {
                for seq in rangeStart...rangeEnd {
                    sequences.append(seq)
                }
            }
        }

        return sequences
    }

    /// Merge overlapping and adjacent ranges to keep the list compact.
    private func mergeOverlappingRanges() {
        guard fetchedRanges.count > 1 else { return }

        // Sort by start sequence
        fetchedRanges.sort { $0.start < $1.start }

        var merged: [FetchedRange] = []
        var current = fetchedRanges[0]

        for i in 1..<fetchedRanges.count {
            let next = fetchedRanges[i]

            if let mergedRange = current.merge(with: next) {
                current = mergedRange
            } else {
                merged.append(current)
                current = next
            }
        }

        merged.append(current)
        fetchedRanges = merged
    }
}
