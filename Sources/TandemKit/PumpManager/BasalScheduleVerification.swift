import Foundation
import LoopKit

/// Compares what the pump holds against the basal schedule the app believes is in force.
/// https://github.com/jwoglom/TandemKit/issues/206
enum BasalScheduleVerification {
    /// Minutes past midnight and milliunits per hour, the units the pump uses, so nothing rounds.
    struct Segment: Equatable, CustomStringConvertible {
        let startMinutes: Int
        let milliunitsPerHour: Int

        var description: String { "\(startMinutes)min=\(milliunitsPerHour)mU/hr" }
    }

    /// How long a delivered rate has to stay wrong before it counts, so one poll cannot raise it.
    static let mismatchConfirmationInterval: TimeInterval = .minutes(4)

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

    /// Compared in start-time order, not segment index: index order is an artefact of how the
    /// segments were written, and the same segments deliver the same insulin in any order.
    static func difference(pump: [Segment], expected: [Segment]) -> String? {
        guard pump != expected else {
            return nil
        }

        return "pump has [\(pump.map(\.description).joined(separator: ", "))], "
            + "expected [\(expected.map(\.description).joined(separator: ", "))]"
    }
}
