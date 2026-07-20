import Foundation

/// Represents a contiguous range of fetched history log sequence numbers.
/// Used to track which portions of pump history have been successfully retrieved.
public struct FetchedRange: Codable, Equatable {
    public let start: UInt32
    public let end: UInt32
    public let fetchedAt: Date

    public init(start: UInt32, end: UInt32, fetchedAt: Date = Date()) {
        self.start = start
        self.end = end
        self.fetchedAt = fetchedAt
    }

    /// Check if a sequence number falls within this range.
    public func contains(_ sequenceNum: UInt32) -> Bool {
        sequenceNum >= start && sequenceNum <= end
    }

    /// Check if this range overlaps with another range.
    public func overlaps(_ other: FetchedRange) -> Bool {
        !(end < other.start || start > other.end)
    }

    /// Check if this range is adjacent to another range (can be merged).
    public func isAdjacent(to other: FetchedRange) -> Bool {
        end + 1 == other.start || other.end + 1 == start
    }

    /// Merge this range with another overlapping or adjacent range.
    /// Returns nil if ranges cannot be merged (not overlapping or adjacent).
    public func merge(with other: FetchedRange) -> FetchedRange? {
        guard overlaps(other) || isAdjacent(to: other) else {
            return nil
        }

        return FetchedRange(
            start: min(start, other.start),
            end: max(end, other.end),
            fetchedAt: max(fetchedAt, other.fetchedAt)
        )
    }

    /// Returns the count of sequence numbers in this range.
    public var count: Int {
        Int(end - start) + 1
    }
}

extension FetchedRange: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let startRaw = rawValue["start"] as? Int,
              let endRaw = rawValue["end"] as? Int,
              let start = UInt32(exactly: startRaw),
              let end = UInt32(exactly: endRaw),
              let fetchedAtInterval = rawValue["fetchedAt"] as? TimeInterval
        else {
            return nil
        }
        self.init(
            start: start,
            end: end,
            fetchedAt: Date(timeIntervalSinceReferenceDate: fetchedAtInterval)
        )
    }

    public var rawValue: RawValue {
        [
            "start": Int(start),
            "end": Int(end),
            "fetchedAt": fetchedAt.timeIntervalSinceReferenceDate
        ]
    }
}
