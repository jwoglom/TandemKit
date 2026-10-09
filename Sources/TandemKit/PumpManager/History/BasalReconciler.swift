import Foundation

/// Compares the basal the pump delivered (`PumpBasalTimeline`) with what the host counts
/// (`ReportedBasalLedger`), chunk by chunk.
///
/// The host counts a change from its command and the pump from its next cycle, so a chunk whose
/// rate matches the host's at its start never differs, whatever the host does later inside it. That
/// residual is left alone and only measured.
enum BasalReconciler {
    /// Milliunits per hour.
    static let rateTolerance = 10

    struct Difference: Equatable {
        let chunk: PumpBasalTimeline.Chunk
        /// What the host counts at the chunk's start.
        let host: ReportedBasalLedger.HostBasal
    }

    struct Result: Equatable {
        var differences: [Difference] = []
        /// Chunks compared that matched.
        var matched = 0
        /// Suspended, before the floor, still running at `now`, or exempt.
        var skipped = 0
        /// Per phone-calendar day, the host's insulin against the pump's over the chunks that
        /// matched, in units: the cycle timing no correction covers.
        var residualByDay: [Date: Double] = [:]
    }

    enum Verdict: Equatable {
        /// With the host's insulin against the pump's over the chunk, in units.
        case matches(residual: Double)
        case differs(ReportedBasalLedger.HostBasal)
        case skipped
    }

    /// - Parameters:
    ///   - floor: Nothing starting earlier is compared.
    ///   - isExempt: A chunk the driver over-reports on purpose (a temp worked out against the next
    ///     segment's rate).
    static func reconcile(
        _ timeline: PumpBasalTimeline,
        against ledger: ReportedBasalLedger,
        schedule: HostBasalSchedule,
        floor: Date,
        now: Date,
        calendar: Calendar = .current,
        isExempt: (PumpBasalTimeline.Chunk) -> Bool = { _ in false }
    ) -> Result {
        var result = Result()
        for chunk in timeline.chunks {
            switch verdict(for: chunk, against: ledger, schedule: schedule, floor: floor, now: now, isExempt: isExempt) {
            case let .matches(residual):
                result.matched += 1
                result.residualByDay[calendar.startOfDay(for: chunk.start), default: 0] += residual
            case let .differs(host):
                result.differences.append(Difference(chunk: chunk, host: host))
            case .skipped:
                result.skipped += 1
            }
        }
        return result
    }

    static func verdict(
        for chunk: PumpBasalTimeline.Chunk,
        against ledger: ReportedBasalLedger,
        schedule: HostBasalSchedule,
        floor: Date,
        now: Date,
        isExempt: (PumpBasalTimeline.Chunk) -> Bool = { _ in false }
    ) -> Verdict {
        guard chunk.kind != .suspended, chunk.start >= max(floor, ledger.trackingSince), chunk.end <= now, !isExempt(chunk) else {
            return .skipped
        }
        let host = ledger.hostBasal(at: chunk.start, schedule: schedule)
        guard host.source != .suspended else {
            return .skipped
        }
        guard matches(chunk, ledger: ledger, schedule: schedule) else {
            return .differs(host)
        }
        let interval = DateInterval(start: chunk.start, end: chunk.end)
        return .matches(residual: abs(ledger.hostUnits(in: interval, schedule: schedule) - chunk.units))
    }

    /// The host's rate at the chunk's start, or either side of a change it was commanded to make
    /// within `transitionMatchTolerance`, which the pump may take up at the 279 either side. Not a
    /// correction's edge: that is the pump's own cycle, and the rate before it the previous chunk's.
    private static func matches(
        _ chunk: PumpBasalTimeline.Chunk,
        ledger: ReportedBasalLedger,
        schedule: HostBasalSchedule
    ) -> Bool {
        if ledger.rows.contains(where: { ledger.correctedSequenceNum(of: $0) == chunk.sequenceNum }) {
            return true
        }
        // A temp runs a whole percent of the profile, as the driver's skewed-clock temps do.
        let tolerance = rateTolerance + (chunk.kind == .temp ? chunk.profileBasalRate / 100 : 0)
        let window = DateInterval(
            start: chunk.start.addingTimeInterval(-TandemPumpManager.transitionMatchTolerance),
            end: chunk.start.addingTimeInterval(TandemPumpManager.transitionMatchTolerance)
        )
        let commands = Set(ledger.changes(in: window, schedule: schedule, includingCorrections: false))
        let points = [window.start] + ledger.changes(in: window, schedule: schedule)
        let instants = [chunk.start] + points.indices.dropFirst()
            .filter { commands.contains(points[$0]) }
            .flatMap { [points[$0 - 1], points[$0]] }
        return instants.contains { instant in
            let rate = Int((ledger.hostBasal(at: instant, schedule: schedule).rate * 1000).rounded())
            return abs(rate - chunk.commandedRate) <= tolerance
        }
    }
}
