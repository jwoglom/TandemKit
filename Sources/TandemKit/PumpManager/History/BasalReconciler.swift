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
        let floor = max(floor, ledger.trackingSince)
        for chunk in timeline.chunks {
            guard chunk.kind != .suspended, chunk.start >= floor, chunk.end <= now, !isExempt(chunk) else {
                result.skipped += 1
                continue
            }
            let host = ledger.hostBasal(at: chunk.start, schedule: schedule)
            guard host.source != .suspended else {
                result.skipped += 1
                continue
            }

            if matches(chunk, ledger: ledger, schedule: schedule) {
                result.matched += 1
                let interval = DateInterval(start: chunk.start, end: chunk.end)
                let residual = abs(ledger.hostUnits(in: interval, schedule: schedule) - chunk.units)
                result.residualByDay[calendar.startOfDay(for: chunk.start), default: 0] += residual
            } else {
                result.differences.append(Difference(chunk: chunk, host: host))
            }
        }
        return result
    }

    /// The host's rate anywhere within `transitionMatchTolerance` of the chunk's start. A temp runs
    /// a whole percent of the profile, so the driver can only ask for a temp within one percent of
    /// the rate it wants, as it does to make up for a skewed pump clock.
    private static func matches(
        _ chunk: PumpBasalTimeline.Chunk,
        ledger: ReportedBasalLedger,
        schedule: HostBasalSchedule
    ) -> Bool {
        let tolerance = rateTolerance + (chunk.kind == .temp ? chunk.profileBasalRate / 100 : 0)
        let window = DateInterval(
            start: chunk.start.addingTimeInterval(-TandemPumpManager.transitionMatchTolerance),
            end: chunk.start.addingTimeInterval(TandemPumpManager.transitionMatchTolerance)
        )
        let instants = [window.start] + ledger.changes(in: window, schedule: schedule) + [window.end]
        return instants.contains { instant in
            let rate = Int((ledger.hostBasal(at: instant, schedule: schedule).rate * 1000).rounded())
            return abs(rate - chunk.commandedRate) <= tolerance
        }
    }
}
