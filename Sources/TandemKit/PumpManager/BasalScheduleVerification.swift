import Foundation
import LoopKit

/// Compares what the pump holds against the basal schedule the app believes is in force.
///
/// A Tandem temp basal is a percent of the pump's *profile* rate, and the driver computes that
/// percent from the app-side schedule, so the two drifting apart means every temp basal is wrong
/// by the same ratio and the loop is told a delivery rate that is not happening.
/// https://github.com/jwoglom/TandemKit/issues/206
enum BasalScheduleVerification {
    /// A profile segment reduced to the two fields that determine basal delivery. Start times are
    /// minutes past midnight and rates milliunits per hour, the units the pump uses on the wire,
    /// so a comparison never rounds.
    struct Segment: Equatable, CustomStringConvertible {
        let startMinutes: Int
        let milliunitsPerHour: Int

        var description: String { "\(startMinutes)min=\(milliunitsPerHour)mU/hr" }
    }

    static func milliunits(_ unitsPerHour: Double) -> Int {
        Int((unitsPerHour * 1000.0).rounded())
    }

    static func segments(for items: [RepeatingScheduleValue<Double>]) -> [Segment] {
        items
            .map { Segment(startMinutes: Int(($0.startTime / 60.0).rounded()), milliunitsPerHour: milliunits($0.value)) }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    static func segments(for responses: [IDPSegmentResponse]) -> [Segment] {
        responses
            .map { Segment(startMinutes: $0.profileStartTime, milliunitsPerHour: $0.profileBasalRate) }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// How the pump's profile differs from `expected`, or nil when they agree.
    ///
    /// Compared in start-time order rather than segment index: index order is an artefact of how
    /// the segments were written, and two profiles holding the same segments deliver the same
    /// insulin whatever order the pump lists them in.
    static func difference(pump: [Segment], expected: [Segment]) -> String? {
        guard pump != expected else {
            return nil
        }

        return "pump has [\(pump.map(\.description).joined(separator: ", "))], "
            + "expected [\(expected.map(\.description).joined(separator: ", "))]"
    }
}

/// A pump delivering a basal rate other than the one the app scheduled, while running its own
/// profile rather than a temp basal.
///
/// Held across observations because a single disagreement can be a clock or segment-boundary
/// artefact; only one that survives `confirmationInterval` is reported. Deliberately not
/// persisted: the next sync re-establishes it within minutes, and a stale one restored from disk
/// would accuse a pump that has since been corrected.
public struct BasalRateMismatch: Equatable {
    public let expectedUnitsPerHour: Double
    public let pumpUnitsPerHour: Double
    public let firstSeen: Date
    public let lastSeen: Date

    /// One Loop cycle plus slack, so a mismatch has to outlive a single poll to count.
    public static let confirmationInterval: TimeInterval = .minutes(4)

    public init(expectedUnitsPerHour: Double, pumpUnitsPerHour: Double, firstSeen: Date, lastSeen: Date) {
        self.expectedUnitsPerHour = expectedUnitsPerHour
        self.pumpUnitsPerHour = pumpUnitsPerHour
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    /// A first sighting has `firstSeen == lastSeen`, so the interval alone gates on a repeat.
    public var isConfirmed: Bool {
        lastSeen.timeIntervalSince(firstSeen) >= Self.confirmationInterval
    }

    /// Extends this mismatch with a fresh sighting, or starts over when the rates changed.
    public func observed(expectedUnitsPerHour: Double, pumpUnitsPerHour: Double, at date: Date) -> BasalRateMismatch {
        guard expectedUnitsPerHour == self.expectedUnitsPerHour, pumpUnitsPerHour == self.pumpUnitsPerHour else {
            return BasalRateMismatch(
                expectedUnitsPerHour: expectedUnitsPerHour,
                pumpUnitsPerHour: pumpUnitsPerHour,
                firstSeen: date,
                lastSeen: date
            )
        }

        return BasalRateMismatch(
            expectedUnitsPerHour: expectedUnitsPerHour,
            pumpUnitsPerHour: pumpUnitsPerHour,
            firstSeen: firstSeen,
            lastSeen: date
        )
    }
}
