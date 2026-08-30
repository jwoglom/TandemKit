import Foundation

/// Decides what to read off the pump on a backfill tick, and how far back events may be
/// reported.
///
/// Pure arithmetic over the pump's advertised range, the persisted bookkeeping and the session
/// store's gaps — no I/O, no clock beyond what is passed in. `HistoryBackfillCoordinator` runs
/// the plan; keeping the decision here means the ordering rules below can be tested without a
/// pump, a BLE stack or a fetch that takes minutes.
enum HistoryBackfillPlanner {
    /// A single tick's worth of reading, in the order it should be performed.
    struct Plan: Equatable {
        /// Everything written since the last read: `watermark + 1 ... last`. Fetched first and
        /// never sliced — recent history is what the loop is waiting on, and the pump writes
        /// entries slowly enough that this range stays small on any normal cadence.
        var incremental: ClosedRange<UInt32>?

        /// Holes inside the span this session has read. A range that was requested but never
        /// streamed back leaves a gap the fetcher's own intra-fetch healing can't reach once that
        /// fetch has ended, so it is re-requested here.
        var gaps: [ClosedRange<UInt32>]

        /// One slice of the walk backward toward `deepFetchTarget`, or nil when the deep
        /// backfill is finished or has nothing left to reach. Capped at `maxDeepSliceSize` so a
        /// first-run backfill of thousands of entries is spread over many ticks instead of
        /// occupying the BLE queue in one uninterruptible block.
        var deep: ClosedRange<UInt32>?

        /// Whether the walk backward has nothing left to reach: the store already covers the
        /// target date, or the pump holds nothing older than what has been read. False on a tick
        /// that has not read anything yet, whose `deep` is nil only for want of a starting floor.
        var isDeepBackfillComplete: Bool

        var isEmpty: Bool {
            incremental == nil && gaps.isEmpty && deep == nil
        }
    }

    /// The most entries a single deep-backfill slice may ask for.
    ///
    /// 255 is one `HistoryLogRequest` (`numberOfLogs` is one byte), which the fetcher walks as a
    /// single chunk. One chunk per tick keeps the pump's command queue free for dosing between
    /// slices — a bolus issued during a backfill waits for at most one chunk, not for the whole
    /// walk.
    static let maxDeepSliceSize: UInt32 = 255

    /// How far back the deep backfill reads, as an offset from now.
    ///
    /// Covers the insulin that could still be acting, so IOB derived from history is complete.
    /// Six hours is the longest DIA Trio and Loop offer; LoopKit gives a `PumpManager` no way to
    /// ask the host app for the configured value, so the driver reads to the worst case rather
    /// than guessing low and under-reporting IOB. Rounded up by an hour of slack so a boundary
    /// dose isn't clipped by clock skew between the pump and the phone.
    static let deepFetchLookback: TimeInterval = .hours(7)

    /// The date the deep backfill reads back to: far enough for insulin still acting, but never
    /// past the floor below which events would be discarded anyway.
    static func deepFetchTarget(emitFloor: Date?, now: Date = Date()) -> Date {
        let lookbackTarget = now.addingTimeInterval(-deepFetchLookback)
        guard let emitFloor else {
            return lookbackTarget
        }
        return max(lookbackTarget, emitFloor)
    }

    /// The earliest date events may be reported for: the later of what the host app will accept
    /// and what this pump's bookkeeping allows.
    ///
    /// The host's floor (`PumpManagerDelegate.startDateToFilterNewPumpEvents`) moves forward as
    /// its own store ages out; events below it are discarded on arrival, so emitting them is
    /// wasted work. The bookkeeping's floor is set when a pump is first seen and never moves,
    /// which is what separates a *re-paired* pump (same serial, original floor kept, so the gap
    /// while the app was away is still reportable) from a *replacement* pump (new serial, a fresh
    /// floor one lookback back, so nothing but its still-acting insulin reaches the loop).
    static func emitFloor(hostFloor: Date?, bookkeeping: HistoryBackfillState?) -> Date? {
        switch (hostFloor, bookkeeping?.emitFloor) {
        case let (hostFloor?, pumpFloor?):
            return max(hostFloor, pumpFloor)
        case let (hostFloor?, nil):
            return hostFloor
        case let (nil, pumpFloor?):
            return pumpFloor
        case (nil, nil):
            return nil
        }
    }

