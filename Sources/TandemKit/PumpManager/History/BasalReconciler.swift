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

    /// How much earlier a later pass, or the next manager after setup's load, can date the record a
    /// correction ends at: each dates by its own clock read, which trails the pump's by up to a second.
    static let recordDatingTolerance: TimeInterval = 2

    struct Difference: Equatable {
        let chunk: PumpBasalTimeline.Chunk
        /// What the host counts from `from`.
        let host: ReportedBasalLedger.HostBasal
        /// The chunk's start, or a change the host was commanded within `transitionMatchTolerance`
        /// after it, which the pump takes up only at its next BasalDelivery record.
        let from: Date
    }

    /// The host's insulin less the pump's over chunks that matched, in units: the cycle timing no
    /// correction covers. A change counts early at both ends of a temp, so `net` can cancel `gross`.
    struct Residual: Equatable {
        var net = 0.0
        var gross = 0.0

        mutating func add(_ residual: Double) {
            net += residual
            gross += abs(residual)
        }
    }

    /// Per phone-calendar day, the residual of each chunk a session compares once, until the day is over.
    struct ResidualDays {
        private var open: [Date: (residual: Residual, chunks: Set<UInt32>)] = [:]
        private var closed = Set<Date>()

        mutating func add(_ residual: Double, of chunk: PumpBasalTimeline.Chunk, calendar: Calendar = .current) {
            let day = calendar.startOfDay(for: chunk.start)
            guard !closed.contains(day), open[day, default: (Residual(), [])].chunks.insert(chunk.sequenceNum).inserted else {
                return
            }
            open[day]?.residual.add(residual)
        }

        /// The days not closed yet, oldest first.
        var current: [(day: Date, residual: Residual, cycles: Int)] {
            open.sorted { $0.key < $1.key }.map { ($0.key, $0.value.residual, $0.value.chunks.count) }
        }

        /// The days before `now`'s, each once.
        mutating func close(before now: Date, calendar: Calendar = .current) -> [(day: Date, residual: Residual, cycles: Int)] {
            let today = calendar.startOfDay(for: now)
            let over = open.filter { $0.key < today }.sorted { $0.key < $1.key }
            for (day, _) in over {
                open[day] = nil
                closed.insert(day)
            }
            return over.map { ($0.key, $0.value.residual, $0.value.chunks.count) }
        }
    }

    struct Result: Equatable {
        var differences: [Difference] = []
        /// Chunks compared that matched.
        var matched = 0
        /// Suspended, before the floor, still running at `now`, or exempt.
        var skipped = 0
        /// Per phone-calendar day.
        var residualByDay: [Date: Residual] = [:]
    }

    enum Verdict: Equatable {
        /// The host's insulin less the pump's over the chunk, in units.
        case matches(residual: Double)
        case differs(ReportedBasalLedger.HostBasal, from: Date)
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
                result.residualByDay[calendar.startOfDay(for: chunk.start), default: Residual()].add(residual)
            case let .differs(host, from):
                result.differences.append(Difference(chunk: chunk, host: host, from: from))
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
        let start = hostStart(of: chunk, in: ledger)
        let host = ledger.hostBasal(at: start, schedule: schedule)
        guard host.source != .suspended else {
            return .skipped
        }
        guard matches(chunk, from: start, ledger: ledger, schedule: schedule) else {
            // The row a change just after the record ended may hold only a second of the chunk.
            let from = ledger.rowEdges(
                in: DateInterval(start: start, end: min(chunk.end, chunk.start.addingTimeInterval(TandemPumpManager.transitionMatchTolerance))),
                includingCorrections: false
            ).last ?? start
            return .differs(ledger.hostBasal(at: from, schedule: schedule), from: from)
        }
        let interval = DateInterval(start: chunk.start, end: chunk.end)
        return .matches(residual: ledger.hostUnits(in: interval, schedule: schedule) - chunk.units)
    }

    /// The chunk's start, or the previous chunk's correction's end when the record is dated just before it.
    private static func hostStart(of chunk: PumpBasalTimeline.Chunk, in ledger: ReportedBasalLedger) -> Date {
        ledger.rows
            .filter { ledger.correctedSequenceNum(of: $0) != nil }
            .map(\.end)
            .filter { chunk.start < $0 && $0 <= chunk.start.addingTimeInterval(recordDatingTolerance) }
            .max() ?? chunk.start
    }

    /// The host's rate at the chunk's start, or either side of a change it was commanded to make
    /// within `transitionMatchTolerance`, which the pump may take up at the BasalDelivery record
    /// either side. Not a correction's edge: that is the pump's own cycle, and the rate before it
    /// the previous chunk's.
    private static func matches(
        _ chunk: PumpBasalTimeline.Chunk,
        from start: Date,
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
        let instants = [start] + points.indices.dropFirst()
            .filter { commands.contains(points[$0]) }
            .flatMap { [points[$0 - 1], points[$0]] }
        return instants.contains { instant in
            let rate = Int((ledger.hostBasal(at: instant, schedule: schedule).rate * 1000).rounded())
            return abs(rate - chunk.commandedRate) <= tolerance
        }
    }
}
