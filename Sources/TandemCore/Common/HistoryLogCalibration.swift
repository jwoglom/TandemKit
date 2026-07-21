import Foundation

/// Approximate two-way mapping between history-log sequence numbers and dates.
///
/// The pump exposes history logs by sequence number, but the viewer needs to navigate by *date*
/// ("show me around three days ago"). Downloading every log just to learn its timestamp is far
/// too slow, so instead we sample a handful of single logs spread across the sequence range —
/// "guideposts" — and interpolate between them.
///
/// Between two adjacent guideposts the mapping is treated as linear; past either end it
/// extrapolates along the nearest segment. Results are clamped to the pump's known
/// `[firstSequenceNum, lastSequenceNum]` bounds when the caller supplies them.
///
/// The mapping assumes sequence number and date increase together. Pump clock changes can break
/// that locally, so every value produced here is an *estimate* — good enough to jump to the right
/// neighbourhood, after which a binary search (`binarySearchBoundary`) can pin an exact edge.
public struct HistoryLogCalibration: Equatable {
    /// A single sampled (sequenceNum, date) pair.
    public struct Point: Equatable, Comparable {
        public let sequenceNum: UInt32
        public let date: Date

        public init(sequenceNum: UInt32, date: Date) {
            self.sequenceNum = sequenceNum
            self.date = date
        }

        public static func < (lhs: Point, rhs: Point) -> Bool {
            lhs.sequenceNum < rhs.sequenceNum
        }
    }

    /// Guidepost points, sorted ascending by sequence number and deduplicated (last write wins).
    public private(set) var points: [Point]

    public init(points: [Point] = []) {
        self.points = Self.normalize(points)
    }

    public var isEmpty: Bool { points.isEmpty }
    public var count: Int { points.count }
    public var earliest: Point? { points.first }
    public var latest: Point? { points.last }

    /// At least two distinct points are required before interpolation is meaningful.
    public var isUsable: Bool { points.count >= 2 }

    /// Adds (or replaces) a guidepost and keeps `points` sorted and deduplicated.
    public mutating func insert(sequenceNum: UInt32, date: Date) {
        points = Self.normalize(points + [Point(sequenceNum: sequenceNum, date: date)])
    }

    public mutating func insert(_ point: Point) {
        insert(sequenceNum: point.sequenceNum, date: point.date)
    }

    // MARK: - Estimation

    /// Estimated date for a sequence number. Returns `nil` only when no guideposts exist.
    public func estimatedDate(forSequenceNum sequenceNum: UInt32) -> Date? {
        guard !points.isEmpty else { return nil }
        guard points.count > 1 else { return points[0].date }

        let pairs = points.map { (x: Double($0.sequenceNum), y: $0.date.timeIntervalSince1970) }
        let seconds = Self.interpolate(Double(sequenceNum), in: pairs)
        return Date(timeIntervalSince1970: seconds)
    }

    /// Estimated sequence number for a date, clamped to the supplied bounds. Returns `nil` only
    /// when no guideposts exist.
    public func estimatedSequenceNum(
        forDate date: Date,
        lowerBound: UInt32? = nil,
        upperBound: UInt32? = nil
    ) -> UInt32? {
        guard !points.isEmpty else { return nil }
        guard points.count > 1 else {
            return Self.clamp(Double(points[0].sequenceNum), lowerBound: lowerBound, upperBound: upperBound)
        }

        // Invert the mapping: date is the independent axis here, so order pairs by date.
        let pairs = points
            .map { (x: $0.date.timeIntervalSince1970, y: Double($0.sequenceNum)) }
            .sorted { $0.x < $1.x }
        let estimate = Self.interpolate(date.timeIntervalSince1970, in: pairs)
        return Self.clamp(estimate, lowerBound: lowerBound, upperBound: upperBound)
    }