    /// Build a tick's plan.
    ///
    /// The two coverage inputs are deliberately separate. `watermark` is persisted, so it
    /// survives a relaunch and keeps the read of *new* entries incremental. `sessionCovered` is
    /// what this process has actually put in the store, which after a relaunch is nothing —
    /// gap healing and the walk backward are scoped to it, because both exist to fill the
    /// session store, and scoping them to the persisted watermark instead would make a cold
    /// start treat its whole history as one enormous hole.
    ///
    /// - Parameters:
    ///   - firstSequenceNum: Oldest entry the pump still holds (`HistoryLogStatusResponse`).
    ///   - lastSequenceNum: Newest entry the pump holds.
    ///   - watermark: Highest sequence number ever read from this pump, already validated
    ///     against its serial. Nil if none has been.
    ///   - sessionCovered: The span this session has read into the store, nil if none.
    ///   - storeGaps: Missing ranges the store reports within `sessionCovered`, retention
    ///     watermark already applied (`HistoryLogStore.missingRanges`).
    ///   - isDeepTargetCovered: Whether the oldest entry the store holds is at or before
    ///     `deepFetchTarget`. Answering this needs a timestamp, which is the coordinator's job;
    ///     the planner only consumes the verdict.
    static func plan(
        firstSequenceNum: UInt32,
        lastSequenceNum: UInt32,
        watermark: UInt32?,
        sessionCovered: ClosedRange<UInt32>? = nil,
        storeGaps: [ClosedRange<UInt32>] = [],
        isDeepTargetCovered: Bool
    ) -> Plan {
        guard lastSequenceNum >= firstSequenceNum else {
            return Plan(incremental: nil, gaps: [], deep: nil, isDeepBackfillComplete: true)
        }

        let pumpRange = firstSequenceNum ... lastSequenceNum

        let incremental: ClosedRange<UInt32>?
        if let watermark {
            // `watermark >= lastSequenceNum` when the pump has written nothing new. A pump whose
            // log was erased reports a last sequence *below* the watermark, which the same
            // comparison covers: there is still nothing new to read.
            incremental = watermark < lastSequenceNum
                ? clamp((watermark + 1) ... lastSequenceNum, to: pumpRange)
                : nil
        } else {
            // Nothing has ever been read from this pump. Take the newest slice and let later
            // ticks walk backward from it, rather than opening with a read of its whole log.
            incremental = max(firstSequenceNum, subtractingSliceSize(from: lastSequenceNum)) ... lastSequenceNum
        }

        // Gaps come from the store already clamped to the session span and to the retention
        // watermark; drop anything the pump no longer holds so a pruned entry isn't chased.
        let gaps = storeGaps.compactMap { clamp($0, to: pumpRange) }

        let deep = deepSlice(
            firstSequenceNum: firstSequenceNum,
            sessionCovered: sessionCovered,
            isDeepTargetCovered: isDeepTargetCovered
        )

        return Plan(
            incremental: incremental,
            gaps: gaps,
            deep: deep,
            // Complete means "nothing older is worth reading": either the store already reaches
            // past the target date, or the pump holds nothing older. A nil `deep` on a tick that
            // has yet to read anything is neither — the walk simply has no floor to start from.
            isDeepBackfillComplete: isDeepTargetCovered
                || (sessionCovered.map { $0.lowerBound <= firstSequenceNum } ?? false)
        )
    }

    /// The next slice of the backward walk, or nil when there is nothing left to reach.
    ///
    /// Nil before this session has read anything: the walk needs a floor to step down from, and
    /// the tick's incremental read establishes one.
    private static func deepSlice(
        firstSequenceNum: UInt32,
        sessionCovered: ClosedRange<UInt32>?,
        isDeepTargetCovered: Bool
    ) -> ClosedRange<UInt32>? {
        guard !isDeepTargetCovered,
              let lowestCovered = sessionCovered?.lowerBound,
              lowestCovered > firstSequenceNum
        else {
            return nil
        }
        let end = lowestCovered - 1
        return max(firstSequenceNum, subtractingSliceSize(from: end)) ... end
    }

    /// `value - (maxDeepSliceSize - 1)`, saturating at zero.
    private static func subtractingSliceSize(from value: UInt32) -> UInt32 {
        value >= maxDeepSliceSize ? value - (maxDeepSliceSize - 1) : 0
    }

    private static func clamp(_ range: ClosedRange<UInt32>, to bounds: ClosedRange<UInt32>) -> ClosedRange<UInt32>? {
        let lower = max(range.lowerBound, bounds.lowerBound)
        let upper = min(range.upperBound, bounds.upperBound)
        return lower <= upper ? lower ... upper : nil
    }
}
