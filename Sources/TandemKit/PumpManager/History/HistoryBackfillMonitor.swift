import Foundation

struct HistoryLogStatusReading: Equatable {
    let numEntries: UInt32
    let firstSequenceNum: UInt32
    let lastSequenceNum: UInt32
    /// Host clock.
    let readAt: Date

    init(_ response: HistoryLogStatusResponse, readAt: Date) {
        numEntries = response.numEntries
        firstSequenceNum = response.firstSequenceNum
        lastSequenceNum = response.lastSequenceNum
        self.readAt = readAt
    }
}

/// What the history backfill and dose reporting have done since launch, for the diagnostics
/// screen. In memory only; nothing here decides a dose.
final class HistoryBackfillMonitor {
    enum SkipReason: String, Equatable {
        case flagOff
        case noPumpSerial
        /// Runs once the running tick ends.
        case queuedBehindRunningTick
        case readerBusy
        case noStatus
    }

    struct TickRecord: Equatable {
        let startedAt: Date
        let finishedAt: Date
        /// Nil when the tick did its work.
        let skipped: SkipReason?
        let outcome: HistoryBackfillCoordinator.TickOutcome?
    }

    struct WatermarkAdvance: Equatable {
        let at: Date
        let from: UInt32?
        let to: UInt32
    }

    struct ReportingPass: Equatable {
        enum Result: Equatable {
            case completed
            /// The command job could not connect; the next tick tries again.
            case deferred(String)
            case storeUnreadable
        }

        let date: Date
        let covered: ClosedRange<UInt32>
        let floor: Date
        var result: Result = .completed
        /// Bolus doses mapped from the window, floor not yet applied.
        var boluses = 0
        var belowFloor = 0
        var reported = 0
        var alreadyFinalized = 0
        /// Reported in flight earlier and not re-reported until its completion is read (#452).
        var awaitingCompletion = 0
        var leftToLivePath = 0
        var extendedBoluses = 0
    }

    struct Totals: Equatable {
        var ticksCompleted = 0
        var ticksSkipped: [SkipReason: Int] = [:]
        var entriesRead = 0
        var rangesFailed = 0
        var watermarkResets = 0
        var deepSliceCapHits = 0
    }

    struct Snapshot: Equatable {
        let startedAt: Date
        let runningTickStartedAt: Date?
        /// Newest first.
        let recentTicks: [TickRecord]
        let lastCompletedTick: TickRecord?
        let lastStatus: HistoryLogStatusReading?
        let sessionCovered: ClosedRange<UInt32>?
        let lastWatermarkAdvance: WatermarkAdvance?
        let lastReportingPass: ReportingPass?
        let totals: Totals
    }

    static let recentTickLimit = 20

    private let startedAt: Date
    private let lock = NSLock()
    private var runningTickStartedAt: Date?
    private var recentTicks: [TickRecord] = []
    private var lastCompletedTick: TickRecord?
    private var lastStatus: HistoryLogStatusReading?
    private var sessionCovered: ClosedRange<UInt32>?
    private var lastWatermarkAdvance: WatermarkAdvance?
    private var lastReportingPass: ReportingPass?
    private var totals = Totals()

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            startedAt: startedAt,
            runningTickStartedAt: runningTickStartedAt,
            recentTicks: recentTicks.reversed(),
            lastCompletedTick: lastCompletedTick,
            lastStatus: lastStatus,
            sessionCovered: sessionCovered,
            lastWatermarkAdvance: lastWatermarkAdvance,
            lastReportingPass: lastReportingPass,
            totals: totals
        )
    }

    func tickSkipped(_ reason: SkipReason, at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        totals.ticksSkipped[reason, default: 0] += 1
        append(TickRecord(startedAt: date, finishedAt: date, skipped: reason, outcome: nil))
    }

    func tickStarted(at date: Date) {
        lock.lock()
        runningTickStartedAt = date
        lock.unlock()
    }

    /// A nil `outcome` is a tick that got no history log status.
    func tickFinished(startedAt: Date, finishedAt: Date, outcome: HistoryBackfillCoordinator.TickOutcome?) {
        lock.lock()
        defer { lock.unlock() }
        runningTickStartedAt = nil

        guard let outcome else {
            totals.ticksSkipped[.noStatus, default: 0] += 1
            append(TickRecord(startedAt: startedAt, finishedAt: finishedAt, skipped: .noStatus, outcome: nil))
            return
        }

        let record = TickRecord(startedAt: startedAt, finishedAt: finishedAt, skipped: nil, outcome: outcome)
        append(record)
        lastCompletedTick = record
        totals.ticksCompleted += 1
        totals.entriesRead += outcome.rangesRead.reduce(0) { $0 + $1.count }
        totals.rangesFailed += outcome.rangesFailed.count
        if outcome.watermarkWasReset {
            totals.watermarkResets += 1
        }
        if outcome.hitDeepSliceCap {
            totals.deepSliceCapHits += 1
        }
        if let status = outcome.pumpStatus {
            lastStatus = status
        }
        sessionCovered = outcome.sessionCovered

        let before = outcome.watermarkWasReset ? nil : outcome.watermarkBefore
        if let after = outcome.bookkeeping.watermark, after != before {
            lastWatermarkAdvance = WatermarkAdvance(at: finishedAt, from: before, to: after)
        }
    }

    func statusRead(_ reading: HistoryLogStatusReading) {
        lock.lock()
        lastStatus = reading
        lock.unlock()
    }

    func reportingPassFinished(_ pass: ReportingPass) {
        lock.lock()
        lastReportingPass = pass
        lock.unlock()
    }

    func resetTotals() {
        lock.lock()
        totals = Totals()
        lock.unlock()
    }

    private func append(_ record: TickRecord) {
        recentTicks.append(record)
        if recentTicks.count > Self.recentTickLimit {
            recentTicks.removeFirst(recentTicks.count - Self.recentTickLimit)
        }
    }
}