    /// Tightest pair of guidepost sequence numbers that bracket `date`, useful for narrowing a
    /// binary search. Returns `nil` when `date` falls outside the sampled range (the caller should
    /// then fall back to the pump's full `[first, last]` bounds).
    public func sequenceBounds(forDate date: Date) -> (lower: UInt32, upper: UInt32)? {
        guard points.count > 1 else { return nil }
        let ordered = points.sorted { $0.date < $1.date }
        guard let first = ordered.first, let last = ordered.last,
              date >= first.date, date <= last.date else {
            return nil
        }
        var lower = first
        var upper = last
        for point in ordered {
            if point.date <= date, point.sequenceNum >= lower.sequenceNum {
                lower = point
            }
            if point.date >= date {
                upper = point
                break
            }
        }
        let lo = min(lower.sequenceNum, upper.sequenceNum)
        let hi = max(lower.sequenceNum, upper.sequenceNum)
        return (lo, hi)
    }

    // MARK: - Binary search

    /// Which edge of a date to resolve when binary searching the exact boundary log.
    public enum Boundary {
        /// Smallest sequence number whose date is at or after `target` (the newer/"from" edge).
        case firstAtOrAfter
        /// Largest sequence number whose date is at or before `target` (the older/"to" edge).
        case lastAtOrBefore
    }

    /// Resolves the exact sequence number at a date boundary by probing individual logs.
    ///
    /// `probe` returns the pump date for a sequence number, or `nil` if it could not be read; a
    /// `nil` probe ends the search early and returns the best bound found so far. Assumes date is
    /// non-decreasing in sequence number within `[lowerBound, upperBound]`. Never issues more than
    /// `maxProbes` probes so a bad bracket can't spin forever.
    public static func binarySearchBoundary(
        _ boundary: Boundary,
        target: Date,
        lowerBound: UInt32,
        upperBound: UInt32,
        maxProbes: Int = 24,
        probe: (UInt32) -> Date?
    ) -> UInt32 {
        guard lowerBound < upperBound else { return lowerBound }

        var lo = lowerBound
        var hi = upperBound
        var probes = 0

        switch boundary {
        case .firstAtOrAfter:
            // Lower bound: smallest index with date >= target.
            while lo < hi, probes < maxProbes {
                let mid = lo + (hi - lo) / 2
                guard let date = probe(mid) else { break }
                probes += 1
                if date >= target {
                    hi = mid
                } else {
                    lo = mid + 1
                }
            }
            return lo

        case .lastAtOrBefore:
            // Upper bound: largest index with date <= target.
            while lo < hi, probes < maxProbes {
                let mid = lo + (hi - lo + 1) / 2
                guard let date = probe(mid) else { break }
                probes += 1
                if date <= target {
                    lo = mid
                } else {
                    hi = mid - 1
                }
            }
            return lo
        }
    }

    // MARK: - Private helpers

    private static func normalize(_ points: [Point]) -> [Point] {
        var bySequence: [UInt32: Point] = [:]
        for point in points {
            bySequence[point.sequenceNum] = point
        }
        return bySequence.values.sorted()
    }

    /// Piecewise-linear interpolation over `pairs` (sorted ascending by `x`, at least two entries).
    /// Extrapolates along the nearest segment when `x` is outside the sampled range.
    private static func interpolate(_ x: Double, in pairs: [(x: Double, y: Double)]) -> Double {
        guard let first = pairs.first, let last = pairs.last else { return 0 }
        guard pairs.count > 1 else { return first.y }

        if x <= first.x {
            return segmentValue(x, pairs[0], pairs[1])
        }
        if x >= last.x {
            let n = pairs.count
            return segmentValue(x, pairs[n - 2], pairs[n - 1])
        }

        var lo = 0
        var hi = pairs.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if pairs[mid].x <= x {
                lo = mid
            } else {
                hi = mid
            }
        }
        return segmentValue(x, pairs[lo], pairs[hi])
    }

    /// Value on the line through `a` and `b` at `x` (extends beyond the segment for extrapolation).
    private static func segmentValue(_ x: Double, _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x
        guard abs(dx) > .ulpOfOne else {
            return (a.y + b.y) / 2
        }
        let t = (x - a.x) / dx
        return a.y + t * (b.y - a.y)
    }

    private static func clamp(_ value: Double, lowerBound: UInt32?, upperBound: UInt32?) -> UInt32 {
        let floor = Double(lowerBound ?? 0)
        let ceiling = Double(upperBound ?? UInt32.max)
        var v = value.rounded()
        if v < floor { v = floor }
        if v > ceiling { v = ceiling }
        return UInt32(v)
    }
}
