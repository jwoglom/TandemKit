import Foundation

/// What the recent history passes found, for the Reconciliation debug screen. In memory only, like
/// the session store the passes read, so a relaunch starts it empty.
struct ReconciliationLog: Equatable {
    static let passLimit = 20
    static let differenceLimit = 50
    static let problemLimit = 20

    /// One history pass: what was reported after one backfill tick.
    struct Pass: Equatable {
        let startedAt: Date
        var finishedAt: Date
        /// The session store span the pass compared; nil when the tick did not read the log.
        var covered: ClosedRange<UInt32>?
        var readsThroughPumpEnd = false
        /// Why nothing was compared, for a pass that could not run.
        var skipped: String?
        /// Suspends, resumes and temp basal ends from pump history.
        var transitionsReported = 0
        var basal: Basal?
        var bolusesReported = 0
    }

    struct Basal: Equatable {
        enum HeldBack: Equatable {
            case storeGap(ClosedRange<UInt32>)
            case openChunk(UInt32)
            case pendingDeliveryChange
            /// The temp basal the host holds, whose completion history has not read.
            case heldTempBasal(Date)
            /// A finalized temp basal whose chunks are not all read yet.
            case finalizedTempBasal(Date)
        }

        var matched = 0
        var differed = 0
        var corrections = 0
        var reconciledThrough: UInt32?
        /// What the pass left for a later one, with every chunk after it.
        var heldBack: HeldBack?
    }

    enum HostSource: Equatable {
        case schedule
        case heldTempBasal
        case finalizedTempBasal
    }

    enum Outcome: Equatable {
        case corrected
        case heldTempEnded
        case heldTempRestated
        /// Its record fails the pump history's cross-check.
        case untrusted
        case reportingOff
        case waiting
        /// Acted on with nothing to send: nothing left to correct, or the host holds a temp basal the driver does not.
        case notCorrected
    }

    /// A chunk the pump delivered at a rate other than the one the host counts, and what was done about it.
    struct Difference: Equatable, Identifiable {
        let sequenceNum: UInt32
        let start: Date
        let end: Date
        let pumpKind: PumpBasalTimeline.Kind
        /// Units per hour.
        let pumpRate: Double
        let hostRate: Double
        let hostSource: HostSource
        var outcome: Outcome
        var noticedAt: Date

        var id: UInt32 { sequenceNum }
        /// The host's insulin less the pump's over the chunk.
        var units: Double { (hostRate - pumpRate) * end.timeIntervalSince(start) / .hours(1) }
    }

    /// A pump record that fails the cross-check against the pump's other records.
    struct Problem: Equatable, Identifiable {
        let sequenceNum: UInt32
        let date: Date
        let description: String
        let noticedAt: Date

        var id: UInt32 { sequenceNum }
    }

    /// Host less pump, in units, over the cycles that matched on one phone-calendar day.
    struct ResidualDay: Equatable, Identifiable {
        let day: Date
        let net: Double
        let gross: Double
        let cycles: Int

        var id: Date { day }
    }

    /// Oldest first.
    private(set) var passes: [Pass] = []
    /// The pass under way.
    var current: Pass?
    /// By BasalDelivery record, ascending; a chunk compared again replaces its entry.
    private(set) var differences: [Difference] = []
    private(set) var problems: [Problem] = []
    /// The days not closed yet, oldest first.
    var residualDays: [ResidualDay] = []
    /// Bolus insulin the pump holds that the host was never told of, while the monitor flags it.
    var unreportedInsulinOnBoard: Double?

    mutating func begin(_ outcome: HistoryBackfillCoordinator.TickOutcome, at now: Date) {
        current = Pass(
            startedAt: outcome.startedAt,
            finishedAt: now,
            covered: outcome.sessionCovered,
            readsThroughPumpEnd: outcome.readsThroughPumpEnd
        )
    }

    mutating func end(at now: Date) {
        guard var pass = current else { return }
        pass.finishedAt = now
        current = nil
        append(pass)
    }

    mutating func recordSkippedPass(startedAt: Date, reason: String, at now: Date) {
        append(Pass(startedAt: startedAt, finishedAt: now, skipped: reason))
    }

    mutating func record(_ difference: Difference) {
        differences.removeAll { $0.sequenceNum == difference.sequenceNum }
        differences.append(difference)
        differences.sort { $0.sequenceNum < $1.sequenceNum }
        if differences.count > Self.differenceLimit {
            differences.removeFirst(differences.count - Self.differenceLimit)
        }
    }

    mutating func record(_ problem: Problem) {
        problems.removeAll { $0.sequenceNum == problem.sequenceNum }
        problems.append(problem)
        problems.sort { $0.sequenceNum < $1.sequenceNum }
        if problems.count > Self.problemLimit {
            problems.removeFirst(problems.count - Self.problemLimit)
        }
    }

    private mutating func append(_ pass: Pass) {
        passes.append(pass)
        if passes.count > Self.passLimit {
            passes.removeFirst(passes.count - Self.passLimit)
        }
    }
}
